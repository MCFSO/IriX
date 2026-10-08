// 插件 C ABI 接口定义（宿主侧约定，插件必须导出这些符号）
//
// 插件以 C ABI 与宿主通信，宿主不依赖任何 Rust 具体 ABI。所有跨边界数据
// 用 JSON 字符串传递；插件返回的字符串由插件按 libc::malloc 分配，宿主用
// libc::free 释放（见 [free_c_string]）。
//
// 约定的导出函数：
//   plugin_init() -> i32                      // 0 成功
//   plugin_name() -> *const c_char             // 插件名（C 字符串）
//   plugin_version() -> *const c_char          // 插件版本
//   plugin_handle_event(type, payload) -> *const c_char  // 返回 JSON 结果
//   plugin_shutdown()                          // 清理
//
// 通过 libloading 以 Symbol<T> 方式加载并调用。

use std::os::raw::{c_char, c_int};

/// 事件类型常量（宿主向插件派发的事件）。
/// 与 Flutter / Rust 宿主侧保持一致。
#[allow(dead_code)]
pub mod event_type {
    pub const INSTANCE_STARTED: &str = "instance.started";
    pub const INSTANCE_STOPPED: &str = "instance.stopped";
    pub const BACKUP_COMPLETED: &str = "backup.completed";
    pub const SERVER_READY: &str = "server.ready";
}

/// 插件导出的一组 C 函数指针，宿主加载后一次性查询。
#[derive(Clone, Copy)]
pub struct PluginApi {
    pub init: unsafe extern "C" fn() -> c_int,
    pub name: unsafe extern "C" fn() -> *const c_char,
    pub version: unsafe extern "C" fn() -> *const c_char,
    pub handle_event: unsafe extern "C" fn(*const c_char, *const c_char) -> *const c_char,
    pub shutdown: unsafe extern "C" fn(),
}

/// 释放插件返回的字符串：约定插件用 libc::malloc 分配，这里用 libc::free 释放。
/// 传入的是指向字符串内容开头的裸指针（非 CString::into_raw 的包装），因此
/// 不能走 CString::from_raw（那会假定 String 布局，不安全）。
pub unsafe fn free_c_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { libc::free(ptr as *mut libc::c_void) };
    }
}

/// 把插件返回的 C 字符串读成 Rust String（不含结尾 NUL）。
/// 返回 None 表示空指针或不是有效 UTF-8。
pub unsafe fn read_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let bytes = unsafe { libc::strlen(ptr) };
    if bytes == 0 {
        return Some(String::new());
    }
    let slice = unsafe { std::slice::from_raw_parts(ptr as *const u8, bytes) };
    String::from_utf8(slice.to_vec()).ok()
}
