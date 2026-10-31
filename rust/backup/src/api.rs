//! 统一 FFI 入口：`backup_request(op, argsJson, progressCb)` → JSON 字符串。
//!
//! 返回结构：
//! - 成功：`{"ok":true,"data":{...}}`
//! - 失败：`{"ok":false,"error":"...","cancelled":bool}`
//!
//! 字符串由 Rust 分配，Dart 侧必须用 `free_string` 释放。
//!
//! 支持的操作（op）：
//!
//! | op | 说明 |
//! |----|------|
//! | `status` | 仓库概览：策略、平台、全量/增量列表 |
//! | `full_create` | 全量备份（整个实例目录 → ZIP） |
//! | `full_restore` | 用全量备份覆盖恢复实例目录 |
//! | `full_delete` | 删除全量备份 |
//! | `snapshot_create` | 增量备份（rsync 硬链接快照 / CAS） |
//! | `snapshot_restore` | 恢复增量快照 |
//! | `snapshot_verify` | 校验增量快照完整性 |
//! | `snapshot_delete` | 删除增量快照并回收 CAS 空间 |
//! | `gc` | 回收未被引用的 CAS 对象 |

use std::ffi::{CStr, CString};
use std::io;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;

use serde_json::{json, Value};

use crate::model::*;
use crate::progress::ProgressCallback;
use crate::repo::Repo;
use crate::{full, progress, snapshot, util};

/// 操作失败信息。
#[derive(Debug)]
struct OpError {
    message: String,
    cancelled: bool,
}

impl OpError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            cancelled: false,
        }
    }
}

impl From<io::Error> for OpError {
    fn from(e: io::Error) -> Self {
        Self {
            cancelled: progress::is_cancel_error(&e),
            message: e.to_string(),
        }
    }
}

impl From<String> for OpError {
    fn from(message: String) -> Self {
        Self::new(message)
    }
}

impl From<&str> for OpError {
    fn from(message: &str) -> Self {
        Self::new(message)
    }
}

type OpResult = Result<Value, OpError>;

/// 统一 FFI 入口。
///
/// 指针为空、JSON 非法、内部 panic 都不会跨 FFI unwind，
/// 一律返回 `{"ok":false,...}`。
#[no_mangle]
pub extern "C" fn backup_request(
    op: *const libc::c_char,
    args_json: *const libc::c_char,
    progress_cb: Option<ProgressCallback>,
) -> *mut libc::c_char {
    let value = catch_unwind(AssertUnwindSafe(|| {
        handle_request(op, args_json, progress_cb)
    }))
    .unwrap_or_else(|_| fail("Rust 侧 panic，已捕获", false));
    respond(value)
}

fn handle_request(
    op_ptr: *const libc::c_char,
    args_ptr: *const libc::c_char,
    cb: Option<ProgressCallback>,
) -> Value {
    crate::clear_cancel();

    if op_ptr.is_null() {
        return fail("op 为空指针", false);
    }
    let op = match unsafe { CStr::from_ptr(op_ptr) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return fail("op 不是合法的 UTF-8 字符串", false),
    };
    let args_text = if args_ptr.is_null() {
        "{}".to_string()
    } else {
        match unsafe { CStr::from_ptr(args_ptr) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return fail("参数不是合法的 UTF-8 字符串", false),
        }
    };
    let args: Value = match serde_json::from_str(&args_text) {
        Ok(v) => v,
        Err(e) => return fail(format!("参数不是合法 JSON: {e}"), false),
    };

    let result: OpResult = match op.as_str() {
        "status" => op_status(&args),
        "full_create" => op_full_create(&args, cb),
        "full_restore" => op_full_restore(&args, cb),
        "full_delete" => op_full_delete(&args),
        "snapshot_create" => op_snapshot_create(&args, cb),
        "snapshot_restore" => op_snapshot_restore(&args, cb),
        "snapshot_verify" => op_snapshot_verify(&args, cb),
        "snapshot_delete" => op_snapshot_delete(&args),
        "gc" => op_gc(&args),
        other => Err(OpError::new(format!("未知操作: {other}"))),
    };

    match result {
        Ok(data) => json!({ "ok": true, "data": data }),
        Err(e) => {
            crate::set_last_error(&e.message);
            fail(e.message, e.cancelled)
        }
    }
}

// ======================== 各操作实现 ========================

/// 仓库概览：当前平台的增量策略 + 已有备份列表。
fn op_status(args: &Value) -> OpResult {
    let repo = open_repo(args)?;
    let snapshots = repo.list_snapshots()?;
    let full_list = repo.list_full()?;
    let total_logical: u64 = snapshots.iter().map(|s| s.bytes_total).sum::<u64>()
        + full_list.iter().map(|f| f.bytes_total).sum::<u64>();
    let total_stored: u64 = snapshots.iter().map(|s| s.stored_bytes).sum::<u64>()
        + full_list.iter().map(|f| f.stored_bytes).sum::<u64>();
    Ok(json!({
        "repoRoot": util::path_to_slash(repo.root()),
        "platform": std::env::consts::OS,
        "strategy": repo.strategy_note(),
        "rsyncAvailable": crate::rsync::available(),
        "rsyncVersion": crate::rsync::version_string(),
        "snapshots": snapshots,
        "full": full_list,
        "totalLogicalBytes": total_logical,
        "totalStoredBytes": total_stored,
    }))
}

fn op_full_create(args: &Value, cb: Option<ProgressCallback>) -> OpResult {
    let repo = open_repo(args)?;
    let source = arg_path(args, "sourceRoot")?;
    let level = arg_u64(args, "compressionLevel", 6).min(9) as u32;
    let name = arg_str_opt(args, "name")
        .unwrap_or_else(|| util::utc_name_from_secs(util::now_secs()));
    let meta = full::create(&repo, &source, &name, level, cb)?;
    Ok(json!(meta))
}

fn op_full_restore(args: &Value, cb: Option<ProgressCallback>) -> OpResult {
    let repo = open_repo(args)?;
    let name = arg_str(args, "name")?;
    let target = arg_path(args, "targetRoot")?;
    let outcome = full::restore(&repo, &name, &target, cb)?;
    Ok(json!(outcome))
}

fn op_full_delete(args: &Value) -> OpResult {
    let repo = open_repo(args)?;
    let name = arg_str(args, "name")?;
    let outcome = full::delete(&repo, &name)?;
    Ok(json!(outcome))
}

fn op_snapshot_create(args: &Value, cb: Option<ProgressCallback>) -> OpResult {
    let repo = open_repo(args)?;
    let source = arg_path(args, "sourceRoot")?;
    let name = arg_str_opt(args, "name")
        .unwrap_or_else(|| util::utc_name_from_secs(util::now_secs()));
    let parent = arg_str_opt(args, "parent");
    let label = arg_str_opt(args, "label");
    let meta = snapshot::create(&repo, &source, &name, parent.as_deref(), label.as_deref(), cb)?;
    Ok(json!(meta))
}

fn op_snapshot_restore(args: &Value, cb: Option<ProgressCallback>) -> OpResult {
    let repo = open_repo(args)?;
    let name = arg_str(args, "name")?;
    let target = arg_path(args, "targetRoot")?;
    let prune = arg_bool(args, "prune", false);
    let outcome = snapshot::restore(&repo, &name, &target, prune, cb)?;
    Ok(json!(outcome))
}

fn op_snapshot_verify(args: &Value, cb: Option<ProgressCallback>) -> OpResult {
    let repo = open_repo(args)?;
    let name = arg_str(args, "name")?;
    let deep = arg_bool(args, "deep", false);
    let report = snapshot::verify(&repo, &name, deep, cb)?;
    Ok(json!(report))
}

fn op_snapshot_delete(args: &Value) -> OpResult {
    let repo = open_repo(args)?;
    let name = arg_str(args, "name")?;
    let (objects_removed, bytes_freed) = snapshot::delete(&repo, &name)?;
    Ok(json!(DeleteOutcome {
        name,
        kind: KIND_SNAPSHOT.to_string(),
        objects_removed,
        bytes_freed,
    }))
}

fn op_gc(args: &Value) -> OpResult {
    let repo = open_repo(args)?;
    let (objects_removed, bytes_freed) = repo.gc_objects()?;
    Ok(json!({
        "objectsRemoved": objects_removed,
        "bytesFreed": bytes_freed,
    }))
}

// ======================== 参数解析 ========================

fn open_repo(args: &Value) -> Result<Repo, OpError> {
    let root = arg_path(args, "repoRoot")?;
    Repo::open(&root).map_err(OpError::from)
}

fn arg_str(args: &Value, key: &str) -> Result<String, OpError> {
    match args.get(key).and_then(|v| v.as_str()) {
        Some(s) if !s.trim().is_empty() => Ok(s.to_string()),
        _ => Err(OpError::new(format!("缺少参数: {key}"))),
    }
}

fn arg_str_opt(args: &Value, key: &str) -> Option<String> {
    args.get(key)
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn arg_u64(args: &Value, key: &str, default: u64) -> u64 {
    args.get(key).and_then(|v| v.as_u64()).unwrap_or(default)
}

fn arg_bool(args: &Value, key: &str, default: bool) -> bool {
    args.get(key).and_then(|v| v.as_bool()).unwrap_or(default)
}

fn arg_path(args: &Value, key: &str) -> Result<PathBuf, OpError> {
    Ok(PathBuf::from(arg_str(args, key)?))
}

// ======================== 响应封送 ========================

fn fail(message: impl Into<String>, cancelled: bool) -> Value {
    json!({
        "ok": false,
        "error": message.into(),
        "cancelled": cancelled,
    })
}

fn respond(value: Value) -> *mut libc::c_char {
    let text = serde_json::to_string(&value).unwrap_or_else(|e| {
        format!("{{\"ok\":false,\"error\":\"响应序列化失败: {e}\",\"cancelled\":false}}")
    });
    match CString::new(text) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new("{\"ok\":false,\"error\":\"响应包含 nul 字节\",\"cancelled\":false}")
            .expect("静态字符串不含 nul")
            .into_raw(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_root(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "xmc_api_{}_{}_{}",
            tag,
            std::process::id(),
            crate::next_temp_id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn status_reports_empty_repo() {
        let tmp = temp_root("status");
        let repo_root = tmp.join("repo");
        let repo = Repo::open(&repo_root).unwrap();
        let value = op_status(&json!({ "repoRoot": util::path_to_slash(repo.root()) })).unwrap();
        assert_eq!(value["snapshots"].as_array().unwrap().len(), 0);
        assert_eq!(value["full"].as_array().unwrap().len(), 0);
        assert!(value["strategy"].as_str().is_some());
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn json_args_are_validated() {
        let err = arg_path(&json!({}), "repoRoot").unwrap_err();
        assert!(err.message.contains("repoRoot"));
        assert_eq!(arg_u64(&json!({"level": 3}), "level", 6), 3);
        assert_eq!(arg_u64(&json!({}), "level", 6), 6);
        assert!(arg_bool(&json!({"deep": true}), "deep", false));
        assert_eq!(arg_str_opt(&json!({"name": "  "}), "name"), None);
    }
}
