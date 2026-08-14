//! 跨物理机存档迁移状态机
//!
//! 流程（Dart 执行层逐步骤回报）：
//! Stopping → Archiving → Transferring → Restoring → Creating → Starting → Done
//! 任一步骤失败：记录错误并停留在当前状态，Dart 重试同一步骤即可继续；
//! `migrate_cancel` 置为 Failed 终止。

use rusqlite::Connection;
use serde_json::json;

use crate::db;
use crate::engine;
use crate::models::{
    Action, ActionKind, McService, MigrationJob, MigrationState, ReplicaDesired,
};

/// 发起迁移：为副本创建任务并产出第一步动作（停止副本）。
pub fn migrate_start(
    conn: &mut Connection,
    service_id: &str,
    replica_id: &str,
    to_node: &str,
    now_ms_input: i64,
) -> Result<(MigrationJob, Action), String> {
    let now = crate::engine::now_ms_exposed(now_ms_input);
    let service = db::get_service(conn, service_id)?
        .ok_or_else(|| format!("服务不存在: {service_id}"))?;
    let replica = find_replica(conn, service_id, replica_id)?
        .ok_or_else(|| format!("副本不存在: {replica_id}"))?;
    if to_node.trim().is_empty() {
        return Err("目标节点不能为空".to_string());
    }
    if replica.node_id == to_node {
        return Err("目标节点与当前节点相同".to_string());
    }
    if db::active_migration(conn, replica_id)?.is_some() {
        return Err("该副本已有进行中的迁移任务".to_string());
    }

    let archive_name = format!(
        "world_{}_{}.zip",
        sanitize(&service.name),
        replica.index_no
    );
    let job = MigrationJob {
        id: format!("m-{}-{:x}", replica.id, now),
        service_id: service.id.clone(),
        replica_id: replica.id.clone(),
        from_node: replica.node_id.clone(),
        to_node: to_node.to_string(),
        state: MigrationState::Stopping,
        error: None,
        archive_name,
        created_at_ms: now,
        updated_at_ms: now,
    };
    db::upsert_migration(conn, &job, now)?;
    let action = step_action(&service, &replica, &job)?;
    Ok((job, action))
}

/// 上报步骤结果：ok=true 推进状态机并返回下一步动作；
/// ok=false 记录错误并返回同一步骤动作（重试）。
pub fn report_migration(
    conn: &mut Connection,
    job_id: &str,
    ok: bool,
    error: Option<String>,
    now_ms_input: i64,
) -> Result<(MigrationJob, Option<Action>), String> {
    let now = crate::engine::now_ms_exposed(now_ms_input);
    let mut job = db::get_migration(conn, job_id)?
        .ok_or_else(|| format!("迁移任务不存在: {job_id}"))?;
    if job.state == MigrationState::Done || job.state == MigrationState::Failed {
        return Ok((job, None));
    }

    if !ok {
        job.error = Some(error.unwrap_or_else(|| "未知错误".to_string()));
        job.updated_at_ms = now;
        db::upsert_migration(conn, &job, now)?;
        let replica = find_replica(conn, &job.service_id, &job.replica_id)?
            .ok_or_else(|| "副本已不存在".to_string())?;
        let service = db::get_service(conn, &job.service_id)?
            .ok_or_else(|| "服务已不存在".to_string())?;
        let action = step_action(&service, &replica, &job)?;
        return Ok((job, Some(action)));
    }

    job.error = None;
    job.updated_at_ms = now;
    // 推进到下一状态
    job.advance();

    if job.state == MigrationState::Done {
        // 收尾：副本归属切到目标节点、清除崩溃状态、期望运行
        if let Some(mut replica) = find_replica(conn, &job.service_id, &job.replica_id)? {
            replica.node_id = job.to_node.clone();
            replica.crash_count = 0;
            replica.crash_loop = false;
            replica.backoff_secs = 0;
            replica.last_attempt_ms = 0;
            replica.desired = ReplicaDesired::Running;
            db::upsert_replica(conn, &replica, now)?;
        }
        db::upsert_migration(conn, &job, now)?;
        return Ok((job, None));
    }

    db::upsert_migration(conn, &job, now)?;
    let replica = find_replica(conn, &job.service_id, &job.replica_id)?
        .ok_or_else(|| "副本已不存在".to_string())?;
    let service = db::get_service(conn, &job.service_id)?
        .ok_or_else(|| "服务已不存在".to_string())?;
    let action = step_action(&service, &replica, &job)?;
    Ok((job, Some(action)))
}

/// 终止迁移任务。
pub fn migrate_cancel(conn: &Connection, job_id: &str, now_ms_input: i64) -> Result<(), String> {
    let now = crate::engine::now_ms_exposed(now_ms_input);
    let mut job = db::get_migration(conn, job_id)?
        .ok_or_else(|| format!("迁移任务不存在: {job_id}"))?;
    if job.state != MigrationState::Done {
        job.state = MigrationState::Failed;
        job.error = Some("用户取消".to_string());
        job.updated_at_ms = now;
        db::upsert_migration(conn, &job, now)?;
    }
    Ok(())
}

/// 当前状态对应的动作。
fn step_action(
    service: &McService,
    replica: &crate::models::McReplica,
    job: &MigrationJob,
) -> Result<Action, String> {
    let base = Action {
        kind: ActionKind::Noop,
        service_id: service.id.clone(),
        replica_id: replica.id.clone(),
        node_id: String::new(),
        payload: json!({}),
        delay_ms: 0,
        migration_id: job.id.clone(),
    };
    let action = match job.state {
        MigrationState::Pending => Action {
            kind: ActionKind::StopContainer,
            node_id: job.from_node.clone(),
            payload: json!({ "name": replica.container_name }),
            ..base
        },
        MigrationState::Stopping => Action {
            kind: ActionKind::StopContainer,
            node_id: job.from_node.clone(),
            payload: json!({ "name": replica.container_name }),
            ..base
        },
        MigrationState::Archiving => Action {
            kind: ActionKind::ArchiveWorld,
            node_id: job.from_node.clone(),
            payload: json!({
                "path": service.world_dir,
                "archiveName": job.archive_name,
            }),
            ..base
        },
        MigrationState::Transferring => Action {
            kind: ActionKind::TransferArchive,
            node_id: job.to_node.clone(),
            payload: json!({
                "archiveName": job.archive_name,
                "fromNode": job.from_node,
                "toNode": job.to_node,
            }),
            ..base
        },
        MigrationState::Restoring => Action {
            kind: ActionKind::RestoreArchive,
            node_id: job.to_node.clone(),
            payload: json!({
                "path": service.world_dir,
                "archiveName": job.archive_name,
            }),
            ..base
        },
        MigrationState::Creating => Action {
            kind: ActionKind::CreateContainer,
            node_id: job.to_node.clone(),
            payload: engine::create_payload(service, replica.index_no),
            ..base
        },
        MigrationState::Starting => Action {
            kind: ActionKind::StartContainer,
            node_id: job.to_node.clone(),
            payload: json!({ "name": replica.container_name }),
            ..base
        },
        MigrationState::Done | MigrationState::Failed => base,
    };
    Ok(action)
}

fn find_replica(
    conn: &Connection,
    service_id: &str,
    replica_id: &str,
) -> Result<Option<crate::models::McReplica>, String> {
    for r in db::list_replicas(conn, Some(service_id))? {
        if r.id == replica_id {
            return Ok(Some(r));
        }
    }
    Ok(None)
}

fn sanitize(name: &str) -> String {
    let s: String = name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
        .collect();
    let t = s.trim_matches('-');
    if t.is_empty() { "svc".to_string() } else { t.to_string() }
}
