//! 对账引擎（K8s Controller 风格）
//!
//! 核心循环：观测输入 → 与期望状态 diff → 产出动作（Dart 执行）→ 持久化状态。
//! 覆盖：
//! - 副本保障：副本缺失创建、超出销毁（含调度：标签亲和 + 运行时匹配 + 资源打分）
//! - 崩溃自愈：running→down 转换识别崩溃，指数退避重启，CrashLoopBackOff 阈值
//! - 弹性扩缩容：按就绪副本平均在线人数决策，冷却窗口防抖
//! - 迁移规划：跨物理机存档迁移状态机（见 migration 模块）

use rusqlite::Connection;
use serde_json::{json, Value};

use crate::db;
use crate::models::{
    Action, ActionKind, McReplica, McService, MigrationJob, MigrationState, NodeStatus,
    ReconcileInput, ReplicaDesired, ReplicaObserved, ServiceStatus,
};

/// 新副本创建失败时的占位节点（待调度）。
const PENDING_NODE: &str = "";

/// 稳定运行窗口：连续运行达到该时长后清零崩溃状态（退出 CrashLoopBackOff）。
const STABLE_WINDOW_MS: i64 = 60_000;

// ======================== 入口 ========================

/// 执行一轮对账：应用观测、自愈、弹性、副本保障，返回待执行动作。
pub fn reconcile(conn: &mut Connection, input: &ReconcileInput) -> Result<Vec<Action>, String> {
    let now = now_ms(input.now_ms);
    let mut actions = Vec::new();

    // 1. 观测副本状态（含崩溃识别）
    apply_observations(conn, &input.replicas, now)?;

    let services = db::list_services(conn)?;
    let mut all_replicas = db::list_replicas(conn, None)?;

    // 2. 逐服务对账
    for service in &services {
        let replicas: Vec<McReplica> = all_replicas
            .iter()
            .filter(|r| r.service_id == service.id)
            .cloned()
            .collect();

        // 2.1 崩溃自愈
        actions.extend(heal_crashes(conn, service, &replicas, now)?);

        // 2.2 弹性扩缩容（可能修改 desired_replicas）
        autoscale(conn, service, &replicas, now)?;
        // 自愈 / 弹性可能已更新服务与副本行，统一重读快照再对账副本数量
        let service = db::get_service(conn, &service.id)?
            .unwrap_or_else(|| service.clone());
        all_replicas = db::list_replicas(conn, None)?;
        let replicas: Vec<McReplica> = all_replicas
            .iter()
            .filter(|r| r.service_id == service.id)
            .cloned()
            .collect();

        // 2.3 副本保障（创建缺失 / 销毁多余 / 启动未运行）
        actions.extend(ensure_replicas(conn, &service, &replicas, &input.nodes, now)?);
    }

    // 3. 运行中副本的在线人数探测（弹性数据源）
    all_replicas = db::list_replicas(conn, None)?;
    for replica in &all_replicas {
        if replica.desired != ReplicaDesired::Running || !replica.running {
            continue;
        }
        let service = db::get_service(conn, &replica.service_id)?;
        let Some(service) = service else { continue };
        if service.autoscale || service.auto_heal {
            actions.push(Action {
                kind: ActionKind::Ping,
                service_id: replica.service_id.clone(),
                replica_id: replica.id.clone(),
                node_id: replica.node_id.clone(),
                payload: json!({
                    "host": replica.node_id,   // Dart 侧替换为节点地址
                    "port": replica.host_port,
                }),
                delay_ms: 0,
                migration_id: String::new(),
            });
        }
    }

    Ok(actions)
}

/// 仅记录观测（不触发动作），返回副本状态列表。
pub fn observe(
    conn: &mut Connection,
    observed: &[ReplicaObserved],
    now_ms_input: i64,
) -> Result<Vec<McReplica>, String> {
    let now = now_ms(now_ms_input);
    apply_observations(conn, observed, now)?;
    db::list_replicas(conn, None)
}

/// 服务 + 副本聚合状态（UI 快照）。
pub fn status(conn: &Connection, service_id: Option<&str>) -> Result<Vec<ServiceStatus>, String> {
    let services = db::list_services(conn)?;
    let replicas = db::list_replicas(conn, None)?;
    let migrations = db::list_migrations(conn)?;
    let mut out = Vec::new();
    for service in services {
        if let Some(sid) = service_id {
            if service.id != sid {
                continue;
            }
        }
        let mine: Vec<McReplica> = replicas
            .iter()
            .filter(|r| r.service_id == service.id)
            .cloned()
            .collect();
        let running_replicas = mine
            .iter()
            .filter(|r| r.running && r.desired == ReplicaDesired::Running)
            .count() as i64;
        let total_players: i64 = mine.iter().map(|r| r.players_online).sum();
        let ready: Vec<&McReplica> = mine
            .iter()
            .filter(|r| r.running && r.desired == ReplicaDesired::Running && r.ready)
            .collect();
        let avg_players = if ready.is_empty() {
            0.0
        } else {
            total_players as f64 / ready.len() as f64
        };
        let migrating = mine.iter().any(|r| {
            migrations
                .iter()
                .any(|m| m.replica_id == r.id && m.state != MigrationState::Done
                    && m.state != MigrationState::Failed)
        });
        out.push(ServiceStatus {
            service,
            replicas: mine,
            running_replicas,
            total_players,
            avg_players,
            migrating,
        });
    }
    Ok(out)
}

// ======================== 观测应用 ========================

fn apply_observations(
    conn: &mut Connection,
    observed: &[ReplicaObserved],
    now: i64,
) -> Result<(), String> {
    for obs in observed {
        let mut replica = match find_replica(conn, &obs.id)? {
            Some(r) => r,
            None => continue,
        };
        let was_running = replica.running;
        replica.last_observed_ms = now;
        replica.running = obs.running;
        if let Some(players) = obs.players {
            replica.players_online = players;
            replica.ready = obs.running;
        } else if !obs.running {
            replica.ready = false;
        }
        if obs.running {
            // 稳定窗口：连续运行满 STABLE_WINDOW_MS 后退出崩溃状态
            if replica.stable_since_ms == 0 {
                replica.stable_since_ms = now;
            } else if now - replica.stable_since_ms >= STABLE_WINDOW_MS {
                replica.crash_count = 0;
                replica.crash_loop = false;
                replica.backoff_secs = 0;
                replica.stable_since_ms = now;
            }
        } else {
            replica.stable_since_ms = 0;
            // 期望运行且此前在运行 → down = 崩溃
            if was_running && replica.desired == ReplicaDesired::Running {
                replica.crash_count += 1;
            }
        }
        db::upsert_replica(conn, &replica, now)?;
    }
    Ok(())
}

fn find_replica(conn: &Connection, id: &str) -> Result<Option<McReplica>, String> {
    for r in db::list_replicas(conn, None)? {
        if r.id == id {
            return Ok(Some(r));
        }
    }
    Ok(None)
}

// ======================== 崩溃自愈 ========================

fn heal_crashes(
    conn: &mut Connection,
    service: &McService,
    replicas: &[McReplica],
    now: i64,
) -> Result<Vec<Action>, String> {
    let mut actions = Vec::new();
    if !service.auto_heal {
        return Ok(actions);
    }
    for replica in replicas {
        if replica.desired != ReplicaDesired::Running {
            continue;
        }
        if replica.running {
            continue; // 运行中：无需处理
        }
        let mut updated = replica.clone();
        // 崩溃路径：此前有启动尝试或已有崩溃记录（含启动即失败）
        let is_crash = updated.last_attempt_ms > 0 || updated.crash_count > 0;
        if is_crash {
            if updated.crash_count == 0 {
                updated.crash_count = 1; // 首次启动失败也算 1 次崩溃
            }
            updated.backoff_secs = backoff_secs(service, updated.crash_count);
            updated.crash_loop = updated.crash_count >= service.crash_threshold;
            // 退避窗口内：等待，不产生动作
            if now - updated.last_attempt_ms < updated.backoff_secs * 1000 {
                db::upsert_replica(conn, &updated, now)?;
                continue;
            }
        } else {
            updated.crash_count = 0;
            updated.backoff_secs = 0;
        }
        updated.last_attempt_ms = now;
        db::upsert_replica(conn, &updated, now)?;
        actions.push(Action {
            kind: if is_crash { ActionKind::RestartContainer } else { ActionKind::StartContainer },
            service_id: service.id.clone(),
            replica_id: replica.id.clone(),
            node_id: replica.node_id.clone(),
            payload: json!({
                "crashCount": updated.crash_count,
                "crashLoop": updated.crash_loop,
                "backoffSecs": updated.backoff_secs,
            }),
            delay_ms: updated.backoff_secs * 1000,
            migration_id: String::new(),
        });
    }
    Ok(actions)
}

/// 指数退避：base * 2^crash_count，封顶 max。
fn backoff_secs(service: &McService, crash_count: i64) -> i64 {
    let shift = crash_count.min(20);
    let base = service.backoff_base_secs.max(1);
    let value = base.saturating_mul(1i64 << shift);
    value.min(service.max_backoff_secs.max(base))
}

// ======================== 弹性扩缩容 ========================

/// 按在线人数决策扩缩容。返回是否变更了期望副本数。
fn autoscale(
    conn: &mut Connection,
    service: &McService,
    replicas: &[McReplica],
    now: i64,
) -> Result<bool, String> {
    if !service.autoscale {
        return Ok(false);
    }
    // 冷却窗口（仅对历史扩缩容生效；首次决策不受限）
    let last = db::last_scale_ms(conn, &service.id)?;
    if last > 0 && now - last < service.cooldown_secs.saturating_mul(1000) {
        return Ok(false);
    }
    // 就绪副本（有在线人数观测的）
    let ready: Vec<&McReplica> = replicas
        .iter()
        .filter(|r| r.desired == ReplicaDesired::Running && r.running && r.ready)
        .collect();
    if ready.is_empty() {
        return Ok(false);
    }
    let total: i64 = ready.iter().map(|r| r.players_online).sum();
    let avg = total as f64 / ready.len() as f64;
    let current = replicas.len() as i64;

    let mut desired = current;
    if avg >= service.scale_up_players as f64 && current < service.max_replicas {
        desired = (current + 1).min(service.max_replicas);
    } else if avg <= service.scale_down_players as f64 && current > service.min_replicas {
        desired = (current - 1).max(service.min_replicas);
    }
    if desired == current {
        return Ok(false);
    }
    let mut updated = service.clone();
    updated.desired_replicas = desired;
    db::upsert_service(conn, &updated, now)?;
    db::set_last_scale_ms(conn, &service.id, now)?;
    Ok(true)
}

// ======================== 副本保障 + 调度 ========================

fn ensure_replicas(
    conn: &mut Connection,
    service: &McService,
    replicas: &[McReplica],
    nodes: &[NodeStatus],
    now: i64,
) -> Result<Vec<Action>, String> {
    let mut actions = Vec::new();
    let current = replicas.len() as i64;
    let desired = service.desired_replicas.clamp(service.min_replicas, service.max_replicas);

    // 待调度副本（node_id 为空的占位）→ 尝试重新调度
    for replica in replicas.iter().filter(|r| r.node_id == PENDING_NODE) {
        if let Some(node) = schedule(service, replicas, nodes, replica.index_no) {
            let mut updated = replica.clone();
            updated.node_id = node.clone();
            updated.container_name = container_name(service, replica.index_no);
            db::upsert_replica(conn, &updated, now)?;
            actions.push(create_action(service, &updated, &node));
            actions.push(start_action(service, &updated, &node));
        }
    }

    // 缺失副本 → 创建
    let mut next_index = replicas.iter().map(|r| r.index_no).max().unwrap_or(-1) + 1;
    for _ in current..desired {
        // 迁移中的副本不参与缩容，但新副本正常创建
        let replica = McReplica {
            id: new_id(service),
            service_id: service.id.clone(),
            index_no: next_index,
            node_id: String::new(),
            container_name: container_name(service, next_index),
            host_port: host_port_for(service, next_index),
            ip: bastille_ip_for(service, next_index),
            desired: ReplicaDesired::Running,
            running: false,
            ready: false,
            players_online: 0,
            crash_count: 0,
            crash_loop: false,
            last_attempt_ms: now, // 创建即视为一次启动尝试（避免重复 Start）
            backoff_secs: 0,
            last_observed_ms: 0,
            stable_since_ms: 0,
            created_at_ms: now,
        };
        next_index += 1;
        let node = schedule(service, replicas, nodes, replica.index_no);
        let mut replica = replica;
        if let Some(node_id) = node {
            replica.node_id = node_id.clone();
            db::upsert_replica(conn, &replica, now)?;
            actions.push(create_action(service, &replica, &node_id));
            actions.push(start_action(service, &replica, &node_id));
        } else {
            // 无可用节点：占位保存，下一轮重试调度
            replica.last_attempt_ms = 0; // 未调度不算启动尝试
            db::upsert_replica(conn, &replica, now)?;
            actions.push(Action {
                kind: ActionKind::Noop,
                service_id: service.id.clone(),
                replica_id: replica.id.clone(),
                node_id: String::new(),
                payload: json!({"reason": "unschedulable", "message": "无满足条件的节点（运行时/标签/资源）"}),
                delay_ms: 0,
                migration_id: String::new(),
            });
        }
    }

    // 多余副本 → 销毁（避开进行中迁移的副本）
    if current > desired {
        let excess = current - desired;
        let migrations = db::list_migrations(conn)?;
        let candidates: Vec<&McReplica> = replicas
            .iter()
            .filter(|r| {
                !migrations.iter().any(|m| {
                    m.replica_id == r.id
                        && m.state != MigrationState::Done
                        && m.state != MigrationState::Failed
                })
            })
            .collect();
        let mut indexed: Vec<&&McReplica> = candidates.iter().collect();
        indexed.sort_by_key(|r| -r.index_no);
        for replica in indexed.into_iter().take(excess as usize) {
            db::delete_replica(conn, &replica.id)?;
            actions.push(Action {
                kind: ActionKind::DestroyContainer,
                service_id: service.id.clone(),
                replica_id: replica.id.clone(),
                node_id: replica.node_id.clone(),
                payload: json!({ "force": true }),
                delay_ms: 0,
                migration_id: String::new(),
            });
        }
    }
    Ok(actions)
}

// ======================== 调度器 ========================

/// 为服务新副本选择节点：
/// 1. 可用 + 运行时匹配（docker→linux / bastille→freebsd）
/// 2. 标签亲和全匹配
/// 3. 打分：同服务副本数最少优先（分散容灾），再比可用内存、CPU
fn schedule(
    service: &McService,
    existing: &[McReplica],
    nodes: &[NodeStatus],
    _index: i64,
) -> Option<String> {
    let mut candidates: Vec<&NodeStatus> = nodes
        .iter()
        .filter(|n| n.supports(&service.runtime))
        .filter(|n| {
            service
                .node_selector
                .iter()
                .all(|(k, v)| n.labels.get(k) == Some(v))
        })
        .collect();
    if candidates.is_empty() {
        return None;
    }
    candidates.sort_by(|a, b| {
        let count_a = existing
            .iter()
            .filter(|r| r.node_id == a.id)
            .count();
        let count_b = existing
            .iter()
            .filter(|r| r.node_id == b.id)
            .count();
        count_a
            .cmp(&count_b)
            .then(b.free_mem_mb.cmp(&a.free_mem_mb))
            .then(b.free_cpus.cmp(&a.free_cpus))
    });
    Some(candidates.first()?.id.clone())
}

// ======================== 动作组装 ========================

/// 构造容器 / jail 创建动作（payload 与 ContainerBackend 契约一致）。
fn create_action(service: &McService, replica: &McReplica, node_id: &str) -> Action {
    let mut ports: Vec<String> = Vec::new();
    for spec in &service.ports {
        if let Some((host, container)) = spec.split_once(':') {
            let host_port: i64 = host.trim().parse().unwrap_or(0);
            ports.push(format!("{}:{}", host_port + replica.index_no, container.trim()));
        }
    }
    let mut payload = json!({
        "name": replica.container_name,
        "runtime": service.runtime,
        "image": service.image,
        "command": service.command,
        "ports": ports,
        "volumes": service.volumes,
        "env": service.env,
        "restartPolicy": service.restart_policy,
        "memoryLimitMb": service.memory_limit_mb,
        "cpus": service.cpus,
        "workdir": service.workdir,
    });
    if service.runtime == "bastille" {
        let obj = payload.as_object_mut().expect("payload 对象");
        obj.insert("ip".to_string(), json!(replica.ip));
        obj.insert("jailType".to_string(), json!(service.jail_type));
        obj.insert("vnetMode".to_string(), json!(service.vnet_mode));
    }
    Action {
        kind: ActionKind::CreateContainer,
        service_id: service.id.clone(),
        replica_id: replica.id.clone(),
        node_id: node_id.to_string(),
        payload,
        delay_ms: 0,
        migration_id: String::new(),
    }
}

fn start_action(service: &McService, replica: &McReplica, node_id: &str) -> Action {
    Action {
        kind: ActionKind::StartContainer,
        service_id: service.id.clone(),
        replica_id: replica.id.clone(),
        node_id: node_id.to_string(),
        payload: json!({ "name": replica.container_name }),
        delay_ms: 0,
        migration_id: String::new(),
    }
}

// ======================== 工具 ========================

/// 容器名：xmc-<服务名净化>-<序号>（仅 ASCII 字母数字 _ -，连续 - 折叠）。
pub fn container_name(service: &McService, index: i64) -> String {
    let mut base = String::new();
    let mut last_dash = false;
    for c in service.name.chars() {
        if c.is_ascii_alphanumeric() || c == '_' {
            base.push(c);
            last_dash = false;
        } else if !last_dash {
            base.push('-');
            last_dash = true;
        }
    }
    let trimmed = base.trim_matches('-');
    if trimmed.is_empty() {
        format!("xmc-s{}-r{}", short_id(&service.id), index)
    } else {
        format!("xmc-{}-r{}", trimmed, index)
    }
}

/// 副本 id 单调计数器（同一毫秒内多次创建也保证唯一）。
static ID_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// 副本 id：r-<服务短id>-<时间戳36>-<序列>。
fn new_id(service: &McService) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let seq = ID_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    format!("r-{}-{}-{:x}", short_id(&service.id), now, seq & 0xfffff)
}

fn short_id(id: &str) -> String {
    let mut chars = id.chars();
    let mut out = String::new();
    for _ in 0..6 {
        match chars.next() {
            Some(c) if c.is_ascii_alphanumeric() => out.push(c),
            Some(_) => {}
            None => break,
        }
    }
    if out.is_empty() { "svc".to_string() } else { out }
}

/// 玩家入口宿主端口：第一个端口映射的宿主端口 + 序号。
fn host_port_for(service: &McService, index: i64) -> Option<i64> {
    let spec = service.ports.first()?;
    let host = spec.split(':').next()?.trim();
    host.parse::<i64>().ok().map(|p| p + index)
}

/// Bastille IP：基址末段 + 序号。
fn bastille_ip_for(service: &McService, index: i64) -> Option<String> {
    if service.runtime != "bastille" {
        return None;
    }
    let base = service.bastille_ip_base.as_ref()?;
    let mask = service.bastille_ip_mask.clamp(0, 32);
    // 兼容 "192.168.1.50" 与 "192.168.1.50/24"
    let (addr, mask_override) = match base.split_once('/') {
        Some((a, m)) => (a, m.parse::<u32>().ok()),
        None => (base.as_str(), None),
    };
    let mask = mask_override.unwrap_or(mask);
    let octets: Vec<&str> = addr.split('.').collect();
    if octets.len() != 4 {
        return None;
    }
    let last = octets[3].parse::<u32>().ok()?;
    let bumped = last.checked_add(index as u32)?;
    if bumped > 254 {
        return None;
    }
    Some(format!(
        "{}.{}.{}.{}/{}",
        octets[0], octets[1], octets[2], bumped, mask
    ))
}

/// 当前时间（毫秒）；入参 > 0 时以入参为准（可测试性）。
fn now_ms(input: i64) -> i64 {
    if input > 0 {
        return input;
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// 供其它模块使用的当前时间入口。
pub fn now_ms_exposed(input: i64) -> i64 {
    now_ms(input)
}

// ======================== 迁移入口（状态机见 migration.rs）=====================

/// 发起跨物理机迁移：为副本创建迁移任务并产出第一步动作（停止）。
pub fn migrate_start(
    conn: &mut Connection,
    service_id: &str,
    replica_id: &str,
    to_node: &str,
    now_ms_input: i64,
) -> Result<(MigrationJob, Action), String> {
    crate::migration::migrate_start(conn, service_id, replica_id, to_node, now_ms_input)
}

/// 上报迁移步骤结果，推进状态机并返回下一步动作。
pub fn report_migration(
    conn: &mut Connection,
    job_id: &str,
    ok: bool,
    error: Option<String>,
    now_ms_input: i64,
) -> Result<(MigrationJob, Option<Action>), String> {
    crate::migration::report_migration(conn, job_id, ok, error, now_ms_input)
}

/// 服务规格 → 创建动作 payload 的工具（供 Dart 侧直接预览/复用）。
pub fn create_payload(service: &McService, index: i64) -> Value {
    let dummy = McReplica {
        id: String::new(),
        service_id: service.id.clone(),
        index_no: index,
        node_id: String::new(),
        container_name: container_name(service, index),
        host_port: host_port_for(service, index),
        ip: bastille_ip_for(service, index),
        desired: ReplicaDesired::Running,
        running: false,
        ready: false,
        players_online: 0,
        crash_count: 0,
        crash_loop: false,
        last_attempt_ms: 0,
        backoff_secs: 0,
        last_observed_ms: 0,
        stable_since_ms: 0,
        created_at_ms: 0,
    };
    create_action(service, &dummy, "").payload
}

// ======================== 单元测试 ========================

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_conn() -> Connection {
        let conn = Connection::open_in_memory().expect("内存库");
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS services (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, spec TEXT NOT NULL, created_at INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS replicas (
                id TEXT PRIMARY KEY, service_id TEXT NOT NULL, index_no INTEGER NOT NULL,
                spec TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(service_id, index_no));
             CREATE TABLE IF NOT EXISTS migrations (
                id TEXT PRIMARY KEY, replica_id TEXT NOT NULL, spec TEXT NOT NULL,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS scale_log (
                service_id TEXT PRIMARY KEY, last_scale_ms INTEGER NOT NULL);",
        )
        .expect("建表");
        conn
    }

    fn docker_service() -> McService {
        serde_json::from_value(json!({
            "id": "s1", "name": "survival", "runtime": "docker",
            "image": "itzg/minecraft-server:latest",
            "ports": ["25565:25565"],
            "desiredReplicas": 2, "minReplicas": 1, "maxReplicas": 4,
            "autoscale": false, "targetPlayers": 20,
        }))
        .expect("docker service")
    }

    fn bastille_service() -> McService {
        serde_json::from_value(json!({
            "id": "s2", "name": "bsd-sky", "runtime": "bastille",
            "image": "14.2-RELEASE", "ports": ["25565:25565"],
            "bastilleIpBase": "192.168.1.50", "bastilleIpMask": 24,
            "desiredReplicas": 1, "minReplicas": 0, "maxReplicas": 2,
        }))
        .expect("bastille service")
    }

    fn linux_node() -> NodeStatus {
        serde_json::from_value(json!({
            "id": "n1", "runtime": "docker", "platform": "linux",
            "available": true, "freeMemMb": 8192, "freeCpus": 4
        }))
        .expect("linux node")
    }

    fn bsd_node() -> NodeStatus {
        serde_json::from_value(json!({
            "id": "n2", "runtime": "bastille", "platform": "freebsd",
            "available": true, "freeMemMb": 4096, "freeCpus": 8
        }))
        .expect("bsd node")
    }

    fn setup_service(conn: &Connection, service: &McService) {
        db::upsert_service(conn, service, 1000).expect("upsert");
    }

    fn reconcile_with(conn: &mut Connection, service: &McService, nodes: Vec<NodeStatus>, observed: Vec<ReplicaObserved>, now: i64) -> Vec<Action> {
        // 仅在服务不存在时写入：后续轮次保留引擎对 desired_replicas 的修改
        if db::get_service(conn, &service.id).expect("get service").is_none() {
            setup_service(conn, service);
        }
        reconcile(
            conn,
            &ReconcileInput { nodes, replicas: observed, now_ms: now },
        )
        .expect("reconcile")
    }

    #[test]
    fn container_name_sanitizes() {
        let mut s = docker_service();
        s.name = "My 生存 Server!".to_string();
        assert_eq!(container_name(&s, 2), "xmc-My-Server-r2");
    }

    #[test]
    fn host_port_shifts_by_index() {
        let s = docker_service();
        assert_eq!(host_port_for(&s, 0), Some(25565));
        assert_eq!(host_port_for(&s, 3), Some(25568));
    }

    #[test]
    fn bastille_ip_increments_last_octet() {
        let s = bastille_service();
        assert_eq!(bastille_ip_for(&s, 0), Some("192.168.1.50/24".to_string()));
        assert_eq!(bastille_ip_for(&s, 2), Some("192.168.1.52/24".to_string()));
        // 带掩码基址
        let mut s2 = bastille_service();
        s2.bastille_ip_base = Some("10.0.0.200/16".to_string());
        assert_eq!(bastille_ip_for(&s2, 1), Some("10.0.0.201/16".to_string()));
    }

    #[test]
    fn backoff_grows_exponentially_and_caps() {
        let s = docker_service();
        assert_eq!(backoff_secs(&s, 1), 10);
        assert_eq!(backoff_secs(&s, 2), 20);
        assert_eq!(backoff_secs(&s, 4), 80);
        assert_eq!(backoff_secs(&s, 20), 300);
    }

    #[test]
    fn creates_replicas_on_first_reconcile() {
        let mut conn = test_conn();
        let s = docker_service();
        let actions = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 10_000);
        let creates: Vec<_> = actions.iter().filter(|a| a.kind == ActionKind::CreateContainer).collect();
        assert_eq!(creates.len(), 2, "期望 2 副本 → 2 创建动作");
        assert_eq!(actions.iter().filter(|a| a.kind == ActionKind::StartContainer).count(), 2);
        // 端口顺延
        let ports = &creates[0].payload["ports"];
        let first_port = ports[0].as_str().unwrap();
        assert!(first_port.starts_with("25565:") || first_port.starts_with("25566:"));
        // 副本落库
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        assert_eq!(replicas.len(), 2);
        assert!(replicas.iter().all(|r| r.node_id == "n1"));
    }

    #[test]
    fn schedules_bastille_to_freebsd_node_only() {
        let mut conn = test_conn();
        let s = bastille_service();
        let actions = reconcile_with(&mut conn, &s, vec![linux_node(), bsd_node()], vec![], 10_000);
        let creates: Vec<_> = actions.iter().filter(|a| a.kind == ActionKind::CreateContainer).collect();
        assert_eq!(creates.len(), 1);
        assert_eq!(creates[0].node_id, "n2");
        assert_eq!(creates[0].payload["ip"], json!("192.168.1.50/24"));
        assert_eq!(creates[0].payload["runtime"], json!("bastille"));
    }

    #[test]
    fn unschedulable_when_no_matching_node() {
        let mut conn = test_conn();
        let s = docker_service();
        let actions = reconcile_with(&mut conn, &s, vec![bsd_node()], vec![], 10_000);
        assert!(actions.iter().all(|a| a.kind != ActionKind::CreateContainer));
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        assert_eq!(replicas.len(), 2);
        assert!(replicas.iter().all(|r| r.node_id.is_empty()), "无匹配节点 → 待调度");
    }

    #[test]
    fn crash_healing_restarts_with_backoff() {
        let mut conn = test_conn();
        let s = docker_service();
        // 第一轮：创建并启动
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 10_000);
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        // 观测为运行
        let observed: Vec<ReplicaObserved> = replicas
            .iter()
            .map(|r| ReplicaObserved { id: r.id.clone(), running: true, players: Some(5) })
            .collect();
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], observed, 20_000);
        // 崩溃：转 down
        let observed: Vec<ReplicaObserved> = replicas
            .iter()
            .map(|r| ReplicaObserved { id: r.id.clone(), running: false, players: None })
            .collect();
        let actions = reconcile_with(&mut conn, &s, vec![linux_node()], observed, 30_000);
        let restarts: Vec<_> = actions.iter().filter(|a| a.kind == ActionKind::RestartContainer).collect();
        assert_eq!(restarts.len(), 2, "两副本均崩溃 → 重启动作");
        assert!(restarts.iter().all(|a| a.delay_ms > 0));
        // 退避窗口内不重复下发
        let actions2 = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 31_000);
        assert!(actions2.iter().all(|a| a.kind != ActionKind::RestartContainer));
        // 退避结束后重试
        let actions3 = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 60_000);
        assert_eq!(actions3.iter().filter(|a| a.kind == ActionKind::RestartContainer).count(), 2);
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        assert!(replicas.iter().all(|r| r.crash_count >= 1));
    }

    #[test]
    fn crash_loop_flag_after_threshold() {
        let mut conn = test_conn();
        let mut s = docker_service();
        s.desired_replicas = 1;
        s.crash_threshold = 3;
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 1_000);
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        let rid = replicas[0].id.clone();
        let mut now = 10_000i64;
        for _ in 0..4 {
            // 观测运行 → 转 down
            let _ = reconcile_with(&mut conn, &s, vec![linux_node()],
                vec![ReplicaObserved { id: rid.clone(), running: true, players: Some(1) }], now);
            now += 1000;
            let _ = reconcile_with(&mut conn, &s, vec![linux_node()],
                vec![ReplicaObserved { id: rid.clone(), running: false, players: None }], now);
            now += 30_000; // 越过退避
        }
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        assert!(replicas[0].crash_loop, "超过阈值 → CrashLoopBackOff");
        assert!(replicas[0].crash_count >= 3);
    }

    #[test]
    fn autoscale_up_and_down_with_cooldown() {
        let mut conn = test_conn();
        let mut s = docker_service();
        s.desired_replicas = 1;
        s.autoscale = true;
        s.scale_up_players = 20;
        s.scale_down_players = 10;
        s.cooldown_secs = 300;
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 1_000);
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        let rid = replicas[0].id.clone();
        // 在线 30 → 扩容到 2
        let actions = reconcile_with(&mut conn, &s, vec![linux_node()],
            vec![ReplicaObserved { id: rid.clone(), running: true, players: Some(30) }], 10_000);
        assert!(actions.iter().any(|a| a.kind == ActionKind::CreateContainer), "应扩容");
        let services = db::list_services(&conn).expect("services");
        assert_eq!(services[0].desired_replicas, 2);
        // 冷却窗口内不再扩
        let actions2 = reconcile_with(&mut conn, &s, vec![linux_node()],
            vec![ReplicaObserved { id: rid.clone(), running: true, players: Some(30) }], 20_000);
        assert!(!actions2.iter().any(|a| a.kind == ActionKind::CreateContainer), "冷却期内不扩容");
        // 冷却后在线 3 → 缩容（副本实际 2 → desired 1 但当前实际 2 需销毁 1 个）
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        let observed: Vec<ReplicaObserved> = replicas.iter().map(|r| ReplicaObserved {
            id: r.id.clone(), running: true, players: Some(3),
        }).collect();
        let actions3 = reconcile_with(&mut conn, &s, vec![linux_node()], observed, 400_000);
        assert!(actions3.iter().any(|a| a.kind == ActionKind::DestroyContainer), "应缩容销毁");
    }

    #[test]
    fn node_selector_respected() {
        let mut conn = test_conn();
        let mut s = docker_service();
        s.desired_replicas = 1;
        s.node_selector.insert("zone".to_string(), "east".to_string());
        let mut n = linux_node();
        n.labels.insert("zone".to_string(), "west".to_string());
        let mut n2 = linux_node();
        n2.id = "n3".to_string();
        n2.labels.insert("zone".to_string(), "east".to_string());
        let actions = reconcile_with(&mut conn, &s, vec![n, n2], vec![], 1_000);
        let creates: Vec<_> = actions.iter().filter(|a| a.kind == ActionKind::CreateContainer).collect();
        assert_eq!(creates.len(), 1);
        assert_eq!(creates[0].node_id, "n3");
    }

    #[test]
    fn status_aggregates_players() {
        let mut conn = test_conn();
        let s = docker_service();
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], vec![], 1_000);
        let replicas = db::list_replicas(&conn, Some("s1")).expect("replicas");
        let observed: Vec<ReplicaObserved> = replicas.iter().map(|r| ReplicaObserved {
            id: r.id.clone(), running: true, players: Some(8),
        }).collect();
        let _ = reconcile_with(&mut conn, &s, vec![linux_node()], observed, 10_000);
        let status = status(&conn, Some("s1")).expect("status");
        assert_eq!(status.len(), 1);
        assert_eq!(status[0].total_players, 16);
        assert_eq!(status[0].running_replicas, 2);
    }
}

