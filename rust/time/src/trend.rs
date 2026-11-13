//! 长基线频率/温度趋势。
//!
//! 4 状态 KF 里 aging / temp_coeff 是弱可观测量；短时间 NTP 只能学到 offset。
//! 这里保存每 5 分钟一个 `(时间, KF 频率, 温度)` 点，做长基线回归：
//!
//! ```text
//! freq_ppm ≈ f0 + aging * days + temp_coeff * (T - T_ref)
//! ```
//!
//! 只有跨度/温差/样本数足够时才把结果写回 KF，避免几分钟的数据“学出”假老化。

use std::collections::VecDeque;

use serde::{Deserialize, Serialize};

const MAX_POINTS: usize = 2016; // 7 天，5 分钟一个点
const MIN_INTERVAL_S: i64 = 300;
const MIN_FIT_POINTS: usize = 12;
const MIN_AGING_SPAN_S: i64 = 6 * 3600;
const MIN_TEMP_SPAN_C: f64 = 1.0;
const MAX_AGING_SD: f64 = 5.0;
const MAX_TEMP_SD: f64 = 5.0;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TrendPoint {
    pub unix_s: i64,
    pub freq_ppm: f64,
    #[serde(default)]
    pub temp_c: Option<f64>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct TrendFit {
    pub points: usize,
    pub span_s: i64,
    pub temp_span_c: f64,
    pub aging_ppm_day: Option<f64>,
    pub aging_sd: Option<f64>,
    pub aging_ok: bool,
    pub temp_coeff_ppm_per_c: Option<f64>,
    pub temp_sd: Option<f64>,
    pub temp_ok: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct TrendStore {
    #[serde(default)]
    points: VecDeque<TrendPoint>,
    #[serde(default)]
    last_s: i64,
}

impl TrendStore {
    pub fn observe(&mut self, unix_s: i64, freq_ppm: f64, temp_c: Option<f64>) {
        if !freq_ppm.is_finite() {
            return;
        }
        if self.last_s > 0 && unix_s.saturating_sub(self.last_s) < MIN_INTERVAL_S {
            return;
        }
        if self.points.len() == MAX_POINTS {
            self.points.pop_front();
        }
        self.points.push_back(TrendPoint {
            unix_s,
            freq_ppm,
            temp_c: temp_c.filter(|t| t.is_finite()),
        });
        self.last_s = unix_s;
    }

    pub fn points(&self) -> Vec<TrendPoint> {
        self.points.iter().cloned().collect()
    }

    pub fn restore(&mut self, mut points: Vec<TrendPoint>) {
        if points.len() > MAX_POINTS {
            points.drain(0..points.len() - MAX_POINTS);
        }
        self.last_s = points.last().map(|p| p.unix_s).unwrap_or(0);
        self.points = points.into();
    }

    pub fn fit(&self, temp_ref_c: f64) -> TrendFit {
        let n = self.points.len();
        if n < MIN_FIT_POINTS {
            return TrendFit {
                points: n,
                ..Default::default()
            };
        }
        let first = self.points.front().unwrap().unix_s;
        let last = self.points.back().unwrap().unix_s;
        let span_s = last.saturating_sub(first);
        let times: Vec<f64> = self
            .points
            .iter()
            .map(|p| (p.unix_s - first) as f64 / 86_400.0)
            .collect();
        let freqs: Vec<f64> = self.points.iter().map(|p| p.freq_ppm).collect();

        // 带有温度的样本做联合回归，避免“时间趋势”和“温度趋势”互相污染。
        let mut fit_days = Vec::new();
        let mut fit_temps = Vec::new();
        let mut fit_freqs = Vec::new();
        for p in &self.points {
            let Some(t) = p.temp_c else { continue };
            fit_days.push((p.unix_s - first) as f64 / 86_400.0);
            fit_temps.push(t - temp_ref_c);
            fit_freqs.push(p.freq_ppm);
        }
        let temp_span_c = if fit_temps.is_empty() {
            0.0
        } else {
            let lo = fit_temps.iter().cloned().fold(f64::INFINITY, f64::min);
            let hi = fit_temps.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
            (hi - lo).max(0.0)
        };

        let joint = if fit_freqs.len() >= MIN_FIT_POINTS && temp_span_c >= MIN_TEMP_SPAN_C {
            multi_fit(&fit_days, &fit_temps, &fit_freqs)
        } else {
            None
        };
        let (aging, aging_sd, temp_coeff, temp_sd) = if let Some((coef, cov)) = joint {
            (
                Some(coef[1]),
                Some(cov[1][1].max(0.0).sqrt()),
                Some(coef[2]),
                Some(cov[2][2].max(0.0).sqrt()),
            )
        } else {
            let (_, a, sd) = linear_fit(&times, &freqs);
            (a, sd, None, None)
        };
        let aging_ok = span_s >= MIN_AGING_SPAN_S
            && aging.is_some()
            && aging_sd.map(|s| s.is_finite() && s <= MAX_AGING_SD).unwrap_or(false);
        let temp_ok = temp_span_c >= MIN_TEMP_SPAN_C
            && temp_coeff.is_some()
            && temp_sd.map(|s| s.is_finite() && s <= MAX_TEMP_SD).unwrap_or(false);

        TrendFit {
            points: n,
            span_s,
            temp_span_c,
            aging_ppm_day: aging,
            aging_sd,
            aging_ok,
            temp_coeff_ppm_per_c: temp_coeff,
            temp_sd,
            temp_ok,
        }
    }
}

/// 简单 OLS：返回 (intercept, slope, slope_se)。
fn linear_fit(x: &[f64], y: &[f64]) -> (Option<f64>, Option<f64>, Option<f64>) {    let n = x.len().min(y.len());
    if n < 3 {
        return (None, None, None);
    }
    let mean_x = x[..n].iter().sum::<f64>() / n as f64;
    let mean_y = y[..n].iter().sum::<f64>() / n as f64;
    let mut sxx = 0.0;
    let mut sxy = 0.0;
    for i in 0..n {
        let dx = x[i] - mean_x;
        sxx += dx * dx;
        sxy += dx * (y[i] - mean_y);
    }
    if !sxx.is_finite() || sxx <= 1e-18 {
        return (None, None, None);
    }
    let slope = sxy / sxx;
    let intercept = mean_y - slope * mean_x;
    let mut sse = 0.0;
    for i in 0..n {
        let r = y[i] - (intercept + slope * x[i]);
        sse += r * r;
    }
    let se = if n > 2 {
        (sse / (n as f64 - 2.0) / sxx).sqrt()
    } else {
        f64::NAN
    };
    (Some(intercept), Some(slope), Some(se))
}

/// 3 参数联合最小二乘：y ≈ c0 + c1*x1 + c2*x2。
fn multi_fit(x1: &[f64], x2: &[f64], y: &[f64]) -> Option<([f64; 3], [[f64; 3]; 3])> {
    let n = x1.len().min(x2.len()).min(y.len());
    if n < 4 {
        return None;
    }
    let mut a = [[0.0f64; 3]; 3];
    let mut b = [0.0f64; 3];
    for i in 0..n {
        let row = [1.0, x1[i], x2[i]];
        for j in 0..3 {
            for k in 0..3 {
                a[j][k] += row[j] * row[k];
            }
            b[j] += row[j] * y[i];
        }
    }
    for j in 0..3 {
        a[j][j] += 1e-12;
    }
    let coef = solve3(a, b)?;
    let inv = inverse3(a)?;
    let mut sse = 0.0;
    for i in 0..n {
        let pred = coef[0] + coef[1] * x1[i] + coef[2] * x2[i];
        let r = y[i] - pred;
        sse += r * r;
    }
    let sigma2 = sse / (n as f64 - 3.0);
    let mut cov = [[0.0f64; 3]; 3];
    for j in 0..3 {
        for k in 0..3 {
            cov[j][k] = inv[j][k] * sigma2;
        }
    }
    Some((coef, cov))
}

fn solve3(mut a: [[f64; 3]; 3], mut b: [f64; 3]) -> Option<[f64; 3]> {
    for col in 0..3 {
        let mut pivot = col;
        for row in (col + 1)..3 {
            if a[row][col].abs() > a[pivot][col].abs() {
                pivot = row;
            }
        }
        if !a[pivot][col].is_finite() || a[pivot][col].abs() < 1e-18 {
            return None;
        }
        a.swap(col, pivot);
        b.swap(col, pivot);
        let p = a[col][col];
        for j in col..3 {
            a[col][j] /= p;
        }
        b[col] /= p;
        for row in 0..3 {
            if row == col {
                continue;
            }
            let f = a[row][col];
            if f == 0.0 {
                continue;
            }
            for j in col..3 {
                a[row][j] -= f * a[col][j];
            }
            b[row] -= f * b[col];
        }
    }
    Some(b)
}

fn inverse3(a: [[f64; 3]; 3]) -> Option<[[f64; 3]; 3]> {
    let mut inv = [[0.0f64; 3]; 3];
    for col in 0..3 {
        let mut unit = [0.0f64; 3];
        unit[col] = 1.0;
        let solved = solve3(a, unit)?;
        for row in 0..3 {
            inv[row][col] = solved[row];
        }
    }
    Some(inv)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovers_aging_and_temp() {
        let mut store = TrendStore::default();
        let start = 1_700_000_000i64;
        for hour in 0..72 {
            let days = hour as f64 / 24.0;
            let temp = 25.0 + 4.0 * (hour as f64 * 0.5).sin();
            let freq = 1.5 + 0.4 * days + 0.8 * (temp - 25.0);
            store.observe(start + hour * 3600, freq, Some(temp));
        }
        let fit = store.fit(25.0);
        assert!(fit.aging_ok, "{fit:?}");
        assert!(fit.temp_ok, "{fit:?}");
        assert!((fit.aging_ppm_day.unwrap() - 0.4).abs() < 0.05, "{fit:?}");
        assert!((fit.temp_coeff_ppm_per_c.unwrap() - 0.8).abs() < 0.05, "{fit:?}");
    }

    #[test]
    fn refuses_short_history() {
        let mut store = TrendStore::default();
        for minute in 0..30 {
            store.observe(1_700_000_000 + minute * 300, 1.0, Some(25.0));
        }
        let fit = store.fit(25.0);
        assert!(!fit.aging_ok);
        assert!(!fit.temp_ok);
    }

    #[test]
    fn throttles_to_five_minutes() {
        let mut store = TrendStore::default();
        store.observe(1_700_000_000, 1.0, None);
        store.observe(1_700_000_100, 2.0, None);
        assert_eq!(store.points().len(), 1);
    }
}
