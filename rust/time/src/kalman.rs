//! 4 状态卡尔曼滤波：偏移、频率、日老化率、温度系数。
//!
//! 取代原来的“加权线性回归 + 纪律环累加频率”模型。状态向量：
//!
//! ```text
//! x = [ offset_s, freq_ppm, aging_ppm_per_day, temp_coeff_ppm_per_c ]
//! ```
//!
//! - `offset_s`：需要加到本地时钟上的时间（正 = 本地慢）；
//! - `freq_ppm`：参考温度 `T_ref` 下需要施加的频率修正（正 = 加快）；
//! - `aging_ppm_per_day`：频率随时间的老化率；
//! - `temp_coeff_ppm_per_c`：温度每升高 1°C，所需频率修正的变化量
//!   （对常见晶振，温度升高频率下降，因此该值通常为正）。
//!
//! 预测模型（`dt` 秒，温度 `T`）：
//!
//! ```text
//! offset += (freq + temp_coeff*(T - T_ref)) * 1e-6 * dt
//!           + 0.5 * aging * 1e-6 * dt^2 / 86400
//! freq   += aging * dt / 86400
//! ```
//!
//! 观测只有 NTP 偏移（H = [1,0,0,0]），观测噪声 R 由 RTT/2、root dispersion、
//! 时间戳抖动合成。温度系数和老化率是弱可观测量，靠过程噪声与长时间历史慢慢
//! 收敛；因此对状态做了物理上限约束，并用新息门限抑制坏样本。

use serde::{Deserialize, Serialize};

const N: usize = 4;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct KalmanConfig {
    /// 偏移随机游走（s²/s）。
    pub q_offset: f64,
    /// 频率随机游走（ppm²/s）。
    pub q_freq: f64,
    /// 老化率随机游走（(ppm/day)²/s）。
    pub q_aging: f64,
    /// 温度系数随机游走（(ppm/°C)²/s）。
    pub q_temp: f64,
    pub initial_offset_var: f64,
    pub initial_freq_var: f64,
    pub initial_aging_var: f64,
    pub initial_temp_var: f64,
    /// 新息门限（σ），超过则放大 R 抑制该样本。
    pub gate_sigma: f64,
    pub max_freq_ppm: f64,
    pub max_aging_ppm_day: f64,
    pub max_temp_coeff: f64,
}

impl Default for KalmanConfig {
    fn default() -> Self {
        KalmanConfig {
            q_offset: 1e-12,
            q_freq: 1e-8,
            q_aging: 1e-10,
            q_temp: 1e-7,
            initial_offset_var: 1e-4,          // 10ms
            initial_freq_var: 25.0,            // 5ppm
            initial_aging_var: 4.0,            // 2ppm/day
            initial_temp_var: 4.0,             // 2ppm/°C
            gate_sigma: 5.0,
            max_freq_ppm: 500.0,
            max_aging_ppm_day: 20.0,
            max_temp_coeff: 10.0,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
pub struct KalmanState {
    pub offset_s: f64,
    pub freq_ppm: f64,
    pub aging_ppm_day: f64,
    pub temp_coeff_ppm_per_c: f64,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct KalmanSnapshot {
    pub state: KalmanState,
    pub p_diag: [f64; 4],
    pub temp_ref_c: f64,
}

#[derive(Clone, Debug)]
pub struct KalmanFilter {
    x: [f64; N],
    p: [[f64; N]; N],
    cfg: KalmanConfig,
    temp_ref_c: f64,
    updates: u32,
}

impl KalmanFilter {
    pub fn new(cfg: KalmanConfig, state: KalmanState, p_diag: [f64; 4], temp_ref_c: f64) -> Self {
        let mut p = [[0.0; N]; N];
        for i in 0..N {
            p[i][i] = p_diag[i].max(1e-18);
        }
        let mut kf = KalmanFilter {
            x: [
                state.offset_s,
                state.freq_ppm,
                state.aging_ppm_day,
                state.temp_coeff_ppm_per_c,
            ],
            p,
            cfg,
            temp_ref_c,
            updates: 0,
        };
        kf.clamp_state();
        kf
    }

    pub fn with_defaults() -> Self {
        Self::new(
            KalmanConfig::default(),
            KalmanState::default(),
            [1e-4, 25.0, 4.0, 4.0],
            25.0,
        )
    }

    pub fn state(&self) -> KalmanState {
        KalmanState {
            offset_s: self.x[0],
            freq_ppm: self.x[1],
            aging_ppm_day: self.x[2],
            temp_coeff_ppm_per_c: self.x[3],
        }
    }

    pub fn snapshot(&self) -> KalmanSnapshot {
        KalmanSnapshot {
            state: self.state(),
            p_diag: [self.p[0][0], self.p[1][1], self.p[2][2], self.p[3][3]],
            temp_ref_c: self.temp_ref_c,
        }
    }

    pub fn temp_ref_c(&self) -> f64 {
        self.temp_ref_c
    }

    /// 参考温度下的总频率修正 = 频率状态 + 温度项（老化已在 predict 中累计进 freq）。
    pub fn total_freq_ppm(&self, temp_c: f64) -> f64 {
        let dt = temp_c - self.temp_ref_c;
        (self.x[1] + self.x[3] * dt).clamp(-self.cfg.max_freq_ppm, self.cfg.max_freq_ppm)
    }

    pub fn offset_sd_s(&self) -> f64 {
        self.p[0][0].max(0.0).sqrt()
    }

    pub fn freq_sd_ppm(&self) -> f64 {
        self.p[1][1].max(0.0).sqrt()
    }

    pub fn aging_sd_ppm_day(&self) -> f64 {
        self.p[2][2].max(0.0).sqrt()
    }

    pub fn temp_coeff_sd(&self) -> f64 {
        self.p[3][3].max(0.0).sqrt()
    }

    /// 预测到下一时刻。`temp_c` 是当前温度（认为 dt 内近似不变）。
    pub fn predict(&mut self, dt_s: f64, temp_c: f64) {
        self.predict_with_drain(dt_s, temp_c, 0.0);
    }

    /// 预测，并把“正在施加的 drain 速率”作为已知控制量。
    ///
    /// `drain_ppm` 正 = 时钟正在加快以消化正偏移，因此偏移会额外减小
    /// `drain_ppm * 1e-6 * dt`。
    pub fn predict_with_drain(&mut self, dt_s: f64, temp_c: f64, drain_ppm: f64) {
        let dt = dt_s.max(0.0);
        if dt <= 0.0 {
            return;
        }
        let dt2 = dt * dt;
        let freq_ppm = self.x[1];
        let aging = self.x[2];
        let dtemp = temp_c - self.temp_ref_c;

        self.x[0] += (freq_ppm + self.x[3] * dtemp) * 1e-6 * dt
            + 0.5 * aging * 1e-6 * dt2 / 86_400.0
            - drain_ppm * 1e-6 * dt;
        self.x[1] += aging * dt / 86_400.0;

        // F = I + 稀疏项
        let mut f = [[0.0; N]; N];
        for i in 0..N {
            f[i][i] = 1.0;
        }
        f[0][1] = 1e-6 * dt;
        f[0][2] = 0.5 * 1e-6 * dt2 / 86_400.0;
        f[0][3] = dtemp * 1e-6 * dt;
        f[1][2] = dt / 86_400.0;

        self.p = mat_add(
            &mat_mul(&mat_mul(&f, &self.p), &transpose(&f)),
            &diag(&[
                self.cfg.q_offset * dt,
                self.cfg.q_freq * dt,
                self.cfg.q_aging * dt,
                self.cfg.q_temp * dt,
            ]),
        );
        self.clamp_state();
        self.symmetrize();
    }

    /// 用一次 NTP 偏移观测更新。`variance_s2` 是测量方差（秒²）。
    pub fn update(&mut self, offset_s: f64, variance_s2: f64) {
        if !offset_s.is_finite() || !variance_s2.is_finite() {
            return;
        }
        let r = variance_s2.max(1e-12);
        let y = offset_s - self.x[0];
        let s = self.p[0][0] + r;
        if s <= 0.0 || !s.is_finite() {
            return;
        }
        // 新息门限：坏样本不直接丢弃，而是放大 R（鲁棒更新）。
        // 冷启动前两次不做门限，否则第一次同步几秒的偏移会被“鲁棒”地压掉，
        // 导致需要很多轮才能收敛。
        let gate = if self.updates < 2 {
            f64::INFINITY
        } else {
            self.cfg.gate_sigma.max(1.0)
        };
        let norm2 = y * y / s;
        let r_eff = if norm2 > gate * gate {
            r * (norm2 / (gate * gate)).min(1e6)
        } else {
            r
        };
        let s_eff = self.p[0][0] + r_eff;
        let mut k = [0.0; N];
        for i in 0..N {
            k[i] = self.p[i][0] / s_eff;
        }
        for i in 0..N {
            self.x[i] += k[i] * y;
        }

        // Joseph 形式：P = (I-KH)P(I-KH)^T + K R K^T
        let mut a = identity();
        for i in 0..N {
            a[i][0] -= k[i];
        }
        let ap = mat_mul(&a, &self.p);
        let mut p = mat_mul(&ap, &transpose(&a));
        for i in 0..N {
            for j in 0..N {
                p[i][j] += k[i] * r_eff * k[j];
            }
        }
        self.p = p;
        self.updates = self.updates.saturating_add(1);
        self.clamp_state();
        self.symmetrize();
    }

    /// 时钟被步进 `applied_s` 后，更新偏移状态（新偏移 = 旧偏移 - 步进量）。
    pub fn correct_offset(&mut self, applied_s: f64) {
        self.x[0] -= applied_s;
        // 步进会引入新的执行误差；方差略微放大。
        self.p[0][0] += 1e-12;
    }

    /// 外部已经施加的频率修正与 KF 状态对齐时使用（例如恢复持久化状态）。
    pub fn set_freq(&mut self, freq_ppm: f64) {
        self.x[1] = freq_ppm;
        self.clamp_state();
    }

    /// 恢复持久化状态时，时钟已经被对齐到应用时间，偏移状态应清零。
    pub fn reset_offset(&mut self) {
        self.x[0] = 0.0;
        self.p[0][0] = self.p[0][0].max(1e-12);
    }

    /// 热启动/大偏移恢复时使用：避免旧的极小 P00 让新观测几乎无法改变 offset。
    pub fn inflate_offset_variance(&mut self, variance: f64) {
        self.p[0][0] = self.p[0][0].max(variance.max(1e-18));
        self.symmetrize();
    }

    /// 长基线趋势拟合结果写回。只有拟合标准误优于当前状态方差时才应调用。
    pub fn set_aging(&mut self, value: f64, sd: f64) {
        self.x[2] = value.clamp(-self.cfg.max_aging_ppm_day, self.cfg.max_aging_ppm_day);
        self.p[2][2] = (sd.max(1e-9)).powi(2);
        self.symmetrize();
    }

    pub fn set_temp_coeff(&mut self, value: f64, sd: f64) {
        self.x[3] = value.clamp(-self.cfg.max_temp_coeff, self.cfg.max_temp_coeff);
        self.p[3][3] = (sd.max(1e-9)).powi(2);
        self.symmetrize();
    }

    pub fn reset_covariance(&mut self, p_diag: [f64; 4]) {
        for i in 0..N {
            self.p[i][i] = p_diag[i].max(1e-18);
        }
        self.symmetrize();
    }

    pub fn set_temp_ref(&mut self, temp_c: f64) {
        if temp_c.is_finite() {
            self.temp_ref_c = temp_c.clamp(-40.0, 120.0);
        }
    }

    fn clamp_state(&mut self) {
        let cfg = &self.cfg;
        self.x[1] = self.x[1].clamp(-cfg.max_freq_ppm, cfg.max_freq_ppm);
        self.x[2] = self
            .x[2]
            .clamp(-cfg.max_aging_ppm_day, cfg.max_aging_ppm_day);
        self.x[3] = self.x[3].clamp(-cfg.max_temp_coeff, cfg.max_temp_coeff);
        if !self.x[0].is_finite() {
            self.x[0] = 0.0;
        }
    }

    fn symmetrize(&mut self) {
        for i in 0..N {
            for j in (i + 1)..N {
                let v = (self.p[i][j] + self.p[j][i]) * 0.5;
                self.p[i][j] = v;
                self.p[j][i] = v;
            }
            if self.p[i][i] < 1e-18 {
                self.p[i][i] = 1e-18;
            }
        }
    }
}

fn identity() -> [[f64; N]; N] {
    let mut m = [[0.0; N]; N];
    for i in 0..N {
        m[i][i] = 1.0;
    }
    m
}

fn diag(v: &[f64; N]) -> [[f64; N]; N] {
    let mut m = [[0.0; N]; N];
    for i in 0..N {
        m[i][i] = v[i];
    }
    m
}

fn transpose(a: &[[f64; N]; N]) -> [[f64; N]; N] {
    let mut m = [[0.0; N]; N];
    for i in 0..N {
        for j in 0..N {
            m[i][j] = a[j][i];
        }
    }
    m
}

fn mat_mul(a: &[[f64; N]; N], b: &[[f64; N]; N]) -> [[f64; N]; N] {
    let mut m = [[0.0; N]; N];
    for i in 0..N {
        for k in 0..N {
            let aik = a[i][k];
            if aik == 0.0 {
                continue;
            }
            for j in 0..N {
                m[i][j] += aik * b[k][j];
            }
        }
    }
    m
}

fn mat_add(a: &[[f64; N]; N], b: &[[f64; N]; N]) -> [[f64; N]; N] {
    let mut m = [[0.0; N]; N];
    for i in 0..N {
        for j in 0..N {
            m[i][j] = a[i][j] + b[i][j];
        }
    }
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 合成一个带 10ppm 频率误差、0.5ppm/day 老化、(0.8ppm/°C) 温度系数的时钟，
    /// 喂 2 天的 1 分钟 NTP 观测，检查 KF 收敛。
    #[test]
    fn estimates_frequency_aging_and_temperature() {
        let cfg = KalmanConfig {
            initial_freq_var: 100.0,
            initial_aging_var: 9.0,
            initial_temp_var: 9.0,
            ..Default::default()
        };
        let mut kf = KalmanFilter::new(cfg, KalmanState::default(), [1e-4, 100.0, 9.0, 9.0], 25.0);
        let true_freq = 10.0; // ppm
        let true_aging = 0.5; // ppm/day
        let true_temp = 0.8; // ppm/°C (correction increases with temp)
        let mut offset = 0.0;
        let dt = 60.0;
        let mut t = 0.0f64;
        let mut temp_phase = 0.0f64;
        // 用简单确定性噪声序列，避免测试依赖随机数。
        let mut noise = 0.0f64;
        for _ in 0..(2 * 86_400 / 60) {
            let temp = 25.0 + 5.0 * (temp_phase).sin();
            temp_phase += 0.001;
            t += dt;
            // 真实偏移按真实频率/老化/温度累积。
            offset += (true_freq + true_temp * (temp - 25.0) + true_aging * (t / 86_400.0))
                * 1e-6
                * dt;
            kf.predict(dt, temp);
            noise = if noise > 0.0 { -0.0004 } else { 0.0004 };
            kf.update(offset + noise, 0.001 * 0.001);
        }
        let st = kf.state();
        // 2 天后 freq 状态包含老化累积：freq(2d) = freq(0) + aging*2。
        let base_freq = st.freq_ppm - st.aging_ppm_day * 2.0;
        assert!(
            (base_freq - true_freq).abs() < 0.2,
            "base freq {base_freq} (state {} aging {})",
            st.freq_ppm,
            st.aging_ppm_day
        );
        assert!(
            (st.temp_coeff_ppm_per_c - true_temp).abs() < 0.5,
            "temp coeff {}",
            st.temp_coeff_ppm_per_c
        );
    }

    #[test]
    fn outlier_is_suppressed() {
        let mut kf = KalmanFilter::with_defaults();
        for _ in 0..20 {
            kf.predict(60.0, 25.0);
            kf.update(0.001, 1e-6);
        }
        let before = kf.state().offset_s;
        kf.update(before + 10.0, 1e-6); // 10 秒坏样本
        let after = kf.state().offset_s;
        assert!(
            (after - before).abs() < 0.1,
            "outlier moved offset by {}",
            after - before
        );
    }

    #[test]
    fn step_correction_zeros_offset() {
        let mut kf = KalmanFilter::with_defaults();
        kf.update(0.005, 1e-9);
        let off = kf.state().offset_s;
        kf.correct_offset(off);
        assert!(kf.state().offset_s.abs() < 1e-9);
    }
}
