//! 温度输入与热漂移辅助。
//!
//! 温度不是“绝对真值”来源，而是卡尔曼滤波的协变量：晶振频率会随温度变化，
//! 把温度变化纳入预测能显著降低 24h 保持误差。
//!
//! 平台策略：
//! - Linux：读取 `/sys/class/thermal/thermal_zone*/temp` 与
//!   `/sys/class/hwmon/hwmon*/temp*_input`（毫摄氏度），取可用传感器的最大值；
//! - Windows/macOS：内核没有稳定的用户态温度接口，默认返回 `None`，由 Dart 侧
//!   通过 FFI `temperature` op 注入（例如借助 LibreHardwareMonitor / SMC）；
//! - 所有平台都支持外部注入，便于测试与无传感器机器。
//!
//! 注意：主板/CPU 传感器测的不是晶振温度，只能作为“机箱热环境”的代理变量。
//! 温度系数由卡尔曼滤波在线学习，传感器与晶振的热耦合误差最终会体现在
//! `temp_coeff` 的估计和频率不确定度里，不会被“魔法消除”。

use std::sync::Mutex;
use std::time::{Duration, Instant};

const MIN_C: f64 = -40.0;
const MAX_C: f64 = 150.0;

#[derive(Clone, Copy, Debug)]
pub struct TemperatureReading {
    pub celsius: f64,
    pub source: &'static str,
}

/// 读取本机温度（摄氏度）。无可用传感器时返回 `None`。
pub fn read_celsius() -> Option<TemperatureReading> {
    #[cfg(target_os = "linux")]
    {
        if let Some(c) = read_linux_sysfs() {
            return Some(TemperatureReading {
                celsius: c,
                source: "sysfs",
            });
        }
    }
    None
}

#[cfg(target_os = "linux")]
fn read_linux_sysfs() -> Option<f64> {
    let mut values = Vec::new();
    for base in ["/sys/class/thermal", "/sys/class/hwmon"] {
        let Ok(entries) = std::fs::read_dir(base) else {
            continue;
        };
        for entry in entries.flatten() {
            let dir = entry.path();
            if base.ends_with("thermal") {
                push_millideg(&dir.join("temp"), &mut values);
            } else {
                // hwmon 下可能有 temp1_input、temp2_input...
                let Ok(files) = std::fs::read_dir(&dir) else {
                    continue;
                };
                for f in files.flatten() {
                    let name = f.file_name();
                    let name = name.to_string_lossy();
                    if name.starts_with("temp") && name.ends_with("_input") {
                        push_millideg(&f.path(), &mut values);
                    }
                }
            }
        }
    }
    values.sort_by(f64::total_cmp);
    // 取最大值：CPU 热点最接近“晶振所在热环境”的上界。
    values.last().copied()
}

#[cfg(target_os = "linux")]
fn push_millideg(path: &std::path::Path, out: &mut Vec<f64>) {
    let Ok(text) = std::fs::read_to_string(path) else {
        return;
    };
    let Ok(raw) = text.trim().parse::<f64>() else {
        return;
    };
    let c = raw / 1000.0;
    if (MIN_C..=MAX_C).contains(&c) {
        out.push(c);
    }
}

/// EMA 温度滤波器 + 采样节流。
#[derive(Debug)]
pub struct ThermalMonitor {
    ema_c: Option<f64>,
    last_sample: Option<Instant>,
    interval: Duration,
    last_source: &'static str,
    injected: Mutex<Option<f64>>,
    platform_reads: bool,
}

impl ThermalMonitor {
    pub fn new(interval: Duration) -> Self {
        ThermalMonitor {
            ema_c: None,
            last_sample: None,
            interval,
            last_source: "none",
            injected: Mutex::new(None),
            platform_reads: true,
        }
    }

    #[cfg(test)]
    fn disable_platform_reads(&mut self) {
        self.platform_reads = false;
    }

    /// 外部注入温度（FFI / 测试）。下一次 `sample()` 会优先使用它。
    pub fn inject(&self, celsius: f64) {
        if !celsius.is_finite() || !(MIN_C..=MAX_C).contains(&celsius) {
            return;
        }
        if let Ok(mut g) = self.injected.lock() {
            *g = Some(celsius);
        }
    }

    pub fn last_celsius(&self) -> Option<f64> {
        self.ema_c
    }

    pub fn last_source(&self) -> &'static str {
        self.last_source
    }

    /// 采样（按 interval 节流）。优先外部注入，其次平台传感器。
    pub fn sample(&mut self, force: bool) -> Option<f64> {
        let due = force
            || self
                .last_sample
                .map(|t| t.elapsed() >= self.interval)
                .unwrap_or(true);
        if !due {
            return self.ema_c;
        }
        self.last_sample = Some(Instant::now());

        let injected = self
            .injected
            .lock()
            .ok()
            .and_then(|g| *g);
        let (raw, source) = if let Some(c) = injected {
            (Some(c), "external")
        } else if self.platform_reads {
            if let Some(r) = read_celsius() {
                (Some(r.celsius), r.source)
            } else {
                (None, "none")
            }
        } else {
            (None, "none")
        };
        if let Some(c) = raw {
            // α=0.2：约 5 个样本跟上温度变化，兼顾噪声。
            self.ema_c = Some(match self.ema_c {
                Some(prev) => prev + 0.2 * (c - prev),
                None => c,
            });
            self.last_source = source;
        }
        self.ema_c
    }
}

impl Default for ThermalMonitor {
    fn default() -> Self {
        Self::new(Duration::from_secs(60))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn injected_temperature_is_filtered() {
        let mut m = ThermalMonitor::new(Duration::ZERO);
        m.inject(30.0);
        assert_eq!(m.sample(true), Some(30.0));
        m.inject(40.0);
        let v = m.sample(true).unwrap();
        assert!((v - 32.0).abs() < 1e-6, "{v}");
        assert_eq!(m.last_source(), "external");
    }

    #[test]
    fn invalid_temperature_is_ignored() {
        let mut m = ThermalMonitor::new(Duration::ZERO);
        m.disable_platform_reads();
        m.inject(999.0);
        assert_eq!(m.sample(true), None);
    }
}
