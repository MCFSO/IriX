//! 应用时钟：把单调时钟映射成 UTC 纳秒，并承载 NTP 纪律命令。
//!
//! 模型：
//!
//! ```text
//! app_time(mono) = anchor_unix + (mono - anchor_mono) * (1 + rate_ppm*1e-6)
//!                  + drain(mono)
//! ```
//!
//! - `rate_ppm` 是 rusty_time 纪律环计算出的 **绝对频率修正**（正 = 本机时钟慢，
//!   需要走快）；
//! - `drain` 是“在限定时间内消化掉残余偏移”的临时速率，预算用尽即停，不会过冲；
//! - 每次改速率/步进前先 `rebase`，把已经走过的修正固化进锚点，保证时间连续；
//! - `high_water` 提供进程内单调性保证：向后步进时输出会短暂冻结（最多 5 秒），
//!   超过 5 秒的向后跳变则如实回退，避免应用被“冻死”；
//! - 不确定度 = 上次同步误差 + 保持（holdover）漂移预算，随断网时间线性增长。

use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::RwLock;

use serde::Serialize;

use crate::precise;

pub const NS_PER_SEC: i64 = 1_000_000_000;
/// 向后步进时最多冻结多久；超过则允许时间回退（并记录 backward_jump）。
const MAX_FREEZE_NS: i64 = 5 * NS_PER_SEC;
/// 频率修正的安全上限（±500ppm），防止坏样本把时间拉飞。
const MAX_RATE_PPM: f64 = 500.0;
/// 同步后默认的保持漂移预算（晶振温漂 + 老化）。
pub const DEFAULT_HOLDOVER_PPM: f64 = 15.0;

#[derive(Clone, Debug, Serialize)]
pub struct ClockSnapshot {
    pub unix_ns: i64,
    pub mono_ns: u64,
    pub uncertainty_ns: i64,
    pub synced: bool,
    pub locked: bool,
    pub source: String,
    pub stratum: u8,
    pub leap: i8,
    pub generation: u64,
    pub frozen: bool,
    pub rate_ppm: f64,
    pub total_steps: u64,
    pub backward_jumps: u64,
}

#[derive(Clone, Debug, Serialize)]
pub struct SyncInfo {
    pub synced: bool,
    pub source: String,
    pub stratum: u8,
    pub leap: i8,
    pub last_sync_unix_ns: i64,
    pub last_sync_mono_ns: u64,
    pub uncertainty_ns: i64,
    pub holdover_ppm: f64,
    pub offset_ns: i64,
    pub freq_ppm: f64,
    pub poll_s: f64,
    pub samples: usize,
    pub precision: String,
    pub leap_pending: bool,
    pub last_error: Option<String>,
}

impl Default for SyncInfo {
    fn default() -> Self {
        SyncInfo {
            synced: false,
            source: "system".to_string(),
            stratum: 16,
            leap: 3,
            last_sync_unix_ns: 0,
            last_sync_mono_ns: 0,
            uncertainty_ns: 250_000_000, // 未同步时按 250ms 处理
            holdover_ppm: DEFAULT_HOLDOVER_PPM,
            offset_ns: 0,
            freq_ppm: 0.0,
            poll_s: 0.0,
            samples: 0,
            precision: "zeitstempel".to_string(),
            leap_pending: false,
            last_error: None,
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct Drain {
    start_mono_ns: u64,
    total_ns: i64,
    rate_ppm: f64,
}

struct Inner {
    anchor_mono_ns: u64,
    anchor_unix_ns: i64,
    rate_ppm: f64,
    drain: Option<Drain>,
    sync: SyncInfo,
    total_steps: u64,
    backward_jumps: u64,
}

impl Inner {
    fn value_at(&self, mono: u64) -> i64 {
        let dt = mono.saturating_sub(self.anchor_mono_ns) as f64;
        let rate = 1.0 + self.rate_ppm * 1e-6;
        let mut v = self.anchor_unix_ns as i128 + (dt * rate).round() as i128;
        if let Some(d) = self.drain {
            let elapsed = mono.saturating_sub(d.start_mono_ns) as f64;
            let amount = (elapsed * d.rate_ppm * 1e-6).min(d.total_ns.unsigned_abs() as f64);
            v += i128::from(d.total_ns.signum()) * amount.round() as i128;
        }
        clamp_i64(v)
    }

    fn rebase(&mut self, mono: u64) {
        let v = self.value_at(mono);
        self.anchor_unix_ns = v;
        self.anchor_mono_ns = mono;
        self.drain = None;
    }

    fn uncertainty_at(&self, mono: u64) -> i64 {
        if !self.sync.synced {
            return self.sync.uncertainty_ns.max(250_000_000);
        }
        let age = mono.saturating_sub(self.sync.last_sync_mono_ns) as f64;
        let growth = self.sync.holdover_ppm * 1e-6 * age;
        let v = self.sync.uncertainty_ns as f64 + growth;
        v.clamp(0.0, 3_600.0 * 1e9) as i64
    }

    fn synced_at(&self, mono: u64) -> bool {
        if !self.sync.synced {
            return false;
        }
        let age_s = mono.saturating_sub(self.sync.last_sync_mono_ns) as f64 * 1e-9;
        // 24 小时没有成功同步就认为进入“自由运行”，状态不再宣称已同步。
        age_s < 86_400.0
    }

    fn locked_at(&self, mono: u64) -> bool {
        self.synced_at(mono)
            && self.uncertainty_at(mono) < 10_000_000
            && mono.saturating_sub(self.sync.last_sync_mono_ns) < 4 * 600 * NS_PER_SEC as u64
    }
}

pub struct AppClock {
    inner: RwLock<Inner>,
    high_water: AtomicI64,
    generation: AtomicU64,
}

impl AppClock {
    pub fn new() -> Self {
        let mono = precise::mono_or_fallback();
        let unix = xmc_time_base::mono::system_unix_ns();
        AppClock {
            inner: RwLock::new(Inner {
                anchor_mono_ns: mono,
                anchor_unix_ns: unix,
                rate_ppm: 0.0,
                drain: None,
                sync: SyncInfo::default(),
                total_steps: 0,
                backward_jumps: 0,
            }),
            high_water: AtomicI64::new(unix),
            generation: AtomicU64::new(0),
        }
    }

    /// 当前单调时间（优先 TSC 插值）。
    #[inline]
    pub fn mono_ns(&self) -> u64 {
        precise::mono_or_fallback()
    }

    pub fn generation(&self) -> u64 {
        self.generation.load(Ordering::Acquire)
    }

    pub fn rate_ppm(&self) -> f64 {
        self.inner.read().map(|g| g.rate_ppm).unwrap_or(0.0)
    }

    /// 原始应用时间：不做单调性保护。用于 NTP 的 t1/t4 采样（需要真实经过时间）。
    pub fn raw_at(&self, mono: u64) -> i64 {
        self.inner.read().map(|g| g.value_at(mono)).unwrap_or(0)
    }

    pub fn raw_now_ns(&self) -> i64 {
        let mono = self.mono_ns();
        self.raw_at(mono)
    }

    /// 对外时间：保证同一进程内不倒退。
    pub fn now_ns(&self) -> i64 {
        self.snapshot().unix_ns
    }

    pub fn snapshot(&self) -> ClockSnapshot {
        self.snapshot_at(self.mono_ns())
    }

    pub fn snapshot_at(&self, mono: u64) -> ClockSnapshot {
        let (
            raw,
            uncertainty,
            synced,
            locked,
            source,
            stratum,
            leap,
            gen,
            rate,
            total_steps,
            backward_jumps,
        ) = {
            let g = match self.inner.read() {
                Ok(g) => g,
                Err(p) => p.into_inner(),
            };
            (
                g.value_at(mono),
                g.uncertainty_at(mono),
                g.synced_at(mono),
                g.locked_at(mono),
                g.sync.source.clone(),
                g.sync.stratum,
                g.sync.leap,
                self.generation.load(Ordering::Acquire),
                g.rate_ppm,
                g.total_steps,
                g.backward_jumps,
            )
        };
        // fetch_max 原子地取最大值并返回旧值，避免“读-改-写”竞争把高水位降回去。
        let high = self.high_water.fetch_max(raw, Ordering::AcqRel);
        let out = raw.max(high);
        ClockSnapshot {
            unix_ns: out,
            mono_ns: mono,
            uncertainty_ns: uncertainty,
            synced,
            locked,
            source,
            stratum,
            leap,
            generation: gen,
            frozen: out > raw,
            rate_ppm: rate,
            total_steps,
            backward_jumps,
        }
    }

    /// 立即步进（可正可负）。
    pub fn step(&self, add_seconds: f64) {
        if !add_seconds.is_finite() {
            return;
        }
        let add_ns = (add_seconds * NS_PER_SEC as f64).round() as i128;
        let add_ns = clamp_i128(add_ns, i64::MIN as i128 / 2, i64::MAX as i128 / 2);
        let mono = self.mono_ns();
        let mut g = match self.inner.write() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        g.rebase(mono);
        g.anchor_unix_ns = clamp_i64(g.anchor_unix_ns as i128 + add_ns);
        g.total_steps += 1;
        let new_raw = g.value_at(mono);
        drop(g);

        self.generation.fetch_add(1, Ordering::AcqRel);
        let prev = self.high_water.fetch_max(new_raw, Ordering::AcqRel);
        if new_raw < prev && prev - new_raw > MAX_FREEZE_NS {
            // 大幅向后跳变（例如系统时间严重错误后的首次校正）：如实回退。
            // 仅当高水位仍是本次读到的旧值时才降低，避免覆盖其它线程的推进。
            let _ = self.high_water.compare_exchange(
                prev,
                new_raw,
                Ordering::AcqRel,
                Ordering::Acquire,
            );
            if let Ok(mut g) = self.inner.write() {
                g.backward_jumps += 1;
            }
        }
    }

    /// 强制步进：无视 high_water 的向后冻结，直接切换输出时间。
    /// 仅供用户显式“Force Re-anchor”使用。
    pub fn force_step(&self, add_seconds: f64) {
        if !add_seconds.is_finite() {
            return;
        }
        let add_ns = (add_seconds * NS_PER_SEC as f64).round() as i128;
        let add_ns = clamp_i128(add_ns, i64::MIN as i128 / 2, i64::MAX as i128 / 2);
        let mono = self.mono_ns();
        let mut g = match self.inner.write() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        g.rebase(mono);
        g.anchor_unix_ns = clamp_i64(g.anchor_unix_ns as i128 + add_ns);
        g.total_steps += 1;
        let new_raw = g.value_at(mono);
        drop(g);

        let prev = self.high_water.swap(new_raw, Ordering::AcqRel);
        self.generation.fetch_add(1, Ordering::AcqRel);
        if new_raw < prev {
            if let Ok(mut g) = self.inner.write() {
                g.backward_jumps += 1;
            }
        }
    }

    /// 设定绝对频率修正（ppm，正 = 加快）并可选地启动一次偏移消耗（drain）。
    pub fn slew(&self, freq_ppm: f64, drain_offset_s: f64, drain_rate_ppm: f64) {
        let freq = if freq_ppm.is_finite() {
            freq_ppm.clamp(-MAX_RATE_PPM, MAX_RATE_PPM)
        } else {
            0.0
        };
        let mono = self.mono_ns();
        let mut g = match self.inner.write() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        g.rebase(mono);
        g.rate_ppm = freq;
        let total_ns = (drain_offset_s * NS_PER_SEC as f64).round();
        if total_ns.is_finite() && total_ns.abs() >= 1.0 {
            let total_ns = clamp_i128(total_ns as i128, i64::MIN as i128 / 2, i64::MAX as i128 / 2) as i64;
            // 消耗速率必须小于 1e6ppm，否则会倒转时间；留 10% 余量。
            let rate = drain_rate_ppm
                .abs()
                .clamp(1.0, 900_000.0 - freq.abs() * 1.0);
            g.drain = Some(Drain {
                start_mono_ns: mono,
                total_ns,
                rate_ppm: rate,
            });
        }
        drop(g);
        self.generation.fetch_add(1, Ordering::AcqRel);
    }

    /// 把当前 drain 的进度固化，避免下一次改速率时重复计算。
    pub fn settle(&self) {
        let mono = self.mono_ns();
        if let Ok(mut g) = self.inner.write() {
            g.rebase(mono);
        }
    }

    /// 记录一次成功同步。`offset_ns` 是同步前测得的残余偏移（正 = 本地慢）。
    #[allow(clippy::too_many_arguments)]
    pub fn mark_synced(
        &self,
        source: &str,
        stratum: u8,
        leap: i8,
        uncertainty_ns: i64,
        offset_ns: i64,
        freq_ppm: f64,
        poll_s: f64,
        samples: usize,
        precision: &str,
        leap_pending: bool,
        holdover_ppm: f64,
    ) {
        let mono = self.mono_ns();
        let unix = self.raw_at(mono);
        let mut g = match self.inner.write() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        g.sync = SyncInfo {
            synced: true,
            source: source.to_string(),
            stratum,
            leap,
            last_sync_unix_ns: unix,
            last_sync_mono_ns: mono,
            uncertainty_ns: uncertainty_ns.max(1_000),
            holdover_ppm: holdover_ppm.clamp(0.1, 1_000.0),
            offset_ns,
            freq_ppm,
            poll_s,
            samples,
            precision: precision.to_string(),
            leap_pending,
            last_error: None,
        };
    }

    pub fn mark_error(&self, err: &str) {
        if let Ok(mut g) = self.inner.write() {
            g.sync.last_error = Some(err.to_string());
        }
    }

    pub fn sync_info(&self) -> SyncInfo {
        self.inner
            .read()
            .map(|g| g.sync.clone())
            .unwrap_or_default()
    }

    /// 热启动：把持久化的偏移量套到当前系统时钟上（频率修正不预加载，
    /// 因为纪律环的 freq 状态无法安全地从外部注入，见 docs/time-system.md）。
    pub fn restore_offset(&self, offset_ns: i64) {
        let mono = self.mono_ns();
        if let Ok(mut g) = self.inner.write() {
            g.rebase(mono);
            g.anchor_unix_ns = clamp_i64(g.anchor_unix_ns as i128 + offset_ns as i128);
        }
        self.high_water.store(self.raw_now_ns(), Ordering::Release);
        self.generation.fetch_add(1, Ordering::AcqRel);
    }

    /// 热启动：恢复“上次同步认知”，但明确标记为 holdover（未同步）。
    #[allow(clippy::too_many_arguments)]
    pub fn restore_holdover(
        &self,
        offset_ns: i64,
        uncertainty_ns: i64,
        freq_ppm: f64,
        stratum: u8,
        source: &str,
        age_s: i64,
        holdover_ppm: f64,
    ) {
        let mono = self.mono_ns();
        let now_unix = self.raw_at(mono);
        let holdover_ppm = holdover_ppm.clamp(0.1, 1_000.0);
        if let Ok(mut g) = self.inner.write() {
            g.rebase(mono);
            g.anchor_unix_ns = clamp_i64(g.anchor_unix_ns as i128 + offset_ns as i128);
            let grown =
                uncertainty_ns as f64 + holdover_ppm * 1e-6 * (age_s.max(0) as f64) * 1e9;
            g.sync = SyncInfo {
                synced: false,
                source: format!("{source} (holdover)"),
                stratum,
                leap: 0,
                last_sync_unix_ns: now_unix,
                last_sync_mono_ns: mono,
                uncertainty_ns: grown.clamp(0.0, 3_600.0 * 1e9) as i64,
                holdover_ppm,
                offset_ns,
                freq_ppm,
                poll_s: 0.0,
                samples: 0,
                precision: "persisted".to_string(),
                leap_pending: false,
                last_error: None,
            };
        }
        self.high_water.store(self.raw_now_ns(), Ordering::Release);
        self.generation.fetch_add(1, Ordering::AcqRel);
    }

    /// 重置为操作系统时间（测试/排障用）。
    pub fn reset_to_system(&self) {
        let mono = self.mono_ns();
        let unix = xmc_time_base::mono::system_unix_ns();
        if let Ok(mut g) = self.inner.write() {
            g.anchor_mono_ns = mono;
            g.anchor_unix_ns = unix;
            g.rate_ppm = 0.0;
            g.drain = None;
            g.sync = SyncInfo::default();
        }
        self.high_water.store(unix, Ordering::Release);
        self.generation.fetch_add(1, Ordering::AcqRel);
    }
}

impl Default for AppClock {
    fn default() -> Self {
        Self::new()
    }
}

fn clamp_i64(v: i128) -> i64 {
    v.clamp(i64::MIN as i128, i64::MAX as i128) as i64
}

fn clamp_i128(v: i128, lo: i128, hi: i128) -> i128 {
    v.clamp(lo, hi)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clock_at(unix_ns: i64) -> AppClock {
        let c = AppClock::new();
        c.restore_offset(unix_ns - xmc_time_base::mono::system_unix_ns());
        c
    }

    #[test]
    fn runs_forward_at_one_second_per_second() {
        let c = AppClock::new();
        let t0 = c.now_ns();
        std::thread::sleep(std::time::Duration::from_millis(120));
        let t1 = c.now_ns();
        let dt = t1 - t0;
        assert!(dt > 80_000_000 && dt < 250_000_000, "{dt}");
    }

    #[test]
    fn rate_correction_is_applied() {
        let c = AppClock::new();
        c.slew(400.0, 0.0, 0.0); // +400ppm（时钟上限 ±500ppm）
        let m0 = c.mono_ns();
        let t0 = c.raw_at(m0);
        std::thread::sleep(std::time::Duration::from_millis(120));
        let m1 = c.mono_ns();
        let t1 = c.raw_at(m1);
        let elapsed = (m1 - m0) as f64;
        let delta = (t1 - t0) as f64;
        let ppm = (delta / elapsed - 1.0) * 1e6;
        assert!((ppm - 400.0).abs() < 30.0, "{ppm}");
    }

    #[test]
    fn drain_is_budgeted_not_open_ended() {
        let c = AppClock::new();
        let start = c.raw_now_ns();
        c.slew(0.0, 0.010, 10_000.0); // 10ms，1% 速率 → 1 秒
        std::thread::sleep(std::time::Duration::from_millis(1_300));
        let after = c.raw_now_ns();
        let moved = after - start;
        // 1.3 秒里应只多走约 10ms，不会持续 1% 跑下去
        assert!(moved > 1_280_000_000 && moved < 1_340_000_000, "{moved}");
    }

    #[test]
    fn backwards_step_freezes_then_resumes() {
        let c = clock_at(1_700_000_000_000_000_000);
        let before = c.now_ns();
        c.step(-0.050); // 回退 50ms，小于冻结上限
        let immediate = c.now_ns();
        assert_eq!(immediate, before, "should freeze instead of going backwards");
        std::thread::sleep(std::time::Duration::from_millis(120));
        let later = c.now_ns();
        assert!(later > immediate, "should resume after catch-up");
    }

    #[test]
    fn large_backwards_step_is_allowed() {
        let c = clock_at(1_700_000_000_000_000_000);
        let before = c.now_ns();
        c.step(-10.0);
        let after = c.now_ns();
        assert!(after < before, "large jumps must not freeze the app for minutes");
        assert!((after - (before - 10 * NS_PER_SEC)).abs() < 5_000_000);
    }

    #[test]
    fn uncertainty_grows_in_holdover() {
        let c = AppClock::new();
        c.mark_synced("test", 2, 0, 1_000_000, 0, 0.0, 64.0, 4, "ntp", false, 15.0);
        let u0 = c.snapshot().uncertainty_ns;
        std::thread::sleep(std::time::Duration::from_millis(20));
        // 手工推进：直接读 1 小时后的不确定度
        let g = c.inner.read().unwrap();
        let mono = g.sync.last_sync_mono_ns + 3_600 * NS_PER_SEC as u64;
        let u1 = g.uncertainty_at(mono);
        assert!(u1 > u0 + 50_000_000, "{u0} -> {u1}");
    }

    #[test]
    fn concurrent_readers_never_go_backwards() {
        let c = std::sync::Arc::new(AppClock::new());
        c.step(0.05);
        let mut handles = Vec::new();
        for _ in 0..4 {
            let clock = std::sync::Arc::clone(&c);
            handles.push(std::thread::spawn(move || {
                let mut prev = 0;
                for _ in 0..5_000 {
                    let now = clock.now_ns();
                    assert!(now >= prev, "per-thread monotonic: {prev} -> {now}");
                    prev = now;
                }
            }));
        }
        for h in handles {
            h.join().unwrap();
        }
    }
}
