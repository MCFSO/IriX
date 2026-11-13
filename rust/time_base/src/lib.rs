//! IriX 时间系统基础层（`xmc_time_base`，rlib）。
//!
//! 这里只放 **没有网络、没有 TLS、没有 NTP** 的底层能力，供所有 Rust crate 共享：
//! - [`mono`]：`zeitstempel` 单调时钟；
//! - [`civil`] / [`httpdate`]：无 chrono 依赖的日历与 HTTP 日期换算；
//! - [`link`]：运行时加载 `xmc_time.dll` 的跨 DLL 时间桥（找不到时退化为单调锚定）。
//!
//! 真正的 NTP 客户端与纪律环在 `xmc_time`（cdylib）里，避免每个 FFI DLL 都打包一份
//! NTP/TLS 代码；rustls 时间提供者在 `xmc_time_tls`。

pub mod civil;
pub mod httpdate;
pub mod link;
pub mod mono;

pub use link::{diagnostics, now_unix_ms, now_unix_ns, now_unix_s, note_http_date, synced, uncertainty_ns, BridgeInfo};

/// 便于其它 crate 直接格式化日志时间。
pub fn format_iso8601_ms(unix_ms: i64) -> String {
    civil::format_iso8601_ms(unix_ms)
}

pub fn format_compact_utc(unix_s: i64) -> String {
    civil::format_compact_utc(unix_s)
}

pub fn format_http_date(unix_s: i64) -> String {
    httpdate::format_http_date(unix_s)
}
