//! XMC Server Launcher 向量知识库模块（sqlite-vec）
//!
//! 基于 Rust + rusqlite（bundled）+ sqlite-vec 实现本地向量数据库，
//! 供 Flutter 通过 FFI 调用（xmc_vector_store.dll）。用于 AI 助手的
//! RAG 知识库：用户导入的 .txt/.md 文档分块后向量化（embedding 由
//! Dart 侧调用 AI 模型 /embeddings 接口生成）写入本地 SQLite，
//! 对话时对查询做余弦相似度检索，命中片段作为上下文回填给模型。
//!
//! 统一入口 `vector_request(db_path, op, args_json)`：
//! - op: init / add / search / list_documents / delete_document / stats
//!
//! 返回 JSON 字符串（Dart 侧用 `free_string` 释放）：
//! - 成功: `{"ok":true,"result":{...}}`
//! - 失败: `{"ok":false,"error":"..."}`

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::sync::Once;

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Map, Value as Json};
use zerocopy::IntoBytes;

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

static VEC_INIT: Once = Once::new();

// ======================== 通用工具 ========================

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
        Some(Json::String(s)) => Ok(s.clone()),
        _ => Err(format!("缺少参数: {name}")),
    }
}

fn opt_str_arg(args: &Json, name: &str) -> Option<String> {
    match args.get(name) {
        Some(Json::String(s)) => Some(s.clone()),
        _ => None,
    }
}

fn u64_arg(args: &Json, name: &str, default: u64) -> Result<u64, String> {
    match args.get(name) {
        Some(Json::Number(n)) => n
            .as_u64()
            .ok_or_else(|| format!("参数 {name} 不是正整数: {n}")),
        _ => Ok(default),
    }
}

/// Vec<f32> → sqlite-vec 二进制（f32 LE 字节序列）。
fn vec_blob(vec: &[f32]) -> Vec<u8> {
    vec.as_bytes().to_vec()
}

/// 从 JSON 数组解析 f32 向量。
fn vec_arg(args: &Json, name: &str) -> Result<Vec<f32>, String> {
    match args.get(name) {
        Some(Json::Array(items)) => items
            .iter()
            .map(|v| {
                v.as_f64()
                    .map(|n| n as f32)
                    .ok_or_else(|| format!("参数 {name} 包含非数值元素: {v}"))
            })
            .collect(),
        _ => Err(format!("缺少参数: {name}")),
    }
}

// ======================== sqlite-vec 注册 ========================

/// 进程级注册 sqlite-vec 扩展（自动附加到之后打开的所有连接）。
fn ensure_vec_registered() -> Result<(), String> {
    let mut first_error: Option<String> = None;
    VEC_INIT.call_once(|| {
        use rusqlite::auto_extension::{RawAutoExtension, register_auto_extension};
        let raw: RawAutoExtension =
            unsafe { std::mem::transmute(sqlite_vec::sqlite3_vec_init as *const () as usize) };
        if let Err(e) = unsafe { register_auto_extension(raw) } {
            first_error = Some(format!("注册 sqlite-vec 扩展失败: {e}"));
        }
    });
    match first_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

// ======================== 数据库结构 ========================

/// 打开数据库，确保基础表存在；向量表按 [dimension] 惰性创建。
fn open_db(db_path: &str, dimension: Option<usize>) -> Result<Connection, String> {
    ensure_vec_registered()?;
    let conn = Connection::open(Path::new(db_path))
        .map_err(|e| format!("打开知识库失败: {e}"))?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
         CREATE TABLE IF NOT EXISTS documents (
           id TEXT PRIMARY KEY,
           title TEXT NOT NULL,
           created_at TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS chunks (
           id INTEGER PRIMARY KEY AUTOINCREMENT,
           doc_id TEXT NOT NULL,
           text TEXT NOT NULL
         );",
    )
    .map_err(|e| format!("初始化表失败: {e}"))?;

    let existing_dim: Option<i64> = conn
        .query_row(
            "SELECT value FROM meta WHERE key = 'dimension'",
            [],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| format!("读取维度失败: {e}"))?
        .and_then(|v: String| v.parse::<i64>().ok());

    if existing_dim.is_none() {
        let dim = dimension.ok_or("首次初始化必须提供 dimension 参数")?;
        let sql =
            format!("CREATE VIRTUAL TABLE IF NOT EXISTS vec_items USING vec0(embedding float[{dim}])");
        conn.execute_batch(&sql)
            .map_err(|e| format!("创建向量表失败: {e}"))?;
        conn.execute(
            "INSERT INTO meta (key, value) VALUES ('dimension', ?)",
            params![dim.to_string()],
        )
        .map_err(|e| format!("保存维度失败: {e}"))?;
    } else if let Some(dim) = dimension {
        if existing_dim.unwrap() as usize != dim {
            return Err(format!(
                "向量维度不一致：库为 {} 维，当前模型为 {dim} 维。请手动删除知识库后重新导入",
                existing_dim.unwrap()
            ));
        }
    }
    Ok(conn)
}

fn get_dimension(conn: &Connection) -> Result<u64, String> {
    let v: String = conn
        .query_row("SELECT value FROM meta WHERE key = 'dimension'", [], |r| r.get(0))
        .map_err(|e| format!("读取维度失败: {e}"))?;
    v.parse::<u64>().map_err(|_| "维度元数据损坏".to_string())
}

// ======================== 操作实现 ========================

/// 初始化（幂等）：确保表存在并返回维度。
fn op_init(conn: &Connection) -> Result<Json, String> {
    Ok(json!({ "dimension": get_dimension(conn)? }))
}

/// 写入文档（覆盖同 id 旧文档）。参数: doc_id, title, created_at, chunks[{text, embedding}]。
fn op_add(conn: &Connection, args: &Json) -> Result<Json, String> {
    let doc_id = str_arg(args, "doc_id")?;
    let title = str_arg(args, "title")?;
    let created_at = opt_str_arg(args, "created_at").unwrap_or_else(|| "".to_string());
    let chunks = match args.get("chunks") {
        Some(Json::Array(items)) => items,
        _ => return Err("缺少参数: chunks".to_string()),
    };

    let dimension = get_dimension(conn)? as usize;
    let mut parsed = Vec::with_capacity(chunks.len());
    for (i, item) in chunks.iter().enumerate() {
        let obj = item
            .as_object()
            .ok_or_else(|| format!("chunks[{i}] 不是对象"))?;
        let text = obj
            .get("text")
            .and_then(|v| v.as_str())
            .ok_or_else(|| format!("chunks[{i}] 缺少 text"))?
            .to_string();
        let embedding = match obj.get("embedding") {
            Some(Json::Array(items)) => items
                .iter()
                .map(|v| {
                    v.as_f64()
                        .map(|n| n as f32)
                        .ok_or_else(|| format!("chunks[{i}] embedding 含非数值"))
                })
                .collect::<Result<Vec<f32>, String>>()?,
            _ => return Err(format!("chunks[{i}] 缺少 embedding")),
        };
        if embedding.len() != dimension {
            return Err(format!(
                "chunks[{i}] 维度 {} 与库维度 {dimension} 不一致",
                embedding.len()
            ));
        }
        parsed.push((text, embedding));
    }
    if parsed.is_empty() {
        return Err("没有可写入的分块".to_string());
    }

    // 幂等：覆盖同一文档。
    op_delete_inner(conn, &doc_id)?;

    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("开始事务失败: {e}"))?;
    {
        tx.execute(
            "INSERT INTO documents (id, title, created_at) VALUES (?, ?, ?)",
            params![doc_id, title, created_at],
        )
        .map_err(|e| format!("插入文档失败: {e}"))?;

        let mut ins_chunk = tx
            .prepare("INSERT INTO chunks (doc_id, text) VALUES (?, ?)")
            .map_err(|e| format!("准备 chunk 语句失败: {e}"))?;
        let mut ins_vec = tx
            .prepare("INSERT INTO vec_items (rowid, embedding) VALUES (?, ?)")
            .map_err(|e| format!("准备向量语句失败: {e}"))?;

        for (text, embedding) in &parsed {
            ins_chunk
                .execute(params![doc_id, text])
                .map_err(|e| format!("插入 chunk 失败: {e}"))?;
            let rowid = tx.last_insert_rowid();
            ins_vec
                .execute(params![rowid, to_vec_blob(embedding)])
                .map_err(|e| format!("写入向量失败: {e}"))?;
        }
    }
    tx.commit().map_err(|e| format!("提交事务失败: {e}"))?;

    Ok(json!({ "doc_id": doc_id, "chunk_count": parsed.len() }))
}

/// 相似度检索。参数：embedding, top_k。
fn op_search(conn: &Connection, args: &Json) -> Result<Json, String> {
    let embedding = vec_arg(args, "embedding")?;
    let top_k = u64_arg(args, "top_k", 5)?.clamp(1, 50) as usize;
    let dimension = get_dimension(conn)? as usize;
    if embedding.len() != dimension {
        return Err(format!(
            "查询向量维度 {} 与库维度 {dimension} 不一致",
            embedding.len()
        ));
    }

    let mut stmt = conn
        .prepare(
            "SELECT rowid, distance FROM vec_items
             WHERE embedding MATCH ?1 AND k = ?2
             ORDER BY distance",
        )
        .map_err(|e| format!("准备检索语句失败: {e}"))?;
    let rows = stmt
        .query_map(params![to_vec_blob(&embedding), top_k as i64], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, f64>(1)?))
        })
        .map_err(|e| format!("检索失败: {e}"))?
        .collect::<rusqlite::Result<Vec<(i64, f64)>>>()
        .map_err(|e| format!("读取检索结果失败: {e}"))?;

    let mut results = Vec::with_capacity(rows.len());
    for (rowid, distance) in rows {
        let (doc_id, text): (String, String) = conn
            .query_row(
                "SELECT doc_id, text FROM chunks WHERE id = ?",
                params![rowid],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(|e| format!("读取 chunk 失败: {e}"))?
            .unwrap_or_default();
        let title = conn
            .query_row(
                "SELECT title FROM documents WHERE id = ?",
                params![doc_id],
                |r| r.get::<_, String>(0),
            )
            .optional()
            .map_err(|e| format!("读取文档标题失败: {e}"))?
            .unwrap_or_default();

        results.push(json!({
            "doc_id": doc_id,
            "title": title,
            "text": text,
            "distance": distance,
        }));
    }
    Ok(json!({ "results": results }))
}

fn op_list_documents(conn: &Connection) -> Result<Json, String> {
    let mut stmt = conn
        .prepare(
            "SELECT d.id, d.title, d.created_at,
                    (SELECT COUNT(*) FROM chunks c WHERE c.doc_id = d.id) AS chunk_count
             FROM documents d
             ORDER BY d.created_at DESC",
        )
        .map_err(|e| format!("准备文档列表语句失败: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok(json!({
                "id": row.get::<_, String>(0)?,
                "title": row.get::<_, String>(1)?,
                "created_at": row.get::<_, String>(2)?,
                "chunk_count": row.get::<_, i64>(3)?,
            }))
        })
        .map_err(|e| format!("查询文档列表失败: {e}"))?
        .collect::<rusqlite::Result<Vec<Json>>>()
        .map_err(|e| format!("读取文档列表失败: {e}"))?;
    Ok(json!({ "documents": rows }))
}

fn op_delete_document(conn: &Connection, args: &Json) -> Result<Json, String> {
    let doc_id = str_arg(args, "doc_id")?;
    op_delete_inner(conn, &doc_id)?;
    Ok(json!({ "deleted": true }))
}

/// 删除文档及其全部 chunk/向量。
fn op_delete_inner(conn: &Connection, doc_id: &str) -> Result<(), String> {
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("开始事务失败: {e}"))?;
    {
        let chunk_ids: Vec<i64> = tx
            .prepare("SELECT id FROM chunks WHERE doc_id = ?1")
            .map_err(|e| format!("准备查询失败: {e}"))?
            .query_map(params![doc_id], |r| r.get(0))
            .map_err(|e| format!("查询失败: {e}"))?
            .collect::<rusqlite::Result<Vec<i64>>>()
            .map_err(|e| format!("读取失败: {e}"))?;
        for id in chunk_ids {
            tx.execute("DELETE FROM vec_items WHERE rowid = ?1", params![id])
                .map_err(|e| format!("删除向量失败: {e}"))?;
        }
        tx.execute("DELETE FROM chunks WHERE doc_id = ?1", params![doc_id])
            .map_err(|e| format!("删除 chunk 失败: {e}"))?;
        tx.execute("DELETE FROM documents WHERE id = ?1", params![doc_id])
            .map_err(|e| format!("删除文档失败: {e}"))?;
    }
    tx.commit().map_err(|e| format!("提交事务失败: {e}"))?;
    Ok(())
}

fn op_stats(conn: &Connection) -> Result<Json, String> {
    let document_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0))
        .map_err(|e| format!("统计文档失败: {e}"))?;
    let chunk_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM chunks", [], |r| r.get(0))
        .map_err(|e| format!("统计分块失败: {e}"))?;
    Ok(json!({
        "document_count": document_count,
        "chunk_count": chunk_count,
        "dimension": get_dimension(conn)?,
    }))
}

// ======================== FFI 入口 ========================

/// 统一向量库操作入口。`db_path`、`op`、`args_json` 均为 UTF-8 字符串指针。
#[no_mangle]
pub extern "C" fn vector_request(
    db_path: *const libc::c_char,
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    catch_unwind(AssertUnwindSafe(|| vector_request_inner(db_path, op, args_json)))
        .unwrap_or_else(|_| {
            let msg = "Rust panic in vector_request".to_string();
            set_last_error(&msg);
            cstring_out(json!({ "ok": false, "error": msg }).to_string())
        })
}

fn vector_request_inner(
    db_path: *const libc::c_char,
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    let result = (|| -> Result<String, String> {
        if db_path.is_null() {
            return Err("db_path 为空指针".to_string());
        }
        let db_raw = unsafe { CStr::from_ptr(db_path) }
            .to_str()
            .map_err(|_| "db_path 不是有效的 UTF-8".to_string())?;
        if op.is_null() {
            return Err("op 为空指针".to_string());
        }
        let op_name = unsafe { CStr::from_ptr(op) }
            .to_str()
            .map_err(|_| "op 不是有效的 UTF-8".to_string())?;
        let args = parse_args(args_json)?;

        let payload = match op_name {
            "init" => {
                let conn = open_db(db_raw, requested_dimension(&args))?;
                op_init(&conn)?
            }
            "add" => {
                let conn = open_db(db_raw, requested_dimension(&args))?;
                op_add(&conn, &args)?
            }
            "search" => {
                let conn = open_db(db_raw, None)?;
                op_search(&conn, &args)?
            }
            "list_documents" => {
                let conn = open_db(db_raw, None)?;
                op_list_documents(&conn)?
            }
            "delete_document" => {
                let conn = open_db(db_raw, None)?;
                op_delete_document(&conn, &args)?
            }
            "stats" => {
                let conn = open_db(db_raw, None)?;
                op_stats(&conn)?
            }
            other => return Err(format!("不支持的向量库操作: {other}")),
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

/// 释放 [vector_request] 返回的字符串指针。
#[no_mangle]
pub extern "C" fn free_string(s: *mut libc::c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 获取最后一次错误的文本（调试接口）。
#[no_mangle]
pub extern "C" fn get_last_error() -> *mut libc::c_char {
    LAST_ERROR.with(|cell| {
        let cstr = cell
            .borrow()
            .clone()
            .or_else(|| CString::new("未知错误").ok())
            .unwrap_or_else(|| CString::new("未知错误").unwrap());
        cstr.into_raw()
    })
}

// ======================== 辅助 ========================

/// 请求里的 dimension 参数（无则为 None）。
fn requested_dimension(args: &Json) -> Option<usize> {
    u64_arg(args, "dimension", 0).ok().and_then(|d| {
        if d == 0 {
            None
        } else {
            Some(d as usize)
        }
    })
}

/// f32 向量 → 用作 sqlite-vec 嵌入的二进制（平台原生 f32 字节序，LE）。
fn to_vec_blob(vec: &[f32]) -> Vec<u8> {
    vec_blob(vec)
}

// ======================== 单元测试 ========================

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn call(db: &str, op: &str, args: &str) -> Json {
        let db_c = CString::new(db).unwrap();
        let op_c = CString::new(op).unwrap();
        let args_c = CString::new(args).unwrap();
        let raw = vector_request(
            db_c.as_ptr(),
            op_c.as_ptr(),
            args_c.as_ptr(),
        );
        let s = unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned();
        unsafe { free_string(raw) };
        serde_json::from_str(&s).unwrap()
    }

    fn tmp_db(name: &str) -> String {
        let path = std::env::temp_dir().join(format!(
            "xmc_vec_{}_{name}.db",
            std::process::id()
        ));
        if path.exists() {
            std::fs::remove_file(&path).ok();
        }
        path.to_string_lossy().into_owned()
    }

    #[test]
    fn test_init_stats() {
        let db = tmp_db("init");
        let res = call(&db, "init", r#"{"dimension":4}"#);
        assert!(res["ok"] == true, "{res}");
        assert_eq!(res["result"]["dimension"], 4);
        let res = call(&db, "stats", "{}");
        assert!(res["ok"] == true, "{res}");
        assert_eq!(res["result"]["document_count"], 0);
        assert_eq!(res["result"]["chunk_count"], 0);
    }

    #[test]
    fn test_add_search_delete() {
        let db = tmp_db("crud");
        let res = call(&db, "init", r#"{"dimension":3}"#);
        assert!(res["ok"] == true, "{res}");

        let res = call(
            &db,
            "add",
            r#"{"doc_id":"d1","title":"魔兽","created_at":"2026-01-01T00:00:00Z","chunks":[{"text":"末影龙是结束之地的 Boss","embedding":[1.0,0.0,0.0]},{"text":"下界合金装备最坚固","embedding":[0.0,1.0,0.0]}]}"#,
        );
        assert!(res["ok"] == true, "{res}");
        assert_eq!(res["result"]["chunk_count"], 2);

        let res = call(
            &db,
            "add",
            r#"{"doc_id":"d2","title":"红石","created_at":"2026-01-02T00:00:00Z","chunks":[{"text":"红石中继器可延长信号","embedding":[0.0,0.0,1.0]}]}"#,
        );
        assert!(res["ok"] == true, "{res}");

        let res = call(
            &db,
            "search",
            r#"{"embedding":[0.9,0.1,0.1],"top_k":3}"#,
        );
        assert!(res["ok"] == true, "{res}");
        let results = res["result"]["results"].as_array().unwrap();
        assert!(!results.is_empty());
        assert!(results[0]["distance"].as_f64().unwrap() < 1.0);

        let res = call(&db, "list_documents", "{}");
        assert!(res["ok"] == true, "{res}");
        assert_eq!(res["result"]["documents"].as_array().unwrap().len(), 2);

        let res = call(&db, "stats", "{}");
        assert_eq!(res["result"]["document_count"], 2);
        assert_eq!(res["result"]["chunk_count"], 3);

        // 覆盖 d1（幂等）
        let res = call(
            &db,
            "add",
            r#"{"doc_id":"d1","title":"魔兽新","created_at":"2026-01-03T00:00:00Z","chunks":[{"text":"新版末影龙更强","embedding":[1.0,1.0,1.0]}]}"#,
        );
        assert!(res["ok"] == true, "{res}");
        let res = call(&db, "stats", "{}");
        assert_eq!(res["result"]["document_count"], 2);
        assert_eq!(res["result"]["chunk_count"], 2);

        let res = call(&db, "delete_document", r#"{"doc_id":"d2"}"#);
        assert!(res["ok"] == true, "{res}");
        let res = call(&db, "stats", "{}");
        assert_eq!(res["result"]["document_count"], 1);
        assert_eq!(res["result"]["chunk_count"], 1);
    }

    #[test]
    fn test_dimension_mismatch() {
        let db = tmp_db("dim");
        let res = call(&db, "init", r#"{"dimension":3}"#);
        assert!(res["ok"] == true, "{res}");
        let res = call(
            &db,
            "add",
            r#"{"doc_id":"d","title":"t","chunks":[{"text":"x","embedding":[1.0,2.0]}]}"#,
        );
        assert!(res["ok"] == false, "{res}");
        assert!(res["error"].as_str().unwrap().contains("维度"));
    }

    #[test]
    fn test_unknown_op() {
        let db = tmp_db("unknown");
        let _ = call(&db, "init", r#"{"dimension":2}"#);
        let res = call(&db, "nope", "{}");
        assert!(res["ok"] == false, "{res}");
        assert!(res["error"].as_str().unwrap().contains("不支持的向量库操作"));
    }
}