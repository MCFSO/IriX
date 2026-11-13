//! 高精度时钟：用 CPU TSC（`high_precision_clock`）在两个 `zeitstempel` 采样点之间
//! 做亚百纳秒插值。
//!
//! 设计要点：
//! - **不信任 TSC 的绝对时间**。`SimpleHighPrecisionClock` 内部用 SystemTime 标定，
//!   我们只把它当作一个高分辨率的自由运行计数器；
//! - 用最近若干组 `(tsc, mono)` 做最小二乘拟合，把 TSC 映射到 `zeitstempel` 时间轴，
//!   斜率吸收 TSC 与单调时钟之间的频率差（这就是第二层“漂移补偿”）；
//! - 每次读取都与同刻的 `zeitstempel` 对照，偏差超过 100µs 视为跨核 TSC 不一致/
//!   虚拟化迁移，立即重置拟合；连续失败则整体禁用，退回纯 zeitstempel；
//! - 仅在 x86_64 编译（`rdtsc`）。ARM（Apple Silicon/Windows on ARM）直接返回 `None`。
//!
//! 只在需要高精度时间戳的路径上调用（NTP 发包/收包、PTP 时间戳），普通 `now()`
//! 使用 zeitstempel 即可。

use std::sync::{Mutex, OnceLock};

use serde::Serialize;

/// 拟合窗口：保留最近 8 组采样（约 2 秒）。
const FIT_WINDOW: usize = 8;
/// 采样间隔：250ms。更密会引入量化噪声，更疏则频率漂移无法跟踪。
const SAMPLE_INTERVAL_NS: u64 = 250_000_000;
/// 判定 TSC 与单调时钟不一致的阈值。
const SANITY_LIMIT_NS: i64 = 100_000;

#[derive(Clone, Copy, Debug, Default, Serialize)]
pub struct PrecisionStats {
    pub available: bool,
    pub used: bool,
    pub ratio: f64,
    pub samples: usize,
    pub error_ns: i64,
    pub resets: u64,
    pub engine: &'static str,
}

/// 一次“批量时间戳”结果。
#[derive(Clone, Copy, Debug, Serialize)]
pub struct BatchStamp {
    /// 估计的单调时间（纳秒）。
    pub mono_ns: u64,
    /// 估计的 1σ 不确定度（纳秒）。
    pub uncertainty_ns: u64,
    /// 样本残差极差（纳秒）。
    pub spread_ns: u64,
    pub samples: u32,
}

#[cfg(target_arch = "x86_64")]
mod imp {
    use super::*;
    use high_precision_clock::SimpleHighPrecisionClock;

    #[derive(Clone, Copy)]
    struct Fit {
        slope: f64,
        intercept: f64,
    }

    struct Inner {
        clock: SimpleHighPrecisionClock,
        points: Vec<(f64, f64)>, // (tsc_ns, mono_ns)
        fit: Option<Fit>,
        /// 首次拟合出的斜率，作为“比例漂移”的参考；TSC 自身频率变化才会改变它。
        reference_slope: Option<f64>,
        last_sample_mono: u64,
        resets: u64,
        used: bool,
        /// 连续失败次数；达到 3 次直接关闭，避免每次 now() 都做无用功。
        failures: u32,
    }

    impl Inner {
        fn new() -> Self {
            // 200ms 标定间隔只影响 high_precision_clock 内部的 SystemTime 校正，
            // 我们不使用它的绝对时间，因此不会调用 calibrate()。
            let clock = SimpleHighPrecisionClock::new(200_000_000);
            Inner {
                clock,
                points: Vec::with_capacity(FIT_WINDOW),
                fit: None,
                reference_slope: None,
                last_sample_mono: 0,
                resets: 0,
                used: false,
                failures: 0,
            }
        }

        fn push(&mut self, tsc: f64, mono: f64) {
            if self.points.len() == FIT_WINDOW {
                self.points.remove(0);
            }
            self.points.push((tsc, mono));
            if self.points.len() >= 4 {
                let fitted = fit(&self.points);
                if let Some(f) = fitted {
                    self.reference_slope.get_or_insert(f.slope);
                }
                self.fit = fitted;
            }
        }

        fn reset(&mut self) {
            self.points.clear();
            self.fit = None;
            self.resets += 1;
            self.failures += 1;
            if self.failures >= 3 {
                self.used = false;
            }
        }
    }

    fn fit(points: &[(f64, f64)]) -> Option<Fit> {
        let n = points.len() as f64;
        let mean_x = points.iter().map(|p| p.0).sum::<f64>() / n;
        let mean_y = points.iter().map(|p| p.1).sum::<f64>() / n;
        let mut sxx = 0.0;
        let mut sxy = 0.0;
        for (x, y) in points {
            let dx = x - mean_x;
            sxx += dx * dx;
            sxy += dx * (y - mean_y);
        }
        if sxx <= f64::EPSILON {
            return None;
        }
        let slope = sxy / sxx;
        // high_precision_clock 内部的 ns_per_tsc 只做 20ms 粗标定，绝对比例可能
        // 偏离 1 几个百分点；这里让最小二乘学习真实比例，只拒绝明显异常
        // （跨核 TSC 抖动/虚拟化迁移导致的非物理斜率）。
        if !(0.5..=2.0).contains(&slope) {
            return None;
        }
        Some(Fit {
            slope,
            intercept: mean_y - slope * mean_x,
        })
    }

    static STATE: OnceLock<Mutex<Option<Inner>>> = OnceLock::new();

    fn state() -> &'static Mutex<Option<Inner>> {
        STATE.get_or_init(|| Mutex::new(Some(Inner::new())))
    }

    pub fn mono_ns() -> Option<u64> {
        let mut guard = state().lock().ok()?;
        let inner = guard.as_mut()?;
        if !inner.used && inner.failures >= 3 {
            return None;
        }

        let tsc = inner.clock.now();
        let mono = xmc_time_base::mono::now_ns();

        if mono.saturating_sub(inner.last_sample_mono) >= SAMPLE_INTERVAL_NS {
            inner.last_sample_mono = mono;
            inner.push(tsc as f64, mono as f64);
        }

        // 拟合未就绪（启动后的第一秒）直接退回 zeitstempel，避免用错误的
        // 1:1 假设外推，反而触发误判重置。
        let Some(fit) = inner.fit else {
            return None;
        };
        let est = fit.intercept + fit.slope * tsc as f64;
        if !est.is_finite() || est < 0.0 || est > u64::MAX as f64 {
            inner.reset();
            return None;
        }
        let diff = est.round() as i64 - mono as i64;
        if diff.abs() > SANITY_LIMIT_NS {
            inner.reset();
            return None;
        }
        inner.failures = 0;
        inner.used = true;
        Some(est.round() as u64)
    }

    fn robust_line(points: &[(f64, f64)]) -> Option<(f64, f64)> {
        fn line(pts: &[(f64, f64)]) -> Option<(f64, f64)> {
            let n = pts.len() as f64;
            if n < 2.0 {
                return None;
            }
            let mx = pts.iter().map(|p| p.0).sum::<f64>() / n;
            let my = pts.iter().map(|p| p.1).sum::<f64>() / n;
            let mut sxx = 0.0;
            let mut sxy = 0.0;
            for (x, y) in pts {
                sxx += (x - mx) * (x - mx);
                sxy += (x - mx) * (y - my);
            }
            if sxx <= f64::EPSILON {
                return None;
            }
            let slope = sxy / sxx;
            Some((slope, my - slope * mx))
        }

        let (slope, intercept) = line(points)?;
        let mut residuals: Vec<f64> = points
            .iter()
            .map(|(x, y)| y - (intercept + slope * x))
            .collect();
        residuals.sort_by(f64::total_cmp);
        let median = residuals[residuals.len() / 2];
        let mut deviations: Vec<f64> = residuals.iter().map(|r| (r - median).abs()).collect();
        deviations.sort_by(f64::total_cmp);
        let mad = deviations[deviations.len() / 2].max(1.0);
        let keep: Vec<(f64, f64)> = points
            .iter()
            .filter(|(x, y)| (y - (intercept + slope * x) - median).abs() <= 3.0 * mad)
            .copied()
            .collect();
        if keep.len() >= 2 {
            line(&keep)
        } else {
            Some((slope, intercept))
        }
    }

    /// 批量读取 TSC/单调时钟，鲁棒拟合后给出“当前单调时间 + 不确定度”。
    ///
    /// 用于 NTP 的 t1/t4：多次采样可以剔除被调度器打断的离群点，并把残差
    /// 直接计入测量噪声，而不是假设时间戳没有误差。
    pub fn batch_stamp(samples: u16) -> BatchStamp {
        let n = (samples as usize).clamp(3, 31);
        let mut guard = match state().lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        let Some(inner) = guard.as_mut() else {
            return fallback_stamp();
        };
        let mut points: Vec<(f64, f64)> = Vec::with_capacity(n);
        for _ in 0..n {
            let tsc = inner.clock.now();
            let mono = xmc_time_base::mono::now_ns();
            points.push((tsc as f64, mono as f64));
        }
        let Some((slope, intercept)) = robust_line(&points) else {
            return fallback_stamp();
        };
        let (tsc_last, _) = *points.last().unwrap();
        let est = intercept + slope * tsc_last;
        if !est.is_finite() || est <= 0.0 {
            return fallback_stamp();
        }
        let residuals: Vec<f64> = points
            .iter()
            .map(|(x, y)| y - (intercept + slope * x))
            .collect();
        let mean = residuals.iter().sum::<f64>() / residuals.len() as f64;
        let rms = (residuals
            .iter()
            .map(|r| (r - mean) * (r - mean))
            .sum::<f64>()
            / residuals.len() as f64)
            .sqrt();
        let spread = residuals
            .iter()
            .copied()
            .fold(f64::NEG_INFINITY, f64::max)
            - residuals
                .iter()
                .copied()
                .fold(f64::INFINITY, f64::min);
        let uncertainty = (rms + spread / (n as f64).sqrt() + 50.0).clamp(20.0, 100_000.0);
        BatchStamp {
            mono_ns: est.round().max(0.0) as u64,
            uncertainty_ns: uncertainty as u64,
            spread_ns: spread.max(0.0) as u64,
            samples: n as u32,
        }
    }

    fn fallback_stamp() -> BatchStamp {
        BatchStamp {
            mono_ns: xmc_time_base::mono::now_ns(),
            uncertainty_ns: 1_000,
            spread_ns: 0,
            samples: 1,
        }
    }

    pub fn stats() -> PrecisionStats {
        let Ok(guard) = state().lock() else {
            return PrecisionStats::default();
        };
        let Some(inner) = guard.as_ref() else {
            return PrecisionStats::default();
        };
        PrecisionStats {
            available: true,
            used: inner.used,
            ratio: match (inner.fit.as_ref(), inner.reference_slope) {
                (Some(f), Some(r)) if r != 0.0 => f.slope / r,
                _ => 1.0,
            },
            samples: inner.points.len(),
            error_ns: inner
                .fit
                .as_ref()
                .map(|f| {
                    let last = inner.points.last().copied().unwrap_or((0.0, 0.0));
                    (f.intercept + f.slope * last.0 - last.1).round() as i64
                })
                .unwrap_or(0),
            resets: inner.resets,
            engine: "high_precision_clock(tsc)",
        }
    }
}

#[cfg(not(target_arch = "x86_64"))]
mod imp {
    use super::*;

    pub fn mono_ns() -> Option<u64> {
        None
    }

    pub fn stats() -> PrecisionStats {
        PrecisionStats {
            available: false,
            engine: "zeitstempel",
            ..Default::default()
        }
    }

    pub fn batch_stamp(_samples: u16) -> BatchStamp {
        BatchStamp {
            mono_ns: xmc_time_base::mono::now_ns(),
            uncertainty_ns: 1_000,
            spread_ns: 0,
            samples: 1,
        }
    }
}

pub use imp::{batch_stamp, mono_ns, stats};

/// 取得单调时间：优先 TSC 插值，失败则退回 zeitstempel。
#[inline]
pub fn mono_or_fallback() -> u64 {
    mono_ns().unwrap_or_else(xmc_time_base::mono::now_ns)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn precision_converges_and_tracks_monotonic() {
        if !cfg!(target_arch = "x86_64") {
            return;
        }
        // 拟合窗口需要至少 4 个采样（250ms 间隔），约 1 秒后才可用。
        for _ in 0..6 {
            let _ = mono_ns();
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
        let s = stats();
        assert!(s.samples >= 4 || s.resets > 0, "{s:?}");
        if let Some(p) = mono_ns() {
            let m = xmc_time_base::mono::now_ns();
            let diff = p as i64 - m as i64;
            assert!(diff.abs() < 50_000, "precision clock off by {diff} ns");
        }
    }

    #[test]
    fn stats_are_reported() {
        let s = stats();
        if cfg!(target_arch = "x86_64") {
            assert!(s.available);
        }
    }

    #[test]
    fn batch_stamp_is_bounded_and_monotonic() {
        let mut prev = 0;
        for _ in 0..20 {
            let s = batch_stamp(9);
            assert!(s.mono_ns > 0);
            assert!(s.mono_ns >= prev, "batch stamp went backwards");
            assert!(s.uncertainty_ns <= 100_000, "uncertainty {}ns", s.uncertainty_ns);
            prev = s.mono_ns;
        }
    }
}
