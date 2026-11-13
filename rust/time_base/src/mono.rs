//! 单调时钟：wendung `zeitstempel`。
//!
//! `zeitstempel::now()` 返回自某个未指定原点（通常是系统启动）起的纳秒数。
//! 它的关键价值是 **跨线程一致** 且 **包含系统挂起时间**：Windows 用
//! QueryUnbiasedInterruptTime/QPC，Linux 用 CLOCK_MONOTONIC（经 QLOCK 保证多线程
//! 读一致），macOS 用 mach_continuous_time。所有换算都基于“同一进程内同一时钟”，
//! 不依赖系统墙上时钟。

/// 单调时钟读取（纳秒）。
#[inline]
pub fn now_ns() -> u64 {
    zeitstempel::now()
}

/// 单调时钟读取（秒，f64）。只用于 rusty_time 的样本时间轴，不用于绝对时间输出。
#[inline]
pub fn now_secs_f64() -> f64 {
    // 纳秒 → 秒；在当前机器 uptime 范围内 f64 的精度远优于 1ns。
    now_ns() as f64 / 1_000_000_000.0
}

/// 操作系统墙上时钟（仅用于启动引导/诊断，绝不作为应用时间权威）。
pub fn system_unix_ns() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_nanos().min(i64::MAX as u128) as i64,
        Err(e) => -(e.duration().as_nanos().min(i64::MAX as u128) as i64),
    }
}

/// 操作系统墙上时钟（秒，f64）。
pub fn system_unix_secs_f64() -> f64 {
    system_unix_ns() as f64 / 1_000_000_000.0
}

/// 单调时钟精度（纳秒），用于状态展示。
pub fn resolution_ns() -> u64 {
    // zeitstempel 没有公开分辨率 API；各平台典型值：QPC 100ns、CLOCK_MONOTONIC ~1ns。
    #[cfg(windows)]
    {
        let mut freq = 0i64;
        // SAFETY: QueryPerformanceFrequency 只写一个 i64。
        if unsafe { windows_qpc_frequency(&mut freq) } && freq > 0 {
            return (1_000_000_000i64 / freq).max(1) as u64;
        }
        100
    }
    #[cfg(not(windows))]
    {
        1
    }
}

#[cfg(windows)]
unsafe fn windows_qpc_frequency(out: &mut i64) -> bool {
    #[link(name = "kernel32")]
    extern "system" {
        fn QueryPerformanceFrequency(lpFrequency: *mut i64) -> i32;
    }
    QueryPerformanceFrequency(out) != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn monotonic_never_goes_backwards() {
        let mut prev = now_ns();
        for _ in 0..10_000 {
            let now = now_ns();
            assert!(now >= prev, "monotonic clock went backwards: {prev} -> {now}");
            prev = now;
        }
    }

    #[test]
    fn system_clock_is_plausible() {
        // 2020-01-01 .. 2200-01-01
        let ns = system_unix_ns();
        assert!(ns > 1_577_836_800_000_000_000);
        assert!(ns < 7_258_118_400_000_000_000);
    }
}
