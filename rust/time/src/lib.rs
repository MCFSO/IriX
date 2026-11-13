//! IriX 统一时间系统（`xmc_time`）。
//!
//! 目标：应用内所有“现在”都来自同一个可解释、可校准、可审计的时间权威，
//! 不再各 crate 各自 `SystemTime::now()`：
//!
//! - **单调时钟**：`zeitstempel`（跨线程一致、包含挂起时间），在 `xmc_time_base`；
//! - **NTP 客户端**：`rusty_time-core` 的 NTPv4 编解码/回归滤波/纪律环，
//!   本 crate 提供 UDP I/O、防欺骗校验、多源选择；
//! - **漂移补偿**：回归斜率直接测频 + 临时 drain 预算；
//! - **精度提升**：`high_precision_clock` 的 TSC 插值（x86_64），把 NTP 收发
//!   时间戳的量化误差压到亚百纳秒；
//! - **HTTPS**：`xmc_time_tls` 的 rustls `TimeProvider` 用本时钟裁决证书有效期；
//! - **持久化**：热启动沿用上次偏移认知，断网时按保持漂移预算给出不确定度；
//! - **跨 DLL**：`xmc_time_base::link` 动态加载本 DLL，其它 FFI 库共享同一时间权威。
//!
//! FFI 入口见 [`ffi::time_request`]；Dart 封装在 `lib/services/time_ffi.dart`。

pub mod clock;
pub mod ffi;
pub mod gnss_bridge;
pub mod kalman;
pub mod ntp;
pub mod precise;
pub mod service;
pub mod state;
pub mod thermal;
pub mod trend;

pub use clock::{AppClock, ClockSnapshot, SyncInfo};
pub use service::{Config, Service, Status};

/// 便于其它 crate 直接格式化日志时间，无需再复制一份日历算法。
pub fn format_iso8601_ms(unix_ms: i64) -> String {
    xmc_time_base::civil::format_iso8601_ms(unix_ms)
}

pub fn format_compact_utc(unix_s: i64) -> String {
    xmc_time_base::civil::format_compact_utc(unix_s)
}

pub fn format_http_date(unix_s: i64) -> String {
    xmc_time_base::httpdate::format_http_date(unix_s)
}
