// 集群状态管理层
// 汇总多机管理模式下的集群实例、监控节点、节点资源快照与运行态，
// 作为 UI 与持久化层之间的桥梁。通过 ChangeNotifier 暴露响应式状态。

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/cluster_instance.dart';
import '../models/remote.dart';
import '../services/cluster_instance_store.dart';
import '../services/management_mode_settings.dart';

/// 集群全局状态。
class ClusterState extends ChangeNotifier {
  /// 集群实例持久化服务。
  final ClusterInstanceStore _store = ClusterInstanceStore();

  /// 当前已加载的集群实例列表。
  List<ClusterInstance> _instances = [];

  /// 当前管理模式（默认单机）。
  ManagementMode _mode = ManagementMode.single;

  /// 多机模式监控节点 id（可空：2 节点互相监控 / 节点不足）。
  String? _monitorNodeId;

  /// 节点资源快照（nodeId → 最近概览系统信息）。
  final Map<String, OverviewSystem> _resourceSnapshot = {};

  /// 监控循环是否在运行。
  bool _monitorActive = false;

  /// 当前集群实例列表（只读视图）。
  List<ClusterInstance> get instances => List.unmodifiable(_instances);

  /// 当前管理模式。
  ManagementMode get mode => _mode;

  /// 多机模式监控节点 id（可空）。
  String? get monitorNodeId => _monitorNodeId;

  /// 节点资源快照（只读视图）。
  Map<String, OverviewSystem> get resourceSnapshot =>
      Map.unmodifiable(_resourceSnapshot);

  /// 监控循环是否在运行。
  bool get monitorActive => _monitorActive;

  /// 生成集群实例唯一标识。
  String _generateId() {
    final random = Random();
    final suffix = random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return 'c-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  /// 初始化：加载模式、监控节点与集群实例列表。
  Future<void> init() async {
    _mode = await ManagementModeSettings.getMode();
    _monitorNodeId = await ManagementModeSettings.getMonitorNodeId();
    _instances = await _store.loadInstances();
    notifyListeners();
  }

  /// 切换管理模式并持久化。
  Future<void> setMode(ManagementMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await ManagementModeSettings.setMode(mode);
    notifyListeners();
  }

  /// 设置监控节点 id 并持久化。
  Future<void> setMonitorNode(String? nodeId) async {
    if (_monitorNodeId == nodeId) return;
    _monitorNodeId = nodeId;
    await ManagementModeSettings.setMonitorNodeId(nodeId);
    notifyListeners();
  }

  /// 更新节点资源快照（单节点）。
  void updateResourceSnapshot(String nodeId, OverviewSystem? sys) {
    if (sys == null) {
      _resourceSnapshot.remove(nodeId);
    } else {
      _resourceSnapshot[nodeId] = sys;
    }
    notifyListeners();
  }

  /// 清空全部资源快照。
  void clearResourceSnapshot() {
    _resourceSnapshot.clear();
    notifyListeners();
  }

  /// 设置监控循环运行态。
  void setMonitorActive(bool active) {
    if (_monitorActive == active) return;
    _monitorActive = active;
    notifyListeners();
  }

  /// 按 id 查找内存中的集群实例。
  ClusterInstance? instanceById(String id) {
    for (final instance in _instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// 添加集群实例并持久化。
  Future<ClusterInstance> addInstance({
    required String name,
    required String nodeId,
    required String daemonId,
    required String remoteUuid,
    required String cwd,
    required String startCommand,
  }) async {
    final instance = ClusterInstance(
      id: _generateId(),
      name: name,
      nodeId: nodeId,
      daemonId: daemonId,
      remoteUuid: remoteUuid,
      cwd: cwd,
      startCommand: startCommand,
    );
    await _store.addInstance(instance);
    _instances.add(instance);
    notifyListeners();
    return instance;
  }

  /// 删除集群实例并持久化。
  Future<void> removeInstance(String id) async {
    await _store.removeInstance(id);
    _instances.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  /// 更新集群实例的节点位置（迁移后），并持久化。
  Future<void> updatePlacement(
    String id, {
    required String nodeId,
    required String daemonId,
    required String remoteUuid,
  }) async {
    final instance = instanceById(id);
    if (instance == null) return;
    final updated = instance.copyWith(
      nodeId: nodeId,
      daemonId: daemonId,
      remoteUuid: remoteUuid,
    );
    await _store.updateInstance(updated);
    final index = _instances.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _instances[index] = updated;
    }
    notifyListeners();
  }

  /// 崩溃计数 +1 并持久化，返回新的计数值（未找到返回 null）。
  Future<int?> incrementCrash(String id) async {
    final instance = instanceById(id);
    if (instance == null) return null;
    final updated = instance.copyWith(crashCount: instance.crashCount + 1);
    await _store.updateInstance(updated);
    final index = _instances.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _instances[index] = updated;
    }
    notifyListeners();
    return updated.crashCount;
  }

  /// 重置崩溃计数并持久化。
  Future<void> resetCrash(String id) async {
    final instance = instanceById(id);
    if (instance == null || instance.crashCount == 0) return;
    final updated = instance.copyWith(crashCount: 0);
    await _store.updateInstance(updated);
    final index = _instances.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _instances[index] = updated;
    }
    notifyListeners();
  }

  /// 记录最近一次增量同步时间并持久化。
  Future<void> markSynced(String id, DateTime time) async {
    final instance = instanceById(id);
    if (instance == null) return;
    final updated = instance.copyWith(lastSyncedAt: time);
    await _store.updateInstance(updated);
    final index = _instances.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _instances[index] = updated;
    }
    notifyListeners();
  }
}
