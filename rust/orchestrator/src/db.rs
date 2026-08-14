//! SQLite 持久化层
//!
//! 每个 FFI 调用携带 dbPath，按需打开连接、执行、关闭（与 db_client
//! 「即用即连」风格一致）。表结构：
//! - services   ：服务规格（JSON）
//! - replicas   ：副本状态（JSON）
//! - migrations ：迁移任务（JSON）
//! - scale_log  ：扩缩容时间戳（冷却判定）

use rusqlite::{params, Connection, OptionalExtension};

use crate::models::{McReplica, McService, MigrationJob};

/// 打开数据库并初始化表结构。
pub fn open(db_path: &str) -> Result<Connection, String> {
    let conn = Connection::open(db_path).map_err(|e| format!("打开数据库失败: {e}"))?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS services (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            spec TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS replicas (
            id TEXT PRIMARY KEY,
            service_id TEXT NOT NULL,
            index_no INTEGER NOT NULL,
            spec TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            UNIQUE(service_id, index_no)
        );
        CREATE TABLE IF NOT EXISTS migrations (
            id TEXT PRIMARY KEY,
            replica_id TEXT NOT NULL,
            spec TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS scale_log (
            service_id TEXT PRIMARY KEY,
            last_scale_ms INTEGER NOT NULL
        );",
    )
    .map_err(|e| format!("初始化数据库失败: {e}"))?;
    Ok(conn)
}

// ======================== services ========================

pub fn upsert_service(conn: &Connection, service: &McService, now_ms: i64) -> Result<(), String> {
    let spec = serde_json::to_string(service).map_err(|e| format!("序列化服务失败: {e}"))?;
    conn.execute(
        "INSERT INTO services (id, name, spec, created_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, spec = excluded.spec",
        params![service.id, service.name, spec, now_ms],
    )
    .map_err(|e| format!("保存服务失败: {e}"))?;
    Ok(())
}

pub fn delete_service(conn: &Connection, service_id: &str) -> Result<(), String> {
    conn.execute("DELETE FROM services WHERE id = ?1", params![service_id])
        .map_err(|e| format!("删除服务失败: {e}"))?;
    conn.execute(
        "DELETE FROM replicas WHERE service_id = ?1",
        params![service_id],
    )
    .map_err(|e| format!("删除副本失败: {e}"))?;
    conn.execute(
        "DELETE FROM migrations WHERE id IN (SELECT m.id FROM migrations m JOIN replicas r ON m.replica_id = r.id WHERE r.service_id = ?1)",
        params![service_id],
    )
    .map_err(|e| format!("删除迁移任务失败: {e}"))?;
    Ok(())
}

pub fn get_service(conn: &Connection, service_id: &str) -> Result<Option<McService>, String> {
    let spec: Option<String> = conn
        .query_row(
            "SELECT spec FROM services WHERE id = ?1",
            params![service_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("查询服务失败: {e}"))?;
    match spec {
        Some(raw) => serde_json::from_str(&raw).map(Some).map_err(|e| format!("解析服务失败: {e}")),
        None => Ok(None),
    }
}

pub fn list_services(conn: &Connection) -> Result<Vec<McService>, String> {
    let mut stmt = conn
        .prepare("SELECT spec FROM services ORDER BY name")
        .map_err(|e| format!("查询服务列表失败: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("遍历服务列表失败: {e}"))?;
    let mut out = Vec::new();
    for row in rows {
        let raw = row.map_err(|e| format!("读取服务行失败: {e}"))?;
        out.push(serde_json::from_str(&raw).map_err(|e| format!("解析服务失败: {e}"))?);
    }
    Ok(out)
}

// ======================== replicas ========================

pub fn upsert_replica(conn: &Connection, replica: &McReplica, now_ms: i64) -> Result<(), String> {
    let spec = serde_json::to_string(replica).map_err(|e| format!("序列化副本失败: {e}"))?;
    conn.execute(
        "INSERT INTO replicas (id, service_id, index_no, spec, created_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET spec = excluded.spec",
        params![replica.id, replica.service_id, replica.index_no, spec, now_ms],
    )
    .map_err(|e| format!("保存副本失败: {e}"))?;
    Ok(())
}

pub fn delete_replica(conn: &Connection, replica_id: &str) -> Result<(), String> {
    conn.execute("DELETE FROM replicas WHERE id = ?1", params![replica_id])
        .map_err(|e| format!("删除副本失败: {e}"))?;
    Ok(())
}

pub fn list_replicas(
    conn: &Connection,
    service_id: Option<&str>,
) -> Result<Vec<McReplica>, String> {
    let mut out = Vec::new();
    let mut stmt = conn
        .prepare("SELECT spec FROM replicas ORDER BY service_id, index_no")
        .map_err(|e| format!("查询副本失败: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("遍历副本失败: {e}"))?;
    for row in rows {
        let raw = row.map_err(|e| format!("读取副本行失败: {e}"))?;
        let replica: McReplica =
            serde_json::from_str(&raw).map_err(|e| format!("解析副本失败: {e}"))?;
        if let Some(sid) = service_id {
            if replica.service_id != sid {
                continue;
            }
        }
        out.push(replica);
    }
    Ok(out)
}

/// 删除某服务中序号最大的 `count` 个副本（缩容）。
/// 返回被删除副本列表（调用方据此产出 destroy 动作）。
#[allow(dead_code)]
pub fn trim_replicas(
    conn: &Connection,
    service_id: &str,
    count: i64,
) -> Result<Vec<McReplica>, String> {
    let replicas = list_replicas(conn, Some(service_id))?;
    let mut indexed: Vec<_> = replicas.into_iter().filter(|r| r.index_no >= 0).collect();
    indexed.sort_by_key(|r| -r.index_no); // 序号大的先删
    let mut removed = Vec::new();
    for replica in indexed.into_iter().take(count as usize) {
        delete_replica(conn, &replica.id)?;
        removed.push(replica);
    }
    Ok(removed)
}

// ======================== migrations ========================

pub fn upsert_migration(
    conn: &Connection,
    job: &MigrationJob,
    now_ms: i64,
) -> Result<(), String> {
    let spec = serde_json::to_string(job).map_err(|e| format!("序列化迁移任务失败: {e}"))?;
    conn.execute(
        "INSERT INTO migrations (id, replica_id, spec, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET spec = excluded.spec, updated_at = excluded.updated_at",
        params![job.id, job.replica_id, spec, now_ms, now_ms],
    )
    .map_err(|e| format!("保存迁移任务失败: {e}"))?;
    Ok(())
}

pub fn get_migration(conn: &Connection, job_id: &str) -> Result<Option<MigrationJob>, String> {
    let spec: Option<String> = conn
        .query_row(
            "SELECT spec FROM migrations WHERE id = ?1",
            params![job_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("查询迁移任务失败: {e}"))?;
    match spec {
        Some(raw) => serde_json::from_str(&raw).map(Some).map_err(|e| format!("解析迁移任务失败: {e}")),
        None => Ok(None),
    }
}

pub fn list_migrations(conn: &Connection) -> Result<Vec<MigrationJob>, String> {
    let mut stmt = conn
        .prepare("SELECT spec FROM migrations ORDER BY created_at DESC")
        .map_err(|e| format!("查询迁移任务失败: {e}"))?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("遍历迁移任务失败: {e}"))?;
    let mut out = Vec::new();
    for row in rows {
        let raw = row.map_err(|e| format!("读取迁移任务失败: {e}"))?;
        out.push(serde_json::from_str(&raw).map_err(|e| format!("解析迁移任务失败: {e}"))?);
    }
    Ok(out)
}

/// 某副本是否有未完成的迁移任务。
pub fn active_migration(
    conn: &Connection,
    replica_id: &str,
) -> Result<Option<MigrationJob>, String> {
    for job in list_migrations(conn)? {
        if job.replica_id == replica_id
            && job.state != crate::models::MigrationState::Done
            && job.state != crate::models::MigrationState::Failed
        {
            return Ok(Some(job));
        }
    }
    Ok(None)
}

// ======================== scale_log ========================

pub fn last_scale_ms(conn: &Connection, service_id: &str) -> Result<i64, String> {
    let value: Option<i64> = conn
        .query_row(
            "SELECT last_scale_ms FROM scale_log WHERE service_id = ?1",
            params![service_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("查询扩缩容时间失败: {e}"))?;
    Ok(value.unwrap_or(0))
}

pub fn set_last_scale_ms(conn: &Connection, service_id: &str, ms: i64) -> Result<(), String> {
    conn.execute(
        "INSERT INTO scale_log (service_id, last_scale_ms) VALUES (?1, ?2)
         ON CONFLICT(service_id) DO UPDATE SET last_scale_ms = excluded.last_scale_ms",
        params![service_id, ms],
    )
    .map_err(|e| format!("记录扩缩容时间失败: {e}"))?;
    Ok(())
}
