//! C ABI：Dart 与其它 Rust 动态库的统一入口。
//!
//! `time_request(op, args_json)` 返回 `{"ok":true,"data":…}` / `{"ok":false,"error":…}`，
//! 与 `dev_auth_request` / `backup_request` 的约定一致。另外导出几个极快的
//! “热路径”函数（`xmc_time_now_unix_ns` 等），供 `link` 跨 DLL 调用，避免每次
//! 取时间都经过 JSON 解析。

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde_json::{json, Value};

use crate::clock::NS_PER_SEC;
use crate::service::{now_json, Config, GnssSample, Service};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = CString::new(msg.as_ref()).ok();
    });
}

fn cstring_out(s: String) -> *mut libc::c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new(r#"{"ok":false,"error":"结果包含 nul 字节"}"#)
            .unwrap()
            .into_raw(),
    }
}

fn parse_args(args_json: *const libc::c_char) -> Result<Value, String> {
    if args_json.is_null() {
        return Ok(json!({}));
    }
    let raw = unsafe { CStr::from_ptr(args_json) }
        .to_str()
        .map_err(|_| "args_json 不是有效 UTF-8".to_string())?;
    if raw.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(raw).map_err(|e| format!("args_json 解析失败: {e}"))
}

fn dispatch(op: &str, args: &Value) -> Result<Value, String> {
    let svc = Service::global();
    match op {
        "init" | "start" => {
            svc.start(args)?;
            serde_json::to_value(svc.status()).map_err(|e| e.to_string())
        }
        "stop" | "shutdown" => {
            svc.stop();
            Ok(json!({ "stopped": true }))
        }
        "now" => Ok(now_json(svc)),
        "status" => serde_json::to_value(svc.status()).map_err(|e| e.to_string()),
        "configure" => {
            let cfg = svc.configure(args)?;
            svc.request_sync();
            Ok(json!({ "config": cfg }))
        }
        "sync" => {
            // 可选：本次同步临时指定服务器列表（同时持久化到配置）。
            if args.get("servers").is_some() {
                svc.configure(args)?;
            }
            serde_json::to_value(svc.sync_now()).map_err(|e| e.to_string())
        }
        "probe" => serde_json::to_value(svc.probe()).map_err(|e| e.to_string()),
        "accuracy" => serde_json::to_value(svc.accuracy()).map_err(|e| e.to_string()),
        "note_http_date" => {
            let server = args
                .get("unix_s")
                .and_then(Value::as_i64)
                .ok_or("缺少 unix_s")?;
            let rtt = args.get("rtt_ms").and_then(Value::as_i64).unwrap_or(0);
            let skew = svc.note_http_date(server, rtt);
            Ok(json!({ "skew_ms": skew }))
        }
        "temperature" => {
            let celsius = args
                .get("celsius")
                .and_then(Value::as_f64)
                .ok_or("缺少 celsius")?;
            if !svc.set_temperature(celsius) {
                return Err("温度超出 -40..150°C 合理范围".to_string());
            }
            Ok(json!({ "celsius": celsius }))
        }
        "gnss_sample" => {
            let sample = GnssSample::from_json(args)?;
            serde_json::to_value(svc.ingest_gnss(sample)).map_err(|e| e.to_string())
        }
        "gnss_hello" => {
            let protocol = args
                .get("protocol")
                .and_then(Value::as_i64)
                .unwrap_or(1);
            if protocol != 1 {
                return Err(format!("不支持的 gnss 协议版本: {protocol}"));
            }
            let same_process = args
                .get("same_process")
                .and_then(Value::as_bool)
                .unwrap_or(false)
                || args
                    .get("transport")
                    .and_then(Value::as_str)
                    .map(|t| t.eq_ignore_ascii_case("ffi"))
                    .unwrap_or(false);
            let external = if same_process {
                false
            } else {
                match args.get("external_axis_mapping").and_then(Value::as_str) {
                    Some("same_process") | Some("none") => false,
                    Some("required") => true,
                    _ => true,
                }
            };
            svc.gnss_hello(protocol, external)
        }
        "gnss_bridge_start" => {
            let addr = args
                .get("addr")
                .and_then(Value::as_str)
                .unwrap_or("127.0.0.1:47820");
            let token = args
                .get("token")
                .and_then(Value::as_str)
                .unwrap_or("irix-adb");
            serde_json::to_value(crate::gnss_bridge::start(svc.clone(), addr, token))
                .map_err(|e| e.to_string())
        }
        "gnss_bridge_stop" => {
            serde_json::to_value(crate::gnss_bridge::stop()).map_err(|e| e.to_string())
        }
        "gnss_bridge_status" => {
            serde_json::to_value(crate::gnss_bridge::status()).map_err(|e| e.to_string())
        }
        "force_reanchor" => serde_json::to_value(svc.force_reanchor()?).map_err(|e| e.to_string()),
        "persist" => {
            svc.persist();
            Ok(json!({ "saved": true }))
        }
        "reset" => {
            svc.reset();
            serde_json::to_value(svc.status()).map_err(|e| e.to_string())
        }
        "mono" => {
            let mono = svc.clock.mono_ns();
            let precise = crate::precise::mono_ns();
            Ok(json!({
                "mono_ns": mono,
                "precise_ns": precise,
                "resolution_ns": xmc_time_base::mono::resolution_ns(),
                "precision": crate::precise::stats(),
            }))
        }
        "bridge" => {
            let d = xmc_time_base::link::diagnostics();
            Ok(json!({
                "attached": d.attached,
                "path": d.path,
                "fallback": d.fallback,
            }))
        }
        "self_test" => Ok(self_test()),
        other => Err(format!("未知的时间系统操作: {other}")),
    }
}

fn self_test() -> Value {
    let mut checks: Vec<Value> = Vec::new();
    let mut push = |name: &str, ok: bool, detail: String| {
        checks.push(json!({ "name": name, "ok": ok, "detail": detail }));
    };

    let a = xmc_time_base::mono::now_ns();
    let b = xmc_time_base::mono::now_ns();
    push(
        "monotonic_clock",
        b >= a && a > 0,
        format!("{a} -> {b}"),
    );

    let parsed = xmc_time_base::httpdate::parse_http_date("Sun, 06 Nov 1994 08:49:37 GMT");
    push(
        "http_date",
        parsed == Some(784_111_777),
        format!("{parsed:?}"),
    );

    let iso = xmc_time_base::civil::format_iso8601_ms(1_700_000_000_123);
    push(
        "civil_calendar",
        iso == "2023-11-14T22:13:20.123Z",
        iso,
    );

    use rusty_time_core::ntp::{NtpPacket, NtpTimestamp};
    let bytes = NtpPacket::client_request(4, NtpTimestamp(0x1234_5678_9ABC_DEF0)).to_bytes();
    let ok = NtpPacket::parse(&bytes)
        .map(|p| p.transmit_ts.0 == 0x1234_5678_9ABC_DEF0)
        .unwrap_or(false);
    push("ntp_codec", ok, "client_request -> parse".to_string());

    let snap = Service::global().clock.snapshot();
    push(
        "app_clock",
        snap.unix_ns > 1_577_836_800 * NS_PER_SEC,
        format!(
            "synced={} source={} uncertainty={}ns",
            snap.synced, snap.source, snap.uncertainty_ns
        ),
    );

    let ok = checks
        .iter()
        .all(|c| c.get("ok").and_then(Value::as_bool).unwrap_or(false));
    json!({ "ok": ok, "checks": checks })
}

/// 统一入口：`op` + JSON 参数，返回 JSON 字符串（Dart 侧用 `free_string` 释放）。
#[no_mangle]
pub extern "C" fn time_request(
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if op.is_null() {
            return Err("op 为空指针".to_string());
        }
        let op = unsafe { CStr::from_ptr(op) }
            .to_str()
            .map_err(|_| "op 不是有效 UTF-8".to_string())?;
        let args = parse_args(args_json)?;
        dispatch(op, &args)
    }));
    match result {
        Ok(Ok(data)) => cstring_out(json!({ "ok": true, "data": data }).to_string()),
        Ok(Err(e)) => {
            set_last_error(&e);
            cstring_out(json!({ "ok": false, "error": e }).to_string())
        }
        Err(_) => {
            let msg = "Rust panic in time_request".to_string();
            set_last_error(&msg);
            cstring_out(json!({ "ok": false, "error": msg }).to_string())
        }
    }
}

/// 释放 [time_request] 返回的字符串。
#[no_mangle]
pub extern "C" fn xmc_time_free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[no_mangle]
pub extern "C" fn xmc_time_get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        cell.borrow()
            .clone()
            .unwrap_or_else(|| CString::new("未知错误").unwrap())
            .into_raw()
    })
}

// ---------------------------------------------------------------------------
// 热路径导出：跨 DLL 时间桥直接调用，避免 JSON 往返。
// ---------------------------------------------------------------------------

/// 当前 Unix 纳秒（应用时间权威）。
#[no_mangle]
pub extern "C" fn xmc_time_now_unix_ns() -> i64 {
    // 注意：兜底绝不能再走 `link::now_unix_ns()`，否则会递归加载本 DLL。
    catch_unwind(|| Service::global().clock.now_ns()).unwrap_or_else(|_| xmc_time_base::mono::system_unix_ns())
}

#[no_mangle]
pub extern "C" fn xmc_time_now_unix_ms() -> i64 {
    xmc_time_now_unix_ns().div_euclid(1_000_000)
}

#[no_mangle]
pub extern "C" fn xmc_time_mono_ns() -> u64 {
    Service::global().clock.mono_ns()
}

/// 0 = 未同步，1 = 已同步。
#[no_mangle]
pub extern "C" fn xmc_time_synced() -> libc::c_int {
    catch_unwind(|| i32::from(Service::global().clock.snapshot().synced)).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn xmc_time_uncertainty_ns() -> i64 {
    catch_unwind(|| Service::global().clock.snapshot().uncertainty_ns).unwrap_or(250_000_000)
}

/// HTTPS `Date` 头偏差诊断；返回服务器时间与本地时间的毫秒差。
#[no_mangle]
pub extern "C" fn xmc_time_note_http_date(server_unix_s: i64, rtt_ms: i64) -> i64 {
    catch_unwind(|| Service::global().note_http_date(server_unix_s, rtt_ms))
        .unwrap_or_else(|_| (server_unix_s - xmc_time_base::mono::system_unix_ns() / 1_000_000_000) * 1_000 - rtt_ms / 2)
}

/// 退出前调用：停止后台线程并落盘。
#[no_mangle]
pub extern "C" fn time_shutdown() {
    let _ = catch_unwind(|| Service::global().stop());
}

/// 返回默认配置（Dart 首次启动时可先读取再决定覆盖哪些字段）。
#[no_mangle]
pub extern "C" fn xmc_time_default_config_json() -> *mut libc::c_char {
    cstring_out(serde_json::to_string(&Config::default()).unwrap_or_else(|_| "{}".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(op: &str, args: &str) -> Value {
        let op = CString::new(op).unwrap();
        let args = CString::new(args).unwrap();
        let ptr = time_request(op.as_ptr(), args.as_ptr());
        let s = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        xmc_time_free_string(ptr);
        serde_json::from_str(&s).unwrap()
    }

    #[test]
    fn now_op_returns_valid_time() {
        let v = call("now", "{}");
        assert_eq!(v["ok"], true);
        let ns = v["data"]["unix_ns"].as_i64().unwrap();
        assert!(ns > 1_577_836_800 * NS_PER_SEC);
        assert!(v["data"]["iso8601"].as_str().unwrap().ends_with('Z'));
    }

    #[test]
    fn self_test_passes() {
        let v = call("self_test", "{}");
        assert_eq!(v["ok"], true);
        assert_eq!(v["data"]["ok"], true, "{v}");
    }

    #[test]
    fn unknown_op_errors() {
        let v = call("nope", "{}");
        assert_eq!(v["ok"], false);
        assert!(v["error"].as_str().unwrap().contains("未知"));
    }

    #[test]
    fn fast_path_matches_now() {
        let ns = xmc_time_now_unix_ns();
        let ms = xmc_time_now_unix_ms();
        assert!((ns / 1_000_000 - ms).abs() <= 1);
    }
}
