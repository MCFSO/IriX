# 编排系统设计：K8s 风格的 MC 服务器编排（Docker + Bastille）

> 目标：用 K8s 管理微服务的思路编排 Minecraft 服务器，运行时为 Docker 或 Bastille，
> 提供**崩溃自动修复、按在线人数弹性开服、跨物理机迁移存档**三大能力。
> 控制平面核心（对账 / 弹性 / 调度 / 迁移状态机）用 **Rust** 实现（`xmc_orchestrator` crate），
> Dart 层负责观测采集与动作落地。客户端本身不支持 FreeBSD，Bastille 全部经远程节点 API。

---

## 1. 架构总览

```
┌────────────────────────── IriX 桌面客户端（控制平面宿主）──────────────────────────┐
│                                                                                    │
│  ClusterOrchestrationScreen（编排页：服务/副本/迁移状态 + 期望状态编辑）             │
│        │                                                                           │
│  OrchestratorService（Dart 执行层，10s 对账循环）                                    │
│     ├─ 观测采集：节点资源快照（ClusterState）· 容器运行状态（ContainerBackend）       │
│     │             · MC 在线人数（Rust Server List Ping）                            │
│     ├─ 送入引擎：orchestrator_request("reconcile", observed) → actions              │
│     └─ 动作落地：容器生命周期（NodeApiClient/ContainerBackend）                     │
│                    · 迁移执行（节点级归档 压缩→传输→恢复）                            │
│        │                                                                           │
│  OrchestratorFfi（后台 isolate）── FFI ──► xmc_orchestrator.dll/.so/.dylib（Rust）  │
│     · McService/McReplica/MigrationJob 状态（SQLite）                               │
│     · reconcile：自愈 / 弹性 / 调度 / 副本保障                                      │
│     · 迁移状态机：Stopping→Archiving→Transferring→Restoring→Creating→Starting→Done │
│     · mc_ping：Minecraft Server List Ping（std::net，在线人数数据源）               │
└────────────────────────────────────────────────────────────────────────────────────┘
        │ HTTP（NodeApiClient → Rust http_client）
        ▼
┌───────────────────────────── 节点（Linux：Docker / FreeBSD：Bastille）─────────────┐
│  irix-node 守护进程：/api/container/* · /api/bastille/* · /api/container/archive/* │
└────────────────────────────────────────────────────────────────────────────────────┘
```

K8s 概念映射：

| K8s | 编排系统 | 说明 |
|-----|---------|------|
| Deployment/StatefulSet | `McService` | 期望副本数、镜像/发行版、弹性阈值、自愈策略、节点亲和 |
| Pod | `McReplica` | 有状态序号（IP/端口顺延）、部署节点、崩溃计数、稳定窗口 |
| Controller 对账循环 | `reconcile(observed) → actions` | 观测 → diff → 动作（Dart 落地） |
| Liveness/Readiness | MC Server List Ping | 存活 + 在线人数（弹性数据源） |
| Horizontal scaling | 按在线人数扩缩容 | 冷却窗口 + min/max 边界 |
| CrashLoopBackOff | 崩溃指数退避 | 稳定 60s 自动恢复 |
| Scheduler | Rust 调度器 | 运行时匹配 + 标签亲和 + 分散 + 资源打分 |
| PV 迁移 | 存档迁移状态机 | 压缩 → 传输 → 恢复 → 重建 |

---

## 2. Rust 引擎（rust/orchestrator）

### 2.1 模块

- `models.rs` — 服务 / 副本 / 节点 / 迁移任务 / 动作模型（serde camelCase）
- `db.rs` — SQLite 持久化（services / replicas / migrations / scale_log）
- `engine.rs` — 对账核心：观测应用、崩溃自愈、弹性决策、副本保障、调度器
- `migration.rs` — 跨物理机迁移状态机
- `mcping.rs` — Minecraft Server List Ping（纯 std::net，VarInt 手写）
- `lib.rs` — FFI 入口 `orchestrator_request(args_json, op)` + `orchestrator_free_string`

### 2.2 崩溃自动修复

- 观测转换 **running → down**（期望运行）即计 1 次崩溃；
- 重启退避指数增长：`backoff = min(base × 2^crash, max)`（默认 5s 起、300s 封顶）；
- 崩溃次数 ≥ `crashThreshold` → 副本进入 **CrashLoopBackOff**（UI 红色标记）；
- 连续稳定运行 60s → 崩溃计数清零（退出 BackOff）。

### 2.3 按在线人数弹性开服

- 就绪副本（运行且有玩家观测）平均在线人数：
  - `avg ≥ scaleUpPlayers` → 期望副本 +1（不超 `maxReplicas`）
  - `avg ≤ scaleDownPlayers` → 期望副本 −1（不低于 `minReplicas`）
- 扩缩容冷却窗口（默认 300s）防抖；首次决策不受冷却限制；
- 扩容副本端口/IP 按序号顺延（`25565→25566`、`192.168.1.50→.51`）。

### 2.4 跨物理机迁移存档

状态机（每步由 Dart 执行并回报，失败停留当前步可重试，可取消）：

```
Stopping → Archiving → Transferring → Restoring → Creating → Starting → Done
```

- 完成时副本归属切到目标节点、崩溃状态清零；
- 存档对象为 `worldDir`（容器内路径，宿主路径由服务 volumes 推导）。

### 2.5 调度器

节点选择：可用 ∧ 运行时匹配（docker→linux / bastille→freebsd）∧ 标签亲和全匹配，
打分优先级：同服务副本数最少（分散容灾）→ 可用内存 → 可用 CPU。
无满足条件的节点 → 副本以「待调度」占位，下一轮重试。

### 2.6 FFI 操作表

| op | 说明 |
|----|------|
| `init` | 初始化 SQLite 表结构（dbPath 参数） |
| `upsert_service` / `delete_service` / `list_services` / `get_service` | 服务 CRUD（delete 返回销毁动作） |
| `reconcile` | 对账：`{observed: {nodes, replicas, nowMs?}}` → `{actions: [...]}` |
| `observe` | 仅记录观测（副本状态 + 玩家数） |
| `status` | 服务 + 副本聚合快照（UI） |
| `migrate_start` / `report_migration` / `migrate_cancel` / `list_migrations` | 迁移状态机 |
| `mc_ping` | MC 状态探测（host/port/timeoutMs） |
| `reset` | 清空数据 |

返回信封：`{"ok":true,"result":...}` / `{"ok":false,"error":"..."}`。

---

## 3. Dart 执行层（lib/services/orchestrator_service.dart）

- `OrchestratorFfi`（lib/services/orchestrator_ffi.dart）：后台 isolate FFI 封装；
- `OrchestratorService`：单例，`attach(NodeState, ClusterState)` + `startTicking(10s)`；
  - 每轮：采集观测（节点快照 + 容器列表 + MC ping）→ `reconcile` → 顺序执行动作；
  - 动作映射：
    | 动作 | 落地 |
    |------|------|
    | create_container | `ContainerBackend.createContainer`（payload 即 CreateContainerRequest 契约） |
    | start/stop/restart/destroy | 对应后端生命周期方法 |
    | archive_world / restore_archive | 节点级归档端点（`/api/container/archive*`） |
    | transfer_archive | 源节点下载字节 → 目标节点上传（桌面中继） |
    | ping | `mc_ping` 结果经 `observe` 回写 |
- 迁移执行：`migrate_start` → `runMigrationStep` 逐步推进至 Done/Failed；
- 状态持久化在 Rust 侧 SQLite（应用文档目录 `xmc_orchestrator.db`）。

---

## 4. UI（lib/screens/cluster_orchestration_screen.dart）

多机模式导航「编排」页：

- **服务卡片（Deployment 视图）**：名称 + 运行时徽章、`当前/期望 副本`、
  在线人数合计与均值、自动修复/弹性开服开关、手动扩缩容按钮、
  迁移菜单（选副本 + 目标节点）、删除服务；
- **副本块（Pod 视图）**：序号/节点、容器名、在线人数、崩溃计数、
  CrashLoopBackOff 红色标记、玩家入口端口、待调度提示；
- **迁移任务列表**：状态标签（中文）、错误、继续执行 / 取消；
- **新建服务对话框**：运行时（Docker/Bastille）、镜像/发行版、端口、
  数据目录挂载、世界存档目录、min/desired/max 副本、弹性阈值、
  Bastille IP 基址；顶部「立即对账」按钮 + 最近错误提示。

---

## 5. 边界与回退

- 引擎为纯计算（无网络 I/O），决策可单测（15 个 Rust 测试 + Dart 模型测试）；
- 节点离线 → 副本观测为 down，引擎按崩溃流程退避重启（节点恢复后自然拉起）；
- MCSM 节点受限模式不提供节点级归档端点 → 迁移类动作失败并在 UI 展示原因；
- 玩家数采集失败（如服务器 mod 屏蔽 ping）→ 该副本无玩家观测，不参与弹性决策，
  弹性开服建议配合 irix-node 的在线人数上报（后续增强）。
