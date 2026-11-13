//! 跨 DLL 的时间桥。
//!
//! 每个 `xmc_*.dll` 都静态链接自己的一份 Rust 代码，静态状态不共享。为了让
//! http_client / downloader 的 TLS 校验、devlog 的日志时间戳、backup/orchestrator
//! 的时间字段都指向 **同一个** 时间权威，本模块在运行时加载 `xmc_time.dll` 并调用
//! 其导出的 C 函数。
//!
//! - 找到动态库：用它的应用时钟（NTP 同步后的真实时间）；
//! - 找不到（例如单独跑 `cargo test -p xmc_http_client`）：退回本进程内以
//!   `zeitstempel` 单调时钟锚定的系统时间估计，保证功能可用且不会倒退。

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use libloading::Library;

type NowFn = unsafe extern "C" fn() -> i64;
type SyncedFn = unsafe extern "C" fn() -> libc::c_int;
type UncertaintyFn = unsafe extern "C" fn() -> i64;
type NoteDateFn = unsafe extern "C" fn(i64, i64) -> i64;

struct Bridge {
    _lib: Library,
    now_ns: NowFn,
    synced: SyncedFn,
    uncertainty_ns: UncertaintyFn,
    note_http_date: Option<NoteDateFn>,
    path: PathBuf,
}

// SAFETY: `libloading::Library` 的符号在进程生命周期内保持有效；函数指针本身是
// 不可变代码地址，可安全跨线程共享。Library 的 Drop 只会在静态销毁时发生。
unsafe impl Send for Bridge {}
unsafe impl Sync for Bridge {}

fn library_name() -> &'static str {
    if cfg!(windows) {
        "xmc_time.dll"
    } else if cfg!(target_os = "macos") {
        "libxmc_time.dylib"
    } else {
        "libxmc_time.so"
    }
}

fn candidate_paths() -> Vec<PathBuf> {
    let name = library_name();
    let mut dirs: Vec<PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            dirs.push(parent.to_path_buf());
            // Linux Flutter bundle：可执行文件在 bundle/，动态库在 bundle/lib/。
            dirs.push(parent.join("lib"));
            // macOS .app bundle：Contents/MacOS -> Contents/Frameworks
            dirs.push(parent.join("../Frameworks"));
            dirs.push(parent.join("../Resources"));
            dirs.push(parent.join("../lib"));
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        dirs.push(cwd.clone());
        dirs.push(cwd.join("windows/runner"));
        dirs.push(cwd.join("linux"));
        dirs.push(cwd.join("macos"));
        dirs.push(cwd.join("build/windows/x64/runner/Release"));
    }
    let mut out = Vec::new();
    for d in dirs {
        let p = d.join(name);
        if !out.contains(&p) {
            out.push(p);
        }
    }
    out
}

fn load_from(path: &Path) -> Option<Bridge> {
    if !path.is_file() {
        return None;
    }
    // SAFETY: 只加载本应用自带的动态库；函数签名与 Rust 导出一致。
    let lib = unsafe { Library::new(path) }.ok()?;
    unsafe {
        let now_ns: NowFn = *lib.get(b"xmc_time_now_unix_ns\0").ok()?;
        let synced: SyncedFn = *lib.get(b"xmc_time_synced\0").ok()?;
        let uncertainty_ns: UncertaintyFn = *lib.get(b"xmc_time_uncertainty_ns\0").ok()?;
        let note_http_date: Option<NoteDateFn> = lib
            .get::<NoteDateFn>(b"xmc_time_note_http_date\0")
            .ok()
            .map(|s| *s);
        Some(Bridge {
            _lib: lib,
            now_ns,
            synced,
            uncertainty_ns,
            note_http_date,
            path: path.to_path_buf(),
        })
    }
}

fn load() -> Option<Bridge> {
    for p in candidate_paths() {
        if let Some(b) = load_from(&p) {
            return Some(b);
        }
    }
    // 最后交给系统搜索路径（安装目录通常已在 PATH / 应用目录）。
    // SAFETY: 同上。
    unsafe {
        let lib = Library::new(library_name()).ok()?;
        let now_ns: NowFn = *lib.get(b"xmc_time_now_unix_ns\0").ok()?;
        let synced: SyncedFn = *lib.get(b"xmc_time_synced\0").ok()?;
        let uncertainty_ns: UncertaintyFn = *lib.get(b"xmc_time_uncertainty_ns\0").ok()?;
        let note_http_date: Option<NoteDateFn> = lib
            .get::<NoteDateFn>(b"xmc_time_note_http_date\0")
            .ok()
            .map(|s| *s);
        Some(Bridge {
            _lib: lib,
            now_ns,
            synced,
            uncertainty_ns,
            note_http_date,
            path: PathBuf::from(library_name()),
        })
    }
}

fn bridge() -> Option<&'static Bridge> {
    static BRIDGE: OnceLock<Option<Bridge>> = OnceLock::new();
    BRIDGE.get_or_init(load).as_ref()
}

/// 本进程的兜底时间：以单调时钟锚定首次调用时的系统时间。
fn fallback_now_ns() -> i64 {
    static ANCHOR: OnceLock<(u64, i64)> = OnceLock::new();
    let (m0, u0) = ANCHOR.get_or_init(|| (crate::mono::now_ns(), crate::mono::system_unix_ns()));
    u0 + crate::mono::now_ns().saturating_sub(*m0) as i64
}

/// 当前 Unix 纳秒（应用时间权威）。
pub fn now_unix_ns() -> i64 {
    if let Some(b) = bridge() {
        // SAFETY: 函数指针来自已加载动态库的有效导出。
        let v = unsafe { (b.now_ns)() };
        if v > 0 {
            return v;
        }
    }
    fallback_now_ns()
}

pub fn now_unix_ms() -> i64 {
    now_unix_ns().div_euclid(1_000_000)
}

pub fn now_unix_s() -> i64 {
    now_unix_ns().div_euclid(1_000_000_000)
}

pub fn synced() -> bool {
    bridge()
        .map(|b| unsafe { (b.synced)() != 0 })
        .unwrap_or(false)
}

pub fn uncertainty_ns() -> i64 {
    bridge()
        .map(|b| unsafe { (b.uncertainty_ns)() })
        .unwrap_or(250_000_000)
}

/// 把 HTTPS 响应的 `Date` 头交给时间系统做偏差诊断（不会拨钟）。
pub fn note_http_date(server_unix_s: i64, rtt_ms: i64) -> i64 {
    if let Some(b) = bridge() {
        if let Some(f) = b.note_http_date {
            return unsafe { f(server_unix_s, rtt_ms) };
        }
    }
    let local_s = now_unix_s();
    (server_unix_s - local_s) * 1_000 - rtt_ms / 2
}

/// 诊断信息：桥是否接上、接的是哪个文件。
#[derive(Clone, Debug)]
pub struct BridgeInfo {
    pub attached: bool,
    pub path: Option<String>,
    pub fallback: bool,
}

pub fn diagnostics() -> BridgeInfo {
    match bridge() {
        Some(b) => BridgeInfo {
            attached: true,
            path: Some(b.path.to_string_lossy().to_string()),
            fallback: false,
        },
        None => BridgeInfo {
            attached: false,
            path: None,
            fallback: true,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn now_is_plausible_and_monotonic() {
        let a = now_unix_ns();
        assert!(a > 1_577_836_800_000_000_000);
        let b = now_unix_ns();
        assert!(b >= a);
    }

    #[test]
    fn diagnostics_never_panics() {
        let info = diagnostics();
        assert!(info.attached || info.fallback);
    }
}
