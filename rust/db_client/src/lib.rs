//! XMC Server Launcher 远程数据库客户端模块
//!
//! 基于 Rust 实现 MySQL / MariaDB / PostgreSQL / Redis 的连接与操作，
//! 供 Flutter 通过 FFI 调用（xmc_db_client.dll），替代 Dart 侧
//! mysql_dart / postgres / redis 包。遵循项目约定：数据库网络操作由
//! Rust 执行（与 HTTP 走 Rust 一致），无 OpenSSL 依赖（MySQL TLS 用
//! rustls，PG/Redis 默认不启用 TLS）。
//!
//! 设计为"即用即连、用完即关"的一次性调用：每次调用携带完整连接信息，
//! 函数内部建立连接、执行操作、关闭连接，不维护跨调用长连接。
//!
//! 统一入口 `db_request(conn_json, op, args_json)`：
//! - conn_json: `{"type":"mysql|mariadb|postgres|redis","host":"...",
//!    "port":3306,"username":"...","password":"...","database":null}`
//! - op: 操作名（test_connection / get_databases / get_tables /
//!   query_table / count_rows / execute / get_primary_keys / update_row /
//!   insert_row / delete_row / create_database_with_user / drop_database /
//!   get_users / create_user / drop_user / redis_keys / redis_get /
//!   redis_set / redis_delete）
//! - args_json: 操作参数 JSON（可为空指针）
//!
//! 返回 JSON 字符串（Dart 侧用 `free_string` 释放）：
//! - 成功: `{"ok":true,"result":{...}}`
//! - 失败: `{"ok":false,"error":"..."}`

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::Duration;

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde_json::{json, Map, Value as Json};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

const CONN_TIMEOUT: Duration = Duration::from_secs(15);
const IO_TIMEOUT: Duration = Duration::from_secs(120);

// ======================== 连接信息 ========================

#[derive(serde::Deserialize)]
struct ConnInfo {
    #[serde(rename = "type")]
    db_type: String,
    host: String,
    port: u16,
    #[serde(default)]
    username: Option<String>,
    #[serde(default)]
    password: Option<String>,
    #[serde(default)]
    database: Option<String>,
    /// 是否使用 TLS 加密连接（MySQL/PG/Redis 均支持，rustls，无 OpenSSL）。
    #[serde(default)]
    ssl: bool,
}

#[allow(dead_code)]
impl ConnInfo {
    fn is_redis(&self) -> bool {
        self.db_type == "redis"
    }
    fn is_mysql(&self) -> bool {
        self.db_type == "mysql" || self.db_type == "mariadb"
    }
    fn is_postgres(&self) -> bool {
        self.db_type == "postgres"
    }
    fn user_or(&self, default: &str) -> String {
        self.username.clone().filter(|s| !s.is_empty()).unwrap_or_else(|| default.to_string())
    }
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

fn bool_arg(args: &Json, name: &str, default: bool) -> Result<bool, String> {
    match args.get(name) {
        Some(Json::Bool(b)) => Ok(*b),
        _ => Ok(default),
    }
}

fn map_arg(args: &Json, name: &str) -> Result<Map<String, Json>, String> {
    match args.get(name) {
        Some(Json::Object(m)) => Ok(m.clone()),
        _ => Err(format!("缺少参数: {name}")),
    }
}

/// 二进制字节 → JSON：能按 UTF-8 解码用字符串，否则 base64（带前缀）
fn bytes_to_json(bytes: Vec<u8>) -> Json {
    match String::from_utf8(bytes) {
        Ok(s) => Json::String(s),
        Err(e) => Json::String(format!("[binary base64]{}", BASE64.encode(e.into_bytes()))),
    }
}

// == SQL 转义与值序列化（语义与 Dart 侧原实现一致）==

fn esc_mysql_ident(ident: &str) -> String {
    ident.replace('`', "``")
}
fn esc_mysql_str(s: &str) -> String {
    s.replace('\\', "\\\\").replace('\'', "''")
}
fn esc_pg_ident(ident: &str) -> String {
    ident.replace('"', "\"\"")
}
fn esc_pg_str(s: &str) -> String {
    s.replace('\'', "''")
}

/// 校验 MySQL/PostgreSQL 用户名与主机名（白名单，M-4 根治）。
///
/// MySQL 用户名允许字母、数字、`_`、`$`；host 允许 `%`、`.`、`-`、
/// 字母数字与通配。拒绝含引号/反引号/空白等可能改变语句语义的字符。
fn validate_user_ident(s: &str, allow_percent: bool) -> Result<(), String> {
    let ok = !s.is_empty()
        && s.bytes().all(|b| {
            b.is_ascii_alphanumeric()
                || b == b'_'
                || b == b'$'
                || (allow_percent && b == b'%')
                || b == b'-'
                || b == b'.'
        });
    if ok {
        Ok(())
    } else {
        Err(format!("无效的用户名/主机名: {s:?}（仅允许字母、数字、_、$、-、.{}）",
            if allow_percent { "、%" } else { "" }))
    }
}

/// 值 → SQL 字面量：null → NULL，空字符串 → NULL，其余转义为字符串
fn sql_value(v: &Json, esc: fn(&str) -> String) -> String {
    match v {
        Json::Null => "NULL".to_string(),
        Json::String(s) if s.is_empty() => "NULL".to_string(),
        Json::String(s) => format!("'{}'", esc(s)),
        other => format!("'{}'", esc(&other.to_string())),
    }
}

fn mysql_value(v: &Json) -> String {
    sql_value(v, esc_mysql_str)
}
fn pg_value(v: &Json) -> String {
    sql_value(v, esc_pg_str)
}

// ======================== MySQL / MariaDB ========================

fn mysql_opts(conn: &ConnInfo, db_override: Option<&str>) -> mysql::Opts {
    let pass = conn.password.clone().unwrap_or_default();
    let db = db_override
        .map(|s| s.to_string())
        .or_else(|| conn.database.clone());
    let mut builder = mysql::OptsBuilder::new()
        .ip_or_hostname(Some(conn.host.as_str()))
        .tcp_port(conn.port)
        .user(Some(conn.user_or("root").as_str()))
        .pass(Some(pass.as_str()))
        .db_name(db.as_deref())
        .tcp_connect_timeout(Some(CONN_TIMEOUT))
        .read_timeout(Some(IO_TIMEOUT))
        .write_timeout(Some(IO_TIMEOUT));
    if conn.ssl {
        // rustls 后端 + webpki-roots（Mozilla）校验证书，无 OpenSSL。
        builder = builder.ssl_opts(Some(mysql::SslOpts::default()));
    }
    builder.into()
}

fn mysql_connect(conn: &ConnInfo, db_override: Option<&str>) -> Result<mysql::Conn, String> {
    mysql::Conn::new(mysql_opts(conn, db_override)).map_err(|e| format!("MySQL 连接失败: {e}"))
}

/// MySQL 日期/时间值 → 字符串
fn mysql_date_to_str(y: u16, mo: u8, d: u8, h: u8, mi: u8, s: u8, us: u32) -> String {
    if h == 0 && mi == 0 && s == 0 && us == 0 {
        format!("{y:04}-{mo:02}-{d:02}")
    } else if us == 0 {
        format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}")
    } else {
        format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}.{us:06}")
    }
}

fn mysql_time_to_str(negative: bool, days: u32, h: u8, mi: u8, s: u8, us: u32) -> String {
    let sign = if negative { "-" } else { "" };
    let total_h = days as u64 * 24 + h as u64;
    if us == 0 {
        format!("{sign}{total_h}:{mi:02}:{s:02}")
    } else {
        format!("{sign}{total_h}:{mi:02}:{s:02}.{us:06}")
    }
}

/// MySQL 列值 → JSON
fn mysql_cell_to_json(v: mysql::Value) -> Json {
    match v {
        mysql::Value::NULL => Json::Null,
        mysql::Value::Bytes(b) => bytes_to_json(b),
        mysql::Value::Int(i) => json!(i),
        mysql::Value::UInt(u) => json!(u),
        mysql::Value::Float(f) => json!(f),
        mysql::Value::Double(d) => json!(d),
        mysql::Value::Date(y, mo, d, h, mi, s, us) => json!(mysql_date_to_str(y, mo, d, h, mi, s, us)),
        mysql::Value::Time(neg, days, h, mi, s, us) => {
            json!(mysql_time_to_str(neg, days, h, mi, s, us))
        }
    }
}

/// MySQL 列值 → 字符串（用户/主机等文本列）
fn mysql_cell_string(v: mysql::Value) -> String {
    match v {
        mysql::Value::Bytes(b) => String::from_utf8_lossy(&b).into_owned(),
        mysql::Value::NULL => String::new(),
        other => format!("{other:?}"),
    }
}

/// 执行查询并返回 {columns, rows, affected}
fn mysql_query_rows(
    conn: &mut mysql::Conn,
    sql: &str,
    params: Option<(u64, u64)>,
    name: &str,
) -> Result<Json, String> {
    use mysql::prelude::Queryable;
    let result = match params {
        Some((limit, offset)) => conn
            .exec_iter(sql, (limit, offset))
            .map_err(|e| format!("{name} 执行失败: {e}"))?,
        None => conn
            .exec_iter(sql, ())
            .map_err(|e| format!("{name} 执行失败: {e}"))?,
    };
    let affected = result.affected_rows();
    let columns: Vec<String> = result
        .columns()
        .as_ref()
        .iter()
        .map(|c| c.name_str().to_string())
        .collect();
    let mut rows = Vec::new();
    for row in result {
        let row = row.map_err(|e| format!("{name} 读取行失败: {e}"))?;
        let mut map = Map::new();
        for i in 0..row.len() {
            if i < columns.len() {
                map.insert(columns[i].clone(), mysql_cell_to_json(row[i].clone()));
            }
        }
        rows.push(Json::Object(map));
    }
    Ok(json!({ "columns": columns, "rows": rows, "affected": affected }))
}

/// 执行非查询语句并返回影响行数
fn mysql_exec_affected(conn: &mut mysql::Conn, sql: &str, name: &str) -> Result<Json, String> {
    use mysql::prelude::Queryable;
    conn.query_drop(sql).map_err(|e| format!("{name} 执行失败: {e}"))?;
    Ok(json!({ "columns": [], "rows": [], "affected": conn.affected_rows() }))
}

// ======================== PostgreSQL ========================

fn pg_config(conn: &ConnInfo, db_override: Option<&str>) -> postgres::Config {
    let user = conn.user_or("postgres");
    let db = db_override
        .map(|s| s.to_string())
        .or_else(|| conn.database.clone())
        .unwrap_or_else(|| "postgres".to_string());
    let mut cfg = postgres::Config::new();
    cfg.host(conn.host.as_str())
        .port(conn.port)
        .user(user.as_str())
        .dbname(db.as_str());
    if let Some(p) = conn.password.as_ref().filter(|s| !s.is_empty()) {
        cfg.password(p.as_str());
    }
    cfg.connect_timeout(CONN_TIMEOUT);
    cfg
}

fn pg_connect(conn: &ConnInfo, db_override: Option<&str>) -> Result<postgres::Client, String> {
    let cfg = pg_config(conn, db_override);
    if conn.ssl {
        // rustls 连接器，webpki-roots（Mozilla）校验证书，无 OpenSSL。
        let tls = rustls_tokio_postgres::MakeRustlsConnect::new(
            rustls_tokio_postgres::config_webpki_roots(),
        );
        cfg.connect(tls).map_err(|e| format!("PostgreSQL 连接失败: {e}"))
    } else {
        cfg.connect(postgres::NoTls)
            .map_err(|e| format!("PostgreSQL 连接失败: {e}"))
    }
}

/// PostgreSQL 列值 → JSON
fn pg_cell_to_json(row: &postgres::Row, idx: usize) -> Json {
    // NULL 判定：任何类型下 Option<T> 为 None
    if row
        .try_get::<_, Option<i64>>(idx)
        .map(|v| v.is_none())
        .unwrap_or(false)
    {
        return Json::Null;
    }
    if let Ok(Some(s)) = row.try_get::<_, Option<String>>(idx) {
        return json!(s);
    }
    if let Ok(Some(n)) = row.try_get::<_, Option<i64>>(idx) {
        return json!(n);
    }
    if let Ok(Some(f)) = row.try_get::<_, Option<f64>>(idx) {
        return json!(f);
    }
    if let Ok(Some(b)) = row.try_get::<_, Option<bool>>(idx) {
        return json!(b);
    }
    if let Ok(Some(d)) = row.try_get::<_, Option<chrono::NaiveDate>>(idx) {
        return json!(d.to_string());
    }
    if let Ok(Some(t)) = row.try_get::<_, Option<chrono::NaiveTime>>(idx) {
        return json!(t.to_string());
    }
    if let Ok(Some(ts)) = row.try_get::<_, Option<chrono::NaiveDateTime>>(idx) {
        return json!(ts.to_string());
    }
    if let Ok(Some(bin)) = row.try_get::<_, Option<Vec<u8>>>(idx) {
        return bytes_to_json(bin);
    }
    Json::Null
}

fn pg_rows_to_json(rows: &[postgres::Row]) -> Result<Json, String> {
    let columns: Vec<String> = rows
        .first()
        .map(|r| r.columns().iter().map(|c| c.name().to_string()).collect())
        .unwrap_or_default();
    let mut arr = Vec::new();
    for row in rows {
        let mut map = Map::new();
        for (i, col) in row.columns().iter().enumerate() {
            map.insert(col.name().to_string(), pg_cell_to_json(row, i));
        }
        arr.push(Json::Object(map));
    }
    Ok(json!({ "columns": columns, "rows": arr, "affected": 0 }))
}

// ======================== Redis ========================

fn redis_connect(conn: &ConnInfo) -> Result<redis::Connection, String> {
    let scheme = if conn.ssl { "rediss" } else { "redis" };
    let url = format!("{scheme}://{}:{}", conn.host, conn.port);
    let client = if conn.ssl {
        // rustls + 本地信任库验证证书，无 OpenSSL。
        redis::Client::build_with_tls(
            url.as_str(),
            redis::TlsCertificates { client_tls: None, root_cert: None },
        )
        .map_err(|e| format!("Redis 地址无效: {e}"))?
    } else {
        redis::Client::open(url.as_str()).map_err(|e| format!("Redis 地址无效: {e}"))?
    };
    let mut con = client
        .get_connection_with_timeout(CONN_TIMEOUT)
        .map_err(|e| format!("Redis 连接失败: {e}"))?;
    if let Some(pwd) = conn.password.as_ref().filter(|s| !s.is_empty()) {
        let mut cmd = redis::cmd("AUTH");
        if let Some(user) = conn.username.as_ref().filter(|s| !s.is_empty()) {
            cmd.arg(user);
        }
        cmd.arg(pwd)
            .query::<()>(&mut con)
            .map_err(|e| format!("Redis 认证失败: {e}"))?;
    }
    Ok(con)
}

// ======================== 各操作实现 ========================

fn op_test_connection(conn: &ConnInfo) -> Result<Json, String> {
    if conn.is_redis() {
        let mut con = redis_connect(conn)?;
        let pong = redis::cmd("PING")
            .query::<String>(&mut con)
            .map_err(|e| format!("Redis PING 失败: {e}"))?;
        if pong != "PONG" {
            return Err(format!("PING 响应异常: {pong}"));
        }
    } else if conn.is_mysql() {
        mysql_connect(conn, None)?;
    } else if conn.is_postgres() {
        pg_connect(conn, None)?;
    } else {
        return Err(format!("不支持的数据库类型: {}", conn.db_type));
    }
    Ok(json!({ "message": "connected" }))
}

fn op_get_databases(conn: &ConnInfo) -> Result<Json, String> {
    if conn.is_redis() {
        return Ok(json!({ "databases": ["default"] }));
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        let dbs: Vec<String> = c
            .query("SHOW DATABASES")
            .map_err(|e| format!("SHOW DATABASES 失败: {e}"))?;
        return Ok(json!({ "databases": dbs }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        let rows = client
            .query(
                "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
                &[],
            )
            .map_err(|e| format!("查询 pg_database 失败: {e}"))?;
        let dbs: Vec<String> = rows
            .iter()
            .filter_map(|r| pg_cell_to_json(r, 0).as_str().map(|s| s.to_string()))
            .collect();
        return Ok(json!({ "databases": dbs }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_get_tables(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    if conn.is_redis() {
        return Ok(json!({ "tables": [] }));
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let tables: Vec<String> = c
            .query("SHOW TABLES")
            .map_err(|e| format!("SHOW TABLES 失败: {e}"))?;
        return Ok(json!({ "tables": tables }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let rows = client
            .query(
                "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename",
                &[],
            )
            .map_err(|e| format!("查询 pg_tables 失败: {e}"))?;
        let tables: Vec<String> = rows
            .iter()
            .filter_map(|r| pg_cell_to_json(r, 0).as_str().map(|s| s.to_string()))
            .collect();
        return Ok(json!({ "tables": tables }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_query_table(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    let limit = u64_arg(args, "limit", 100)?;
    let offset = u64_arg(args, "offset", 0)?;
    if conn.is_redis() {
        return Err("Redis 不支持表查询".to_string());
    }
    if conn.is_mysql() {
        let mut c = mysql_connect(conn, Some(&database))?;
        let sql = format!("SELECT * FROM `{}` LIMIT ? OFFSET ?", esc_mysql_ident(&table));
        return mysql_query_rows(&mut c, &sql, Some((limit, offset)), "表查询");
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let sql = format!("SELECT * FROM \"{}\" LIMIT $1 OFFSET $2", esc_pg_ident(&table));
        let rows = client
            .query(&sql, &[&(limit as i64), &(offset as i64)])
            .map_err(|e| format!("表查询失败: {e}"))?;
        return pg_rows_to_json(&rows);
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_count_rows(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    if conn.is_redis() {
        return Err("Redis 不支持表查询".to_string());
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let sql = format!("SELECT COUNT(*) AS c FROM `{}`", esc_mysql_ident(&table));
        let count: u64 = c
            .query_first(sql)
            .map_err(|e| format!("统计行数失败: {e}"))?
            .unwrap_or(0);
        return Ok(json!({ "count": count }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let sql = format!("SELECT COUNT(*) AS c FROM \"{}\"", esc_pg_ident(&table));
        let count: i64 = client
            .query_one(&sql, &[])
            .map_err(|e| format!("统计行数失败: {e}"))?
            .get(0);
        return Ok(json!({ "count": count }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_execute(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let sql = str_arg(args, "sql")?;
    let is_query = bool_arg(args, "is_query", false)?;
    if conn.is_redis() {
        return Err("Redis 不支持 SQL，请使用 Redis 专用操作".to_string());
    }
    if conn.is_mysql() {
        let mut c = mysql_connect(conn, Some(&database))?;
        return if is_query {
            mysql_query_rows(&mut c, &sql, None, "SQL 执行")
        } else {
            mysql_exec_affected(&mut c, &sql, "SQL 执行")
        };
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        return if is_query {
            let rows = client
                .query(&sql, &[])
                .map_err(|e| format!("SQL 执行失败: {e}"))?;
            pg_rows_to_json(&rows)
        } else {
            let affected = client
                .execute(&sql, &[])
                .map_err(|e| format!("SQL 执行失败: {e}"))?;
            Ok(json!({ "columns": [], "rows": [], "affected": affected }))
        };
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_get_primary_keys(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    if conn.is_redis() {
        return Ok(json!({ "keys": [] }));
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let sql = format!(
            "SELECT kcu.column_name FROM information_schema.table_constraints tc \
             JOIN information_schema.key_column_usage kcu \
               ON tc.constraint_name = kcu.constraint_name \
              AND tc.table_schema = kcu.table_schema \
             WHERE tc.constraint_type = 'PRIMARY KEY' \
               AND tc.table_schema = DATABASE() \
               AND tc.table_name = '{}' \
             ORDER BY kcu.ordinal_position",
            esc_mysql_str(&table)
        );
        let keys: Vec<String> = c.query(sql).map_err(|e| format!("查询主键失败: {e}"))?;
        return Ok(json!({ "keys": keys }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let sql = format!(
            "SELECT kcu.column_name FROM information_schema.table_constraints tc \
             JOIN information_schema.key_column_usage kcu \
               ON tc.constraint_name = kcu.constraint_name \
              AND tc.table_schema = kcu.table_schema \
             WHERE tc.constraint_type = 'PRIMARY KEY' \
               AND tc.table_schema = 'public' \
               AND tc.table_name = '{}' \
             ORDER BY kcu.ordinal_position",
            esc_pg_str(&table)
        );
        let rows = client
            .query(&sql, &[])
            .map_err(|e| format!("查询主键失败: {e}"))?;
        let keys: Vec<String> = rows
            .iter()
            .filter_map(|r| pg_cell_to_json(r, 0).as_str().map(|s| s.to_string()))
            .collect();
        return Ok(json!({ "keys": keys }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_update_row(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    let new_values = map_arg(args, "new_values")?;
    let where_row = map_arg(args, "where_row")?;
    if conn.is_redis() {
        return Err("Redis 不支持表编辑".to_string());
    }
    let where_clause = build_where_clause(conn, &where_row)?;
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let set_clause: Vec<String> = new_values
            .iter()
            .map(|(k, v)| format!("`{}` = {}", esc_mysql_ident(k), mysql_value(v)))
            .collect();
        let sql = format!(
            "UPDATE `{}` SET {} WHERE {}",
            esc_mysql_ident(&table),
            set_clause.join(", "),
            where_clause
        );
        c.query_drop(&sql).map_err(|e| format!("更新行失败: {e}"))?;
        return Ok(json!({ "affected": c.affected_rows() }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let set_clause: Vec<String> = new_values
            .iter()
            .map(|(k, v)| format!("\"{}\" = {}", esc_pg_ident(k), pg_value(v)))
            .collect();
        let sql = format!(
            "UPDATE \"{}\" SET {} WHERE {}",
            esc_pg_ident(&table),
            set_clause.join(", "),
            where_clause
        );
        let affected = client.execute(&sql, &[]).map_err(|e| format!("UPDATE 行失败: {e}"))?;
        return Ok(json!({ "affected": affected }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_insert_row(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    let values = map_arg(args, "values")?;
    if conn.is_redis() {
        return Err("Redis 不支持表编辑".to_string());
    }
    let cols: Vec<&String> = values.keys().collect();
    let vals: Vec<String> = values.values().map(mysql_value).collect();
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let col_sql: Vec<String> = cols.iter().map(|k| format!("`{}`", esc_mysql_ident(k))).collect();
        let sql = format!(
            "INSERT INTO `{}` ({}) VALUES ({})",
            esc_mysql_ident(&table),
            col_sql.join(", "),
            vals.join(", ")
        );
        c.query_drop(&sql).map_err(|e| format!("INSERT 失败: {e}"))?;
        return Ok(json!({ "affected": c.affected_rows() }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let col_sql: Vec<String> = cols.iter().map(|k| format!("\"{}\"", esc_pg_ident(k))).collect();
        let pg_vals: Vec<String> = values.values().map(pg_value).collect();
        let sql = format!(
            "INSERT INTO \"{}\" ({}) VALUES ({})",
            esc_pg_ident(&table),
            col_sql.join(", "),
            pg_vals.join(", ")
        );
        let affected = client.execute(&sql, &[]).map_err(|e| format!("INSERT 失败: {e}"))?;
        return Ok(json!({ "affected": affected }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_delete_row(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let table = str_arg(args, "table")?;
    let where_row = map_arg(args, "where_row")?;
    if conn.is_redis() {
        return Err("Redis 不支持表编辑".to_string());
    }
    let where_clause = build_where_clause(conn, &where_row)?;
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, Some(&database))?;
        let sql = format!(
            "DELETE FROM `{}` WHERE {}",
            esc_mysql_ident(&table),
            where_clause
        );
        c.query_drop(&sql).map_err(|e| format!("DELETE 失败: {e}"))?;
        return Ok(json!({ "affected": c.affected_rows() }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, Some(&database))?;
        let sql = format!(
            "DELETE FROM \"{}\" WHERE {}",
            esc_pg_ident(&table),
            where_clause
        );
        let affected = client.execute(&sql, &[]).map_err(|e| format!("DELETE 失败: {e}"))?;
        return Ok(json!({ "affected": affected }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

/// 构造 WHERE 子句：主键列优先，无主键用整行匹配（跳过 rowKey 辅助列）
fn build_where_clause(conn: &ConnInfo, where_row: &Map<String, Json>) -> Result<String, String> {
    let cols: Vec<String> = where_row
        .keys()
        .filter(|k| *k != "rowKey")
        .cloned()
        .collect();
    if conn.is_mysql() || conn.is_postgres() {
        let esc_ident = if conn.is_mysql() { esc_mysql_ident } else { esc_pg_ident };
        let esc_val = if conn.is_mysql() { mysql_value } else { pg_value };
        let parts: Vec<String> = cols
            .iter()
            .map(|k| format!("{} = {}", esc_ident(k), esc_val(where_row.get(k).unwrap())))
            .collect();
        if parts.is_empty() {
            return Err("无法定位数据行（表为空 WHERE）".to_string());
        }
        return Ok(parts.join(" AND "));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_create_database_with_user(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    let username = str_arg(args, "username")?;
    let password = str_arg(args, "password")?;
    if conn.is_redis() {
        return Err("Redis 不支持创建数据库".to_string());
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        let db = esc_mysql_ident(&database);
        validate_user_ident(&username, false)?;
        validate_user_ident(&database, false)?;
        // M-4：username 出现在单引号字符串字面量中，必须用字符串转义器；
        // 白名单校验（validate_user_ident）保证其只含安全字符。
        let user = esc_mysql_str(&username);
        let pwd = esc_mysql_str(&password);
        let statements = [
            format!("CREATE DATABASE `{db}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"),
            format!("CREATE USER '{user}'@'%' IDENTIFIED BY '{pwd}'"),
            format!("GRANT ALL PRIVILEGES ON `{db}`.* TO '{user}'@'%'"),
            "FLUSH PRIVILEGES".to_string(),
        ];
        for stmt in statements {
            c.query_drop(&stmt).map_err(|e| format!("创建数据库失败: {e}"))?;
        }
        return Ok(json!({}));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        let db = esc_pg_ident(&database);
        validate_user_ident(&username, false)?;
        validate_user_ident(&database, false)?;
        let user = esc_pg_ident(&username);
        let pwd = esc_pg_str(&password);
        let statements = [
            format!("CREATE DATABASE \"{db}\""),
            format!("CREATE USER \"{user}\" WITH PASSWORD '{pwd}'"),
            format!("GRANT ALL PRIVILEGES ON DATABASE \"{db}\" TO \"{user}\""),
        ];
        for stmt in statements {
            client
                .execute(&stmt, &[])
                .map_err(|e| format!("创建数据库失败: {e}"))?;
        }
        return Ok(json!({}));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_drop_database(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let database = str_arg(args, "database")?;
    if conn.is_redis() {
        return Err("Redis 不支持删除数据库".to_string());
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        let sql = format!("DROP DATABASE `{}`", esc_mysql_ident(&database));
        c.query_drop(&sql).map_err(|e| format!("删除数据库失败: {e}"))?;
        return Ok(json!({}));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        let sql = format!("DROP DATABASE \"{}\"", esc_pg_ident(&database));
        client.execute(&sql, &[]).map_err(|e| format!("删除数据库失败: {e}"))?;
        return Ok(json!({}));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_get_users(conn: &ConnInfo) -> Result<Json, String> {
    if conn.is_redis() {
        return Ok(json!({ "users": [] }));
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        let rows = c
            .query_iter("SELECT User, Host FROM mysql.user ORDER BY User")
            .map_err(|e| format!("查询用户失败: {e}"))?;
        let mut users = Vec::new();
        for row in rows {
            let row = row.map_err(|e| format!("读取用户行失败: {e}"))?;
            users.push(json!({
                "username": mysql_cell_string(row[0].clone()),
                "host": mysql_cell_string(row[1].clone()),
            }));
        }
        return Ok(json!({ "users": users }));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        let rows = client
            .query("SELECT usename FROM pg_user ORDER BY usename", &[])
            .map_err(|e| format!("查询用户失败: {e}"))?;
        let users: Vec<Json> = rows
            .iter()
            .map(|r| json!({ "username": pg_cell_to_json(r, 0) }))
            .collect();
        return Ok(json!({ "users": users }));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_create_user(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let username = str_arg(args, "username")?;
    let password = str_arg(args, "password")?;
    let host = opt_str_arg(args, "host").unwrap_or_else(|| "%".to_string());
    if conn.is_redis() {
        return Err("Redis 不支持用户管理".to_string());
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        // M-4：username/host 出现在单引号字符串字面量中，用字符串转义器
        // + 白名单校验（CREATE USER 的 'user'@'host' 均为字符串字面量）。
        validate_user_ident(&username, false)?;
        validate_user_ident(&host, true)?;
        let user = esc_mysql_str(&username);
        let pwd = esc_mysql_str(&password);
        let h = esc_mysql_str(&host);
        c.query_drop(format!("CREATE USER '{user}'@'{h}' IDENTIFIED BY '{pwd}'"))
            .map_err(|e| format!("创建用户失败: {e}"))?;
        c.query_drop("FLUSH PRIVILEGES").map_err(|e| format!("刷新权限失败: {e}"))?;
        return Ok(json!({}));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        validate_user_ident(&username, false)?;
        let user = esc_pg_ident(&username);
        let pwd = esc_pg_str(&password);
        let sql = format!("CREATE USER \"{user}\" WITH PASSWORD '{pwd}'");
        client.execute(&sql, &[]).map_err(|e| format!("创建用户失败: {e}"))?;
        return Ok(json!({}));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_drop_user(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let username = str_arg(args, "username")?;
    let host = opt_str_arg(args, "host").unwrap_or_else(|| "%".to_string());
    if conn.is_redis() {
        return Err("Redis 不支持用户管理".to_string());
    }
    if conn.is_mysql() {
        use mysql::prelude::Queryable;
        let mut c = mysql_connect(conn, None)?;
        // M-4：DROP USER 的 'user'@'host' 为字符串字面量，需白名单 + 字符串转义。
        validate_user_ident(&username, false)?;
        validate_user_ident(&host, true)?;
        let user = esc_mysql_str(&username);
        let h = esc_mysql_str(&host);
        c.query_drop(format!("DROP USER '{user}'@'{h}'"))
            .map_err(|e| format!("删除用户失败: {e}"))?;
        c.query_drop("FLUSH PRIVILEGES").map_err(|e| format!("刷新权限失败: {e}"))?;
        return Ok(json!({}));
    }
    if conn.is_postgres() {
        let mut client = pg_connect(conn, None)?;
        validate_user_ident(&username, false)?;
        let user = esc_pg_ident(&username);
        let sql = format!("DROP USER \"{user}\"");
        client.execute(&sql, &[]).map_err(|e| format!("删除用户失败: {e}"))?;
        return Ok(json!({}));
    }
    Err(format!("不支持的数据库类型: {}", conn.db_type))
}

fn op_redis_keys(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let pattern = opt_str_arg(args, "pattern").unwrap_or_else(|| "*".to_string());
    let mut con = redis_connect(conn)?;
    let keys: Vec<String> = redis::cmd("KEYS")
        .arg(pattern)
        .query(&mut con)
        .map_err(|e| format!("Redis KEYS 失败: {e}"))?;
    Ok(json!({ "keys": keys }))
}

fn op_redis_get(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let key = str_arg(args, "key")?;
    let mut con = redis_connect(conn)?;
    let value: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query(&mut con)
        .map_err(|e| format!("Redis GET 失败: {e}"))?;
    Ok(json!({ "value": value }))
}

fn op_redis_set(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let key = str_arg(args, "key")?;
    let value = str_arg(args, "value")?;
    let mut con = redis_connect(conn)?;
    redis::cmd("SET")
        .arg(&key)
        .arg(&value)
        .query::<()>(&mut con)
        .map_err(|e| format!("Redis SET 失败: {e}"))?;
    Ok(json!({}))
}

fn op_redis_delete(conn: &ConnInfo, args: &Json) -> Result<Json, String> {
    let key = str_arg(args, "key")?;
    let mut con = redis_connect(conn)?;
    let deleted: u64 = redis::cmd("DEL")
        .arg(&key)
        .query(&mut con)
        .map_err(|e| format!("Redis DEL 失败: {e}"))?;
    Ok(json!({ "deleted": deleted }))
}

// ======================== FFI 入口 ========================

/// 统一数据库操作入口。
///
/// # 参数
/// - `conn_json`: 连接信息 JSON（见模块文档）
/// - `op`: 操作名
/// - `args_json`: 操作参数 JSON（可为空指针）
///
/// # 返回值
/// 堆分配的 JSON 字符串（Dart 侧用 `free_string` 释放）。
#[no_mangle]
pub extern "C" fn db_request(
    conn_json: *const libc::c_char,
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    catch_unwind(AssertUnwindSafe(|| {
        db_request_inner(conn_json, op, args_json)
    }))
    .unwrap_or_else(|_| {
        let msg = "Rust panic in db_request".to_string();
        set_last_error(&msg);
        cstring_out(json!({ "ok": false, "error": msg }).to_string())
    })
}

fn db_request_inner(
    conn_json: *const libc::c_char,
    op: *const libc::c_char,
    args_json: *const libc::c_char,
) -> *mut libc::c_char {
    let result = (|| -> Result<String, String> {
        if conn_json.is_null() {
            return Err("conn_json 为空指针".to_string());
        }
        let conn_raw = unsafe { CStr::from_ptr(conn_json) }
            .to_str()
            .map_err(|_| "连接信息不是有效的 UTF-8".to_string())?;
        let conn: ConnInfo =
            serde_json::from_str(conn_raw).map_err(|e| format!("连接信息 JSON 解析失败: {e}"))?;
        if op.is_null() {
            return Err("op 为空指针".to_string());
        }
        let op_name = unsafe { CStr::from_ptr(op) }
            .to_str()
            .map_err(|_| "op 不是有效的 UTF-8".to_string())?;
        let args = parse_args(args_json)?;

        let payload = match op_name {
            "test_connection" => op_test_connection(&conn)?,
            "get_databases" => op_get_databases(&conn)?,
            "get_tables" => op_get_tables(&conn, &args)?,
            "query_table" => op_query_table(&conn, &args)?,
            "count_rows" => op_count_rows(&conn, &args)?,
            "execute" => op_execute(&conn, &args)?,
            "get_primary_keys" => op_get_primary_keys(&conn, &args)?,
            "update_row" => op_update_row(&conn, &args)?,
            "insert_row" => op_insert_row(&conn, &args)?,
            "delete_row" => op_delete_row(&conn, &args)?,
            "create_database_with_user" => op_create_database_with_user(&conn, &args)?,
            "drop_database" => op_drop_database(&conn, &args)?,
            "get_users" => op_get_users(&conn)?,
            "create_user" => op_create_user(&conn, &args)?,
            "drop_user" => op_drop_user(&conn, &args)?,
            "redis_keys" => op_redis_keys(&conn, &args)?,
            "redis_get" => op_redis_get(&conn, &args)?,
            "redis_set" => op_redis_set(&conn, &args)?,
            "redis_delete" => op_redis_delete(&conn, &args)?,
            other => return Err(format!("不支持的数据库操作: {other}")),
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

/// 释放 [db_request] 返回的字符串指针。
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