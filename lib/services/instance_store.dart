// 实例持久化服务
// 负责通过 DatabaseManager 将服务器实例列表持久化到 SQLite 数据库。
// 本服务为纯数据持久化层，不包含状态管理逻辑（状态管理由后续任务实现）。

import 'package:flutter/foundation.dart';

import '../models/server_instance.dart';
import '../services/database_manager.dart';

/// 服务器实例的本地持久化服务。
///
/// 通过 [DatabaseManager] 操作 SQLite 数据库的 `servers` 表，
/// 实现实例的增删改查。
///
/// 该类仅负责读写持久化数据，不涉及运行状态管理（如 ChangeNotifier），
/// 状态管理属于后续 Task 8 的职责。
class InstanceStore {
  /// 内存缓存：首次加载后保留，避免每次操作都重新查询数据库。
  /// 为空表示尚未加载过（区别于已加载但列表为空的情况）。
  List<ServerInstance>? _cache;

  /// 将数据库行记录转换为 [ServerInstance]。
  ServerInstance _fromDbRow(Map<String, dynamic> row) {
    final containerConfig = row['container_config'] as String?;
    return ServerInstance(
      id: row['id'] as String,
      name: row['name'] as String,
      rootPath: row['root_path'] as String,
      coreFilePath: row['core_file_path'] as String,
      startCommand: row['start_command'] as String,
      coreType: row['core_type'] as String?,
      coreVersion: row['core_version'] as String?,
      runMode: RunMode.fromString(row['run_mode'] as String?),
      container: containerConfig == null || containerConfig.isEmpty
          ? null
          : ContainerConfig.fromJson(containerConfig),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// 将 [ServerInstance] 转换为数据库行记录。
  ///
  /// 字段名使用 snake_case 以匹配数据库列名。
  Map<String, dynamic> _toDbRow(ServerInstance instance) {
    return {
      'id': instance.id,
      'name': instance.name,
      'root_path': instance.rootPath,
      'core_file_path': instance.coreFilePath,
      'start_command': instance.startCommand,
      'core_type': instance.coreType,
      'core_version': instance.coreVersion,
      'run_mode': instance.runMode.name,
      'container_config': instance.container?.toJson(),
      'created_at': instance.createdAt.toIso8601String(),
    };
  }

  /// 加载全部实例。
  ///
  /// 从数据库查询所有服务器记录并转换为实例列表。
  /// - 加载时每个实例的运行状态会被重置为已关闭（由 [ServerInstance] 默认值处理）。
  ///
  /// 返回列表的副本，避免外部直接修改影响内部缓存。
  Future<List<ServerInstance>> loadInstances() async {
    if (_cache != null) {
      return List<ServerInstance>.of(_cache!);
    }

    try {
      final rows = await DatabaseManager.instance.getAllServers();
      _cache = rows.map(_fromDbRow).toList();
      return List<ServerInstance>.of(_cache!);
    } catch (e) {
      debugPrint('Failed to load instances: $e');
      return _cache ?? [];
    }
  }

  /// 保存实例列表（更新内存缓存）。
  ///
  /// 数据库写入已由各增删改方法单独完成，此处仅同步内存缓存。
  Future<void> saveInstances(List<ServerInstance> instances) async {
    _cache = List<ServerInstance>.of(instances);
  }

  /// 添加单个实例并持久化。
  ///
  /// 将 [instance] 插入数据库，同时更新内存缓存。
  /// 返回被添加的实例，便于调用方链式使用。
  Future<ServerInstance> addInstance(ServerInstance instance) async {
    try {
      await DatabaseManager.instance.insertServer(_toDbRow(instance));
      _cache?.add(instance);
      return instance;
    } catch (e) {
      debugPrint('Failed to add instance: $e');
      return instance;
    }
  }

  /// 按 [id] 删除实例并持久化。
  ///
  /// 从数据库删除指定记录，同时从内存缓存中移除。
  /// 若 [id] 不存在则不做任何更改。
  Future<void> removeInstance(String id) async {
    try {
      await DatabaseManager.instance.deleteServer(id);
      _cache?.removeWhere((e) => e.id == id);
    } catch (e) {
      debugPrint('Failed to remove instance: $e');
    }
  }

  /// 重命名实例并持久化。
  ///
  /// 将指定 [id] 的实例名称更新为 [newName]，同时更新内存缓存。
  /// 若 [id] 不存在则不做任何更改。
  Future<void> renameInstance(String id, String newName) async {
    try {
      await DatabaseManager.instance.updateServer(id, {'name': newName});
      if (_cache != null) {
        for (final e in _cache!) {
          if (e.id == id) {
            e.name = newName;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to rename instance: $e');
    }
  }

  /// 更新实例的启动命令并持久化。
  ///
  /// 将指定 [id] 的实例启动命令更新为 [newCommand]，同时更新内存缓存。
  /// 若 [id] 不存在则不做任何更改。
  Future<void> updateStartCommand(String id, String newCommand) async {
    try {
      await DatabaseManager.instance.updateServer(id, {
        'start_command': newCommand,
      });
      if (_cache != null) {
        for (final e in _cache!) {
          if (e.id == id) {
            e.startCommand = newCommand;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to update start command: $e');
    }
  }

  /// 更新实例的运行方式（原生 / Docker）与容器配置并持久化。
  ///
  /// [container] 为 null 表示清除容器配置；同时更新内存缓存。
  Future<void> updateRunMode(
    String id,
    RunMode runMode,
    ContainerConfig? container,
  ) async {
    try {
      await DatabaseManager.instance.updateServer(id, {
        'run_mode': runMode.name,
        'container_config': container?.toJson(),
      });
      if (_cache != null) {
        for (final e in _cache!) {
          if (e.id == id) {
            e.runMode = runMode;
            e.container = container;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to update run mode: $e');
    }
  }
}
