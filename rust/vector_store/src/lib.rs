//! XMC Server Launcher 向量知识库模块（Milvus）
//!
//! 基于 Rust + milvus-sdk-rust（官方 SDK，纯 rustls、无 OpenSSL）实现远程向量
//! 数据库，供 Flutter 通过 FFI 调用（xmc_vector_store.dll）。用于 AI 助手的
//! RAG 知识库：用户导入的 .txt/.md 文档分块后向量化（embedding 由 Dart 侧
//! 调用 AI 模型 /embeddings 接口生成）写入 Milvus 集合；对话时对查询做余弦
//! 相似度检索，命中片段作为上下文回填给模型。
//!
//! 统一入口 `vector_request(conn_json, op, args_json)`：
//! - conn_json: `{"uri":"http://host:19530","token":"","collection":"xmc_knowledge"}`
//! - op: init / add / search / list_documents / delete_document / stats
//!
//! 返回 JSON 字符串（Dart 侧用 `free_string` 释放）：
//! - 成功: `{"ok":true,"result":{...}}`
//! - 失败: `{"ok":false,"error":"..."}`

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use libc::c_char;
use milvus::v2::prelude::*;
use milvus::v2::ClientV2;
use serde::Deserialize;
use serde_json::{json, Map, Value as Json};
// milvus-sdk-rust 的 prelude 重新导出 1 泛型参数的 Result；此处显式用 std Result，
// 避免 `Result<T, E>` 二泛型写法被 milvus 的 Result 别名遮蔽。
use std::result::Result as StdResult;

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

fn parse_args(args_json: *const c_char) -> StdResult<Json, String> {
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

fn str_arg(args: &Json, name: &str) -> StdResult<String, String> {
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

fn u64_arg(args: &Json, name: &str, default: u64) -> StdResult<u64, String> {
    match args.get(name) {
        Some(Json::Number(n)) => n
            .as_u64()
            .ok_or_else(|| format!("参数 {name} 不是正整数: {n}")),
        _ => Ok(default),
    }
}

/// 从 JSON 数组解析 f32 向量。
fn vec_arg(args: &Json, name: &str) -> StdResult<Vec<f32>, String> {
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

// ======================== 连接配置 ========================

#[derive(Debug, Clone, Deserialize)]
struct ConnInfo {
    uri: String,
    #[serde(default)]
    token: String,
    collection: String,
}

// ======================== Tokio 运行时 ========================

/// 全局 Tokio 运行时（Milvus SDK 为 async/tonic），用于把同步 FFI 调用桥接
/// 到异步 SDK。Milvus 网络 I/O 较重，使用多线程运行时。
fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("创建 Tokio 运行时失败")
    })
}

/// 建立 Milvus 客户端（即用即连，符合项目「即用即连、用完即关」约定）。
async fn connect(conn: &ConnInfo) -> StdResult<ClientV2, String> {
    ClientV2::new(
        &ConnectConfig::new()
            .uri(&conn.uri)
            .token(&conn.token),
    )
    .await
    .map_err(|e| format!("连接 Milvus 失败（{}）: {e}", conn.uri))
}

// ======================== 集合 / Schema ========================

const FIELD_ID: &str = "id";
const FIELD_EMBEDDING: &str = "embedding";
const FIELD_TEXT: &str = "text";
const FIELD_DOC_ID: &str = "doc_id";
const FIELD_TITLE: &str = "title";
const FIELD_CREATED_AT: &str = "created_at";
const DEFAULT_LIMIT: i64 = 16384;
/// 匹配全部行的过滤表达式（Milvus query 要求 filter 非空；doc_id 恒非空，
/// 故 `doc_id != ""` 等价于全表扫描）。
const FILTER_ALL: &str = "doc_id != \"\"";

/// 集合是否已存在。
async fn collection_exists(client: &ClientV2, conn: &ConnInfo) -> StdResult<bool, String> {
    let resp = client
        .has_collection(
            HasCollectionRequest::builder()
                .collection_name(&conn.collection)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("检查集合存在性失败: {e}"))?;
    Ok(resp.exists())
}

/// 读取集合 embedding 字段的维度（集合不存在返回 None）。
async fn collection_dimension(
    client: &ClientV2,
    conn: &ConnInfo,
) -> StdResult<Option<u64>, String> {
    if !collection_exists(client, conn).await? {
        return Ok(None);
    }
    let resp = client
        .describe_collection(
            DescribeCollectionRequest::builder()
                .collection_name(&conn.collection)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("读取集合描述失败: {e}"))?;
    for field in resp.description().get_schema().get_fields() {
        if field.get_name() == FIELD_EMBEDDING {
            return Ok(Some(field.get_dimension() as u64));
        }
    }
    Ok(None)
}

/// 确保向量集合存在：不存在则创建（含 COSINE 索引），存在则校验维度。
async fn ensure_collection(client: &ClientV2, conn: &ConnInfo, dimension: u64) -> StdResult<(), String> {
    if collection_exists(client, conn).await? {
        if let Some(existing) = collection_dimension(client, conn).await? {
            if existing != dimension {
                return Err(format!(
                    "向量维度不一致：库为 {existing} 维，当前模型为 {dimension} 维。请在 Milvus 中删除集合 {coll} 后重新导入",
                    existing = existing,
                    dimension = dimension,
                    coll = conn.collection,
                ));
            }
        }
        return Ok(());
    }

    let schema = CollectionSchema::new()
        .enable_dynamic_field(true)
        .add_field(
            FieldSchema::new()
                .name(FIELD_ID)
                .data_type(DataType::Int64)
                .primary_key(true)
                .auto_id(true),
        )
        .add_field(
            FieldSchema::new()
                .name(FIELD_EMBEDDING)
                .data_type(DataType::FloatVector)
                .dimension(dimension as u32),
        )
        .add_field(
            FieldSchema::new()
                .name(FIELD_TEXT)
                .data_type(DataType::VarChar)
                .max_length(8192),
        )
        .add_field(
            FieldSchema::new()
                .name(FIELD_DOC_ID)
                .data_type(DataType::VarChar)
                .max_length(64),
        )
        .add_field(
            FieldSchema::new()
                .name(FIELD_TITLE)
                .data_type(DataType::VarChar)
                .max_length(512),
        )
        .add_field(
            FieldSchema::new()
                .name(FIELD_CREATED_AT)
                .data_type(DataType::VarChar)
                .max_length(64),
        );

    let index = IndexParam::new()
        .field_name(FIELD_EMBEDDING)
        .index_type(IndexType::AutoIndex)
        .metric_type(MetricType::Cosine);

    client
        .create_collection(
            CreateCollectionRequest::builder()
                .collection_name(&conn.collection)
                .schema(schema)
                .index_param(index)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("创建集合失败: {e}"))?;

    Ok(())
}

/// 加载集合到内存（load 幂等，重复调用无副作用）。注意：集合刚创建时
/// 可能需要等待索引建好，Milvus 会在 load 时处理。
async fn load(client: &ClientV2, conn: &ConnInfo) -> StdResult<(), String> {
    client
        .load_collection(
            LoadCollectionRequest::builder()
                .collection_name(&conn.collection)
                .sync(true)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("加载集合失败: {e}"))
}

// ======================== 操作实现 ========================

/// 初始化（幂等）：确保集合存在并返回维度。参数 dimension 为 embedding 维度。
async fn op_init(conn: &ConnInfo, args: &Json) -> StdResult<Json, String> {
    let dimension = u64_arg(args, "dimension", 0)?;
    if dimension == 0 {
        return Err("首次初始化必须提供 dimension 参数".to_string());
    }
    let client = connect(conn).await?;
    ensure_collection(&client, conn, dimension).await?;
    load(&client, conn).await?;
    Ok(json!({ "dimension": dimension }))
}

/// 写入文档（覆盖同 id 旧文档）。参数: doc_id, title, created_at, chunks[{text, embedding}]。
async fn op_add(conn: &ConnInfo, args: &Json) -> StdResult<Json, String> {
    let doc_id = str_arg(args, "doc_id")?;
    let title = str_arg(args, "title")?;
    let created_at = opt_str_arg(args, "created_at").unwrap_or_default();
    let chunks = match args.get("chunks") {
        Some(Json::Array(items)) => items,
        _ => return Err("缺少参数: chunks".to_string()),
    };

    if chunks.is_empty() {
        return Err("没有可写入的分块".to_string());
    }

    let client = connect(conn).await?;

    // 校验维度：读取集合 embedding 维度，与每个 chunk 的向量长度比对。
    let dimension = collection_dimension(&client, conn)
        .await?
        .ok_or("集合尚未初始化，请先调用 init")? as usize;

    let mut rows = Vec::with_capacity(chunks.len());
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
                .collect::<StdResult<Vec<f32>, String>>()?,
            _ => return Err(format!("chunks[{i}] 缺少 embedding")),
        };
        if embedding.len() != dimension {
            return Err(format!(
                "chunks[{i}] 维度 {} 与库维度 {dimension} 不一致",
                embedding.len()
            ));
        }
        rows.push(json!({
            FIELD_EMBEDDING: embedding,
            FIELD_TEXT: text,
            FIELD_DOC_ID: doc_id,
            FIELD_TITLE: title,
            FIELD_CREATED_AT: created_at,
        }));
    }

    // 幂等：覆盖同一文档（先按 doc_id 删除旧分块）。
    delete_by_doc_id(&client, conn, &doc_id).await?;

    let resp = client
        .insert(
            InsertRequest::builder()
                .collection_name(&conn.collection)
                .rows(rows)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("写入向量失败: {e}"))?;

    Ok(json!({
        "doc_id": doc_id,
        "chunk_count": resp.insert_count() as i64,
    }))
}

/// 相似度检索。参数：embedding, top_k。
async fn op_search(conn: &ConnInfo, args: &Json) -> StdResult<Json, String> {
    let embedding = vec_arg(args, "embedding")?;
    let top_k = u64_arg(args, "top_k", 5)?.clamp(1, 50) as i64;

    let client = connect(conn).await?;
    // 空集合时直接返回空结果（不报错）。
    if !collection_exists(&client, conn).await? {
        let empty: Vec<Json> = Vec::new();
        return Ok(json!({ "results": empty }));
    }
    load(&client, conn).await?;

    let resp = client
        .search(
            SearchRequest::builder()
                .collection_name(&conn.collection)
                .vector_field(FIELD_EMBEDDING)
                .vectors(SearchVectors::Float(vec![embedding]))
                .output_fields([FIELD_DOC_ID, FIELD_TITLE, FIELD_TEXT])
                .limit(top_k)
                .consistency_level(ConsistencyLevel::Strong)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("检索失败: {e}"))?;

    let mut results = Vec::new();
    for single in resp.results().iter() {
        let rows = single.rows().map_err(|e| e.to_string())?;
        for row in rows {
            let doc_id = row.get_str(FIELD_DOC_ID).unwrap_or_default().to_string();
            let title = row.get_str(FIELD_TITLE).unwrap_or_default().to_string();
            let text = row.get_str(FIELD_TEXT).unwrap_or_default().to_string();
            let distance = match row.get("score") {
                Ok(ResultValue::Float(v)) => v as f64,
                _ => 0.0,
            };
            results.push(json!({
                "doc_id": doc_id,
                "title": title,
                "text": text,
                "distance": distance,
            }));
        }
    }
    Ok(json!({ "results": results }))
}

/// 列出文档（按 doc_id 去重并统计 chunk 数）。
async fn op_list_documents(conn: &ConnInfo) -> StdResult<Json, String> {
    let client = connect(conn).await?;
    if !collection_exists(&client, conn).await? {
        let empty: Vec<Json> = Vec::new();
        return Ok(json!({ "documents": empty }));
    }

    let resp = client
        .query(
            QueryRequest::builder()
                .collection_name(&conn.collection)
                .filter(FILTER_ALL)
                .output_fields([FIELD_DOC_ID, FIELD_TITLE, FIELD_CREATED_AT])
                .limit(DEFAULT_LIMIT)
                .consistency_level(ConsistencyLevel::Strong)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("查询文档列表失败: {e}"))?;

    // 按 doc_id 聚合（保留首个标题/创建时间，统计 chunk 数）。
    let mut docs: std::collections::BTreeMap<String, (String, String, i64)> =
        std::collections::BTreeMap::new();
    let rows = resp.results().rows().map_err(|e| e.to_string())?;
    for row in rows {
        let doc_id = row.get_str(FIELD_DOC_ID).unwrap_or_default().to_string();
        let title = row.get_str(FIELD_TITLE).unwrap_or_default().to_string();
        let created_at = row.get_str(FIELD_CREATED_AT).unwrap_or_default().to_string();
        docs.entry(doc_id)
            .and_modify(|(_, _, count)| *count += 1)
            .or_insert((title, created_at, 1));
    }

    let documents = docs
        .into_iter()
        .map(|(id, (title, created_at, chunk_count))| {
            json!({
                "id": id,
                "title": title,
                "created_at": created_at,
                "chunk_count": chunk_count,
            })
        })
        .collect::<Vec<_>>();
    Ok(json!({ "documents": documents }))
}

/// 删除文档（含全部分块向量）。
async fn delete_by_doc_id(client: &ClientV2, conn: &ConnInfo, doc_id: &str) -> StdResult<(), String> {
    // Milvus 删除表达式对字符串值需用双引号包裹并转义内部双引号。
    let escaped = doc_id.replace('\\', "\\\\").replace('"', "\\\"");
    let expr = format!("{FIELD_DOC_ID} == \"{escaped}\"");
    client
        .delete(
            DeleteRequest::builder()
                .collection_name(&conn.collection)
                .filter(&expr)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("删除向量失败: {e}"))?;
    Ok(())
}

async fn op_delete_document(conn: &ConnInfo, args: &Json) -> StdResult<Json, String> {
    let doc_id = str_arg(args, "doc_id")?;
    let client = connect(conn).await?;
    if !collection_exists(&client, conn).await? {
        return Ok(json!({ "deleted": true }));
    }
    delete_by_doc_id(&client, conn, &doc_id).await?;
    Ok(json!({ "deleted": true }))
}

/// 统计：文档数（去重 doc_id）、分块数（总行数）、维度。
async fn op_stats(conn: &ConnInfo) -> StdResult<Json, String> {
    let client = connect(conn).await?;
    if !collection_exists(&client, conn).await? {
        return Ok(json!({
            "document_count": 0,
            "chunk_count": 0,
            "dimension": 0,
        }));
    }

    let dimension = collection_dimension(&client, conn).await?.unwrap_or(0);

    let resp = client
        .query(
            QueryRequest::builder()
                .collection_name(&conn.collection)
                .filter(FILTER_ALL)
                .output_fields([FIELD_DOC_ID])
                .limit(DEFAULT_LIMIT)
                .consistency_level(ConsistencyLevel::Strong)
                .build()
                .map_err(|e| e.to_string())?,
        )
        .await
        .map_err(|e| format!("统计分块失败: {e}"))?;

    let mut document_set = std::collections::HashSet::new();
    let mut chunk_count: i64 = 0;
    let rows = resp.results().rows().map_err(|e| e.to_string())?;
    for row in rows {
        if let Ok(doc_id) = row.get_str(FIELD_DOC_ID) {
            document_set.insert(doc_id.to_string());
        }
        chunk_count += 1;
    }

    Ok(json!({
        "document_count": document_set.len() as i64,
        "chunk_count": chunk_count,
        "dimension": dimension as i64,
    }))
}

// ======================== FFI 入口 ========================

/// 统一向量库操作入口。`conn_json`、`op`、`args_json` 均为 UTF-8 字符串指针。
#[no_mangle]
pub extern "C" fn vector_request(
    conn_json: *const c_char,
    op: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(|| vector_request_inner(conn_json, op, args_json)))
        .unwrap_or_else(|_| {
            let msg = "Rust panic in vector_request".to_string();
            set_last_error(&msg);
            cstring_out(json!({ "ok": false, "error": msg }).to_string())
        })
}

fn vector_request_inner(
    conn_json: *const c_char,
    op: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    let result = (|| -> StdResult<String, String> {
        if conn_json.is_null() {
            return Err("conn_json 为空指针".to_string());
        }
        let conn_raw = unsafe { CStr::from_ptr(conn_json) }
            .to_str()
            .map_err(|_| "conn_json 不是有效的 UTF-8".to_string())?;
        if op.is_null() {
            return Err("op 为空指针".to_string());
        }
        let op_name = unsafe { CStr::from_ptr(op) }
            .to_str()
            .map_err(|_| "op 不是有效的 UTF-8".to_string())?;
        let args = parse_args(args_json)?;

        let conn: ConnInfo = serde_json::from_str(conn_raw)
            .map_err(|e| format!("连接配置解析失败: {e}"))?;

        let payload = match op_name {
            "init" => runtime().block_on(op_init(&conn, &args))?,
            "add" => runtime().block_on(op_add(&conn, &args))?,
            "search" => runtime().block_on(op_search(&conn, &args))?,
            "list_documents" => runtime().block_on(op_list_documents(&conn))?,
            "delete_document" => runtime().block_on(op_delete_document(&conn, &args))?,
            "stats" => runtime().block_on(op_stats(&conn))?,
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
pub extern "C" fn free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 获取最后一次错误的文本（调试接口）。
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

    fn call(conn: &str, op: &str, args: &str) -> Json {
        let conn_c = CString::new(conn).unwrap();
        let op_c = CString::new(op).unwrap();
        let args_c = CString::new(args).unwrap();
        let raw = vector_request(conn_c.as_ptr(), op_c.as_ptr(), args_c.as_ptr());
        let s = unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned();
        free_string(raw);
        serde_json::from_str(&s).unwrap()
    }

    #[test]
    fn test_unknown_op() {
        // 未知 op 在连接前分发，无需 Milvus 即可验证。
        let conn = r#"{"uri":"http://localhost:19530","token":"","collection":"x"}"#;
        let res = call(conn, "nope", "{}");
        assert!(res["ok"] == false, "{res}");
        assert!(res["error"].as_str().unwrap().contains("不支持的向量库操作"));
    }

    #[test]
    fn test_bad_conn_json() {
        let res = call("not-json", "init", "{}");
        assert!(res["ok"] == false, "{res}");
    }

    // 以下测试需要本地运行的 Milvus 实例，默认忽略（避免 CI 无服务时失败）。
    // 运行：cargo test --release -- --ignored
    // 或设 MILVUS_URI=http://localhost:19530 后手动执行。
    fn milvus_conn() -> String {
        let uri = std::env::var("MILVUS_URI").unwrap_or_else(|_| "http://localhost:19530".to_string());
        let coll = format!("xmc_test_{}", std::process::id());
        format!(r#"{{"uri":"{uri}","token":"","collection":"{coll}"}}"#)
    }

    #[tokio::test]
    #[ignore]
    async fn integration_init_add_search_delete() {
        let conn = milvus_conn();
        let client = connect(&serde_json::from_str(&conn).unwrap()).await.unwrap();
        let _ = client
            .drop_collection(
                DropCollectionRequest::builder()
                    .collection_name("xmc_test_integration")
                    .build()
                    .unwrap(),
            )
            .await;

        let res = call(&conn, "init", r#"{"dimension":3}"#);
        assert!(res["ok"] == true, "{res}");

        let res = call(
            &conn,
            "add",
            r#"{"doc_id":"d1","title":"魔兽","created_at":"2026-01-01T00:00:00Z","chunks":[{"text":"末影龙是结束之地的 Boss","embedding":[1.0,0.0,0.0]},{"text":"下界合金装备最坚固","embedding":[0.0,1.0,0.0]}]}"#,
        );
        assert!(res["ok"] == true, "{res}");

        let res = call(
            &conn,
            "search",
            r#"{"embedding":[0.9,0.1,0.1],"top_k":3}"#,
        );
        assert!(res["ok"] == true, "{res}");
        let results = res["result"]["results"].as_array().unwrap();
        assert!(!results.is_empty());
        assert!(results[0]["distance"].as_f64().unwrap() < 1.0);

        let res = call(&conn, "delete_document", r#"{"doc_id":"d1"}"#);
        assert!(res["ok"] == true, "{res}");
    }
}
