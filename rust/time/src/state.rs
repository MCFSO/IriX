//! 时钟状态持久化：让应用重启后仍能沿用上一次的偏移/漂移认知（保持模式）。
//!
//! 只保存“应用时间 - 系统时钟”的差值，而不是应用时间的绝对值：
//! 这样即使系统时钟在两次启动之间被校正，热启动仍然以系统时钟为基准，
//! 再叠加一个已知的小偏移，不会把旧时间硬编码成新的绝对时间。

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::kalman::KalmanSnapshot;

pub const STATE_VERSION: u32 = 1;
/// 超过这个年龄的持久化状态直接丢弃（时钟认知已无意义）。
pub const MAX_STATE_AGE_S: i64 = 30 * 86_400;
/// 只接受幅度合理的偏移，防止损坏/恶意文件把时间拉飞。
pub const MAX_RESTORABLE_OFFSET_NS: i64 = 60 * 1_000_000_000;
/// 持久化锚点比当前系统时间超前超过 1 天，视为状态损坏。
pub const MAX_ANCHOR_AHEAD_NS: i64 = 86_400 * 1_000_000_000;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PersistedState {
    pub version: u32,
    /// 保存时的应用时间（Unix ns）。
    pub saved_at_unix_ns: i64,
    /// 保存时的系统时钟（Unix ns），用于计算离线时长。
    pub saved_at_os_ns: i64,
    /// 保存时的应用时间 - 系统时钟。
    pub offset_ns: i64,
    /// 最后一次成功同步的不确定度。
    pub uncertainty_ns: i64,
    /// 最后一次成功同步的来源/层级/频率，仅用于展示与诊断。
    pub last_sync_unix_ns: i64,
    pub last_freq_ppm: f64,
    pub stratum: u8,
    pub source: String,
    pub synced: bool,
    pub total_syncs: u64,
    /// 卡尔曼状态（偏移/频率/日老化/温度系数 + 协方差对角）。
    #[serde(default)]
    pub kf: Option<KalmanSnapshot>,
    /// 保存时的温度（°C）。
    #[serde(default)]
    pub temp_c: Option<f64>,
    /// 长基线 (时间, 频率, 温度) 点，用于 aging/temp_coeff 收敛。
    #[serde(default)]
    pub trend: Vec<crate::trend::TrendPoint>,
}

impl PersistedState {
    /// 距保存时刻经过的秒数（按系统时钟）。
    pub fn age_seconds(&self) -> i64 {
        (xmc_time_base::mono::system_unix_ns() - self.saved_at_os_ns) / 1_000_000_000
    }

    pub fn is_usable(&self) -> bool {
        self.version == STATE_VERSION
            && self.offset_ns.abs() <= MAX_RESTORABLE_OFFSET_NS
            && self.anchor_sane()
            && self.age_seconds() >= -5
            && self.age_seconds() <= MAX_STATE_AGE_S
    }

    /// 锚点不能比当前系统时间超前 1 天以上；否则视为损坏/被污染。
    pub fn anchor_sane(&self) -> bool {
        let now = xmc_time_base::mono::system_unix_ns();
        self.saved_at_unix_ns.saturating_sub(now) <= MAX_ANCHOR_AHEAD_NS
            && self.saved_at_os_ns.saturating_sub(now) <= MAX_ANCHOR_AHEAD_NS
    }
}

pub fn load(path: &str) -> Option<PersistedState> {
    let p = Path::new(path);
    if !p.exists() {
        return None;
    }
    let text = fs::read_to_string(p).ok()?;
    let state: PersistedState = serde_json::from_str(&text).ok()?;
    if state.is_usable() {
        Some(state)
    } else {
        // 损坏/未来锚点：直接删掉，避免下次启动继续污染。
        let _ = fs::remove_file(p);
        None
    }
}

pub fn save(path: &str, state: &PersistedState) -> Result<(), String> {
    if !state.anchor_sane() {
        let _ = fs::remove_file(path);
        return Err("时钟状态锚点比系统时间超前超过 1 天，已拒绝写入".to_string());
    }
    let p = Path::new(path);
    if let Some(parent) = p.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("创建时钟状态目录失败: {e}"))?;
        }
    }
    let text = serde_json::to_string_pretty(state).map_err(|e| format!("序列化时钟状态失败: {e}"))?;
    let tmp = p.with_extension("json.tmp");
    fs::write(&tmp, text).map_err(|e| format!("写入时钟状态失败: {e}"))?;
    fs::rename(&tmp, p).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("替换时钟状态文件失败: {e}")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let dir = std::env::temp_dir().join(format!(
            "xmc_time_state_test_{}",
            xmc_time_base::mono::now_ns()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.json");
        let path = path.to_string_lossy().to_string();
        let state = PersistedState {
            version: STATE_VERSION,
            saved_at_unix_ns: xmc_time_base::mono::system_unix_ns(),
            saved_at_os_ns: xmc_time_base::mono::system_unix_ns(),
            offset_ns: 1_234_567,
            uncertainty_ns: 50_000,
            last_sync_unix_ns: xmc_time_base::mono::system_unix_ns(),
            last_freq_ppm: -12.5,
            stratum: 2,
            source: "ntp.aliyun.com".to_string(),
            synced: true,
            total_syncs: 3,
            kf: None,
            temp_c: None,
            trend: Vec::new(),
        };
        save(&path, &state).unwrap();
        let loaded = load(&path).unwrap();
        assert_eq!(loaded.offset_ns, state.offset_ns);
        assert!(loaded.is_usable());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_absurd_offset() {
        let mut state = PersistedState {
            version: STATE_VERSION,
            saved_at_unix_ns: 0,
            saved_at_os_ns: xmc_time_base::mono::system_unix_ns(),
            offset_ns: i64::MAX / 2,
            uncertainty_ns: 0,
            last_sync_unix_ns: 0,
            last_freq_ppm: 0.0,
            stratum: 2,
            source: "x".into(),
            synced: true,
            total_syncs: 0,
            kf: None,
            temp_c: None,
            trend: Vec::new(),
        };
        assert!(!state.is_usable());
        state.offset_ns = 0;
        state.version = 99;
        assert!(!state.is_usable());
    }

    #[test]
    fn rejects_and_deletes_future_anchor() {
        let dir = std::env::temp_dir().join(format!(
            "xmc_time_future_anchor_{}",
            xmc_time_base::mono::now_ns()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.json");
        let path = path.to_string_lossy().to_string();
        let now = xmc_time_base::mono::system_unix_ns();
        let state = PersistedState {
            version: STATE_VERSION,
            // 6 天后：模拟被污染的 Application Clock 锚点。
            saved_at_unix_ns: now + 6 * 86_400 * 1_000_000_000,
            saved_at_os_ns: now,
            offset_ns: 0,
            uncertainty_ns: 0,
            last_sync_unix_ns: now,
            last_freq_ppm: 0.0,
            stratum: 2,
            source: "polluted".into(),
            synced: true,
            total_syncs: 0,
            kf: None,
            temp_c: None,
            trend: Vec::new(),
        };
        assert!(!state.is_usable());
        assert!(save(&path, &state).is_err());
        assert!(!Path::new(&path).exists());
        assert!(load(&path).is_none());
        let _ = fs::remove_dir_all(&dir);
    }
}
