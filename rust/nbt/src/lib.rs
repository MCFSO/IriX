//! XMC NBT 模块（Rust FFI，xmc_nbt）
//!
//! 提供 Minecraft NBT 的解析/序列化与树编辑，供 Flutter 通过 FFI 调用
//! （xmc_nbt.dll）。用于复刻 AnkiNBT 的 NBT 编辑能力：
//! - 二进制（gzip 包裹的 NBT，与原 mod 的 .nbt 互导）与 SNBT 文本双向转换；
//! - 树路径增删改查与搜索。
//!
//! 统一入口 `nbt_request(op, args_json)`，返回 JSON 字符串：
//! - 成功: `{"ok":true,"result":{...}}`
//! - 失败: `{"ok":false,"error":"..."}`
//!
//! 阶段 3 将在此文件追加 RCON 客户端相关 op（rcon_connect / rcon_command）。

mod nbt;

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use libc::c_char;
use nbt::{from_binary, from_snbt, from_tree, get_path, delete_path, search_paths, set_path, to_binary, to_snbt, to_tree, Nbt};
use serde_json::{json, Map, Value as Json};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

// ======================== 通用工具 ========================

fn set_last_error(msg: impl AsRef<str>) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = match CString::new(msg.as_ref()) {
            Ok(cstr) => Some(cstr),
            Err(_) => CString::new("错误消息包含 nul 字节").ok(),
        };
    });
}

fn cstring_out(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new(r#"{"ok":false,"error":"结果字符串包含 nul 字节"}"#)
            .unwrap()
            .into_raw(),
    }
}

fn ok_json(payload: Json) -> String {
    json!({ "ok": true, "result": payload }).to_string()
}

fn parse_args(args_json: *const c_char) -> Result<Json, String> {
    if args_json.is_null() {
        return Ok(Json::Object(Map::new()));
    }
    match unsafe { CStr::from_ptr(args_json) }.to_str() {
        Ok(raw) if raw.trim().is_empty() => Ok(Json::Object(Map::new())),
        Ok(raw) => serde_json::from_str::<Json>(raw)
            .map_err(|e| format!("参数 JSON 解析失败: {e}")),
        Err(_) => Err("参数不是有效的 UTF-8".to_string()),
    }
}

fn str_arg(args: &Json, name: &str) -> Result<String, String> {
    match args.get(name) {
        Some(Json::String(s)) => Ok(s.clone()),
        _ => Err(format!("缺少参数: {name}")),
    }
}

fn opt_bool_arg(args: &Json, name: &str) -> bool {
    matches!(args.get(name), Some(Json::Bool(true)))
}

// ======================== op 实现 ========================

/// 解析二进制 NBT（base64）。参数：data(base64), gzip(可选,默认自动检测)。
fn op_parse_binary(args: &Json) -> Result<Json, String> {
    let data_b64 = str_arg(args, "data")?;
    let bytes = base64_decode(&data_b64)?;
    let nbt = from_binary(&bytes)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 序列化为二进制 NBT，返回 base64（gzip 由参数控制，默认 true）。
fn op_to_binary(args: &Json) -> Result<Json, String> {
    let snbt = str_arg(args, "snbt")?;
    let nbt = from_snbt(&snbt)?;
    let gzip = !opt_bool_arg(args, "raw");
    let bytes = to_binary(&nbt, gzip)?;
    Ok(json!({ "data": base64_encode(&bytes), "gzip": gzip }))
}

/// 解析 SNBT。参数：snbt。
fn op_parse_snbt(args: &Json) -> Result<Json, String> {
    let snbt = str_arg(args, "snbt")?;
    let nbt = from_snbt(&snbt)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 转 SNBT。参数：snbt（任意 NBT 值）。
fn op_to_snbt(args: &Json) -> Result<Json, String> {
    let snbt = str_arg(args, "snbt")?;
    let nbt = from_snbt(&snbt)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 取路径节点（返回 SNBT）。参数：snbt, path。
fn op_get(args: &Json) -> Result<Json, String> {
    let nbt = parse_root(args)?;
    let path = str_arg(args, "path")?;
    let value = get_path(&nbt, &path)?;
    Ok(json!({ "snbt": value }))
}

/// 设置路径节点（value 为 SNBT）。参数：snbt, path, value。
fn op_set(args: &Json) -> Result<Json, String> {
    let mut nbt = parse_root(args)?;
    let path = str_arg(args, "path")?;
    let value = str_arg(args, "value")?;
    set_path(&mut nbt, &path, &value)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 删除路径节点。参数：snbt, path。
fn op_delete(args: &Json) -> Result<Json, String> {
    let mut nbt = parse_root(args)?;
    let path = str_arg(args, "path")?;
    delete_path(&mut nbt, &path)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 搜索包含子串的路径。参数：snbt, query, limit(可选,默认200)。
fn op_search(args: &Json) -> Result<Json, String> {
    let nbt = parse_root(args)?;
    let query = str_arg(args, "query")?;
    let limit = match args.get("limit") {
        Some(Json::Number(n)) => n.as_u64().unwrap_or(200) as usize,
        _ => 200,
    };
    let hits = search_paths(&nbt, &query, limit);
    Ok(json!({ "paths": hits }))
}

/// 将 NBT 转为树 JSON（供 UI 渲染）。参数：snbt。
fn op_to_tree(args: &Json) -> Result<Json, String> {
    let nbt = parse_root(args)?;
    Ok(json!({ "tree": to_tree(&nbt) }))
}

/// 从树 JSON 重建 NBT，返回 SNBT（供 UI 编辑后序列化）。参数：tree。
fn op_from_tree(args: &Json) -> Result<Json, String> {
    let tree = args
        .get("tree")
        .ok_or("缺少参数: tree")?
        .clone();
    let nbt = from_tree(&tree)?;
    Ok(json!({ "snbt": to_snbt(&nbt) }))
}

/// 从参数解析根 NBT（snbt）。
fn parse_root(args: &Json) -> Result<Nbt, String> {
    let snbt = str_arg(args, "snbt")?;
    from_snbt(&snbt)
}

// ======================== base64 ========================

fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        let chars = [
            TABLE[((n >> 18) & 63) as usize],
            TABLE[((n >> 12) & 63) as usize],
            TABLE[((n >> 6) & 63) as usize],
            TABLE[(n & 63) as usize],
        ];
        match chunk.len() {
            1 => {
                out.push(chars[0] as char);
                out.push(chars[1] as char);
                out.push('=');
                out.push('=');
            }
            2 => {
                out.push(chars[0] as char);
                out.push(chars[1] as char);
                out.push(chars[2] as char);
                out.push('=');
            }
            _ => {
                for c in chars {
                    out.push(c as char);
                }
            }
        }
    }
    out
}

fn base64_decode(s: &str) -> Result<Vec<u8>, String> {
    let mut buf = Vec::new();
    let mut acc: u32 = 0;
    let mut bits = 0;
    let mut padded = 0;
    for c in s.chars() {
        if c == '=' {
            padded += 1;
            continue;
        }
        let v = match c {
            'A'..='Z' => c as u32 - 'A' as u32,
            'a'..='z' => c as u32 - 'a' as u32 + 26,
            '0'..='9' => c as u32 - '0' as u32 + 52,
            '+' => 62,
            '/' => 63,
            _ => return Err(format!("非法 base64 字符: {c}")),
        };
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            buf.push((acc >> bits) as u8);
        }
    }
    // 校验填充一致性。
    if (buf.len() + padded) % 3 != 0 {
        return Err("base64 长度无效".to_string());
    }
    Ok(buf)
}

// ======================== FFI 入口 ========================

#[no_mangle]
pub extern "C" fn nbt_request(
    op: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| nbt_request_inner(op, args_json)))
        .unwrap_or_else(|_| {
            let msg = "Rust panic in nbt_request".to_string();
            set_last_error(&msg);
            cstring_out(json!({ "ok": false, "error": msg }).to_string())
        })
}

fn nbt_request_inner(op: *const c_char, args_json: *const c_char) -> *mut c_char {
    let result = (|| -> Result<String, String> {
        if op.is_null() {
            return Err("op 为空指针".to_string());
        }
        let op_name = unsafe { CStr::from_ptr(op) }
            .to_str()
            .map_err(|_| "op 不是有效的 UTF-8".to_string())?;
        let args = parse_args(args_json)?;

        let payload = match op_name {
            "parse_binary" => op_parse_binary(&args)?,
            "to_binary" => op_to_binary(&args)?,
            "parse_snbt" => op_parse_snbt(&args)?,
            "to_snbt" => op_to_snbt(&args)?,
            "get" => op_get(&args)?,
            "set" => op_set(&args)?,
            "delete" => op_delete(&args)?,
            "search" => op_search(&args)?,
            "to_tree" => op_to_tree(&args)?,
            "from_tree" => op_from_tree(&args)?,
            // 阶段 3 追加：rcon_connect / rcon_command
            other => return Err(format!("不支持的 NBT 操作: {other}")),
        };
        Ok(ok_json(payload))
    })();

    match result {
        Ok(json_str) => cstring_out(json_str),
        Err(e) => {
            set_last_error(&e);
            cstring_out(json!({ "ok": false, "error": e }).to_string())
        }
    }
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[no_mangle]
pub extern "C" fn get_last_error() -> *mut c_char {
    LAST_ERROR.with(|cell| {
        let cstr = cell
            .borrow()
            .clone()
            .or_else(|| CString::new("未知错误").ok())
            .unwrap_or_else(|| CString::new("未知错误").unwrap());
        cstr.into_raw()
    })
}

// ======================== 单元测试 ========================

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn call(op: &str, args: &str) -> Json {
        let op_c = CString::new(op).unwrap();
        let args_c = CString::new(args).unwrap();
        let raw = nbt_request(op_c.as_ptr(), args_c.as_ptr());
        let s = unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned();
        free_string(raw);
        serde_json::from_str(&s).unwrap()
    }

    #[test]
    fn test_unknown_op() {
        let res = call("nope", "{}");
        assert!(res["ok"] == false, "{res}");
        assert!(res["error"].as_str().unwrap().contains("不支持的 NBT 操作"));
    }

    #[test]
    fn test_snbt_parse_roundtrip() {
        let res = call("parse_snbt", r#"{"snbt":"{a:1b,list:[1,2]}"}"#);
        assert!(res["ok"] == true, "{res}");
        let snbt = res["result"]["snbt"].as_str().unwrap();
        assert!(snbt.contains("a"));
        assert!(snbt.contains("list"));
    }

    #[test]
    fn test_binary_roundtrip() {
        let parsed = call("parse_snbt", r#"{"snbt":"{x:42}"}"#);
        assert!(parsed["ok"] == true, "{parsed}");
        let snbt = parsed["result"]["snbt"].as_str().unwrap();
        let encoded = call("to_binary", &format!(r#"{{"snbt":"{snbt}","raw":true}}"#));
        assert!(encoded["ok"] == true, "{encoded}");
        let data = encoded["result"]["data"].as_str().unwrap();
        let decoded = call("parse_binary", &format!(r#"{{"data":"{data}"}}"#));
        assert!(decoded["ok"] == true, "{decoded}");
        assert_eq!(decoded["result"]["snbt"].as_str().unwrap(), "{x:42}");
    }

    #[test]
    fn test_get_set_delete() {
        let res = call("set", r#"{"snbt":"{a:{b:1}}","path":"a/b","value":"99"}"#);
        assert!(res["ok"] == true, "{res}");
        let snbt = res["result"]["snbt"].as_str().unwrap();
        let got = call("get", &format!(r#"{{"snbt":"{snbt}","path":"a/b"}}"#));
        assert_eq!(got["result"]["snbt"].as_str().unwrap(), "99");
        let del = call("delete", &format!(r#"{{"snbt":"{snbt}","path":"a/b"}}"#));
        assert!(del["ok"] == true, "{del}");
    }
}
