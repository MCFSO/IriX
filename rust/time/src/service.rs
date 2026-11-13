//! 时间系统服务：NTP 轮询、时间源选择、纪律环、应用时钟驱动、状态与持久化。
//!
//! 数据流：
//!
//! ```text
//!  NTP 线程池 ──burst──> 每个服务器一个 SampleRegister（rusty_time filter）
//!                              │
//!                              ▼
//!                    加权线性回归（直接测频，不靠 PLL 时间常数）
//!                              │
//!                              ▼
//!                   falseticker 剔除（区间交集投票）
//!                              │
//!                              ▼
//!              Discipline（step/slew 决策、最大变更保护、leap 处理）
//!                              │
//!                              ▼
//!                  AppClock（虚拟时钟，绝不改操作系统时钟）
//!                              │
//!               ┌──────────────┼─────────────────┐
//!               ▼              ▼                 ▼
//!           日志/FFI      HTTPS 证书有效期    备份/编排/设备绑定
//! ```
//!
//! 关键设计：
//! - 只调整“应用自己的时钟”，不写系统时间，因此无需管理员权限，也不影响其它进程；
//! - 频率修正来自回归斜率（漂移补偿），不是经验性的 PLL 反馈；
//! - 每个服务器独立样本窗口，多源用 falseticker 剔除后再 steer，单一服务器故障
//!   不会把时间带偏；
//! - `poll_drain` 由后台线程按预算完成时刻唤醒调用，保证纪律环账本与实际时钟一致。

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, RwLock};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use rusty_time_core::client::{Estimate, MultiController};
use rusty_time_core::discipline::{ChangeVerdict, ClockCommand, DisciplineConfig};
use rusty_time_core::filter::Sample;
use rusty_time_core::select::{select, SourceEstimate};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::clock::{AppClock, ClockSnapshot, SyncInfo};
use crate::kalman::{KalmanConfig, KalmanFilter};
use crate::ntp::{exchange_burst, query, Burst, NtpSample};
use crate::precise::{self, PrecisionStats};
use crate::state::{self, PersistedState, STATE_VERSION};
use crate::thermal::ThermalMonitor;
use crate::trend::{TrendFit, TrendStore};

pub const DEFAULT_SERVERS: [&str; 4] = [
    "ntp.aliyun.com",
    "ntp.tencent.com",
    "cn.pool.ntp.org",
    "time.cloudflare.com",
];

/// 持久化频率修正的绝对值上限。留出余量给纪律环的残差项（±500ppm）。
const MAX_BASELINE_PPM: f64 = 400.0;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub servers: Vec<String>,
    pub min_poll_log2: i8,
    pub max_poll_log2: i8,
    pub samples_per_poll: u32,
    pub timeout_ms: u64,
    pub precision: bool,
    pub state_path: Option<String>,
    pub auto_start: bool,
    /// |offset| 超过此值且在 makestep 窗口内时直接步进（秒）。
    pub step_threshold_s: f64,
    /// 单次校正的最大幅度（秒）。冷启动前 5 次更新豁免。
    pub max_step_seconds: f64,
    /// 断网保持（holdover）时假定的漂移预算（ppm）。
    ///
    /// 默认 15ppm（普通晶振的保守值，24h 约 1.3s）。知道本机晶振更好
    /// （如 TCXO <1ppm）时可以调小，让不确定度更贴近现实。
    pub holdover_ppm: f64,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            servers: DEFAULT_SERVERS.iter().map(|s| s.to_string()).collect(),
            min_poll_log2: 4,
            max_poll_log2: 8,
            samples_per_poll: 2,
            timeout_ms: 1_200,
            precision: true,
            state_path: None,
            auto_start: true,
            step_threshold_s: 0.5,
            max_step_seconds: 7.0 * 86_400.0,
            holdover_ppm: 15.0,
        }
    }
}

impl Config {
    pub fn apply_json(&mut self, v: &Value) -> Result<(), String> {
        let obj = match v {
            Value::Null => return Ok(()),
            Value::Object(o) => o,
            _ => return Err("参数必须是 JSON 对象".to_string()),
        };
        if let Some(x) = obj.get("servers") {
            let arr = x.as_array().ok_or("servers 必须是数组")?;
            let mut servers = Vec::new();
            for s in arr {
                let s = s.as_str().ok_or("servers 元素必须是字符串")?;
                let s = s.trim();
                if !s.is_empty() {
                    servers.push(s.to_string());
                }
            }
            self.servers = servers;
        }
        if let Some(x) = obj.get("min_poll_log2") {
            self.min_poll_log2 = x.as_i64().ok_or("min_poll_log2 必须是整数")?.clamp(0, 10) as i8;
        }
        if let Some(x) = obj.get("max_poll_log2") {
            self.max_poll_log2 = x.as_i64().ok_or("max_poll_log2 必须是整数")?.clamp(0, 10) as i8;
        }
        if self.min_poll_log2 > self.max_poll_log2 {
            std::mem::swap(&mut self.min_poll_log2, &mut self.max_poll_log2);
        }
        if let Some(x) = obj.get("samples_per_poll") {
            self.samples_per_poll = x.as_u64().ok_or("samples_per_poll 必须是整数")?.clamp(1, 5) as u32;
        }
        if let Some(x) = obj.get("timeout_ms") {
            self.timeout_ms = x.as_u64().ok_or("timeout_ms 必须是整数")?.clamp(200, 10_000);
        }
        if let Some(x) = obj.get("precision") {
            self.precision = x.as_bool().ok_or("precision 必须是布尔值")?;
        }
        if let Some(x) = obj.get("state_path") {
            self.state_path = match x {
                Value::Null => None,
                Value::String(s) => Some(s.clone()),
                _ => return Err("state_path 必须是字符串或 null".to_string()),
            };
        }
        if let Some(x) = obj.get("auto_start") {
            self.auto_start = x.as_bool().ok_or("auto_start 必须是布尔值")?;
        }
        if let Some(x) = obj.get("step_threshold_s") {
            self.step_threshold_s = x
                .as_f64()
                .ok_or("step_threshold_s 必须是数字")?
                .clamp(0.01, 3_600.0);
        }
        if let Some(x) = obj.get("max_step_seconds") {
            self.max_step_seconds = x
                .as_f64()
                .ok_or("max_step_seconds 必须是数字")?
                .clamp(60.0, 365.0 * 86_400.0);
        }
        if let Some(x) = obj.get("holdover_ppm") {
            self.holdover_ppm = x
                .as_f64()
                .ok_or("holdover_ppm 必须是数字")?
                .clamp(0.1, 1_000.0);
        }
        Ok(())
    }
}

fn discipline_config(cfg: &Config) -> DisciplineConfig {
    DisciplineConfig {
        makestep_threshold: Some(cfg.step_threshold_s),
        makestep_limit: 4,
        max_slew_ppm: 10_000.0,
        max_freq_ppm: 500.0,
        min_poll: cfg.min_poll_log2,
        max_poll: cfg.max_poll_log2,
        iburst: true,
        poll_up_streak: 3,
        max_change_s: Some(cfg.max_step_seconds),
        max_change_start: 5,
        max_change_ignore: 8,
        ..Default::default()
    }
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct ServerStatus {
    pub address: String,
    pub reachable: bool,
    pub offset_ms: f64,
    pub delay_ms: f64,
    pub dispersion_ms: f64,
    pub stratum: u8,
    pub leap: i8,
    pub samples: usize,
    pub last_ok_unix_s: f64,
    pub last_error: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct ProbeResult {
    pub address: String,
    pub ok: bool,
    pub offset_ms: f64,
    pub delay_ms: f64,
    pub stratum: u8,
    pub error: Option<String>,
}

/// Android GNSS 时间样本（对应 docs/android-gnss-time-calibration.md §5）。
#[derive(Clone, Debug)]
pub struct GnssSample {
    pub utc_ns: i64,
    pub mono_ns: u64,
    pub uncertainty_ns: i64,
    pub constellation: String,
    pub sv_count: u32,
    pub fix: String,
    pub leap_seconds: Option<i32>,
    pub source: String,
    pub clock_discontinuity: Option<u64>,
    pub age_ms: u64,
    /// Android 侧的对齐方式（诊断/跨设备判断）：`gnss_elapsed_realtime`、
    /// `callback_unbounded`、`rtt_aligned` 等。
    pub alignment: Option<String>,
    /// 跨设备时由接收端/传输层给出的一程延迟（ns）；同设备应为 None。
    pub transport_delay_ns: Option<i64>,
    pub transport_delay_uncertainty_ns: Option<i64>,
}

impl GnssSample {
    /// 从 `gnss_sample` 的 args 对象解析。诊断字段自动忽略。
    pub fn from_json(args: &Value) -> Result<Self, String> {
        let utc_ns = args
            .get("utc_ns")
            .and_then(Value::as_i64)
            .ok_or("缺少 utc_ns")?;
        let mono_ns = args
            .get("mono_ns")
            .and_then(Value::as_u64)
            .ok_or("缺少 mono_ns")?;
        let uncertainty_ns = args
            .get("uncertainty_ns")
            .and_then(Value::as_i64)
            .ok_or("缺少 uncertainty_ns")?;
        Ok(Self {
            utc_ns,
            mono_ns,
            uncertainty_ns,
            constellation: args
                .get("constellation")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string(),
            sv_count: args.get("sv_count").and_then(Value::as_u64).unwrap_or(0) as u32,
            fix: args
                .get("fix")
                .and_then(Value::as_str)
                .unwrap_or("none")
                .to_string(),
            leap_seconds: args
                .get("leap_seconds")
                .and_then(Value::as_i64)
                .map(|v| v as i32),
            source: args
                .get("source")
                .and_then(Value::as_str)
                .unwrap_or("raw")
                .to_string(),
            clock_discontinuity: args.get("clock_discontinuity").and_then(Value::as_u64),
            age_ms: args.get("age_ms").and_then(Value::as_u64).unwrap_or(0),
            alignment: args
                .get("alignment")
                .and_then(Value::as_str)
                .map(|s| s.to_string()),
            transport_delay_ns: args.get("transport_delay_ns").and_then(Value::as_i64),
            transport_delay_uncertainty_ns: args
                .get("transport_delay_uncertainty_ns")
                .and_then(Value::as_i64),
        })
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct GnssResult {
    pub accepted: bool,
    pub offset_ms: f64,
    pub rate_ppm: f64,
    pub uncertainty_ms: f64,
    pub reason: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct GnssStatus {
    pub last_utc_ns: i64,
    pub last_mono_ns: u64,
    pub uncertainty_ns: i64,
    pub age_ms: u64,
    pub constellation: String,
    pub sv_count: u32,
    pub fix: String,
    pub source: String,
    pub leap_seconds: Option<i32>,
    pub accepted: bool,
    pub offset_ms: f64,
    pub samples: u64,
    pub accepted_samples: u64,
    pub last_rx_unix_ns: i64,
    pub last_error: Option<String>,
    pub alignment: String,
    pub step_streak: u32,
}

struct Core {
    controller: MultiController,
    /// 卡尔曼滤波：偏移/频率/日老化/温度系数。时钟速率与步进决策以它为准；
    /// `controller` 的回归样本只用于每个源的 falseticker 预筛。
    kf: KalmanFilter,
    thermal: ThermalMonitor,
    /// KF 上次预测的单调时间（秒）。
    last_kf_mono_s: f64,
    /// 正在施加的 drain（有符号 ppm）；KF 预测会把它当作已知控制量。
    drain_ppm: f64,
    drain_end_mono_s: Option<f64>,
    temp_c: Option<f64>,
    /// 缓存的总频率修正（供状态/持久化快速读取）。
    baseline_ppm: f64,
    gnss: GnssStatus,
    gnss_last_discontinuity: Option<u64>,
    gnss_last_offset_s: Option<f64>,
    gnss_step_streak: u32,
    /// GNSS 作为权威源时，NTP 不再参与拨钟；过期后 NTP 才恢复。
    gnss_authoritative_until_mono_s: f64,
    /// 长基线频率/温度趋势，用于让 aging / temp_coeff 真正收敛。
    trend: TrendStore,
    servers: Vec<ServerStatus>,
    last_delay_s: Vec<f64>,
    last_dispersion_s: Vec<f64>,
    last_estimate: Vec<Option<Estimate>>,
    last_poll_s: f64,
    next_poll_mono_s: f64,
    last_round_unix_ns: i64,
    last_errors: Vec<String>,
    server_addrs: Vec<String>,
    built_with: (usize, i8, i8, f64, f64),
}

impl Core {
    fn new(cfg: &Config) -> Self {
        Self::new_with_kf(cfg, KalmanFilter::with_defaults(), None)
    }

    fn new_with_kf(cfg: &Config, kf: KalmanFilter, temp_c: Option<f64>) -> Self {
        let n = cfg.servers.len().max(1);
        Core {
            controller: MultiController::new(discipline_config(cfg), n),
            kf,
            thermal: ThermalMonitor::default(),
            last_kf_mono_s: xmc_time_base::mono::now_secs_f64(),
            drain_ppm: 0.0,
            drain_end_mono_s: None,
            temp_c,
            baseline_ppm: 0.0,
            gnss: GnssStatus::default(),
            gnss_last_discontinuity: None,
            gnss_last_offset_s: None,
            gnss_step_streak: 0,
            gnss_authoritative_until_mono_s: 0.0,
            trend: TrendStore::default(),
            servers: cfg
                .servers
                .iter()
                .map(|a| ServerStatus {
                    address: a.clone(),
                    ..Default::default()
                })
                .collect(),
            last_delay_s: vec![0.0; n],
            last_dispersion_s: vec![0.0; n],
            last_estimate: vec![None; n],
            last_poll_s: 0.0,
            next_poll_mono_s: 0.0,
            last_round_unix_ns: 0,
            last_errors: Vec::new(),
            server_addrs: cfg.servers.clone(),
            built_with: (
                cfg.servers.len().max(1),
                cfg.min_poll_log2,
                cfg.max_poll_log2,
                cfg.step_threshold_s,
                cfg.max_step_seconds,
            ),
        }
    }

    /// 当前温度（没有传感器时用 KF 参考温度）。
    fn temp(&self) -> f64 {
        self.temp_c.unwrap_or_else(|| self.kf.temp_ref_c())
    }

    /// 实际施加到应用时钟的总频率修正（ppm）。
    fn total_freq_ppm(&self) -> f64 {
        self.kf.total_freq_ppm(self.temp())
    }

    /// 把 KF 预测到 `now_s`，中途把已经结束的 drain 分段积分。
    fn predict_kf(&mut self, now_s: f64, temp_c: f64) {
        if self.last_kf_mono_s <= 0.0 {
            self.last_kf_mono_s = now_s;
            self.temp_c = Some(temp_c);
            return;
        }
        let dt = (now_s - self.last_kf_mono_s).max(0.0);
        if dt <= 0.0 {
            return;
        }
        if let Some(end) = self.drain_end_mono_s {
            if now_s > end {
                let d1 = (end - self.last_kf_mono_s).max(0.0);
                self.kf.predict_with_drain(d1, temp_c, self.drain_ppm);
                self.kf.predict((now_s - end).max(0.0), temp_c);
                self.drain_ppm = 0.0;
                self.drain_end_mono_s = None;
            } else {
                self.kf
                    .predict_with_drain(dt, temp_c, self.drain_ppm);
            }
        } else {
            self.kf.predict(dt, temp_c);
        }
        self.last_kf_mono_s = now_s;
        if self.temp_c.is_none() {
            self.kf.set_temp_ref(temp_c);
        }
        self.temp_c = Some(temp_c);
    }

    fn arm_drain(&mut self, drain_offset_s: f64, drain_rate_ppm: f64, now_s: f64) {
        if drain_offset_s.abs() > 1e-9 && drain_rate_ppm.abs() > 1e-9 {
            self.drain_ppm = drain_rate_ppm.copysign(drain_offset_s);
            let duration = drain_offset_s.abs() / (drain_rate_ppm.abs() * 1e-6);
            self.drain_end_mono_s = Some(now_s + duration);
        } else {
            self.drain_ppm = 0.0;
            self.drain_end_mono_s = None;
        }
    }

    fn clear_drain(&mut self) {
        self.drain_ppm = 0.0;
        self.drain_end_mono_s = None;
    }

    /// 记录一个长基线点，并在样本/跨度/温差足够时把 aging/temp_coeff 写回 KF。
    fn record_trend(&mut self, unix_s: i64, temp_c: f64) {
        let freq = self.kf.state().freq_ppm;
        self.trend.observe(unix_s, freq, Some(temp_c));
        let fit = self.trend.fit(self.kf.temp_ref_c());
        if fit.aging_ok {
            if let (Some(aging), Some(sd)) = (fit.aging_ppm_day, fit.aging_sd) {
                if sd.is_finite() && sd < self.kf.aging_sd_ppm_day() {
                    self.kf.set_aging(aging, sd);
                }
            }
        }
        if fit.temp_ok {
            if let (Some(coeff), Some(sd)) = (fit.temp_coeff_ppm_per_c, fit.temp_sd) {
                if sd.is_finite() && sd < self.kf.temp_coeff_sd() {
                    self.kf.set_temp_coeff(coeff, sd);
                }
            }
        }
    }

    fn trend_fit(&self) -> TrendFit {
        self.trend.fit(self.kf.temp_ref_c())
    }

    /// 重建前缓存当前总修正，供状态展示（真实状态在 KF 快照里）。
    fn rebase_baseline(&mut self) {
        self.baseline_ppm = self.total_freq_ppm();
    }

    fn needs_rebuild(&self, cfg: &Config) -> bool {
        self.server_addrs != cfg.servers
            || self.built_with
                != (
                    cfg.servers.len().max(1),
                    cfg.min_poll_log2,
                    cfg.max_poll_log2,
                    cfg.step_threshold_s,
                    cfg.max_step_seconds,
                )
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct AccuracyReport {
    pub ok: bool,
    pub synced: bool,
    pub source: String,
    /// 各可达服务器相对应用时钟的偏移中位数（ms）。
    pub median_offset_ms: f64,
    pub mean_offset_ms: f64,
    /// 各服务器偏移的极差（ms），反映路径/服务器之间的一致性。
    pub spread_ms: f64,
    /// 应用时钟 - 操作系统时钟（ms）。
    pub system_skew_ms: f64,
    pub uncertainty_ms: f64,
    pub servers: Vec<ProbeResult>,
}

#[derive(Clone, Debug, Serialize)]
pub struct KalmanStatus {
    pub offset_ms: f64,
    pub offset_sd_ms: f64,
    pub freq_ppm: f64,
    pub freq_sd_ppm: f64,
    pub aging_ppm_day: f64,
    pub aging_sd_ppm_day: f64,
    pub temp_coeff_ppm_per_c: f64,
    pub temp_coeff_sd: f64,
    pub temp_c: Option<f64>,
    pub temp_ref_c: f64,
}

#[derive(Clone, Debug, Serialize)]
pub struct Status {
    pub clock: ClockSnapshot,
    pub sync: SyncInfo,
    pub config: Config,
    pub servers: Vec<ServerStatus>,
    pub precision: PrecisionStats,
    pub samples: usize,
    pub freq_ppm: f64,
    pub poll_s: f64,
    pub total_syncs: u64,
    pub uptime_s: f64,
    pub next_poll_in_s: f64,
    pub holdover: bool,
    pub http_date_skew_ms: Option<i64>,
    /// 应用时钟 - 操作系统时钟（毫秒）。用于回答“比系统时间准多少”。
    pub system_skew_ms: f64,
    /// 当前实际施加的总频率修正（baseline + 纪律环残差）。
    pub baseline_ppm: f64,
    pub kalman: KalmanStatus,
    pub gnss: GnssStatus,
    pub trend: TrendFit,
    pub bridge: crate::gnss_bridge::BridgeStatus,
    pub errors: Vec<String>,
}

pub struct Service {
    pub clock: AppClock,
    config: RwLock<Config>,
    core: Mutex<Core>,
    round_lock: Mutex<()>,
    running: AtomicBool,
    stop: AtomicBool,
    thread: Mutex<Option<JoinHandle<()>>>,
    wake: Mutex<bool>,
    cv: Condvar,
    started_mono_ns: u64,
    total_syncs: AtomicU64,
    state_loaded: AtomicBool,
    /// `gnss_hello` 声明为跨设备时，后续样本必须提供 transport delay。
    gnss_external_axis: AtomicBool,
    http_date_skew_ms: Mutex<Option<i64>>,
    last_error: Mutex<Option<String>>,
}

impl Service {
    pub(crate) fn new() -> Self {
        let cfg = Config::default();
        let core = Core::new(&cfg);
        let clock = AppClock::new();
        Service {
            clock,
            config: RwLock::new(cfg),
            core: Mutex::new(core),
            round_lock: Mutex::new(()),
            running: AtomicBool::new(false),
            stop: AtomicBool::new(false),
            thread: Mutex::new(None),
            wake: Mutex::new(false),
            cv: Condvar::new(),
            started_mono_ns: xmc_time_base::mono::now_ns(),
            total_syncs: AtomicU64::new(0),
            state_loaded: AtomicBool::new(false),
            gnss_external_axis: AtomicBool::new(false),
            http_date_skew_ms: Mutex::new(None),
            last_error: Mutex::new(None),
        }
    }

    pub fn global() -> &'static Arc<Service> {
        static GLOBAL: OnceLock<Arc<Service>> = OnceLock::new();
        GLOBAL.get_or_init(|| Arc::new(Service::new()))
    }

    pub fn config(&self) -> Config {
        self.config.read().map(|c| c.clone()).unwrap_or_default()
    }

    pub fn configure(&self, args: &Value) -> Result<Config, String> {
        let mut cfg = self
            .config
            .write()
            .map_err(|_| "时间配置锁中毒".to_string())?;
        cfg.apply_json(args)?;
        let out = cfg.clone();
        drop(cfg);
        self.rebuild_if_needed();
        Ok(out)
    }

    /// 启动：应用配置、加载持久化状态、启动后台轮询。
    pub fn start(self: &Arc<Self>, args: &Value) -> Result<(), String> {
        let cfg = self.configure(args)?;
        if !self.state_loaded.swap(true, Ordering::SeqCst) {
            self.load_state(&cfg);
        }
        if cfg.auto_start && !cfg.servers.is_empty() {
            self.start_background();
        }
        Ok(())
    }

    fn load_state(&self, cfg: &Config) {
        let Some(path) = cfg.state_path.as_deref() else {
            return;
        };
        let existed = std::path::Path::new(path).exists();
        let Some(st) = state::load(path) else {
            if existed {
                // 锚点超前 >1 天/偏移异常/过期：state::load 已删除坏文件。
                // 清空历史锚点，回到“当前系统时间 + 重新 NTP 冷启动”。
                self.clock.reset_to_system();
                if let Ok(mut core) = self.core.lock() {
                    *core = Core::new(cfg);
                }
                self.set_error("时钟状态锚点损坏（超前系统时间 >1 天），已重置");
                self.request_sync();
            }
            return;
        };
        if self.clock.sync_info().synced {
            return;
        }
        // 恢复卡尔曼状态（频率/日老化/温度系数），偏移量单独由 holdover 恢复；
        // 时钟已经被对齐到应用时间，因此 KF 偏移状态清零。
        let mut kf = match st.kf.as_ref() {
            Some(snap) => KalmanFilter::new(
                KalmanConfig::default(),
                snap.state,
                snap.p_diag,
                snap.temp_ref_c,
            ),
            None => {
                let mut kf = KalmanFilter::with_defaults();
                kf.set_freq(st.last_freq_ppm.clamp(-MAX_BASELINE_PPM, MAX_BASELINE_PPM));
                kf
            }
        };
        kf.reset_offset();
        // 热启动的偏移可能已经错了数百毫秒；旧的 P00 往往极小，必须放大，
        // 否则第一帧 NTP/GNSS 的卡尔曼增益接近 0，永远拉不回来。
        kf.inflate_offset_variance(1.0);
        let temp = st.temp_c.unwrap_or_else(|| kf.temp_ref_c());
        let rate = kf.total_freq_ppm(temp);
        let mono_s = xmc_time_base::mono::now_secs_f64();
        if let Ok(mut core) = self.core.lock() {
            core.kf = kf;
            core.temp_c = Some(temp);
            core.last_kf_mono_s = mono_s;
            core.baseline_ppm = rate;
            core.trend.restore(st.trend.clone());
        }
        self.clock.slew(rate, 0.0, 0.0);
        self.clock.restore_holdover(
            st.offset_ns,
            st.uncertainty_ns,
            rate,
            st.stratum,
            &st.source,
            st.age_seconds(),
            cfg.holdover_ppm,
        );
    }

    /// 重建时保留卡尔曼状态，保证时钟速率/老化/温度模型连续。
    fn rebuild_core(&self, core: &mut Core, cfg: &Config) {
        core.rebase_baseline();
        let kf = core.kf.clone();
        let temp = core.temp_c;
        *core = Core::new_with_kf(cfg, kf, temp);
        core.last_kf_mono_s = xmc_time_base::mono::now_secs_f64();
        let rate = core.total_freq_ppm();
        core.baseline_ppm = rate;
        self.clock.slew(rate, 0.0, 0.0);
    }

    fn rebuild_if_needed(&self) {
        let cfg = self.config();
        if let Ok(mut core) = self.core.lock() {
            if core.needs_rebuild(&cfg) {
                self.rebuild_core(&mut core, &cfg);
            }
        }
        self.request_sync();
    }

    pub fn start_background(self: &Arc<Self>) {
        if self.running.swap(true, Ordering::SeqCst) {
            return;
        }
        self.stop.store(false, Ordering::SeqCst);
        let svc = Arc::clone(self);
        let handle = thread::Builder::new()
            .name("xmc-time-sync".to_string())
            .spawn(move || svc.run_loop());
        if let Ok(mut slot) = self.thread.lock() {
            *slot = handle.ok();
        }
    }

    pub fn stop(&self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Ok(mut w) = self.wake.lock() {
            *w = true;
        }
        self.cv.notify_all();
        let handle = self.thread.lock().ok().and_then(|mut g| g.take());
        if let Some(h) = handle {
            let _ = h.join();
        }
        self.running.store(false, Ordering::SeqCst);
        self.persist();
    }

    pub fn request_sync(&self) {
        if let Ok(mut w) = self.wake.lock() {
            *w = true;
        }
        self.cv.notify_all();
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }

    fn run_loop(self: Arc<Self>) {
        // 给 UI/数据库初始化让路，避免启动瞬间抢 DNS。
        thread::sleep(Duration::from_millis(350));
        loop {
            if self.stop.load(Ordering::SeqCst) {
                break;
            }
            let now_s = self.clock.mono_ns() as f64 * 1e-9;
            let next_poll = {
                let core = match self.core.lock() {
                    Ok(c) => c,
                    Err(p) => p.into_inner(),
                };
                core.next_poll_mono_s
            };
            let target = next_poll.max(now_s);
            let wait_s = (target - now_s).max(0.0);

            {
                let mut guard = match self.wake.lock() {
                    Ok(g) => g,
                    Err(p) => p.into_inner(),
                };
                if !*guard && wait_s > 0.001 {
                    let (g, _) = match self
                        .cv
                        .wait_timeout(guard, Duration::from_secs_f64(wait_s.min(60.0)))
                    {
                        Ok(v) => v,
                        Err(p) => p.into_inner(),
                    };
                    guard = g;
                }
                let woken = *guard;
                *guard = false;
                drop(guard);
                if self.stop.load(Ordering::SeqCst) {
                    break;
                }
                if woken {
                    // 配置变更/手动同步：立即跑一轮。
                    let cfg = self.config();
                    self.round(&cfg);
                    continue;
                }
            }

            let now_s = self.clock.mono_ns() as f64 * 1e-9;
            if now_s + 0.002 >= next_poll {
                let cfg = self.config();
                self.round(&cfg);
            }
        }
    }

    /// 执行一轮 NTP 交换 + 选择 + 纪律，返回距下一轮的秒数。
    pub fn round(&self, cfg: &Config) -> f64 {
        let _round_guard = match self.round_lock.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        if cfg.servers.is_empty() {
            self.set_error("没有配置 NTP 服务器");
            // 避免后台线程因为 next_poll 一直为 0 而空转。
            if let Ok(mut core) = self.core.lock() {
                core.next_poll_mono_s = self.clock.mono_ns() as f64 * 1e-9 + 30.0;
                core.last_errors = vec!["没有配置 NTP 服务器".to_string()];
            }
            return 30.0;
        }

        // 手机 GNSS 已建立权威：NTP 只保留服务器状态，不参与拨钟。
        {
            let mono_now_s = self.clock.mono_ns() as f64 * 1e-9;
            if let Ok(mut core) = self.core.lock() {
                if core.gnss_authoritative_until_mono_s > mono_now_s {
                    core.next_poll_mono_s = mono_now_s + 10.0;
                    core.last_errors = vec!["GNSS 权威源生效，NTP 暂停拨钟".to_string()];
                    return 10.0;
                }
            }
        }

        self.rebuild_if_needed_no_wake(cfg);

        let timeout = Duration::from_millis(cfg.timeout_ms.clamp(200, 10_000));
        let count = cfg.samples_per_poll.clamp(1, 5);
        let clock = &self.clock;
        let servers = &cfg.servers;
        let results: Vec<Burst> = thread::scope(|scope| {
            let mut handles = Vec::with_capacity(servers.len());
            for (idx, server) in servers.iter().enumerate() {
                let server = server.clone();
                handles.push((
                    idx,
                    scope.spawn(move || exchange_burst(&server, count, timeout, clock)),
                ));
            }
            let mut out: Vec<Option<Burst>> = (0..servers.len()).map(|_| None).collect();
            for (idx, h) in handles {
                out[idx] = Some(h.join().unwrap_or_else(|_| Burst {
                    address: servers
                        .get(idx)
                        .cloned()
                        .unwrap_or_else(|| "unknown".to_string()),
                    errors: vec!["NTP 工作线程崩溃".to_string()],
                    ..Default::default()
                }));
            }
            out.into_iter().flatten().collect()
        });

        let mono_now_s = self.clock.mono_ns() as f64 * 1e-9;
        let mut core = match self.core.lock() {
            Ok(c) => c,
            Err(p) => p.into_inner(),
        };

        // 服务器列表可能在 round 期间被改掉：数量或地址不一致就重建。
        if core.controller.sources() != results.len() || core.server_addrs != cfg.servers {
            self.rebuild_core(&mut core, cfg);
        }

        core.last_errors.clear();
        let mut sources: Vec<SourceEstimate> = Vec::new();
        let mut leap_pending = false;
        let mut round_samples = 0usize;

        for (i, burst) in results.iter().enumerate() {
            if burst.samples.is_empty() {
                core.servers[i].reachable = false;
                core.servers[i].last_error = burst.errors.last().cloned();
                core.last_errors.extend(burst.errors.iter().cloned());
                core.last_estimate[i] = None;
                continue;
            }
            core.servers[i].reachable = true;
            core.servers[i].last_error = burst.errors.last().cloned();
            if let Some(err) = burst.errors.last() {
                core.last_errors.push(err.clone());
            }
            for s in &burst.samples {
                update_server_status(&mut core.servers[i], s);
                core.servers[i].samples += 1;
                round_samples += 1;
                if s.leap == 1 || s.leap == 2 {
                    leap_pending = true;
                }
                core.last_delay_s[i] = s.delay_s;
                core.last_dispersion_s[i] = s.dispersion_s;
                let est = core.controller.observe(
                    i,
                    s.t_mono_s,
                    Sample {
                        t: s.t_mono_s,
                        offset: s.offset_s,
                        delay: s.delay_s,
                        dispersion: s.dispersion_s,
                    },
                );
                core.last_estimate[i] = Some(est);
            }
            if let Some(est) = core.last_estimate[i] {
                let rd = (core.last_delay_s[i] * 0.5 + core.last_dispersion_s[i]).max(1e-6);
                sources.push(SourceEstimate {
                    id: i,
                    offset: est.offset_s,
                    root_distance: rd,
                    stratum: core.servers[i].stratum,
                });
            }
        }

        let selection = select(&sources);
        let chosen = selection
            .truechimers
            .iter()
            .min_by(|a, b| {
                let ra = (core.last_delay_s[**a] * 0.5 + core.last_dispersion_s[**a]).max(1e-6);
                let rb = (core.last_delay_s[**b] * 0.5 + core.last_dispersion_s[**b]).max(1e-6);
                ra.total_cmp(&rb)
            })
            .copied()
            .or_else(|| {
                // 只有一个源可达时允许单源工作；多源但彼此矛盾时拒绝 steer。
                if sources.len() == 1 {
                    Some(sources[0].id)
                } else {
                    None
                }
            });

        core.last_round_unix_ns = self.clock.raw_now_ns();
        let mut interval;

        let Some(idx) = chosen else {
            let msg = if sources.is_empty() {
                core.last_errors
                    .first()
                    .cloned()
                    .unwrap_or_else(|| "所有 NTP 服务器都不可达".to_string())
            } else {
                format!(
                    "{} 个时间源无法达成一致，拒绝调整时钟",
                    sources.len()
                )
            };
            self.set_error(&msg);
            self.clock.mark_error(&msg);
            core.last_errors.push(msg);
            interval = core.controller.retry_interval_s().clamp(2.0, 60.0);
            core.next_poll_mono_s = mono_now_s + interval;
            return interval;
        };

        let est = core.last_estimate[idx].unwrap_or(Estimate {
            offset_s: 0.0,
            freq_ppm: None,
            sd_s: 1e-3,
            samples: 0,
        });
        // 温度：有传感器/外部注入就用它，否则沿用上次值/参考温度。
        let temp = core
            .thermal
            .sample(false)
            .or(core.temp_c)
            .unwrap_or_else(|| core.kf.temp_ref_c());
        core.temp_c = Some(temp);

        // KF 预测 + 用本源的 offset 观测更新；观测方差由中位偏移的 MAD、
        // RTT/2、root dispersion 与批量时间戳不确定度合成。
        core.predict_kf(mono_now_s, temp);
        let meas_var = est.sd_s * est.sd_s
            + (core.last_delay_s[idx] * 0.5).powi(2)
            + core.last_dispersion_s[idx].powi(2);
        if est.offset_s.abs() > 0.1 && core.kf.offset_sd_s() < est.offset_s.abs() * 0.1 {
            core.kf.inflate_offset_variance(est.offset_s * est.offset_s);
        }
        core.kf.update(est.offset_s, meas_var.max(1e-12));
        let trend_unix_s = self.clock.raw_now_ns() / 1_000_000_000;
        core.record_trend(trend_unix_s, temp);
        let kf_offset = core.kf.state().offset_s;
        let kf_sd = core.kf.offset_sd_s().max(25e-6);
        let rate = core.kf.total_freq_ppm(temp);
        core.baseline_ppm = rate;

        // 用 KF 的偏移/频率驱动纪律环的 step/drain 决策；freq 传 None，避免旧的
        // 回归频率再次累加。回归在本轮只作为每个源的预筛估计。
        let steer_est = Estimate {
            offset_s: kf_offset,
            freq_ppm: None,
            sd_s: kf_sd,
            samples: core.controller.samples(),
        };
        // 如果上一轮 drain 已经结束，先让纪律环结账，避免它把已经停下的
        // drain 继续记成“跑满整个间隔”（会污染它自己的 drain/poll 判断）。
        if let Some(end) = core.drain_end_mono_s {
            if mono_now_s >= end {
                let _ = core.controller.poll_drain(mono_now_s);
                core.clear_drain();
            }
        }
        let step = core.controller.steer(steer_est, mono_now_s, leap_pending);
        let accepted = matches!(step.verdict, ChangeVerdict::Accepted);
        match step.plan.command {
            ClockCommand::Step { add_seconds } => {
                self.clock.step(add_seconds);
                core.kf.correct_offset(add_seconds);
                core.clear_drain();
            }
            ClockCommand::Slew {
                drain_offset,
                drain_rate_ppm,
                ..
            } => {
                self.clock.slew(rate, drain_offset, drain_rate_ppm);
                if accepted {
                    core.arm_drain(drain_offset, drain_rate_ppm, mono_now_s);
                } else {
                    core.clear_drain();
                }
            }
        }
        core.controller.confirm_last_plan();

        let precision = if cfg.precision {
            precise::stats()
        } else {
            PrecisionStats::default()
        };
        let engine = if precision.available && precision.used {
            precision.engine
        } else {
            "zeitstempel"
        };

        if accepted {
            let uncertainty_s = kf_sd
                + core.last_delay_s[idx] * 0.5
                + core.last_dispersion_s[idx];
            self.clock.mark_synced(
                &core.servers[idx].address,
                core.servers[idx].stratum,
                core.servers[idx].leap,
                (uncertainty_s * 1e9) as i64,
                (kf_offset * 1e9) as i64,
                rate,
                step.plan.next_poll_s,
                core.controller.samples(),
                engine,
                leap_pending,
                cfg.holdover_ppm,
            );
            self.total_syncs.fetch_add(1, Ordering::Relaxed);
            self.clear_error();
        } else {
            let msg = match step.verdict {
                ChangeVerdict::Refused { offset_s, seen } => {
                    format!("偏移 {:.3}s 超过单次校正上限（第 {seen} 次拒绝）", offset_s)
                }
                ChangeVerdict::GiveUp { offset_s } => {
                    format!("偏移 {offset_s:.3}s 连续超限，已停止自动校正")
                }
                ChangeVerdict::Accepted => String::new(),
            };
            self.set_error(&msg);
            self.clock.mark_error(&msg);
            core.last_errors.push(msg);
        }

        core.last_poll_s = step.plan.next_poll_s.max(0.5);
        interval = core.last_poll_s.clamp(0.5, 3_600.0);
        if round_samples == 0 {
            interval = interval.min(15.0);
        }
        core.next_poll_mono_s = mono_now_s + interval;
        drop(core);

        self.persist();
        interval
    }

    fn rebuild_if_needed_no_wake(&self, cfg: &Config) {
        if let Ok(mut core) = self.core.lock() {
            if core.needs_rebuild(cfg) {
                self.rebuild_core(&mut core, cfg);
            }
        }
    }

    /// 同步执行一轮（FFI `sync`），返回最新状态。
    pub fn sync_now(&self) -> Status {
        let cfg = self.config();
        self.round(&cfg);
        self.status()
    }

    pub fn probe(&self) -> Vec<ProbeResult> {
        let cfg = self.config();
        let timeout = Duration::from_millis(cfg.timeout_ms.clamp(200, 10_000));
        let clock = &self.clock;
        let servers = cfg.servers;
        thread::scope(|scope| {
            let mut handles = Vec::new();
            for server in &servers {
                let server = server.clone();
                handles.push(scope.spawn(move || {
                    match query(&server, timeout, clock) {
                        Ok(s) => ProbeResult {
                            address: server,
                            ok: true,
                            offset_ms: s.offset_s * 1e3,
                            delay_ms: s.delay_s * 1e3,
                            stratum: s.stratum,
                            error: None,
                        },
                        Err(e) => ProbeResult {
                            address: server,
                            ok: false,
                            error: Some(e.message),
                            ..Default::default()
                        },
                    }
                }));
            }
            handles
                .into_iter()
                .map(|h| {
                    h.join().unwrap_or_else(|_| ProbeResult {
                        address: "unknown".to_string(),
                        error: Some("探测线程崩溃".to_string()),
                        ..Default::default()
                    })
                })
                .collect()
        })
    }

    /// 用同一组 NTP 服务器做一次“应用时钟 vs NTP 共识”的测量，不拨钟。
    ///
    /// 返回各服务器偏移的中位数/极差，以及应用时钟与系统时钟的差值——这是回答
    /// “比系统时间准多少”最直接的证据。
    pub fn accuracy(&self) -> AccuracyReport {
        let servers = self.probe();
        let mut offsets: Vec<f64> = servers
            .iter()
            .filter(|p| p.ok)
            .map(|p| p.offset_ms)
            .collect();
        offsets.sort_by(f64::total_cmp);
        let n = offsets.len();
        let (median, mean) = if n == 0 {
            (0.0, 0.0)
        } else {
            let median = if n % 2 == 1 {
                offsets[n / 2]
            } else {
                (offsets[n / 2 - 1] + offsets[n / 2]) * 0.5
            };
            (median, offsets.iter().sum::<f64>() / n as f64)
        };
        let spread = if n >= 2 {
            offsets[n - 1] - offsets[0]
        } else {
            0.0
        };
        let snap = self.clock.snapshot();
        AccuracyReport {
            ok: n > 0,
            synced: snap.synced,
            source: snap.source,
            median_offset_ms: median,
            mean_offset_ms: mean,
            spread_ms: spread,
            system_skew_ms: (self.clock.raw_now_ns()
                - xmc_time_base::mono::system_unix_ns()) as f64
                / 1e6,
            uncertainty_ms: snap.uncertainty_ns as f64 / 1e6,
            servers,
        }
    }

    pub fn status(&self) -> Status {
        let clock = self.clock.snapshot();
        let sync = self.clock.sync_info();
        let cfg = self.config();
        let precision = if cfg.precision {
            precise::stats()
        } else {
            PrecisionStats::default()
        };
        let (servers, samples, freq_ppm, baseline_ppm, poll_s, next_poll_in_s, errors, kalman, gnss, trend) = {
            let core = match self.core.lock() {
                Ok(c) => c,
                Err(p) => p.into_inner(),
            };
            let now_s = self.clock.mono_ns() as f64 * 1e-9;
            let samples = (0..core.controller.sources())
                .map(|i| core.controller.samples_from(i))
                .sum();
            let st = core.kf.state();
            let kalman = KalmanStatus {
                offset_ms: st.offset_s * 1e3,
                offset_sd_ms: core.kf.offset_sd_s() * 1e3,
                freq_ppm: st.freq_ppm,
                freq_sd_ppm: core.kf.freq_sd_ppm(),
                aging_ppm_day: st.aging_ppm_day,
                aging_sd_ppm_day: core.kf.aging_sd_ppm_day(),
                temp_coeff_ppm_per_c: st.temp_coeff_ppm_per_c,
                temp_coeff_sd: core.kf.temp_coeff_sd(),
                temp_c: core.temp_c,
                temp_ref_c: core.kf.temp_ref_c(),
            };
            (
                core.servers.clone(),
                samples,
                core.total_freq_ppm(),
                st.freq_ppm,
                core.last_poll_s,
                (core.next_poll_mono_s - now_s).max(0.0),
                core.last_errors.clone(),
                kalman,
                core.gnss.clone(),
                core.trend_fit(),
            )
        };
        let uptime_s = self
            .clock
            .mono_ns()
            .saturating_sub(self.started_mono_ns) as f64
            * 1e-9;
        let system_skew_ms = (self.clock.raw_now_ns() - xmc_time_base::mono::system_unix_ns())
            as f64
            / 1e6;
        Status {
            holdover: !clock.synced && sync.source != "system",
            clock,
            sync,
            config: cfg,
            servers,
            precision,
            samples,
            freq_ppm,
            poll_s,
            total_syncs: self.total_syncs.load(Ordering::Relaxed),
            uptime_s,
            next_poll_in_s,
            http_date_skew_ms: *self.http_date_skew_ms.lock().unwrap_or_else(|p| p.into_inner()),
            system_skew_ms,
            baseline_ppm,
            kalman,
            gnss,
            trend,
            bridge: crate::gnss_bridge::status(),
            errors,
        }
    }

    pub fn persist(&self) {
        let cfg = self.config();
        let Some(path) = cfg.state_path.as_deref() else {
            return;
        };
        let app = self.clock.raw_now_ns();
        let os = xmc_time_base::mono::system_unix_ns();
        if app.saturating_sub(os) > state::MAX_ANCHOR_AHEAD_NS {
            // 不把被污染的锚点写入磁盘；删除旧状态，等待 Force Re-anchor/重启。
            let _ = std::fs::remove_file(path);
            self.set_error("应用时钟比系统时间超前超过 1 天，已拒绝持久化");
            return;
        }
        let sync = self.clock.sync_info();
        let (total_freq, kf, temp_c, trend) = match self.core.lock() {
            Ok(c) => (
                c.total_freq_ppm(),
                Some(c.kf.snapshot()),
                c.temp_c,
                c.trend.points(),
            ),
            Err(p) => {
                let c = p.into_inner();
                (
                    c.total_freq_ppm(),
                    Some(c.kf.snapshot()),
                    c.temp_c,
                    c.trend.points(),
                )
            }
        };
        let st = PersistedState {
            version: STATE_VERSION,
            saved_at_unix_ns: app,
            saved_at_os_ns: os,
            offset_ns: app.saturating_sub(os),
            uncertainty_ns: sync.uncertainty_ns,
            last_sync_unix_ns: sync.last_sync_unix_ns,
            last_freq_ppm: total_freq,
            stratum: sync.stratum,
            source: sync.source.clone(),
            synced: sync.synced,
            total_syncs: self.total_syncs.load(Ordering::Relaxed),
            kf,
            temp_c,
            trend,
        };
        if let Err(e) = state::save(path, &st) {
            self.set_error(&e);
        }
    }

    /// 人工“强制重置时间基准”：无视防倒退/step 限制，直接硬切到 NTP 共识。
    pub fn force_reanchor(&self) -> Result<Status, String> {
        let probes = self.probe();
        let mut offsets: Vec<f64> = probes
            .iter()
            .filter(|p| p.ok)
            .map(|p| p.offset_ms)
            .collect();
        if offsets.is_empty() {
            return Err("没有可达的 NTP 服务器，无法 Force Re-anchor".to_string());
        }
        offsets.sort_by(f64::total_cmp);
        let n = offsets.len();
        let median_ms = if n % 2 == 1 {
            offsets[n / 2]
        } else {
            (offsets[n / 2 - 1] + offsets[n / 2]) / 2.0
        };
        let spread_ms = offsets[n - 1] - offsets[0];
        let stratum = probes
            .iter()
            .filter(|p| p.ok)
            .map(|p| p.stratum)
            .min()
            .unwrap_or(0);
        let offset_s = median_ms / 1e3;
        if !offset_s.is_finite() {
            return Err("NTP 共识偏移无效".to_string());
        }

        self.clock.force_step(offset_s);
        let engine = {
            let stats = precise::stats();
            if stats.available && stats.used {
                stats.engine
            } else {
                "zeitstempel"
            }
        };
        let cfg = self.config();
        let now_s = self.clock.mono_ns() as f64 * 1e-9;
        let (rate, uncertainty_s) = {
            let mut core = self.core.lock().unwrap_or_else(|p| p.into_inner());
            core.kf.reset_offset();
            core.last_kf_mono_s = now_s;
            core.clear_drain();
            core.baseline_ppm = core.total_freq_ppm();
            core.gnss_authoritative_until_mono_s = 0.0;
            core.gnss_step_streak = 0;
            core.gnss_last_offset_s = None;
            core.gnss.step_streak = 0;
            (
                core.baseline_ppm,
                (spread_ms / 2.0).max(1.0) / 1e3 + 0.005,
            )
        };
        self.clock.mark_synced(
            "manual:NTP共识",
            stratum,
            0,
            (uncertainty_s * 1e9) as i64,
            (offset_s * 1e9) as i64,
            rate,
            10.0,
            n,
            engine,
            false,
            cfg.holdover_ppm,
        );
        self.total_syncs.fetch_add(1, Ordering::Relaxed);
        self.clear_error();
        self.persist();
        Ok(self.status())
    }

    /// 外部注入温度（Windows/macOS 无稳定内核温度接口时由 Dart 提供）。
    pub fn set_temperature(&self, celsius: f64) -> bool {
        if !celsius.is_finite() || !(-40.0..=150.0).contains(&celsius) {
            return false;
        }
        if let Ok(mut core) = self.core.lock() {
            core.thermal.inject(celsius);
            core.temp_c = Some(celsius);
        }
        true
    }

    /// GNSS 采集端握手。返回接收端的时间轴要求。
    pub fn gnss_hello(&self, protocol: i64, external_axis: bool) -> Result<serde_json::Value, String> {
        if protocol != 1 {
            return Err(format!("不支持的 gnss 协议版本: {protocol}"));
        }
        self.gnss_external_axis
            .store(external_axis, Ordering::SeqCst);
        Ok(json!({
            "accepted": true,
            "protocol": 1,
            "mono_axis_scope": "device_boot",
            "external_axis_mapping": if external_axis { "required" } else { "same_process" },
            "cross_device_requires_transport_delay_ns": true,
        }))
    }

    /// Android GPS/北斗时间样本入口。
    ///
    /// 与 NTP 路径共用同一个卡尔曼滤波，但 GNSS 通常有更小的观测方差，会被自动
    /// 赋予更高权重。校验/拒收规则见 docs/android-gnss-time-calibration.md §5.1。
    pub fn ingest_gnss(&self, sample: GnssSample) -> GnssResult {
        let cfg = self.config();
        let now_mono_ns = self.clock.mono_ns();
        let now_s = now_mono_ns as f64 * 1e-9;
        let app_now = self.clock.raw_now_ns();
        let engine = {
            let stats = precise::stats();
            if stats.available && stats.used {
                stats.engine
            } else {
                "zeitstempel"
            }
        };
        let mut core = match self.core.lock() {
            Ok(c) => c,
            Err(p) => p.into_inner(),
        };

        core.gnss.samples += 1;
        core.gnss.last_rx_unix_ns = app_now;
        core.gnss.last_utc_ns = sample.utc_ns;
        core.gnss.last_mono_ns = sample.mono_ns;
        core.gnss.uncertainty_ns = sample.uncertainty_ns;
        core.gnss.age_ms = sample.age_ms;
        core.gnss.constellation = sample.constellation.clone();
        core.gnss.sv_count = sample.sv_count;
        core.gnss.fix = sample.fix.clone();
        core.gnss.source = sample.source.clone();
        core.gnss.leap_seconds = sample.leap_seconds;
        core.gnss.accepted = false;

        // 1) UTC 范围
        const MIN_UTC_NS: i64 = 1_577_836_800_000_000_000; // 2020
        const MAX_UTC_NS: i64 = 7_258_118_400_000_000_000; // 2200
        if !(MIN_UTC_NS..=MAX_UTC_NS).contains(&sample.utc_ns) {
            return gnss_reject(&mut core, "utc_ns 超出 2020~2200 合理范围");
        }
        // 2) 时间轴：同设备 BOOTTIME 可直接对齐；跨设备必须给出传输延迟。
        // `gnss_hello` 已声明 external 轴时，不再用“差 ≤2s”猜测同轴。
        let age_ns = now_mono_ns as i128 - sample.mono_ns as i128;
        let external_axis = self.gnss_external_axis.load(Ordering::SeqCst);
        let same_axis = !external_axis && age_ns.abs() <= 2_000_000_000;
        if !same_axis && sample.transport_delay_ns.is_none() {
            return gnss_reject(
                &mut core,
                "mono_ns 跨设备不同源且缺少 transport_delay_ns",
            );
        }
        if sample.age_ms > 2_000 {
            return gnss_reject(&mut core, "样本年龄超过 2s");
        }
        // 3) 不确定度：100ns ~ 50ms
        if sample.uncertainty_ns < 100 || sample.uncertainty_ns > 50_000_000 {
            return gnss_reject(&mut core, "uncertainty_ns 不在 100ns~50ms 范围");
        }
        // 4) 时钟跳变
        if let Some(disc) = sample.clock_discontinuity {
            if let Some(last) = core.gnss_last_discontinuity {
                if disc != last {
                    core.gnss_last_discontinuity = Some(disc);
                    return gnss_reject(&mut core, "GnssClock discontinuity 发生变化，丢弃本帧");
                }
            } else {
                core.gnss_last_discontinuity = Some(disc);
            }
        }
        // 5) fix / 卫星数
        let fix = sample.fix.to_ascii_lowercase();
        if fix == "none" || fix.is_empty() {
            return gnss_reject(&mut core, "无有效 fix");
        }
        if sample.sv_count < 3 {
            return gnss_reject(&mut core, "参与解算卫星数 <3");
        }
        let mut variance_scale = if same_axis { 1.0 } else { 100.0 };
        if fix != "3d" {
            variance_scale *= 10.0; // 2D fix 高度未知，时间仍可用但降权
        }
        if sample.sv_count < 5 {
            variance_scale *= 10.0;
        }

        // 6) 对齐应用时钟，计算 offset。
        // 同设备：使用样本自带的 mono；跨设备：用本机到达时刻 + 传输延迟换算，
        // 且默认降权（没有 RTT 对消时 Wi-Fi 抖动会主导）。
        let (effective_utc_ns, app_at_sample, alignment) = if same_axis {
            (
                sample.utc_ns as i128,
                self.clock.raw_at(sample.mono_ns),
                sample
                    .alignment
                    .clone()
                    .unwrap_or_else(|| "same_process".to_string()),
            )
        } else {
            let delay_ns = sample.transport_delay_ns.unwrap_or(0) as i128;
            if !(-500_000_000..=2_000_000_000).contains(&delay_ns) {
                return gnss_reject(&mut core, "transport_delay_ns 不在 -0.5s~2s 合理范围");
            }
            // utc_ns 是测量时刻；跨设备还要加“测量→送达”的手机年龄、
            // 本机到达时刻差和单程传输延迟。桥接端已把 mono_ns 改成
            // 本机到达时刻，所以 age_ns≈0，age_ms 不能丢。
            (
                sample.utc_ns as i128
                    + age_ns
                    + (sample.age_ms as i128 * 1_000_000)
                    + delay_ns,
                self.clock.raw_at(now_mono_ns),
                sample
                    .alignment
                    .as_ref()
                    .map(|a| format!("cross_device_transport({a})"))
                    .unwrap_or_else(|| "cross_device_transport".to_string()),
            )
        };
        core.gnss.alignment = alignment.clone();
        let offset_s = (effective_utc_ns - app_at_sample as i128) as f64 / 1e9;
        if !offset_s.is_finite() || offset_s.abs() > cfg.max_step_seconds {
            return gnss_reject(&mut core, "GNSS 偏移超过单次校正上限");
        }

        // 7) 卡尔曼预测 + GNSS 观测更新
        let temp = core
            .thermal
            .sample(false)
            .or(core.temp_c)
            .unwrap_or_else(|| core.kf.temp_ref_c());
        core.temp_c = Some(temp);
        core.predict_kf(now_s, temp);
        let age_s = if same_axis {
            age_ns.unsigned_abs() as f64 * 1e-9
        } else {
            0.0
        };
        // 大偏移 + 极小 P00 时先放大偏移方差，否则卡尔曼几乎不动。
        if offset_s.abs() > 0.1 && core.kf.offset_sd_s() < offset_s.abs() * 0.1 {
            core.kf.inflate_offset_variance(offset_s * offset_s);
        }
        let mut gnss_var = (sample.uncertainty_ns as f64 * 1e-9).powi(2) * variance_scale
            + age_s * age_s
            + (sample.age_ms as f64 * 1e-3).powi(2);
        if !same_axis {
            let delay_unc = sample
                .transport_delay_uncertainty_ns
                .unwrap_or(5_000_000)
                .max(100_000) as f64
                * 1e-9;
            gnss_var += delay_unc * delay_unc;
        }
        core.kf.update(offset_s, gnss_var.max(1e-18));
        let trend_unix_s = self.clock.raw_now_ns() / 1_000_000_000;
        core.record_trend(trend_unix_s, temp);

        let kf_offset = core.kf.state().offset_s;
        let kf_sd = core.kf.offset_sd_s().max(25e-6);
        let rate = core.kf.total_freq_ppm(temp);
        core.baseline_ppm = rate;

        // 连续 3 帧一致才允许 step（上游 Android 文档 §5.1 第 8 条）。
        let consistent = match core.gnss_last_offset_s {
            Some(last) => {
                (offset_s - last).abs()
                    <= (sample.uncertainty_ns as f64 * 3e-9).max(1e-3)
            }
            None => false,
        };
        core.gnss_step_streak = if consistent {
            core.gnss_step_streak.saturating_add(1)
        } else {
            1
        };
        core.gnss_last_offset_s = Some(offset_s);
        core.gnss.step_streak = core.gnss_step_streak;
        let may_step = core.gnss_step_streak >= 3
            // 手机 GNSS 是权威源：第一帧、或偏差 >50ms 时立即硬切，
            // 不再等 3 帧，也不让残余 drain 长时间停在百毫秒级。
            || core.gnss.accepted_samples == 0
            || offset_s.abs() > 0.05;
        let immediate = core.gnss.accepted_samples == 0 || offset_s.abs() > 0.05;
        // 用“本帧实测偏移”和 KF 偏移中较大的那个做 step 判断：
        // 前两帧的 drain 可能已经把 KF 偏移拉回阈值以内，但实际时钟仍差
        // 几百毫秒；只看 KF 会导致一直慢慢 drain，偏移均值长时间停在 -700ms。
        let step_offset = if offset_s.abs() > kf_offset.abs() {
            offset_s
        } else {
            kf_offset
        };

        if step_offset.abs() >= if immediate { 0.05 } else { cfg.step_threshold_s } && may_step {
            if immediate {
                // 无视 high_water 的向后冻结，直接切到手机 GNSS。
                self.clock.force_step(step_offset);
            } else {
                self.clock.step(step_offset);
            }
            core.kf.correct_offset(step_offset);
            core.clear_drain();
            core.gnss_step_streak = 0;
            core.gnss_last_offset_s = None;
            core.gnss.step_streak = 0;
        } else {
            // GNSS 残差通常很小：1 秒内消化完，速率上限 5%。
            let drain_rate = ((kf_offset.abs() / 1.0) * 1e6).clamp(100.0, 50_000.0);
            self.clock.slew(rate, kf_offset, drain_rate);
            core.arm_drain(kf_offset, drain_rate, now_s);
        }

        let uncertainty_s = kf_sd + sample.uncertainty_ns as f64 * 1e-9 + age_s;
        self.clock.mark_synced(
            &format!("gnss:{}", sample.constellation),
            0, // GNSS 作为本地 stratum-0 参考
            0,
            (uncertainty_s * 1e9) as i64,
            (offset_s * 1e9) as i64,
            rate,
            1.0,
            1,
            engine,
            false,
            cfg.holdover_ppm,
        );
        self.total_syncs.fetch_add(1, Ordering::Relaxed);
        core.gnss.accepted = true;
        core.gnss.accepted_samples += 1;
        core.gnss.offset_ms = offset_s * 1e3;
        core.gnss.last_error = None;
        // 手机连续供数期间，NTP 不再抢方向盘；断开 5 分钟后才恢复。
        core.gnss_authoritative_until_mono_s = now_s + 300.0;
        // GNSS 可能 1Hz 上报；不要每帧都写盘（Android 闪存寿命）。
        let should_persist = core.gnss.accepted_samples % 60 == 1;
        self.clear_error();
        drop(core);
        if should_persist {
            self.persist();
        }
        GnssResult {
            accepted: true,
            offset_ms: offset_s * 1e3,
            rate_ppm: rate,
            uncertainty_ms: uncertainty_s * 1e3,
            reason: None,
        }
    }

    /// HTTPS 的 `Date` 响应头只作为偏差诊断，绝不直接拨钟。
    pub fn note_http_date(&self, server_unix_s: i64, rtt_ms: i64) -> i64 {
        let local_s = self.clock.raw_now_ns() / 1_000_000_000;
        // Date 头只有 1 秒粒度，按 RTT 的一半做粗略中点修正。
        let skew_ms = (server_unix_s - local_s) * 1_000 - rtt_ms / 2;
        if let Ok(mut g) = self.http_date_skew_ms.lock() {
            *g = Some(skew_ms);
        }
        skew_ms
    }

    pub fn reset(&self) {
        self.clock.reset_to_system();
        self.gnss_external_axis.store(false, Ordering::SeqCst);
        let cfg = self.config();
        if let Ok(mut core) = self.core.lock() {
            *core = Core::new(&cfg);
        }
        if let Some(path) = cfg.state_path.as_deref() {
            let _ = std::fs::remove_file(path);
        }
        self.total_syncs.store(0, Ordering::Relaxed);
        self.clear_error();
    }

    fn set_error(&self, msg: &str) {
        if let Ok(mut g) = self.last_error.lock() {
            *g = Some(msg.to_string());
        }
    }

    fn clear_error(&self) {
        if let Ok(mut g) = self.last_error.lock() {
            *g = None;
        }
    }

    pub fn last_error(&self) -> Option<String> {
        self.last_error
            .lock()
            .ok()
            .and_then(|g| g.clone())
    }
}

fn gnss_reject(core: &mut Core, reason: impl Into<String>) -> GnssResult {
    let reason = reason.into();
    core.gnss.accepted = false;
    core.gnss.last_error = Some(reason.clone());
    GnssResult {
        accepted: false,
        offset_ms: core.gnss.offset_ms,
        rate_ppm: 0.0,
        uncertainty_ms: core.gnss.uncertainty_ns as f64 / 1e6,
        reason: Some(reason),
    }
}

fn update_server_status(status: &mut ServerStatus, s: &NtpSample) {
    status.offset_ms = s.offset_s * 1e3;
    status.delay_ms = s.delay_s * 1e3;
    status.dispersion_ms = s.dispersion_s * 1e3;
    status.stratum = s.stratum;
    status.leap = s.leap;
    status.last_ok_unix_s = s.server_unix_s;
}

/// 供 FFI 的 `now` 使用。
pub fn now_json(service: &Service) -> Value {
    let snap = service.clock.snapshot();
    let unix_ms = snap.unix_ns.div_euclid(1_000_000);
    json!({
        "unix_ns": snap.unix_ns,
        "unix_ms": unix_ms,
        "unix_s": snap.unix_ns.div_euclid(1_000_000_000),
        "mono_ns": snap.mono_ns,
        "iso8601": xmc_time_base::civil::format_iso8601_ms(unix_ms),
        "iso8601_us": xmc_time_base::civil::format_iso8601_us(snap.unix_ns.div_euclid(1_000)),
        "http_date": xmc_time_base::httpdate::format_http_date(snap.unix_ns.div_euclid(1_000_000_000)),
        "uncertainty_ns": snap.uncertainty_ns,
        "synced": snap.synced,
        "locked": snap.locked,
        "source": snap.source,
        "stratum": snap.stratum,
        "leap": snap.leap,
        "generation": snap.generation,
        "frozen": snap.frozen,
        "rate_ppm": snap.rate_ppm,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::UdpSocket;
    use std::sync::atomic::AtomicBool;

    fn spawn_mock(offset_s: f64) -> (String, Arc<AtomicBool>) {
        let socket = UdpSocket::bind("127.0.0.1:0").unwrap();
        let addr = socket.local_addr().unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let stop2 = Arc::clone(&stop);
        thread::spawn(move || {
            socket.set_read_timeout(Some(Duration::from_millis(200))).ok();
            let mut buf = [0u8; 1024];
            while !stop2.load(Ordering::Relaxed) {
                let Ok((len, peer)) = socket.recv_from(&mut buf) else {
                    continue;
                };
                let Ok(req) = rusty_time_core::ntp::NtpPacket::parse(&buf[..len]) else {
                    continue;
                };
                let now = xmc_time_base::mono::system_unix_ns() as f64 / 1e9 + offset_s;
                let secs = now.floor() as i64;
                let nanos = ((now - secs as f64) * 1e9) as u32;
                let ts = rusty_time_core::ntp::NtpTimestamp::from_unix(secs, nanos);
                let mut resp = rusty_time_core::ntp::NtpPacket::client_request(4, req.transmit_ts);
                resp.mode = rusty_time_core::ntp::Mode::Server;
                resp.origin_ts = req.transmit_ts;
                resp.receive_ts = ts;
                resp.transmit_ts = ts;
                resp.stratum = 2;
                resp.precision = -20;
                let _ = socket.send_to(&resp.to_bytes(), peer);
            }
        });
        (addr.to_string(), stop)
    }

    #[test]
    fn service_syncs_and_steps() {
        let (addr, stop) = spawn_mock(3.0);
        let svc = Service::new();
        let cfg = Config {
            servers: vec![addr],
            samples_per_poll: 2,
            timeout_ms: 800,
            state_path: None,
            auto_start: false,
            ..Default::default()
        };
        let before = svc.clock.raw_now_ns();
        svc.round(&cfg);
        let after = svc.clock.raw_now_ns();
        let delta = (after - before) as f64 / 1e9;
        assert!((delta - 3.0).abs() < 0.2, "clock moved {delta}s, expected ~3s");
        let snap = svc.clock.snapshot();
        assert!(snap.synced);
        assert!(snap.uncertainty_ns < 100_000_000);
        stop.store(true, Ordering::Relaxed);
    }

    #[test]
    fn service_rejects_unreachable_servers() {
        let svc = Service::new();
        let cfg = Config {
            servers: vec!["127.0.0.1:9".to_string()],
            samples_per_poll: 1,
            timeout_ms: 200,
            state_path: None,
            auto_start: false,
            ..Default::default()
        };
        svc.round(&cfg);
        assert!(!svc.clock.snapshot().synced);
        assert!(svc.last_error().is_some());
    }

    #[test]
    fn kalman_frequency_drives_clock_rate() {
        let svc = Service::new();
        let rate = {
            let mut core = svc.core.lock().unwrap();
            core.kf.set_temp_ref(25.0);
            core.kf.set_freq(25.0);
            core.temp_c = Some(25.0);
            core.total_freq_ppm()
        };
        svc.clock.slew(rate, 0.0, 0.0);
        assert!((svc.clock.rate_ppm() - 25.0).abs() < 1e-6);
    }

    #[test]
    fn persisted_kalman_state_survives_restart() {
        let dir = std::env::temp_dir().join(format!(
            "xmc_time_freq_restart_{}",
            xmc_time_base::mono::now_ns()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.json").to_string_lossy().to_string();

        let svc = Arc::new(Service::new());
        svc.configure(&json!({ "state_path": path, "auto_start": false }))
            .unwrap();
        {
            let mut core = svc.core.lock().unwrap();
            core.kf.set_temp_ref(25.0);
            core.kf.set_freq(25.0);
            core.temp_c = Some(25.0);
            core.baseline_ppm = 25.0;
        }
        svc.persist();
        let st = state::load(&path).expect("state");
        assert!((st.last_freq_ppm - 25.0).abs() < 1e-6, "{}", st.last_freq_ppm);
        assert!(st.kf.is_some());

        let svc2 = Arc::new(Service::new());
        svc2.start(&json!({ "state_path": path, "auto_start": false }))
            .unwrap();
        assert!((svc2.clock.rate_ppm() - 25.0).abs() < 1e-6);
        let core = svc2.core.lock().unwrap();
        assert!((core.kf.state().freq_ppm - 25.0).abs() < 1e-6);
        drop(core);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn holdover_ppm_is_configurable() {
        let mut cfg = Config::default();
        cfg.apply_json(&json!({ "holdover_ppm": 5.0 })).unwrap();
        assert!((cfg.holdover_ppm - 5.0).abs() < 1e-9);
        cfg.apply_json(&json!({ "holdover_ppm": 10_000.0 }))
            .unwrap();
        assert!((cfg.holdover_ppm - 1_000.0).abs() < 1e-9);
    }

    fn gnss(utc_ns: i64, mono_ns: u64, uncertainty_ns: i64, sv_count: u32, fix: &str, delay: Option<i64>) -> GnssSample {
        GnssSample {
            utc_ns,
            mono_ns,
            uncertainty_ns,
            constellation: "gps".to_string(),
            sv_count,
            fix: fix.to_string(),
            leap_seconds: Some(18),
            source: "raw".to_string(),
            clock_discontinuity: None,
            age_ms: 0,
            alignment: Some("gnss_elapsed_realtime".to_string()),
            transport_delay_ns: delay,
            transport_delay_uncertainty_ns: delay.map(|_| 500_000),
        }
    }

    #[test]
    fn gnss_first_trusted_frame_steps_immediately() {
        let svc = Service::new();
        let before = svc.clock.raw_now_ns();
        let target = before + 2_000_000_000;
        let mut accepted = false;
        for _ in 0..3 {
            let mono = svc.clock.mono_ns();
            let result = svc.ingest_gnss(gnss(target, mono, 500, 12, "3d", None));
            accepted = result.accepted;
        }
        let after = svc.clock.raw_now_ns();
        assert!(accepted);
        assert!(
            ((after - before) as f64 / 1e9 - 2.0).abs() < 0.2,
            "clock moved {}s",
            (after - before) as f64 / 1e9
        );
        let sync = svc.clock.sync_info();
        assert!(sync.synced);
        assert!(sync.source.contains("gnss"), "{}", sync.source);
        let status = svc.status();
        assert!(status.gnss.accepted);
        assert_eq!(status.gnss.accepted_samples, 3);
        assert_eq!(status.gnss.constellation, "gps");
        assert!(status.gnss.step_streak <= 2);
    }

    #[test]
    fn gnss_cross_device_requires_transport_delay() {
        let svc = Service::new();
        let mono = svc.clock.mono_ns();
        let app = svc.clock.raw_at(mono);
        let old_mono = mono.saturating_sub(5_000_000_000);
        let age = (mono - old_mono) as i64;
        if age <= 3_000_000_000 {
            return; // 机器 uptime <5s，无法构造跨设备样本
        }
        let utc_at_measurement = app - age;
        let without_delay = svc.ingest_gnss(gnss(
            utc_at_measurement,
            old_mono,
            2_000_000,
            12,
            "3d",
            None,
        ));
        assert!(!without_delay.accepted);
        let with_delay = svc.ingest_gnss(gnss(
            utc_at_measurement,
            old_mono,
            2_000_000,
            12,
            "3d",
            Some(0),
        ));
        assert!(with_delay.accepted, "{with_delay:?}");
        assert!(svc.status().gnss.alignment.starts_with("cross_device_transport"));
    }

    #[test]
    fn gnss_cross_device_adds_sample_age() {
        let svc = Service::new();
        svc.gnss_hello(1, true).unwrap();
        let mono = svc.clock.mono_ns();
        let app = svc.clock.raw_at(mono);
        // 测量发生在 500ms 前；桥接端把 mono 改成“本机到达时刻”，age_ms 保留。
        let age_ms = 500i64;
        let utc_at_measurement = app - age_ms * 1_000_000;
        let mut sample = gnss(utc_at_measurement, mono, 2_000_000, 12, "3d", Some(0));
        sample.age_ms = age_ms as u64;
        sample.mono_ns = mono;
        let result = svc.ingest_gnss(sample);
        assert!(result.accepted, "{result:?}");
        assert!(result.offset_ms.abs() < 10.0, "{result:?}");
    }

    #[test]
    fn gnss_rejects_bad_samples() {
        let svc = Service::new();
        let mono = svc.clock.mono_ns();
        let utc = xmc_time_base::mono::system_unix_ns();
        // 未来 10s 的 mono：跨设备且无 transport_delay → 拒绝
        assert!(!svc
            .ingest_gnss(gnss(utc, mono.saturating_add(10_000_000_000), 500, 12, "3d", None))
            .accepted);
        // 不确定度超上限
        assert!(!svc
            .ingest_gnss(gnss(utc, mono, 1_000_000_000, 12, "3d", None))
            .accepted);
        // 卫星数不足
        assert!(!svc
            .ingest_gnss(gnss(utc, mono, 500, 2, "2d", None))
            .accepted);
    }

    #[test]
    fn force_reanchor_steps_to_ntp_consensus() {
        let (addr, stop) = spawn_mock(3.0);
        let svc = Service::new();
        svc.configure(&json!({
            "servers": [addr],
            "samples_per_poll": 1,
            "timeout_ms": 500,
            "auto_start": false
        }))
        .unwrap();
        let before = svc.clock.raw_now_ns();
        let status = svc.force_reanchor().unwrap();
        let after = svc.clock.raw_now_ns();
        stop.store(true, Ordering::Relaxed);
        assert!(
            ((after - before) as f64 / 1e9 - 3.0).abs() < 0.2,
            "clock moved {}s",
            (after - before) as f64 / 1e9
        );
        assert!(status.sync.source.contains("manual"), "{}", status.sync.source);
        assert!(status.clock.synced);
    }
}
