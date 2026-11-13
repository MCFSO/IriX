//! HTTPS/TLS 的时间权威。
//!
//! rustls 在验证服务器证书时需要“当前时间”，默认实现读取操作系统时钟。
//! IriX 的证书有效期必须由本时间系统裁决——即使系统时钟被手动改错、或机器长期
//! 离线后系统时间漂移，只要 NTP 已同步，TLS 仍按真实时间判断证书是否过期。
//!
//! `link::now_unix_ns()` 会优先调用已加载的 `xmc_time.dll` 导出的
//! `xmc_time_now_unix_ns`；动态库不存在时退回本进程内以单调时钟锚定的估计值。
//! 这样 http_client / downloader 各自 DLL 里的 rustls 都能拿到同一个时间权威。

use std::sync::{Arc, OnceLock};
use std::time::Duration;

use rustls::client::ClientConfig;
use rustls::pki_types::UnixTime;
use rustls::time_provider::TimeProvider;
use rustls::RootCertStore;

#[derive(Debug)]
struct AppTimeProvider;

impl TimeProvider for AppTimeProvider {
    fn current_time(&self) -> Option<UnixTime> {
        let ns = xmc_time_base::now_unix_ns();
        if ns <= 0 {
            return None;
        }
        let secs = (ns / 1_000_000_000) as u64;
        let nanos = (ns % 1_000_000_000) as u32;
        Some(UnixTime::since_unix_epoch(Duration::new(secs, nanos)))
    }
}

static CONFIG: OnceLock<Arc<ClientConfig>> = OnceLock::new();

/// 构建使用应用时钟的 rustls 客户端配置（webpki 根证书 + ring）。
pub fn client_config() -> Arc<ClientConfig> {
    CONFIG
        .get_or_init(|| {
            let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            let provider = Arc::new(rustls::crypto::ring::default_provider());
            let cfg = ClientConfig::builder_with_details(provider, Arc::new(AppTimeProvider))
                .with_safe_default_protocol_versions()
                .expect("ring provider 必须支持默认 TLS 版本")
                .with_root_certificates(roots)
                .with_no_client_auth();
            Arc::new(cfg)
        })
        .clone()
}

/// 直接取“TLS 眼中的现在”（秒），用于诊断与测试。
pub fn current_tls_time_s() -> Option<u64> {
    AppTimeProvider.current_time().map(|t| t.as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tls_time_follows_app_clock() {
        let now = current_tls_time_s().expect("time");
        let sys = xmc_time_base::mono::system_unix_ns() as u64 / 1_000_000_000;
        assert!(now.abs_diff(sys) < 2, "TLS time {now} vs system {sys}");
    }

    #[test]
    fn client_config_builds() {
        let cfg = client_config();
        assert!(cfg.alpn_protocols.is_empty());
        // 两次调用应复用同一份配置
        assert!(Arc::ptr_eq(&cfg, &client_config()));
    }
}
