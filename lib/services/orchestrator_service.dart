// 编排执行层（K8s 控制循环的观测采集与动作落地）
//
// 分工：
// - Rust xmc_orchestrator：纯计算控制平面（对账决策 / 弹性 / 调度 / 迁移状态机）
// - 本服务（Dart）：采集观测（节点快照、容器状态、MC 在线人数）→ 送入引擎对账
//   → 执行引擎产出的动作（容器生命周期 / 存档迁移的压缩、传输、恢复）
//
// 运行时为 Docker / Bastille，全部经 NodeApiClient + ContainerBackend 落到
// 远程节点（客户端本身不支持 FreeBSD）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/node.dart';
import '../models/orchestration.dart';
import '../models/remote.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import 'container/container_backend.dart';
import 'container/node_container_backend.dart';
import 'node_api_client.dart';
import 'orchestrator_ffi.dart';

/// 编排服务（单例，与 ClusterMonitor 同风格：attach 后 startTicking）。
class OrchestratorService {
  OrchestratorService._();

  static final OrchestratorService instance = OrchestratorService._();

  /// 节点状态（客户端列表 + API 客户端）。
  NodeState? nodeState;

  /// 集群资源快照（调度器输入）。
  ClusterState? clusterState;

  /// 引擎 SQLite 路径（首次使用时解析到应用文档目录）。
  String? dbPath;

  /// 节点 overview 缓存（平台 / 守护进程）。
  final Map<String, OverviewData> _overviews = {};

  /// 对账循环定时器。
  Timer? _timer;

  /// 对账是否进行中（防重入）。
  bool _ticking = false;

  /// 是否已初始化（SQLite 表结构）。
  bool _initialized = false;

  /// 最近一次对账错误（UI 展示）。
  String? lastError;

  /// 最近一轮动作摘要（UI 展示）。
  final List<String> lastActions = [];

  // ======================== 生命周期 ========================

  /// 注入依赖。
  void attach({
    required NodeState nodeState,
    required ClusterState clusterState,
  }) {
    this.nodeState = nodeState;
    this.clusterState = clusterState;
  }

  /// 启动周期对账（默认每 10 秒一轮）。
  void startTicking({Duration interval = const Duration(seconds: 10)}) {
    _timer ??= Timer.periodic(interval, (_) {
      unawaited(tick());
    });
    unawaited(tick());
  }

  void stopTicking() {
    _timer?.cancel();
    _timer = null;
  }

  /// 解析引擎数据库路径（应用文档目录 / xmc_orchestrator.db）。
  Future<String> resolveDbPath() async {
    if (dbPath != null && dbPath!.isNotEmpty) return dbPath!;
    final dir = await getApplicationDocumentsDirectory();
    dbPath = p.join(dir.path, 'xmc_orchestrator.db');
    return dbPath!;
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await OrchestratorFfi.instance.request(
      op: 'init',
      args: {'dbPath': await resolveDbPath()},
    );
    _initialized = true;
  }

  // ======================== 引擎 CRUD ========================

  Future<List<McService>> listServices() async {
    await _ensureInit();
    final result = await OrchestratorFfi.instance.request(
      op: 'list_services',
      args: {'dbPath': dbPath},
    );
    return (result as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(McService.fromJson)
        .toList();
  }

  /// 创建 / 更新服务（期望状态）。
  Future<McService> upsertService(McService service) async {
    await _ensureInit();
    final result = await OrchestratorFfi.instance.request(
      op: 'upsert_service',
      args: {'dbPath': dbPath, 'service': service.toJson()},
    );
    return McService.fromJson((result as Map<String, dynamic>?) ?? {});
  }

  /// 删除服务，返回需要执行的销毁动作。
  Future<List<OrchestrationAction>> deleteService(String id) async {
    await _ensureInit();
    final result =
        await OrchestratorFfi.instance.request(
              op: 'delete_service',
              args: {'dbPath': dbPath, 'id': id},
            )
            as Map<String, dynamic>?;
    final actions = (result?['actions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(OrchestrationAction.fromJson)
        .toList();
    await executeActions(actions);
    return actions;
  }

  /// 服务 + 副本聚合状态。
  Future<List<ServiceStatus>> status({String? serviceId}) async {
    await _ensureInit();
    final result = await OrchestratorFfi.instance.request(
      op: 'status',
      args: {'dbPath': dbPath, 'serviceId': ?serviceId},
    );
    return (result as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceStatus.fromJson)
        .toList();
  }

  Future<List<MigrationJob>> listMigrations() async {
    await _ensureInit();
    final result = await OrchestratorFfi.instance.request(
      op: 'list_migrations',
      args: {'dbPath': dbPath},
    );
    return (result as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MigrationJob.fromJson)
        .toList();
  }

  /// MC Server List Ping（在线人数 / 存活，Rust 实现）。
  Future<McStatus> mcPing(String host, int port) async {
    final result = await OrchestratorFfi.instance.request(
      op: 'mc_ping',
      args: {'host': host, 'port': port, 'timeoutMs': 3000},
    );
    return McStatus.fromJson((result as Map<String, dynamic>?) ?? {});
  }

  // ======================== 对账循环 ========================

  /// 一轮对账：采集观测 → 引擎决策 → 执行动作 → 采集玩家数。
  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _ensureInit();
      final observed = await _collectContainerObservations();
      final nodes = _collectNodeSnapshots();

      final result =
          await OrchestratorFfi.instance.request(
                op: 'reconcile',
                args: {
                  'dbPath': dbPath,
                  'observed': {'nodes': nodes, 'replicas': observed},
                },
              )
              as Map<String, dynamic>?;
      final actions = (result?['actions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(OrchestrationAction.fromJson)
          .toList();
      lastActions
        ..clear()
        ..addAll(actions.map((a) => a.kind.name).take(20));
      await executeActions(actions);
      await _collectPlayerCounts();
      lastError = null;
    } on OrchestratorFfiException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = e.toString();
    } finally {
      _ticking = false;
    }
  }

  /// 采集副本容器运行状态（按节点容器列表匹配容器名）。
  Future<List<Map<String, dynamic>>> _collectContainerObservations() async {
    final out = <Map<String, dynamic>>[];
    final nodes = nodeState?.nodes ?? const <NodeInfo>[];
    final statuses = await status();
    for (final s in statuses) {
      for (final replica in s.replicas) {
        if (replica.nodeId.isEmpty) continue;
        final node = nodes.where((n) => n.id == replica.nodeId).firstOrNull;
        if (node == null || !nodeState!.isOnline(node.id)) {
          out.add({'id': replica.id, 'running': false});
          continue;
        }
        try {
          final backend = await _backendFor(node);
          final containers = await backend.listContainers();
          final info = containers
              .where((c) => c.name == replica.containerName)
              .firstOrNull;
          out.add({'id': replica.id, 'running': info?.isRunning ?? false});
        } catch (_) {
          out.add({'id': replica.id, 'running': false});
        }
      }
    }
    return out;
  }

  /// 节点资源快照（调度器输入）。
  List<Map<String, dynamic>> _collectNodeSnapshots() {
    final nodes = nodeState?.nodes ?? const <NodeInfo>[];
    final out = <Map<String, dynamic>>[];
    for (final node in nodes) {
      final sys = clusterState?.resourceSnapshot[node.id];
      final overview = _overviews[node.id];
      final platform = overview?.system.platform ?? '';
      out.add({
        'id': node.id,
        'runtime': switch (platform.toLowerCase()) {
          'freebsd' => 'bastille',
          'linux' => 'docker',
          _ => null,
        },
        'platform': platform.isEmpty ? null : platform,
        'available': nodeState!.isOnline(node.id),
        'freeMemMb': sys == null ? 0 : (sys.freeMem / (1024 * 1024)).round(),
        'freeCpus': 0,
        'labels': <String, String>{},
      });
    }
    return out;
  }

  /// 对运行副本执行 MC ping，把在线人数送回引擎（弹性数据源）。
  Future<void> _collectPlayerCounts() async {
    final nodes = nodeState?.nodes ?? const <NodeInfo>[];
    final statuses = await status();
    final observed = <Map<String, dynamic>>[];
    for (final s in statuses) {
      for (final replica in s.replicas) {
        if (!replica.running || replica.hostPort == null) continue;
        final node = nodes.where((n) => n.id == replica.nodeId).firstOrNull;
        if (node == null || !nodeState!.isOnline(node.id)) continue;
        final host = _hostOf(node.address);
        try {
          final status = await mcPing(host, replica.hostPort!);
          observed.add({
            'id': replica.id,
            'running': true,
            'players': status.online ? status.players : null,
          });
        } catch (_) {
          observed.add({'id': replica.id, 'running': true});
        }
      }
    }
    if (observed.isEmpty) return;
    await OrchestratorFfi.instance.request(
      op: 'observe',
      args: {'dbPath': dbPath, 'replicas': observed},
    );
  }

  // ======================== 动作执行 ========================

  /// 顺序执行动作（delayMs 为自愈退避等待）。
  Future<void> executeActions(List<OrchestrationAction> actions) async {
    for (final action in actions) {
      if (action.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: action.delayMs));
      }
      try {
        await _executeAction(action);
      } catch (e) {
        debugPrint('编排动作执行失败 ${action.kind.name}: $e');
      }
    }
  }

  Future<void> _executeAction(OrchestrationAction action) async {
    switch (action.kind) {
      case OrchestrationActionKind.noop:
        break;
      case OrchestrationActionKind.ping:
        await _collectPlayerCounts();
      case OrchestrationActionKind.createContainer:
        await _executeCreate(action);
      case OrchestrationActionKind.startContainer:
        await _executeLifecycle(action, (b, name) => b.startContainer(name));
      case OrchestrationActionKind.stopContainer:
        await _executeLifecycle(action, (b, name) => b.stopContainer(name));
      case OrchestrationActionKind.restartContainer:
        await _executeLifecycle(action, (b, name) => b.restartContainer(name));
      case OrchestrationActionKind.destroyContainer:
        await _executeLifecycle(
          action,
          (b, name) => b.removeContainer(name, force: true),
        );
      case OrchestrationActionKind.archiveWorld:
        await _executeArchive(action);
      case OrchestrationActionKind.transferArchive:
        await _executeTransfer(action);
      case OrchestrationActionKind.restoreArchive:
        await _executeRestore(action);
    }
  }

  /// 节点 → 容器后端（含 overview 缓存）。
  Future<ContainerBackend> _backendFor(NodeInfo node) async {
    final overview = await _overviewOf(node);
    return nodeContainerBackend(
      client: NodeApiClient.of(node),
      daemonId: _daemonIdFor(overview),
      platformHint: overview.system.platform,
    );
  }

  Future<OverviewData> _overviewOf(NodeInfo node) async {
    final cached = _overviews[node.id];
    if (cached != null) return cached;
    final overview = await NodeApiClient.of(node).overview();
    _overviews[node.id] = overview;
    return overview;
  }

  String _daemonIdFor(OverviewData overview) {
    if (overview.remote.isEmpty) return '';
    final available = overview.remote.where((d) => d.available).toList();
    return (available.isNotEmpty ? available : overview.remote).first.uuid;
  }

  /// 从节点地址（http://host:port 或 host:port）解析 host。
  String _hostOf(String address) {
    var addr = address.trim();
    if (addr.contains('://')) addr = addr.split('://').last;
    // IPv6 回退：无法可靠解析时原样返回
    if (addr.startsWith('[')) {
      final end = addr.indexOf(']');
      if (end > 0) return addr.substring(1, end);
    }
    return addr.split(':').first;
  }

  /// 创建容器 / jail（payload 与 CreateContainerRequest 契约一致）。
  Future<void> _executeCreate(OrchestrationAction action) async {
    final node = _nodeById(action.nodeId);
    if (node == null) return;
    final backend = await _backendFor(node);
    final payload = action.payload;
    await backend.createContainer(
      CreateContainerRequest(
        name: payload['name'] as String? ?? '',
        image: payload['image'] as String? ?? '',
        command: payload['command'] as String?,
        ports: (payload['ports'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        volumes: (payload['volumes'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        env: (payload['env'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        restartPolicy: payload['restartPolicy'] as String?,
        memoryLimitMb: (payload['memoryLimitMb'] as num?)?.toInt(),
        cpus: (payload['cpus'] as num?)?.toInt(),
        workdir: payload['workdir'] as String?,
        ip: payload['ip'] as String?,
        jailType: payload['jailType'] as String?,
        vnetMode: payload['vnetMode'] as String?,
      ),
    );
  }

  Future<void> _executeLifecycle(
    OrchestrationAction action,
    Future<void> Function(ContainerBackend backend, String name) op,
  ) async {
    final node = _nodeById(action.nodeId);
    if (node == null) return;
    final backend = await _backendFor(node);
    final name = (action.payload['name'] as String?) ?? '';
    if (name.isEmpty) return;
    await op(backend, name);
  }

  NodeInfo? _nodeById(String id) {
    for (final node in nodeState?.nodes ?? const <NodeInfo>[]) {
      if (node.id == id) return node;
    }
    return null;
  }

  // ======================== 迁移执行 ========================

  /// 发起跨物理机迁移（引擎创建任务并产出第一步动作）。
  Future<MigrationJob> migrateStart({
    required String serviceId,
    required String replicaId,
    required String toNode,
  }) async {
    await _ensureInit();
    final result =
        await OrchestratorFfi.instance.request(
              op: 'migrate_start',
              args: {
                'dbPath': dbPath,
                'serviceId': serviceId,
                'replicaId': replicaId,
                'toNode': toNode,
              },
            )
            as Map<String, dynamic>?;
    final action = (result?['action'] as Map<String, dynamic>?) != null
        ? OrchestrationAction.fromJson(
            result!['action'] as Map<String, dynamic>,
          )
        : null;
    if (action != null) {
      await executeActions([action]);
    }
    return MigrationJob.fromJson(result?['job'] as Map<String, dynamic>? ?? {});
  }

  /// 执行迁移任务的当前步骤并回报结果（推进状态机）。
  Future<MigrationJob> runMigrationStep(MigrationJob job) async {
    final result =
        await OrchestratorFfi.instance.request(
              op: 'report_migration',
              args: {'dbPath': dbPath, 'jobId': job.id, 'ok': true},
            )
            as Map<String, dynamic>?;
    final action = result?['action'];
    if (action is Map<String, dynamic>) {
      final parsed = OrchestrationAction.fromJson(action);
      try {
        await _executeAction(parsed);
        return await _reportMigrationResult(job.id, true, null);
      } catch (e) {
        return await _reportMigrationResult(job.id, false, e.toString());
      }
    }
    return MigrationJob.fromJson(result?['job'] as Map<String, dynamic>? ?? {});
  }

  Future<MigrationJob> _reportMigrationResult(
    String jobId,
    bool ok,
    String? error,
  ) async {
    final result =
        await OrchestratorFfi.instance.request(
              op: 'report_migration',
              args: {
                'dbPath': dbPath,
                'jobId': jobId,
                'ok': ok,
                'error': ?error,
              },
            )
            as Map<String, dynamic>?;
    return MigrationJob.fromJson(result?['job'] as Map<String, dynamic>? ?? {});
  }

  /// 取消迁移任务。
  Future<void> migrateCancel(String jobId) async {
    await OrchestratorFfi.instance.request(
      op: 'migrate_cancel',
      args: {'dbPath': dbPath, 'jobId': jobId},
    );
  }

  /// 压缩世界存档：宿主路径 = volumes 首项 host 前缀 + worldDir。
  Future<void> _executeArchive(OrchestrationAction action) async {
    final node = _nodeById(action.nodeId);
    if (node == null) return;
    final service = (await status(serviceId: action.serviceId)).firstOrNull;
    final hostPrefix = _hostWorldPrefix(service);
    final path = (action.payload['path'] as String?) ?? '/data/world';
    await NodeApiClient.of(node).nodeArchive(
      path: '$hostPrefix$path',
      archive: action.payload['archiveName'] as String?,
    );
  }

  /// 传输存档：源节点下载 → 目标节点上传（桌面端中继）。
  Future<void> _executeTransfer(OrchestrationAction action) async {
    final fromId = action.payload['fromNode'] as String? ?? '';
    final toId = action.payload['toNode'] as String? ?? '';
    final archiveName = action.payload['archiveName'] as String? ?? '';
    final from = _nodeById(fromId);
    final to = _nodeById(toId);
    if (from == null || to == null || archiveName.isEmpty) return;
    final bytes = await NodeApiClient.of(from).nodeArchiveDownload(archiveName);
    await NodeApiClient.of(to).nodeArchiveUpload(archiveName, bytes);
  }

  /// 解压恢复存档到目标节点宿主世界目录。
  Future<void> _executeRestore(OrchestrationAction action) async {
    final node = _nodeById(action.nodeId);
    if (node == null) return;
    final service = (await status(serviceId: action.serviceId)).firstOrNull;
    final hostPrefix = _hostWorldPrefix(service);
    final path = (action.payload['path'] as String?) ?? '/data/world';
    await NodeApiClient.of(node).nodeArchiveRestore(
      file: action.payload['archiveName'] as String? ?? '',
      destPath: '$hostPrefix$path',
    );
  }

  /// 世界存档宿主路径前缀（volumes 首项 "host:container" 的 host 部分）。
  String _hostWorldPrefix(ServiceStatus? service) {
    if (service == null || service.service.volumes.isEmpty) return '';
    final first = service.service.volumes.first;
    final idx = first.indexOf(':');
    final host = idx >= 0 ? first.substring(0, idx) : first;
    return host.endsWith('/') ? host : '$host/';
  }
}
