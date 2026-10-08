// 宿主加载器：用 libloading 加载插件动态库 + catch_unwind 隔离 panic
//
// 每个插件在进程中常驻，不支持热卸载。加载成功后返回 [LoadedPlugin]，
// 其中保存了 C 函数指针与选定的动态库句柄（句柄必须存续以维持函数指针有效）。

use std::path::Path;

use libloading::Library;

use crate::abi::{self, PluginApi};

/// 已成功加载的插件运行时句柄。
///
/// 持有 [Library] 以维持已解析函数指针的有效性（库不能提前 unload）。
pub struct LoadedPlugin {
    /// 动态库句柄（仅用于保持库驻留，不直接使用）。
    #[allow(dead_code)]
    lib: Library,
    /// 插件导出函数集合。
    pub api: PluginApi,
}

impl LoadedPlugin {
    /// 加载指定动态库并解析约定符号。
    ///
    /// - 找不到符号返回 Err，不 panic；
    /// - 加载过程用 catch_unwind 包裹，避免库异常带崩宿主。
    pub fn load(path: &Path) -> Result<Self, String> {
        let path_buf = path.to_path_buf();
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            Self::load_inner(&path_buf)
        }))
        .map_err(|_| "加载插件动态库时发生 panic".to_string())?
    }

    unsafe fn load_inner(path: &Path) -> Result<Self, String> {
        let lib = unsafe { Library::new(path) }
            .map_err(|e| format!("无法加载动态库 {}: {e}", path.display()))?;

        let api = unsafe {
            PluginApi {
                init: *lib
                    .get::<unsafe extern "C" fn() -> libc::c_int>(b"plugin_init\0")
                    .map_err(|e| format!("缺少 plugin_init 符号: {e}"))?,
                name: *lib
                    .get::<unsafe extern "C" fn() -> *const libc::c_char>(b"plugin_name\0")
                    .map_err(|e| format!("缺少 plugin_name 符号: {e}"))?,
                version: *lib
                    .get::<unsafe extern "C" fn() -> *const libc::c_char>(b"plugin_version\0")
                    .map_err(|e| format!("缺少 plugin_version 符号: {e}"))?,
                handle_event: *lib
                    .get::<
                        unsafe extern "C" fn(
                            *const libc::c_char,
                            *const libc::c_char,
                        ) -> *const libc::c_char,
                    >(b"plugin_handle_event\0")
                    .map_err(|e| format!("缺少 plugin_handle_event 符号: {e}"))?,
                shutdown: *lib
                    .get::<unsafe extern "C" fn()>(b"plugin_shutdown\0")
                    .map_err(|e| format!("缺少 plugin_shutdown 符号: {e}"))?,
            }
        };

        Ok(Self { lib, api })
    }

    /// 调用 plugin_init。成功返回 0。用 catch_unwind 隔离 panic。
    pub fn init(&self) -> Result<(), String> {
        let rc = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            (self.api.init)()
        }))
        .map_err(|_| "plugin_init 发生 panic".to_string())?;
        if rc != 0 {
            return Err(format!("plugin_init 返回非零: {rc}"));
        }
        Ok(())
    }

    /// 调用 plugin_name / plugin_version，经 libc::malloc/free 约定读取并释放。
    #[allow(dead_code)]
    pub fn read_name_version(&self) -> (String, String) {
        let name = unsafe {
            let p = (self.api.name)();
            let s = abi::read_c_str(p).unwrap_or_default();
            abi::free_c_string(p as *mut _);
            s
        };
        let version = unsafe {
            let p = (self.api.version)();
            let s = abi::read_c_str(p).unwrap_or_default();
            abi::free_c_string(p as *mut _);
            s
        };
        (name, version)
    }

    /// 调用 plugin_handle_event(type, payload)，返回插件 JSON 结果字符串。
    /// 每次调用都用 catch_unwind 包裹并释放插件返回的内存。
    pub fn handle_event(&self, event_type: &str, payload: &str) -> Result<String, String> {
        let event_c =
            std::ffi::CString::new(event_type).map_err(|_| "事件类型含 NUL 字节".to_string())?;
        let payload_c =
            std::ffi::CString::new(payload).map_err(|_| "payload 含 NUL 字节".to_string())?;

        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            (self.api.handle_event)(event_c.as_ptr(), payload_c.as_ptr())
        }))
        .map_err(|_| "plugin_handle_event 发生 panic".to_string())?;

        unsafe {
            let s = abi::read_c_str(result).ok_or_else(|| {
                abi::free_c_string(result as *mut _);
                "plugin_handle_event 返回空指针或非 UTF-8".to_string()
            })?;
            abi::free_c_string(result as *mut _);
            Ok(s)
        }
    }

    /// 调用 plugin_shutdown（捕获 panic）。
    pub fn shutdown(&self) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            (self.api.shutdown)();
        }));
    }
}
