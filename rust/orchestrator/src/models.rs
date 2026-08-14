//! 编排引擎数据模型
//!
//! K8s 风格映射：
//! - `McService`  ≈ Deployment/StatefulSet（期望状态：副本数、镜像、弹性阈值、自愈策略）
//! - `McReplica`  ≈ Pod（有状态副本：序号、部署节点、容器名、观测状态、崩溃计数）
//! - `MigrationJob` ≈ 跨物理机迁移存档的工作流状态机
//! - `Action`      ≈ 引擎对账后产出、由 Dart 执行层落地的原子操作
//! - `NodeStatus`  ≈ 节点资源快照（调度器输入）

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ======================== 服务（Deployment） ========================

/// MC 服务器服务组（期望状态）。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McService {
    /// 服务唯一 id。
    pub id: String,
    /// 显示名称。
    pub name: String,
    /// 运行时：docker | bastille。
    pub runtime: String,
    /// 镜像 / 发行版（如 itzg/minecraft-server:latest、14.2-RELEASE）。
    pub image: String,
    /// 启动命令（可选）。
    #[serde(default)]
    pub command: Option<String>,
    /// 端口映射，如 ["25565:25565"]；扩容时宿主端口按副本序号顺延。
    #[serde(default)]
    pub ports: Vec<String>,
    /// 数据目录挂载 "宿主机:容器内"（实例根目录）。
    #[serde(default)]
    pub volumes: Vec<String>,
    /// 环境变量。
    #[serde(default)]
    pub env: HashMap<String, String>,
    /// 重启策略（Docker）。
    #[serde(default)]
    pub restart_policy: Option<String>,
    /// 内存上限（MB）。
    #[serde(default)]
    pub memory_limit_mb: Option<i64>,
    /// CPU 核数。
    #[serde(default)]
    pub cpus: Option<i64>,
    /// 工作目录（数据目录挂载后强制）。
    #[serde(default)]
    pub workdir: Option<String>,
    /// 世界存档目录（容器内相对路径，迁移对象），默认 /data/world。
    #[serde(default = "default_world_dir")]
    pub world_dir: String,
    /// Bastille：jail 类型（thin/thick/clone/empty/linux）。
    #[serde(default)]
    pub jail_type: Option<String>,
    /// Bastille：VNET 模式（none/vnet/bridge）。
    #[serde(default)]
    pub vnet_mode: Option<String>,
    /// Bastille：IP 基址（如 192.168.1.50），副本按序号顺延（.51、.52…）。
    #[serde(default)]
    pub bastille_ip_base: Option<String>,
    /// Bastille：子网掩码长度（默认 24）。
    #[serde(default = "default_ip_mask")]
    pub bastille_ip_mask: u32,

    // ---- 弹性扩缩容 ----
    /// 期望副本数（手动设定；autoscale 开启时由引擎覆盖）。
    #[serde(default)]
    pub desired_replicas: i64,
    /// 最小副本数。
    #[serde(default)]
    pub min_replicas: i64,
    /// 最大副本数。
    #[serde(default)]
    pub max_replicas: i64,
    /// 是否按在线人数自动扩缩容。
    #[serde(default)]
    pub autoscale: bool,
    /// 每个副本的目标在线人数。
    #[serde(default = "default_target_players")]
    pub target_players: i64,
    /// 单副本在线达到此值 → 扩容（默认 = target_players）。
    #[serde(default = "default_scale_up")]
    pub scale_up_players: i64,
    /// 副本平均在线低于此值 → 缩容（默认 = target_players / 2）。
    #[serde(default = "default_scale_down")]
    pub scale_down_players: i64,
    /// 扩缩容冷却时间（秒）。
    #[serde(default = "default_cooldown")]
    pub cooldown_secs: i64,

    // ---- 自愈 ----
    /// 是否自动修复崩溃（重启容器）。
    #[serde(default = "default_true")]
    pub auto_heal: bool,
    /// 进入 CrashLoopBackOff 的崩溃次数阈值。
    #[serde(default = "default_crash_threshold")]
    pub crash_threshold: i64,
    /// 重启退避基数（秒），指数增长。
    #[serde(default = "default_backoff")]
    pub backoff_base_secs: i64,
    /// 重启退避上限（秒）。
    #[serde(default = "default_max_backoff")]
    pub max_backoff_secs: i64,

    // ---- 调度 ----
    /// 节点标签选择器（kv 全匹配，可选）。
    #[serde(default)]
    pub node_selector: HashMap<String, String>,

    /// 创建时间（毫秒时间戳）。
    #[serde(default)]
    pub created_at_ms: i64,
}

fn default_world_dir() -> String {
    "/data/world".to_string()
}
fn default_ip_mask() -> u32 {
    24
}
fn default_target_players() -> i64 {
    20
}
fn default_scale_up() -> i64 {
    20
}
fn default_scale_down() -> i64 {
    10
}
fn default_cooldown() -> i64 {
    300
}
fn default_true() -> bool {
    true
}
fn default_crash_threshold() -> i64 {
    5
}
fn default_backoff() -> i64 {
    5
}
fn default_max_backoff() -> i64 {
    300
}

impl McService {
    /// 校验服务规格，返回错误描述；合法返回 None。
    pub fn validate(&self) -> Option<String> {
        if self.id.trim().is_empty() || self.name.trim().is_empty() {
            return Some("服务 id 与名称不能为空".to_string());
        }
        if self.runtime != "docker" && self.runtime != "bastille" {
            return Some(format!("未知运行时: {}（docker | bastille）", self.runtime));
        }
        if self.image.trim().is_empty() {
            return Some("镜像 / 发行版不能为空".to_string());
        }
        if self.desired_replicas < 0
            || self.min_replicas < 0
            || self.max_replicas < self.min_replicas
        {
            return Some("副本数配置非法（0 <= min <= max）".to_string());
        }
        if self.target_players < 1 || self.scale_down_players < 0 {
            return Some("在线人数阈值必须为正".to_string());
        }
        if self.backoff_base_secs < 1 || self.max_backoff_secs < self.backoff_base_secs {
            return Some("重启退避配置非法".to_string());
        }
        if self.runtime == "bastille" && self.bastille_ip_base.is_none() {
            return Some("Bastille 服务必须指定 IP 基址（bastilleIpBase）".to_string());
        }
        None
    }
}

// ======================== 副本（Pod） ========================

/// 副本期望状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ReplicaDesired {
    Running,
    Stopped,
}

impl Default for ReplicaDesired {
    fn default() -> Self {
        ReplicaDesired::Running
    }
}

/// MC 服务器副本（一个容器 / jail 实例）。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McReplica {
    /// 副本唯一 id。
    pub id: String,
    /// 所属服务 id。
    pub service_id: String,
    /// 有状态序号（0 起，用于 IP / 端口顺延）。
    pub index_no: i64,
    /// 部署节点 id。
    pub node_id: String,
    /// 容器 / jail 名。
    pub container_name: String,
    /// 玩家入口：第一个端口映射的宿主端口（可空）。
    #[serde(default)]
    pub host_port: Option<i64>,
    /// Bastille 分配的 IP（含掩码）。
    #[serde(default)]
    pub ip: Option<String>,
    /// 期望状态。
    #[serde(default)]
    pub desired: ReplicaDesired,
    /// 最近观测：容器是否运行。
    #[serde(default)]
    pub running: bool,
    /// 是否就绪（可承接玩家）。
    #[serde(default)]
    pub ready: bool,
    /// 最近观测在线人数。
    #[serde(default)]
    pub players_online: i64,
    /// 崩溃计数（稳定运行后清零）。
    #[serde(default)]
    pub crash_count: i64,
    /// 是否处于 CrashLoopBackOff。
    #[serde(default)]
    pub crash_loop: bool,
    /// 上次尝试启动的时间戳（毫秒）。
    #[serde(default)]
    pub last_attempt_ms: i64,
    /// 当前退避间隔（秒）。
    #[serde(default)]
    pub backoff_secs: i64,
    /// 最近观测时间戳（毫秒）。
    #[serde(default)]
    pub last_observed_ms: i64,
    /// 连续稳定运行起始时间戳（毫秒）；达到稳定窗口后清零崩溃状态。
    #[serde(default)]
    pub stable_since_ms: i64,
    /// 创建时间戳（毫秒）。
    #[serde(default)]
    pub created_at_ms: i64,
}

// ======================== 节点（调度输入） ========================

/// 节点资源快照（Dart 侧采集后传入）。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NodeStatus {
    /// 节点 id。
    pub id: String,
    /// 已知运行时（docker | bastille，可为空）。
    #[serde(default)]
    pub runtime: Option<String>,
    /// 平台（linux | freebsd | ...）。
    #[serde(default)]
    pub platform: Option<String>,
    /// 节点是否可用。
    #[serde(default)]
    pub available: bool,
    /// 可用内存（MB）。
    #[serde(default)]
    pub free_mem_mb: i64,
    /// 可用 CPU 核数。
    #[serde(default)]
    pub free_cpus: i64,
    /// 标签（调度亲和）。
    #[serde(default)]
    pub labels: HashMap<String, String>,
}

impl NodeStatus {
    /// 节点能否承载指定运行时的服务。
    pub fn supports(&self, runtime: &str) -> bool {
        if !self.available {
            return false;
        }
        if let Some(r) = &self.runtime {
            return r == runtime;
        }
        match self.platform.as_deref().map(|p| p.to_lowercase()) {
            Some(p) => match runtime {
                "bastille" => p == "freebsd",
                "docker" => p == "linux",
                _ => false,
            },
            None => true, // 未知平台：允许尝试，由后端探测兜底
        }
    }
}

// ======================== 迁移任务 ========================

/// 迁移状态机状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MigrationState {
    /// 等待开始（首个动作为停止副本）。
    Pending,
    /// 已下发停止副本。
    Stopping,
    /// 等待目标节点压缩存档完成。
    Archiving,
    /// 等待存档传输（下载 + 上传）。
    Transferring,
    /// 等待目标节点解压存档。
    Restoring,
    /// 等待目标节点创建容器 / jail。
    Creating,
    /// 等待目标节点启动。
    Starting,
    /// 迁移完成。
    Done,
    /// 迁移失败。
    Failed,
}

impl Default for MigrationState {
    fn default() -> Self {
        MigrationState::Pending
    }
}

impl MigrationState {
    /// 下一状态（推进状态机）。
    fn next_state(&self) -> Option<MigrationState> {
        match self {
            MigrationState::Pending => Some(MigrationState::Stopping),
            MigrationState::Stopping => Some(MigrationState::Archiving),
            MigrationState::Archiving => Some(MigrationState::Transferring),
            MigrationState::Transferring => Some(MigrationState::Restoring),
            MigrationState::Restoring => Some(MigrationState::Creating),
            MigrationState::Creating => Some(MigrationState::Starting),
            MigrationState::Starting => Some(MigrationState::Done),
            MigrationState::Done | MigrationState::Failed => None,
        }
    }
}

/// 跨物理机迁移存档任务。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MigrationJob {
    pub id: String,
    pub service_id: String,
    pub replica_id: String,
    /// 源节点。
    pub from_node: String,
    /// 目标节点。
    pub to_node: String,
    /// 当前状态。
    #[serde(default)]
    pub state: MigrationState,
    /// 失败原因。
    #[serde(default)]
    pub error: Option<String>,
    /// 存档文件名（节点文件系统内，如 world_s1_r0.zip）。
    #[serde(default)]
    pub archive_name: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl MigrationJob {
    /// 推进状态机到下一状态。
    pub fn advance(&mut self) {
        if let Some(next) = self.state.next_state() {
            self.state = next;
        }
    }
}

// ======================== 对账动作 ========================

/// 动作类型（引擎产出 → Dart 执行层落地）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionKind {
    /// 在指定节点创建容器 / jail。
    CreateContainer,
    /// 启动容器 / jail。
    StartContainer,
    /// 重启（自愈；delayMs 为退避等待）。
    RestartContainer,
    /// 优雅停止。
    StopContainer,
    /// 摧毁（缩容 / 删除服务）。
    DestroyContainer,
    /// 在节点压缩世界存档。
    ArchiveWorld,
    /// 传输存档（下载源节点 + 上传目标节点）。
    TransferArchive,
    /// 在节点解压恢复存档。
    RestoreArchive,
    /// 探测 MC 服务器（在线人数 / 存活）。
    Ping,
    /// 等待（占位，无操作）。
    Noop,
}

/// 对账动作。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Action {
    pub kind: ActionKind,
    /// 关联服务 id。
    #[serde(default)]
    pub service_id: String,
    /// 关联副本 id（可空）。
    #[serde(default)]
    pub replica_id: String,
    /// 执行动作的节点 id。
    #[serde(default)]
    pub node_id: String,
    /// 动作参数（容器规格 / 退避延时 / 存档名等）。
    #[serde(default)]
    pub payload: serde_json::Value,
    /// 延迟执行毫秒数（退避自愈）。
    #[serde(default)]
    pub delay_ms: i64,
    /// 迁移任务 id（迁移类动作）。
    #[serde(default)]
    pub migration_id: String,
}

// ======================== 观测输入 ========================

/// 单副本观测（Dart 采集后传入 reconcile）。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ReplicaObserved {
    pub id: String,
    /// 容器是否运行。
    #[serde(default)]
    pub running: bool,
    /// 在线人数（无法获取时为 None）。
    #[serde(default)]
    pub players: Option<i64>,
}

/// reconcile 输入。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ReconcileInput {
    /// 节点资源快照。
    #[serde(default)]
    pub nodes: Vec<NodeStatus>,
    /// 副本观测。
    #[serde(default)]
    pub replicas: Vec<ReplicaObserved>,
    /// 当前时间戳（毫秒，缺省用本机时钟）。
    #[serde(default)]
    pub now_ms: i64,
}

// ======================== 状态快照（UI 用） ========================

/// 服务 + 副本的聚合状态。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServiceStatus {
    #[serde(flatten)]
    pub service: McService,
    pub replicas: Vec<McReplica>,
    /// 在线副本数。
    pub running_replicas: i64,
    /// 在线人数合计。
    pub total_players: i64,
    /// 平均在线（就绪副本）。
    pub avg_players: f64,
    /// 是否有进行中的迁移。
    pub migrating: bool,
}
