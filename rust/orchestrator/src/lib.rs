//! XMC Server Launcher 编排引擎模块（K8s 风格控制平面）
//!
//! 供 Flutter 通过 FFI 调用（xmc_orchestrator.dll / .so / .dylib）：
//! 控制平面核心（对账 / 自愈 / 弹性 / 调度 / 迁移状态机）在 Rust 侧完成，
//! Dart 执行层负责采集观测（节点状态、容器状态、在线人数）与落地动作。
//!
//! 统一入口 `orchestrator_request(args_json, op)`：
//! - args_json: 各操作的参数 JSON（含 `dbPath`，SQLite 按需打开）
//! - op: init / upsert_service / delete_service / list_services / get_service /
//!   list_replicas / reconcile / observe / status / migrate_start /
//!   report_migration / migrate_cancel / list_migrations / mc_ping / reset
//!
//! 返回 JSON 字符串（Dart 侧用 `orchestrator_free_string` 释放）：
//! - 成功: `{"ok":true,"result":{...}}`
//! - 失败: `{"ok":false,"error":"..."}`

mod db;
mod engine;
mod mcping;
mod migration;
mod models;

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use rusqlite::Connection;
use serde_json::{json, Map, Value as Json};

use models::{Action, MigrationJob, ReconcileInput, ReplicaObserved};

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

fn cstring_out(s: String) -> *mut libc::c_char {
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

fn err_json(message: impl AsRef<str>) -> String {
    json!({ "ok": false, "error": message.as_ref() }).to_string()
}

fn parse_args(args_json: *const libc::c_char) -> Result<Json, String> {
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
        Some(Json::String(s)) if !s.is_empty() => Ok(s.clone()),
        Some(Json::String(_)) => Err(format!("参数不能为空: {name}")),
        _ => Err(format!("缺少参数: {name}")),
    }
}

fn opt_str_arg(args: &Json, name: &str) -> Option<String> {
    match args.get(name) {
        Some(Json::String(s)) if !s.is_empty() => Some(s.clone()),
        _ => None,
    }
}

fn i64_arg(args: &Json, name: &str, default: i64) -> i64 {
    match args.get(name) {
        Some(Json::Number(n)) => n.as_i64().unwrap_or(default),
        _ => default,
    }
}

/// 打开数据库（dbPath 参数）。
fn open_db(args: &Json) -> Result<Connection, String> {
    let path = opt_str_arg(args, "dbPath")
        .unwrap_or_else(|| "xmc_orchestrator.db".to_string());
    db::open(&path)
}

/// 动作 → JSON。
fn actions_json(actions: &[Action]) -> Json {
    Json::Array(actions.iter().map(serialize).collect())
}

fn serialize<T: serde::Serialize>(value: &T) -> Json {
    serde_json::to_value(value).unwrap_or(Json::Null)
}

// ======================== FFI 入口 ========================

/// 编排引擎统一入口。
///
/// 参数: args_json（操作参数 JSON）、op（操作名）。
/// 返回 JSON 字符串，用 `orchestrator_free_string` 释放。
#[no_mangle]
pub extern "C" fn orchestrator_request(
    args_json: *const libc::c_char,
    op: *const libc::c_char,
) -> *mut libc::c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let op_name = if op.is_null() {
            String::new()
        } else {
            match unsafe { CStr::from_ptr(op) }.to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    return err_json("操作名不是有效的 UTF-8");
                }
            }
        };
        let args = match parse_args(args_json) {
            Ok(a) => a,
            Err(e) => return err_json(e),
        };
        match dispatch(&op_name, &args) {
            Ok(result) => ok_json(result),
            Err(e) => {
                set_last_error(&e);
                err_json(e)
            }
        }
    }));
    cstring_out(result.unwrap_or_else(|_| {
        set_last_error("Rust 侧 panic");
        err_json("Rust 侧 panic，详见 last error")
    }))
}

/// 释放 `orchestrator_request` 返回的字符串。
#[no_mangle]
pub extern "C" fn orchestrator_free_string(s: *mut libc::c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

/// 最近一次错误消息（调试用）。
#[no_mangle]
pub extern "C" fn orchestrator_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| match cell.borrow().as_ref() {
        Some(msg) => {
            // L-6：改用 CString::into_raw，与 free 侧 CString::from_raw 严格配对，
            // 不再依赖 Vec + mem::forget 的分配器实现细节。
            match msg.to_str() {
                Ok(s) => match CString::new(s) {
                    Ok(cstr) => cstr.into_raw(),
                    Err(_) => std::ptr::null_mut(),
                },
                Err(_) => std::ptr::null_mut(),
            }
        }
        None => std::ptr::null_mut(),
    })
}

// ======================== 操作分发 ========================

fn dispatch(op: &str, args: &Json) -> Result<Json, String> {
    match op {
        "init" => {
            let conn = open_db(args)?;
            drop(conn);
            Ok(json!({ "initialized": true }))
        }
        "upsert_service" => {
            let service: models::McService = serde_json::from_value(
                args.get("service")
                    .cloned()
                    .ok_or_else(|| "缺少参数: service".to_string())?,
            )
            .map_err(|e| format!("服务 JSON 解析失败: {e}"))?;
            if let Some(err) = service.validate() {
                return Err(err);
            }
            let now = now_ms();
            let conn = open_db(args)?;
            db::upsert_service(&conn, &service, now)?;
            Ok(serialize(&service))
        }
        "delete_service" => {
            let id = str_arg(args, "id")?;
            let conn = open_db(args)?;
            // 先收集副本以便返回销毁动作
            let replicas = db::list_replicas(&conn, Some(&id))?;
            db::delete_service(&conn, &id)?;
            let actions: Vec<Action> = replicas
                .iter()
                .filter(|r| !r.node_id.is_empty())
                .map(|r| Action {
                    kind: models::ActionKind::DestroyContainer,
                    service_id: r.service_id.clone(),
                    replica_id: r.id.clone(),
                    node_id: r.node_id.clone(),
                    payload: json!({ "name": r.container_name, "force": true }),
                    delay_ms: 0,
                    migration_id: String::new(),
                })
                .collect();
            Ok(json!({ "actions": actions_json(&actions) }))
        }
        "list_services" => {
            let conn = open_db(args)?;
            Ok(Json::Array(db::list_services(&conn)?.iter().map(serialize).collect()))
        }
        "get_service" => {
            let id = str_arg(args, "id")?;
            let conn = open_db(args)?;
            match db::get_service(&conn, &id)? {
                Some(service) => Ok(serialize(&service)),
                None => Err(format!("服务不存在: {id}")),
            }
        }
        "list_replicas" => {
            let service_id = opt_str_arg(args, "serviceId");
            let conn = open_db(args)?;
            Ok(Json::Array(
                db::list_replicas(&conn, service_id.as_deref())?
                    .iter()
                    .map(serialize)
                    .collect(),
            ))
        }
        "observe" => {
            let observed: Vec<ReplicaObserved> = parse_observed(args)?;
            let now = i64_arg(args, "nowMs", 0);
            let mut conn = open_db(args)?;
            let replicas = engine::observe(&mut conn, &observed, now)?;
            Ok(Json::Array(replicas.iter().map(serialize).collect()))
        }
        "reconcile" => {
            let input: ReconcileInput = serde_json::from_value(
                args.get("observed")
                    .cloned()
                    .ok_or_else(|| "缺少参数: observed".to_string())?,
            )
            .map_err(|e| format!("观测 JSON 解析失败: {e}"))?;
            let mut conn = open_db(args)?;
            let actions = engine::reconcile(&mut conn, &input)?;
            Ok(json!({ "actions": actions_json(&actions) }))
        }
        "status" => {
            let service_id = opt_str_arg(args, "serviceId");
            let conn = open_db(args)?;
            let status = engine::status(&conn, service_id.as_deref())?;
            Ok(Json::Array(status.iter().map(serialize).collect()))
        }
        "migrate_start" => {
            let service_id = str_arg(args, "serviceId")?;
            let replica_id = str_arg(args, "replicaId")?;
            let to_node = str_arg(args, "toNode")?;
            let mut conn = open_db(args)?;
            let (job, action) =
                engine::migrate_start(&mut conn, &service_id, &replica_id, &to_node, 0)?;
            Ok(json!({ "job": serialize(&job), "action": serialize(&action) }))
        }
        "report_migration" => {
            let job_id = str_arg(args, "jobId")?;
            let ok = args.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
            let error = opt_str_arg(args, "error");
            let mut conn = open_db(args)?;
            let (job, action) = engine::report_migration(&mut conn, &job_id, ok, error, 0)?;
            Ok(json!({
                "job": serialize(&job),
                "action": action.as_ref().map(serialize).unwrap_or(Json::Null),
            }))
        }
        "migrate_cancel" => {
            let job_id = str_arg(args, "jobId")?;
            let conn = open_db(args)?;
            migration::migrate_cancel(&conn, &job_id, 0)?;
            Ok(json!({ "cancelled": true }))
        }
        "list_migrations" => {
            let conn = open_db(args)?;
            let jobs: Vec<MigrationJob> = db::list_migrations(&conn)?;
            Ok(Json::Array(jobs.iter().map(serialize).collect()))
        }
        "mc_ping" => {
            let host = str_arg(args, "host")?;
            let port = i64_arg(args, "port", 25565).clamp(1, 65535) as u16;
            let timeout_ms = i64_arg(args, "timeoutMs", 3000).max(100) as u64;
            Ok(serialize(&mcping::ping(&host, port, timeout_ms)))
        }
        "reset" => {
            let path = opt_str_arg(args, "dbPath")
                .unwrap_or_else(|| "xmc_orchestrator.db".to_string());
            drop(std::fs::remove_file(&path)); // 尽力删除
            let conn = open_db(args)?;
            drop(conn);
            Ok(json!({ "reset": true }))
        }
        other => Err(format!("未知操作: {other}")),
    }
}

fn parse_observed(args: &Json) -> Result<Vec<ReplicaObserved>, String> {
    match args.get("replicas") {
        Some(Json::Array(items)) => {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                out.push(
                    serde_json::from_value(item.clone())
                        .map_err(|e| format!("副本观测解析失败: {e}"))?,
                );
            }
            Ok(out)
        }
        _ => Err("缺少参数: replicas（副本观测数组）".to_string()),
    }
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
