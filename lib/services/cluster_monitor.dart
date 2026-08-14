// 集群监控服务（协调器）
// 多机模式下运行于桌面应用内的协调主循环：
// - 周期轮询各节点资源（overview），刷新资源快照
// - 检测实例崩溃（running/starting → stopped 且非用户停止），累计崩溃次数
// - 检测节点资源不足，触发实例迁移
// - 提供实例创建（按资源分配）、优雅停止 + 增量同步、手动迁移入口

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cluster_instance.dart';
import '../models/node.dart';
import '../models/remote.dart';
import '../services/cluster_allocator.dart';
import '../services/cluster_migrator.dart';
import '../services/node_api_client.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';

/// 集群监控服务（协调器单例）。
class ClusterMonitor {
  ClusterMonitor._();

  static final ClusterMonitor instance = ClusterMonitor._();

  /// 轮询周期。
  static const Duration pollInterval = Duration(seconds: 15);

  /// 节点内存使用率阈值（超过即视为资源不足）。
  static const double memUsageThreshold = 0.9;

  /// 崩溃迁移阈值。
  static const int crashMigrateThreshold = 3;

  NodeState? _nodeState;
  ClusterState? _clusterState;
  ClusterMigrator? _migrator;
  Timer? _timer;

  /// 实例上次已知远程状态（instanceId → 状态）。
  final Map<String, RemoteStatus> _lastStatus = {};

  /// 用户已发起停止、等待其正常退出的实例集合。
  final Set<String> _expectedStops = {};

  /// 正在迁移中的实例集合（避免重复触发）。
  final Set<String> _migrating = {};

  /// 最近已迁移的节点（冷却，避免抖动）。
  final Set<String> _resourceMigratedCooldown = {};

  /// 是否已配置。
  bool get configured => _nodeState != null && _clusterState != null;

  NodeInfo? _nodeById(String id) {
    final nodes = _nodeState?.nodes ?? const <NodeInfo>[];
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  /// 启动监控循环。多机模式进入时调用，幂等。
  Future<void> start(NodeState nodeState, ClusterState clusterState) async {
    _nodeState = nodeState;
    _clusterState = clusterState;
    _migrator = ClusterMigrator(
      nodeState: nodeState,
      clusterState: clusterState,
    );
    clusterState.setMonitorActive(true);
    _applyMonitorRole();
    _timer ??= Timer.periodic(pollInterval, (_) => _tick());
    // 立即执行一次。
    unawaited(_tick());
  }

  /// 停止监控循环。切回单机模式时调用。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastStatus.clear();
    _expectedStops.clear();
    _migrating.clear();
    _resourceMigratedCooldown.clear();
    _clusterState?.setMonitorActive(false);
    _clusterState?.clearResourceSnapshot();
    _clusterState?.clearNetworkHistory();
  }

  /// 依据节点数量推导并落盘监控节点。
  void _applyMonitorRole() {
    final cluster = _clusterState;
    final nodes = _nodeState?.nodes ?? const <NodeInfo>[];
    if (cluster == null) return;
    final role = deriveMonitorRole(nodes);
    if (role.strategy != ClusterMonitorStrategy.monitor) {
      cluster.setMonitorNode(null);
    } else {
      // 监控节点必须是仍然存在的 irix-node（MCSM 不能充当监控节点）。
      final current = cluster.monitorNodeId;
      final valid =
          current != null &&
          nodes.any((n) => n.id == current && n.type == NodeType.node);
      if (!valid) {
        cluster.setMonitorNode(role.monitorNodeId);
      }
    }
  }

  /// 单次轮询。
  Future<void> _tick() async {
    final nodeState = _nodeState;
    final cluster = _clusterState;
    final migrator = _migrator;
    if (nodeState == null || cluster == null || migrator == null) return;

    _applyMonitorRole();
    await _refreshResources(nodeState, cluster);
    await _detectCrashes(nodeState, cluster, migrator);
    await _detectResourcePressure(nodeState, cluster, migrator);
  }

  /// 手动刷新资源快照（不触发崩溃/资源检测与迁移）。
  Future<void> refreshNow() async {
    final nodeState = _nodeState;
    final cluster = _clusterState;
    if (nodeState == null || cluster == null) return;
    _applyMonitorRole();
    await _refreshResources(nodeState, cluster);
  }

  /// 刷新全部节点资源快照，并聚合网络吞吐推入历史。
  Future<void> _refreshResources(
    NodeState nodeState,
    ClusterState cluster,
  ) async {
    var totalDownload = 0.0;
    var totalUpload = 0.0;
    for (final node in nodeState.nodes) {
      try {
        final overview = await nodeState.clientFor(node).overview();
        var sys = overview.system;
        // MCSM 面板的磁盘 / 网络数据位于 daemon（remote）而非 system，需要合并。
        if (!sys.hasDisk || !sys.hasNetwork) {
          OverviewSystem merged = sys;
          for (final daemon in overview.remote) {
            merged = merged.mergedWith(daemon.system);
          }
          sys = merged;
        }
        cluster.updateResourceSnapshot(node.id, sys);
        totalDownload += sys.networkDownload;
        totalUpload += sys.networkUpload;
        if (!nodeState.isOnline(node.id)) {
          await nodeState.pingNode(node.id);
        }
      } catch (_) {
        cluster.updateResourceSnapshot(node.id, null);
      }
    }
    cluster.pushNetworkSample(totalDownload, totalUpload);
  }

  /// 检测崩溃：running/starting → stopped 且非用户停止。
  Future<void> _detectCrashes(
    NodeState nodeState,
    ClusterState cluster,
    ClusterMigrator migrator,
  ) async {
    for (final instance in List<ClusterInstance>.of(cluster.instances)) {
      if (_migrating.contains(instance.id)) continue;
      final node = _nodeById(instance.nodeId);
      if (node == null) continue;
      RemoteInstance remote;
      try {
        remote = await nodeState
            .clientFor(node)
            .getInstance(
              uuid: instance.remoteUuid,
              daemonId: instance.daemonId,
            );
      } catch (_) {
        continue;
      }

      final prev = _lastStatus[instance.id];
      final current = remote.status;
      _lastStatus[instance.id] = current;

      final wasActive =
          prev == RemoteStatus.running || prev == RemoteStatus.starting;
      final nowStopped = current == RemoteStatus.stopped;

      if (wasActive && nowStopped) {
        if (_expectedStops.contains(instance.id)) {
          _expectedStops.remove(instance.id);
          continue;
        }
        final count = await cluster.incrementCrash(instance.id) ?? 0;
        if (count >= crashMigrateThreshold) {
          await _migrateToIdle(instance, cluster, migrator);
        }
      }
    }
  }

  /// 检测节点资源不足，迁移该节点上的实例到最空闲节点。
  Future<void> _detectResourcePressure(
    NodeState nodeState,
    ClusterState cluster,
    ClusterMigrator migrator,
  ) async {
    for (final node in nodeState.nodes) {
      if (_resourceMigratedCooldown.contains(node.id)) continue;
      final sys = cluster.resourceSnapshot[node.id];
      final memUsage = sys?.memUsage ?? 0;
      final freeRatio = freeMemoryRatio(sys);
      final pressure =
          memUsage > memUsageThreshold ||
          (sys != null && sys.totalMem > 0 && freeRatio < 0.05);

      if (!pressure) continue;
      _resourceMigratedCooldown.add(node.id);

      final victims = cluster.instances
          .where((i) => i.nodeId == node.id && !_migrating.contains(i.id))
          .toList();
      for (final instance in victims) {
        await _migrateToIdle(instance, cluster, migrator);
        break; // 每轮只迁移一个，避免瞬时高峰。
      }
    }
  }

  /// 迁移到最空闲节点（避开当前节点）。
  Future<void> _migrateToIdle(
    ClusterInstance instance,
    ClusterState cluster,
    ClusterMigrator migrator,
  ) async {
    if (_migrating.contains(instance.id)) return;
    final candidates = (_nodeState?.nodes ?? const <NodeInfo>[])
        .where((n) => n.id != instance.nodeId)
        .toList();
    final targetId = pickMigrationTarget(candidates, cluster.resourceSnapshot);
    if (targetId == null) {
      debugPrint('无可用目标节点，无法迁移实例 ${instance.name}');
      return;
    }
    _migrating.add(instance.id);
    try {
      await migrator.migrate(instance, targetNodeId: targetId);
      _lastStatus.remove(instance.id);
    } catch (e) {
      debugPrint('迁移实例 ${instance.name} 失败: $e');
    } finally {
      _migrating.remove(instance.id);
    }
  }

  /// 创建集群实例（按资源自动分配或指定节点）。
  Future<ClusterInstance?> createWithAllocation({
    required String name,
    required String cwd,
    required String startCommand,
    String? nodeId,
  }) async {
    final nodeState = _nodeState;
    final cluster = _clusterState;
    if (nodeState == null || cluster == null) return null;

    // 刷新资源并确定目标节点。
    await _refreshResources(nodeState, cluster);
    String? targetId = nodeId;
    if (targetId == null || _nodeById(targetId) == null) {
      targetId = pickNodeForAllocation(
        nodeState.nodes,
        cluster.resourceSnapshot,
      );
    }
    if (targetId == null) return null;
    final targetNode = _nodeById(targetId)!;

    final client = nodeState.clientFor(targetNode);
    final daemonId = await _resolveDaemonIdFallback(targetNode);
    final config = InstanceConfig(
      nickname: name,
      startCommand: startCommand,
      stopCommand: 'stop',
      cwd: cwd,
      processType: 'universal',
      autoStart: false,
      autoRestart: false,
    ).toJson();
    final remoteUuid = await client.createInstance(
      daemonId: daemonId,
      config: config,
    );

    return cluster.addInstance(
      name: name,
      nodeId: targetId,
      daemonId: daemonId,
      remoteUuid: remoteUuid,
      cwd: cwd,
      startCommand: startCommand,
    );
  }

  Future<String> _resolveDaemonIdFallback(NodeInfo node) async {
    final overview = await _nodeState!.clientFor(node).overview();
    if (overview.remote.isNotEmpty) {
      final available = overview.remote.where((d) => d.available).toList();
      return (available.isNotEmpty ? available : overview.remote).first.uuid;
    }
    return '';
  }

  /// 启动集群实例。
  Future<void> startInstance(ClusterInstance instance) async {
    final node = _nodeById(instance.nodeId);
    if (node == null) return;
    await _nodeState!
        .clientFor(node)
        .instanceAction(
          uuid: instance.remoteUuid,
          daemonId: instance.daemonId,
          action: RemoteAction.start,
        );
  }

  /// 优雅停止 + 增量同步（人为正常关闭）。
  Future<void> gracefulStopAndSync(ClusterInstance instance) async {
    final node = _nodeById(instance.nodeId);
    if (node == null) return;
    _expectedStops.add(instance.id);
    try {
      await _nodeState!
          .clientFor(node)
          .instanceAction(
            uuid: instance.remoteUuid,
            daemonId: instance.daemonId,
            action: RemoteAction.stop,
          );
      await _migrator?.waitStopped(
        _nodeState!.clientFor(node),
        instance.daemonId,
        instance.remoteUuid,
      );
      await _migrator?.syncToMirror(instance);
      _lastStatus[instance.id] = RemoteStatus.stopped;
    } catch (e) {
      debugPrint('优雅停止/同步实例 ${instance.name} 失败: $e');
    } finally {
      _expectedStops.remove(instance.id);
    }
  }

  /// 手动迁移到指定节点。
  Future<void> migrateTo(
    ClusterInstance instance, {
    required String targetNodeId,
  }) async {
    if (_migrating.contains(instance.id)) return;
    _migrating.add(instance.id);
    try {
      await _migrator?.migrate(instance, targetNodeId: targetNodeId);
      _lastStatus.remove(instance.id);
    } finally {
      _migrating.remove(instance.id);
    }
  }
}
