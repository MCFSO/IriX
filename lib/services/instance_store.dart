// 实例持久化服务
// 负责将服务器实例列表读写到应用文档目录下的 instances.json 文件。
// 本服务为纯数据持久化层，不包含状态管理逻辑（状态管理由后续任务实现）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/server_instance.dart';

/// 服务器实例的本地持久化服务。
///
/// 通过 [getApplicationDocumentsDirectory] 获取应用文档目录，在其中的
/// `instances.json` 文件中以 JSON 数组形式保存实例列表。
///
/// 该类仅负责读写持久化数据，不涉及运行状态管理（如 ChangeNotifier），
/// 状态管理属于后续 Task 8 的职责。
class InstanceStore {
  /// 持久化文件名。
  static const String _fileName = 'instances.json';

  /// 内存缓存：首次加载后保留，避免每次操作都重新读盘。
  /// 为空表示尚未加载过（区别于已加载但列表为空的情况）。
  List<ServerInstance>? _cache;

  /// 获取持久化文件对象。
  ///
  /// 通过 [getApplicationDocumentsDirectory] 取得应用文档目录，
  /// 并使用 [p.join] 拼接目录路径与 [_fileName]。
  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// 加载全部实例。
  ///
  /// 读取 `instances.json` 文件并解析为实例列表：
  /// - 若文件不存在或内容为空，返回空列表。
  /// - 文件内容为 JSON 数组，数组元素可为实例 JSON 字符串或对象，二者均兼容。
  /// - 加载时每个实例的运行状态会被重置为已关闭（由 [ServerInstance.fromJson] 处理）。
  ///
  /// 返回列表的副本，避免外部直接修改影响内部缓存。
  Future<List<ServerInstance>> loadInstances() async {
    // 已缓存则直接返回副本
    if (_cache != null) {
      return List<ServerInstance>.of(_cache!);
    }

    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cache = <ServerInstance>[];
        return List<ServerInstance>.of(_cache!);
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _cache = <ServerInstance>[];
        return List<ServerInstance>.of(_cache!);
      }

      final list = jsonDecode(content) as List<dynamic>;
      _cache = list.map((item) {
        // 兼容数组元素为 JSON 字符串或对象两种格式
        final source = item is String ? item : jsonEncode(item);
        return ServerInstance.fromJson(source);
      }).toList();

      return List<ServerInstance>.of(_cache!);
    } catch (e) {
      debugPrint('Failed to load instances: $e');
      return _cache ?? [];
    }
  }

  /// 保存实例列表到文件。
  ///
  /// 将 [instances] 序列化为 JSON 对象数组并写入 `instances.json`，
  /// 同时更新内存缓存（保存传入列表的副本）。
  Future<void> saveInstances(List<ServerInstance> instances) async {
    try {
      final file = await _getFile();
      // 以对象数组形式持久化：先将每个实例的 JSON 字符串解码为对象，再整体编码
      final encoded = jsonEncode(
        instances.map((e) => jsonDecode(e.toJson())).toList(),
      );
      await file.writeAsString(encoded);
      _cache = List<ServerInstance>.of(instances);
    } catch (e) {
      debugPrint('Failed to save instances: $e');
    }
  }

  /// 添加单个实例并保存。
  ///
  /// 将 [instance] 追加到现有列表后持久化。
  /// 返回被添加的实例，便于调用方链式使用。
  Future<ServerInstance> addInstance(ServerInstance instance) async {
    final instances = await loadInstances();
    instances.add(instance);
    await saveInstances(instances);
    return instance;
  }

  /// 按 [id] 删除实例并保存。
  ///
  /// 若 [id] 不存在则不做任何更改。
  Future<void> removeInstance(String id) async {
    final instances = await loadInstances();
    instances.removeWhere((e) => e.id == id);
    await saveInstances(instances);
  }

  /// 重命名实例并保存。
  ///
  /// 将指定 [id] 的实例名称更新为 [newName]。
  /// 若 [id] 不存在则不做任何更改。
  Future<void> renameInstance(String id, String newName) async {
    final instances = await loadInstances();
    for (final e in instances) {
      if (e.id == id) {
        e.name = newName;
      }
    }
    await saveInstances(instances);
  }

  /// 更新实例的启动命令并保存。
  ///
  /// 将指定 [id] 的实例启动命令更新为 [newCommand]。
  /// 若 [id] 不存在则不做任何更改。
  Future<void> updateStartCommand(String id, String newCommand) async {
    final instances = await loadInstances();
    for (final e in instances) {
      if (e.id == id) {
        e.startCommand = newCommand;
      }
    }
    await saveInstances(instances);
  }
}
