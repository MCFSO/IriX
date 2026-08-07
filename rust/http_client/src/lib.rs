//! XMC Server Launcher 通用 HTTP 请求模块
//!
//! 基于 ureq + rustls 的同步 HTTP 客户端，供 Flutter 通过 FFI 调用。
//! 独立编译为 xmc_http_client.dll，与下载模块 (xmc_downloader.dll) 解耦。
//!
//! 支持 GET/POST/PUT/PATCH/DELETE/HEAD，自定义请求头、请求体、超时与重定向。
//! 一次调用返回完整响应（状态码 + 响应头 + base64 编码的响应体），
//! 结果以 JSON 字符串形式返回，由 Dart 侧解析：
//!
//! - 成功: `{"ok":true,"status":200,"headers":{...},"body_b64":"..."}`
//! - 失败: `{"ok":false,"status":503,"error":"..."}`（status 为 HTTP 状态码时存在）

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::io::Read;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::Duration;

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde_json::json;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// 响应体大小上限 (16 MiB)，防止意外大响应耗尽内存。
const MAX_BODY_BYTES: u64 = 16 * 1024 * 1024;

const DEFAULT_USER_AGENT: &str = "IriX/1.0.0 (https://github.com/MCFSO/IriX)";

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

/// 把结果字符串包装成 C 字符串指针返回（Dart 侧用 free_string 释放）。
fn cstring_out(s: String) -> *mut libc::c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => {
            // 理论上不会发生（输入均为 UTF-8 且无 nul），兜底返回错误 JSON。
            CString::new(r#"{"ok":false,"error":"结果字符串包含 nul 字节"}"#)
                .unwrap()
                .into_raw()
        }
    }
}

fn error_json(message: String) -> String {
    json!({ "ok": false, "error": message }).to_string()
}

/// 发送 HTTP 请求并返回完整响应。
///
/// # 参数
/// - `method`: HTTP 方法 (GET/POST/PUT/PATCH/DELETE/HEAD)
/// - `url`: 完整 URL
/// - `headers_json`: JSON 对象字符串，如 `{"User-Agent":"x","Accept":"application/json"}`
/// - `body`: 请求体字节指针（可为空指针表示无请求体）
/// - `body_len`: 请求体字节数
/// - `timeout_secs`: 读取超时（秒），0 表示使用默认值 60
/// - `max_redirects`: 最大重定向次数
///
/// # 返回值
/// 返回堆分配的 JSON 字符串（Dart 侧用 `free_string` 释放）：
/// - 成功: `{"ok":true,"status":200,"headers":{"k":["v"]},"body_b64":"..."}`
/// - 失败: `{"ok":false,"status":503,"error":"..."}`
#[no_mangle]
pub extern "C" fn http_request(
    method: *const libc::c_char,
    url: *const libc::c_char,
    headers_json: *const libc::c_char,
    body: *const libc::c_uchar,
    body_len: libc::size_t,
    timeout_secs: u64,
    max_redirects: libc::c_uint,
) -> *mut libc::c_char {
    catch_unwind(AssertUnwindSafe(|| http_request_inner(
        method, url, headers_json, body, body_len, timeout_secs, max_redirects,
    )))
    .unwrap_or_else(|_| {
        let msg = "Rust panic in http_request".to_string();
        set_last_error(&msg);
        cstring_out(error_json(msg))
    })
}

fn http_request_inner(
    method: *const libc::c_char,
    url: *const libc::c_char,
    headers_json: *const libc::c_char,
    body: *const libc::c_uchar,
    body_len: libc::size_t,
    timeout_secs: u64,
    max_redirects: libc::c_uint,
) -> *mut libc::c_char {
    if method.is_null() {
        return cstring_out(error_json("method 为空指针".to_string()));
    }
    let method_str = match unsafe { CStr::from_ptr(method) }.to_str() {
        Ok(s) => s,
        Err(_) => return cstring_out(error_json("method 不是有效的 UTF-8".to_string())),
    };
    if url.is_null() {
        return cstring_out(error_json("url 为空指针".to_string()));
    }
    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s,
        Err(_) => return cstring_out(error_json("url 不是有效的 UTF-8".to_string())),
    };

    let headers: serde_json::Map<String, serde_json::Value> = if headers_json.is_null() {
        Default::default()
    } else {
        let raw = match unsafe { CStr::from_ptr(headers_json) }.to_str() {
            Ok(s) => s,
            Err(_) => return cstring_out(error_json("headers 不是有效的 UTF-8".to_string())),
        };
        match serde_json::from_str(raw) {
            Ok(v) => v,
            Err(e) => return cstring_out(error_json(format!("headers JSON 解析失败: {e}"))),
        }
    };

    let body_bytes: &[u8] = if body.is_null() || body_len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(body, body_len) }
    };

    let result = do_request(
        method_str,
        url_str,
        &headers,
        body_bytes,
        timeout_secs,
        max_redirects,
    );
    match result {
        Ok(json_str) => {
            let ptr = cstring_out(json_str);
            ptr
        }
        Err(e) => {
            set_last_error(&e);
            cstring_out(error_json(e))
        }
    }
}

fn do_request(
    method: &str,
    url: &str,
    headers: &serde_json::Map<String, serde_json::Value>,
    body: &[u8],
    timeout_secs: u64,
    max_redirects: u32,
) -> Result<String, String> {
    let read_timeout = if timeout_secs > 0 {
        Duration::from_secs(timeout_secs)
    } else {
        Duration::from_secs(60)
    };

    let agent = ureq::AgentBuilder::new()
        .user_agent(DEFAULT_USER_AGENT)
        .timeout_connect(Duration::from_secs(30))
        .timeout_read(read_timeout)
        .redirects(max_redirects.max(1))
        .build();

    // 构建请求
    let request = match method.to_ascii_uppercase().as_str() {
        "GET" => agent.get(url),
        "POST" => agent.post(url),
        "PUT" => agent.put(url),
        "PATCH" => agent.patch(url),
        "DELETE" => agent.delete(url),
        "HEAD" => agent.head(url),
        other => {
            return Err(format!("不支持的 HTTP 方法: {other}"));
        }
    };

    let request = headers.iter().fold(request, |req, (name, value)| {
        if let Some(v) = value.as_str() {
            req.set(name, v)
        } else {
            req.set(name, &value.to_string())
        }
    });

    // 发送请求。非 2xx 状态码也返回响应（含状态码与响应体），
    // 与 package:http 行为一致，由调用方决定如何处理；仅传输层错误视为失败。
    let response = if body.is_empty() {
        request.call()
    } else {
        request.send_bytes(body)
    };

    let response = match response {
        Ok(r) => r,
        Err(ureq::Error::Status(_, resp)) => resp,
        Err(e) => {
            return Err(format!("网络错误: {e}"));
        }
    };

    let status = response.status();

    // 组装响应头（同名头合并为数组），需在 into_reader 消费响应前收集
    let mut header_map = serde_json::Map::new();
    for name in response.headers_names() {
        let values: Vec<serde_json::Value> = response
            .all(&name)
            .into_iter()
            .map(|v| json!(v))
            .collect();
        header_map.insert(name, json!(values));
    }

    // 读取响应体（限制大小）
    let mut buf: Vec<u8> = Vec::new();
    {
        let mut reader = response.into_reader().take(MAX_BODY_BYTES + 1);
        reader
            .read_to_end(&mut buf)
            .map_err(|e| format!("读取响应体失败: {e}"))?;
    }
    if buf.len() as u64 > MAX_BODY_BYTES {
        return Err(format!("响应体超过上限 {MAX_BODY_BYTES} 字节"));
    }

    Ok(json!({
        "ok": true,
        "status": status,
        "headers": header_map,
        "body_b64": BASE64.encode(&buf),
    })
    .to_string())
}

/// 释放 [http_request] 返回的字符串指针。
#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 获取最后一次错误的文本（与 downloader 模块保持一致的调试接口）。
#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let borrowed = cell.borrow();
        let cstr = borrowed
            .as_ref()
            .map(|s| s.clone())
            .or_else(|| CString::new("未知错误").ok());
        cstr
            .unwrap_or_else(|| CString::new("未知错误").unwrap())
            .into_raw()
    })
}
