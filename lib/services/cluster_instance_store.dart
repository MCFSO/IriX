// 集群实例持久化服务
// 通过 DatabaseManager 将集群实例列表持久化到 SQLite 数据库（cluster_instances 表）。
// 纯数据持久化层，状态管理由 ClusterState 负责。

import '../models/cluster_instance.dart';
import 'database_manager.dart';
import 'entity_store.dart';

/// 集群实例的本地持久化服务。
class ClusterInstanceStore extends EntityStore<ClusterInstance> {
  @override
  String get storeLabel => 'cluster instances';

  @override
  ClusterInstance fromDbRow(Map<String, dynamic> row) {
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

  @override
  Map<String, dynamic> toDbRow(ClusterInstance instance) {
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

  @override
  String idOf(ClusterInstance instance) => instance.id;

  @override
  Future<List<Map<String, dynamic>>> fetchAll() =>
      DatabaseManager.instance.getAllClusterInstances();

  @override
  Future<void> insertRow(Map<String, dynamic> row) =>
      DatabaseManager.instance.insertClusterInstance(row);

  @override
  Future<void> deleteRow(String id) =>
      DatabaseManager.instance.deleteClusterInstance(id);

  @override
  Future<void> updateRow(String id, Map<String, dynamic> row) =>
      DatabaseManager.instance.updateClusterInstance(id, row);

  /// 加载全部集群实例。
  Future<List<ClusterInstance>> loadInstances() => loadAll();

  /// 添加单个集群实例并持久化。
  Future<ClusterInstance> addInstance(ClusterInstance instance) =>
      add(instance);

  /// 按 [id] 删除集群实例并持久化。
  Future<void> removeInstance(String id) => remove(id);

  /// 更新集群实例字段并持久化。
  Future<void> updateInstance(ClusterInstance instance) => update(instance);
}
