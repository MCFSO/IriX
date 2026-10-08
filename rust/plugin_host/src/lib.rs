// 插件宿主动态库 (xmc_plugin_host)
//
// 通过 C ABI 向 Flutter（dart:ffi）暴露插件管理接口：
//   plg_init(base_dir, host_version)  初始化：创建目录 + 处理待删除队列 + 扫描加载
//   plg_list()                         返回插件列表 JSON 数组
//   plg_detail(id)                     返回单个插件详情 JSON
//   plg_readme(id)                     返回 README.md 内容
//   plg_install(zip_path)              安装插件包，返回 JSON {ok,id,message}
//   plg_uninstall(id)                  卸载
//   plg_toggle(id, enabled)            启用/禁用
//   plg_dispatch(event_type, payload)  向启用插件派发事件，返回结果 JSON 数组
//   plg_shutdown()                     关闭全部插件
//   get_last_error() / free_string()   错误与字符串释放（Rust 分配）
//
// 插件本身的加载/事件分发/权限检查全部在此侧完成，Flutter 只做 UI。

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::path::PathBuf;
use std::sync::Mutex;

use crate::registry::PluginRegistry;

mod abi;
mod loader;
mod manifest;
mod registry;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

/// 全局注册表（一次初始化）。
static REGISTRY: Mutex<Option<PluginRegistry>> = Mutex::new(None);

/// 在锁内以可变引用操作注册表。未初始化返回 Err(())。
fn with_registry_mut<R>(f: impl FnOnce(&mut PluginRegistry) -> R) -> Result<R, ()> {
    let mut guard = REGISTRY.lock().map_err(|_| {
        set_last_error("插件系统锁获取失败");
    })?;
    let reg = guard.as_mut().ok_or_else(|| {
        set_last_error("插件系统未初始化");
    })?;
    Ok(f(reg))
}

/// 在锁内以不可变引用操作注册表。未初始化返回 Err(())。
fn with_registry_ref<R>(f: impl FnOnce(&PluginRegistry) -> R) -> Result<R, ()> {
    let guard = REGISTRY.lock().map_err(|_| {
        set_last_error("插件系统锁获取失败");
    })?;
    let reg = guard.as_ref().ok_or_else(|| {
        set_last_error("插件系统未初始化");
    })?;
    Ok(f(reg))
}

// ==================== 字符串工具（宿主分配，Dart 用 free_string 释放） ====================

#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("未知错误").ok());
        cstr.unwrap_or_else(|| CString::new("未知错误").unwrap())
            .into_raw()
    })
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 把 Rust String 转成宿主分配的 C 字符串并返回裸指针。失败返回空指针。
fn to_c_string(s: &str) -> *mut libc::c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 读 C 字符串参数为 String。
fn read_param(ptr: *const libc::c_char, what: &str) -> Result<String, ()> {
    if ptr.is_null() {
        set_last_error(format!("{what} 为空指针"));
        return Err(());
    }
    match unsafe { CStr::from_ptr(ptr) }.to_str() {
        Ok(s) => Ok(s.to_string()),
        Err(_) => {
            set_last_error(format!("{what} 不是有效的 UTF-8"));
            Err(())
        }
    }
}

// ==================== 初始化 / 关闭 ====================

/// 初始化插件系统。
/// [base_dir] 为插件根目录；[host_version] 为宿主版本（用于 min_app_version 校验）。
#[no_mangle]
pub extern "C" fn plg_init(
    base_dir: *const libc::c_char,
    host_version: *const libc::c_char,
) -> libc::c_int {
    let dir = match read_param(base_dir, "base_dir") {
        Ok(s) => s,
        Err(_) => return 1,
    };
    let version = match read_param(host_version, "host_version") {
        Ok(s) => s,
        Err(_) => return 1,
    };

    match PluginRegistry::init(PathBuf::from(dir), version) {
        Ok(reg) => {
            if let Ok(mut guard) = REGISTRY.lock() {
                *guard = Some(reg);
                0
            } else {
                set_last_error("无法初始化插件系统锁");
                1
            }
        }
        Err(e) => {
            set_last_error(e);
            2
        }
    }
}

/// 关闭全部插件（应用退出前调用）。
#[no_mangle]
pub extern "C" fn plg_shutdown() {
    let reg = REGISTRY.lock().ok().and_then(|mut guard| guard.take());
    if let Some(mut reg) = reg {
        reg.shutdown_all();
    }
}

// ==================== 列表 / 详情 ====================

/// 列出全部插件（JSON 数组，不含 README 正文）。
#[no_mangle]
pub extern "C" fn plg_list() -> *mut libc::c_char {
    let arr = match with_registry_ref(|reg| {
        reg.plugins.values().map(|p| p.info()).collect::<Vec<_>>()
    }) {
        Ok(a) => a,
        Err(()) => return std::ptr::null_mut(),
    };
    match serde_json::to_string(&arr) {
        Ok(json) => to_c_string(&json),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// 单个插件详情（JSON 对象，不含 README 正文）。
#[no_mangle]
pub extern "C" fn plg_detail(id: *const libc::c_char) -> *mut libc::c_char {
    let id = match read_param(id, "id") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let value = match with_registry_ref(|reg| reg.plugins.get(&id).map(|e| e.info())) {
        Ok(Some(v)) => v,
        Ok(None) => {
            set_last_error(format!("插件不存在: {id}"));
            return std::ptr::null_mut();
        }
        Err(()) => return std::ptr::null_mut(),
    };
    match serde_json::to_string(&value) {
        Ok(json) => to_c_string(&json),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// 读取插件 README 内容（用于详情预览）。
#[no_mangle]
pub extern "C" fn plg_readme(id: *const libc::c_char) -> *mut libc::c_char {
    let id = match read_param(id, "id") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let readme = match with_registry_ref(|reg| reg.readme(&id)) {
        Ok(r) => r,
        Err(()) => return std::ptr::null_mut(),
    };
    to_c_string(&readme)
}

// ==================== 安装 / 卸载 / 启用禁用 ====================

/// 安装插件：zip 包路径，返回 JSON {ok, id?, message, warning?}。
/// `warning` 表示包已安装但加载失败（如当前平台缺对应动态库）。
#[no_mangle]
pub extern "C" fn plg_install(zip_path: *const libc::c_char) -> *mut libc::c_char {
    let zip_path = match read_param(zip_path, "zip_path") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let result = match with_registry_mut(|reg| reg.install(&zip_path)) {
        Ok(r) => r,
        Err(()) => return std::ptr::null_mut(),
    };
    let json = match result {
        Ok((id, warning)) => {
            let mut obj = serde_json::json!({
                "ok": true,
                "id": id,
                "message": "安装成功",
            });
            if let Some(w) = warning {
                obj["warning"] = serde_json::Value::String(w);
            }
            obj.to_string()
        }
        Err(e) => {
            set_last_error(&e);
            serde_json::json!({"ok": false, "message": e}).to_string()
        }
    };
    to_c_string(&json)
}

/// 卸载插件。返回 0 表示成功（含“标记重启后生效”）。
#[no_mangle]
pub extern "C" fn plg_uninstall(id: *const libc::c_char) -> libc::c_int {
    let id = match read_param(id, "id") {
        Ok(s) => s,
        Err(_) => return 1,
    };
    match with_registry_mut(|reg| reg.uninstall(&id)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_last_error(e);
            2
        }
        Err(()) => 1,
    }
}

/// 启用 / 禁用插件。enabled 非 0 表示启用。
#[no_mangle]
pub extern "C" fn plg_toggle(id: *const libc::c_char, enabled: libc::c_int) -> libc::c_int {
    let id = match read_param(id, "id") {
        Ok(s) => s,
        Err(_) => return 1,
    };
    let on = enabled != 0;
    match with_registry_mut(|reg| reg.toggle(&id, on)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            set_last_error(e);
            2
        }
        Err(()) => 1,
    }
}

// ==================== 事件分发 ====================

/// 向所有启用插件派发事件，返回 JSON 数组。
#[no_mangle]
pub extern "C" fn plg_dispatch(
    event_type: *const libc::c_char,
    payload: *const libc::c_char,
) -> *mut libc::c_char {
    let event_type = match read_param(event_type, "event_type") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let payload = match read_param(payload, "payload") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let results = match with_registry_mut(|reg| reg.dispatch(&event_type, &payload)) {
        Ok(r) => r,
        Err(()) => return std::ptr::null_mut(),
    };
    match serde_json::to_string(&results) {
        Ok(json) => to_c_string(&json),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}
