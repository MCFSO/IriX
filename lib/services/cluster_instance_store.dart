// 集群实例持久化服务
// 通过 DatabaseManager 将集群实例列表持久化到 SQLite 数据库（cluster_instances 表）。
// 纯数据持久化层，状态管理由 ClusterState 负责。

import 'package:flutter/foundation.dart';

import '../models/cluster_instance.dart';
import '../services/database_manager.dart';

/// 集群实例的本地持久化服务。
class ClusterInstanceStore {
  /// 内存缓存：首次加载后保留，避免每次操作都重新查询数据库。
  List<ClusterInstance>? _cache;

  /// 将数据库行记录转换为 [ClusterInstance]。
  ClusterInstance _fromDbRow(Map<String, dynamic> row) {
    return ClusterInstance(
      id: row['id'] as String,
      name: row['name'] as String,
      nodeId: row['node_id'] as String,
      daemonId: row['daemon_id'] as String? ?? '',
      remoteUuid: row['remote_uuid'] as String? ?? '',
      cwd: row['cwd'] as String? ?? '',
      startCommand: row['start_command'] as String? ?? '',
      crashCount: (row['crash_count'] as num?)?.toInt() ?? 0,
      lastSyncedAt: row['last_synced_at'] == null
          ? null
          : DateTime.parse(row['last_synced_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// 将 [ClusterInstance] 转换为数据库行记录。
  Map<String, dynamic> _toDbRow(ClusterInstance instance) {
    return {
      'id': instance.id,
      'name': instance.name,
      'node_id': instance.nodeId,
      'daemon_id': instance.daemonId,
      'remote_uuid': instance.remoteUuid,
      'cwd': instance.cwd,
      'start_command': instance.startCommand,
      'crash_count': instance.crashCount,
      'last_synced_at': instance.lastSyncedAt?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
    };
  }

  /// 加载全部集群实例。
  Future<List<ClusterInstance>> loadInstances() async {
    if (_cache != null) {
      return List<ClusterInstance>.of(_cache!);
    }
    try {
      final rows = await DatabaseManager.instance.getAllClusterInstances();
      _cache = rows.map(_fromDbRow).toList();
      return List<ClusterInstance>.of(_cache!);
    } catch (e) {
      debugPrint('Failed to load cluster instances: $e');
      return _cache ?? [];
    }
  }

  /// 添加单个集群实例并持久化。
  Future<ClusterInstance> addInstance(ClusterInstance instance) async {
    try {
      await DatabaseManager.instance.insertClusterInstance(_toDbRow(instance));
      _cache?.add(instance);
      return instance;
    } catch (e) {
      debugPrint('Failed to add cluster instance: $e');
      return instance;
    }
  }

  /// 按 [id] 删除集群实例并持久化。
  Future<void> removeInstance(String id) async {
    try {
      await DatabaseManager.instance.deleteClusterInstance(id);
      _cache?.removeWhere((e) => e.id == id);
    } catch (e) {
      debugPrint('Failed to remove cluster instance: $e');
    }
  }

  /// 更新集群实例字段并持久化。
  Future<void> updateInstance(ClusterInstance instance) async {
    try {
      await DatabaseManager.instance.updateClusterInstance(
        instance.id,
        _toDbRow(instance),
      );
      if (_cache != null) {
        final index = _cache!.indexWhere((e) => e.id == instance.id);
        if (index >= 0) {
          _cache![index] = instance;
        }
      }
    } catch (e) {
      debugPrint('Failed to update cluster instance ${instance.id}: $e');
    }
  }
}
