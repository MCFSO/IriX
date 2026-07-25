// 应用状态管理层
// 汇总服务器实例列表、运行状态与进程管理器，作为 UI 与持久化/进程层之间的桥梁。
// 通过 ChangeNotifier 向 UI 暴露响应式状态，所有状态变更均会通知监听者并按需持久化。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/server_cores.dart';
import '../models/server_instance.dart';
import '../services/instance_store.dart';
import '../services/server_process.dart';
import '../utils/naming.dart';

/// 应用全局状态。
///
/// 持有全部 [ServerInstance] 及其对应的 [ServerProcessManager]，
/// 负责实例的创建、删除、重命名、启停与命令下发，并在状态变化时
/// 通过 [notifyListeners] 通知 UI、通过 [InstanceStore] 持久化。
class AppState extends ChangeNotifier {
  /// 实例持久化服务。
  final InstanceStore _store = InstanceStore();

  /// 当前已加载的实例列表。
  List<ServerInstance> _instances = [];

  /// 当前实例列表（只读视图）。
  List<ServerInstance> get instances => _instances;

  /// 运行中的进程管理器，按实例 id 索引。
  final Map<String, ServerProcessManager> _managers = {};

  /// 当前选中的实例。
  ServerInstance? _selected;

  /// 当前选中的实例（可空）。
  ServerInstance? get selected => _selected;

  /// 设置当前选中的实例，变更后通知监听者。
  set selected(ServerInstance? value) {
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
  }

  /// 生成实例唯一标识：微秒时间戳的 36 进制串 + 随机后缀。
  String _generateId() {
    final random = Random();
    final suffix =
        random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  /// 按 id 查找内存中的实例。
  ServerInstance? _instanceById(String id) {
    for (final instance in _instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// 初始化：从持久化层加载实例列表。
  ///
  /// 加载后实例状态均为 [InstanceStatus.stopped]（由反序列化处理）。
  /// 不在此处创建进程管理器；管理器在 [startInstance] 时按需创建。
  Future<void> init() async {
    _instances = await _store.loadInstances();
    notifyListeners();
  }

  /// 创建一个通过“导入目录”方式的实例。
  ///
  /// [coreFilePath] 留空，[coreType]/[coreVersion] 为 null。
  Future<void> createImportedInstance({
    required String rootPath,
    required String startCommand,
  }) async {
    final instance = ServerInstance(
      id: _generateId(),
      name: randomInstanceName(),
      rootPath: rootPath,
      coreFilePath: '',
      startCommand: startCommand,
    );
    await _store.addInstance(instance);
    _instances.add(instance);
    notifyListeners();
  }

  /// 创建一个通过“选择本地核心文件”方式的实例。
  Future<void> createFromCoreFile({
    required String coreFilePath,
    required String rootPath,
    required String startCommand,
    String? coreType,
    String? coreVersion,
  }) async {
    final instance = ServerInstance(
      id: _generateId(),
      name: randomInstanceName(),
      rootPath: rootPath,
      coreFilePath: coreFilePath,
      startCommand: startCommand,
      coreType: coreType,
      coreVersion: coreVersion,
    );
    await _store.addInstance(instance);
    _instances.add(instance);
    notifyListeners();
  }

  /// 创建一个通过“下载核心”方式的实例。
  Future<void> createDownloadedInstance({
    required ServerCore core,
    required CoreVersionInfo versionInfo,
    required String coreFilePath,
    required String rootPath,
    required String startCommand,
  }) async {
    final instance = ServerInstance(
      id: _generateId(),
      name: randomInstanceName(),
      rootPath: rootPath,
      coreFilePath: coreFilePath,
      startCommand: startCommand,
      coreType: core.name,
      coreVersion: versionInfo.version,
    );
    await _store.addInstance(instance);
    _instances.add(instance);
    notifyListeners();
  }

  /// 删除指定实例：强制终止进程、释放并移除其进程管理器，从持久化与内存列表中清除。
  ///
  /// 当 [deleteFiles] 为 true 时，同时删除服务器根目录下的所有文件。
  Future<void> removeInstance(String id, {bool deleteFiles = false}) async {
    final instance = _instanceById(id);
    final manager = _managers.remove(id);
    if (manager != null) {
      // 先强制终止正在运行的进程，避免产生孤儿进程。
      await manager.forceStop();
      manager.dispose();
    }
    await _store.removeInstance(id);
    _instances.removeWhere((e) => e.id == id);
    if (_selected?.id == id) {
      _selected = null;
    }
    // 可选：删除服务器根目录下的所有文件。
    if (deleteFiles && instance != null && instance.rootPath.isNotEmpty) {
      try {
        final dir = Directory(instance.rootPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {
        // 删除文件失败不影响实例记录的移除，忽略错误。
      }
    }
    notifyListeners();
  }

  /// 重命名指定实例并持久化。
  Future<void> renameInstance(String id, String newName) async {
    await _store.renameInstance(id, newName);
    final instance = _instanceById(id);
    if (instance != null) {
      instance.name = newName;
    }
    notifyListeners();
  }

  /// 更新指定实例的启动命令并持久化。
  Future<void> updateStartCommand(String id, String newCommand) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    instance.startCommand = newCommand;
    await _store.updateStartCommand(id, newCommand);
    notifyListeners();
  }

  /// 选中指定 id 的实例。
  void selectInstance(String id) {
    _selected = _instanceById(id);
    notifyListeners();
  }

  /// 为指定实例挂载进程退出监听。
  ///
  /// 当进程自然退出时，将实例状态置为 [InstanceStatus.stopped]、
  /// 移除并释放对应管理器，然后通知监听者。
  /// 在重启过程中（状态为 [InstanceStatus.restarting]）跳过处理，
  /// 由 [restartInstance] 在重启结束后重新挂载监听。
  void _watchExit(String id, ServerProcessManager manager) {
    unawaited(manager.onExit.then((code) {
      final instance = _instanceById(id);
      if (instance == null) return;
      if (instance.status == InstanceStatus.restarting) {
        // 重启期间进程退出是预期行为，不翻转状态也不释放管理器；
        // restartInstance 会在新进程启动后重新挂载监听。
        return;
      }
      instance.status = InstanceStatus.stopped;
      _managers.remove(id);
      manager.dispose();
      notifyListeners();
    }));
  }

  /// 启动指定实例。
  ///
  /// 若实例已处于活跃状态则直接返回。按需创建 [ServerProcessManager]，
  /// 置为启动中→启动进程→置为运行中，并挂载退出监听。
  /// 若进程启动失败（如 java 未找到），重置状态为已关闭并清理管理器。
  Future<void> startInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    if (instance.status.isActive) return;

    var manager = _managers[id];
    if (manager == null) {
      manager = ServerProcessManager(instance: instance);
      _managers[id] = manager;
    }

    instance.status = InstanceStatus.starting;
    notifyListeners();

    try {
      await manager.start();
    } catch (e) {
      // 启动失败：重置状态为已关闭，移除并释放管理器。
      instance.status = InstanceStatus.stopped;
      _managers.remove(id);
      manager.dispose();
      notifyListeners();
      rethrow;
    }

    _watchExit(id, manager);

    instance.status = InstanceStatus.running;
    notifyListeners();
  }

  /// 优雅停止指定实例：向进程标准输入写入 `stop`。
  ///
  /// 不在此处变更状态；进程退出后由 [_watchExit] 统一处理为已关闭。
  /// 实例保持活跃状态以供 UI 展示“强制停止”按钮。
  Future<void> stopInstance(String id) async {
    final manager = _managers[id];
    if (manager == null) return;
    await manager.stop();
  }

  /// 强制终止指定实例进程。
  ///
  /// 进程退出后由 [_watchExit] 统一处理状态翻转。
  Future<void> forceStopInstance(String id) async {
    final manager = _managers[id];
    if (manager == null) return;
    await manager.forceStop();
  }

  /// 重启指定实例：置为重启中→stop→等待退出→start→置为运行中。
  ///
  /// restart 内部的 stop→onExit 会触发旧的退出监听（因状态为重启中而被跳过），
  /// 新进程启动后需重新注册管理器并挂载新的退出监听。
  /// 若重启过程中 start 失败，重置状态为已关闭并清理管理器。
  Future<void> restartInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    final manager = _managers[id];
    if (manager == null) return;

    instance.status = InstanceStatus.restarting;
    notifyListeners();

    try {
      await manager.restart();
    } catch (e) {
      // 重启失败：重置状态为已关闭，移除并释放管理器。
      instance.status = InstanceStatus.stopped;
      _managers.remove(id);
      manager.dispose();
      notifyListeners();
      rethrow;
    }

    // restart 内部 start() 已创建新的 onExit Completer，需重新挂载监听。
    _managers[id] = manager;
    _watchExit(id, manager);

    instance.status = InstanceStatus.running;
    notifyListeners();
  }

  /// 获取指定实例的进程管理器（可空）。
  ServerProcessManager? managerFor(String id) => _managers[id];

  /// 获取指定实例的日志流（可空）。
  Stream<String>? logsFor(String id) => _managers[id]?.logs;

  /// 向指定实例的进程发送命令；进程未运行时为空操作。
  void sendCommand(String id, String command) {
    _managers[id]?.sendCommand(command);
  }
}
