// IriX 示例插件
//
// 演示一个符合宿主 C ABI 约定的原生插件：
//   plugin_init() -> i32
//   plugin_name() -> *const c_char
//   plugin_version() -> *const c_char
//   plugin_handle_event(type, payload) -> *const c_char
//   plugin_shutdown()
//
// 关键约定：所有返回给宿主的字符串用 libc::malloc 分配，宿主用 libc::free 释放。
// 宿主与插件之间的所有数据用 JSON 字符串传递。

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::json;

/// 用 libc::malloc 分配一块以 NUL 结尾的 UTF-8 缓冲区并返回指针。
/// 调用方（宿主）负责用 libc::free 释放。
fn alloc_c_string(s: &str) -> *const c_char {
    let bytes = s.as_bytes();
    let size = bytes.len() + 1;
    unsafe {
        let ptr = libc::malloc(size) as *mut u8;
        if ptr.is_null() {
            return std::ptr::null();
        }
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
        *ptr.add(bytes.len()) = 0;
        ptr as *const c_char
    }
}

/// 读取参数 C 字符串为 Rust String（空指针返回空串）。
fn read_param(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned()
}

#[no_mangle]
pub extern "C" fn plugin_init() -> c_int {
    // 返回 0 表示初始化成功。
    0
}

#[no_mangle]
pub extern "C" fn plugin_name() -> *const c_char {
    alloc_c_string("Example Plugin")
}

#[no_mangle]
pub extern "C" fn plugin_version() -> *const c_char {
    alloc_c_string("1.0.0")
}

#[no_mangle]
pub extern "C" fn plugin_handle_event(
    event_type: *const c_char,
    payload: *const c_char,
) -> *const c_char {
    let event = read_param(event_type);
    let payload = read_param(payload);

    // 尝试把 payload 当 JSON 解析；失败则当作纯文本回显。
    let payload_json: serde_json::Value =
        serde_json::from_str(&payload).unwrap_or_else(|_| json!({ "raw": payload }));

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);

    let result = json!({
        "plugin": "irix-example-plugin",
        "handled_event": event,
        "received_payload": payload_json,
        "timestamp_ms": timestamp,
    });

    alloc_c_string(&result.to_string())
}

#[no_mangle]
pub extern "C" fn plugin_shutdown() {
    // 清理资源（本示例无）。
}
