// 应用状态管理层
// 汇总服务器实例列表、运行状态与进程管理器，作为 UI 与持久化/进程层之间的桥梁。
// 通过 ChangeNotifier 向 UI 暴露响应式状态，所有状态变更均会通知监听者并按需持久化。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/server_cores.dart';
import '../models/server_instance.dart';
import '../services/container/container_backend.dart';
import '../services/container/docker_cli_backend.dart';
import '../services/download_settings.dart';
import '../services/instance_store.dart';
import '../services/log_persistence.dart';
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

  /// 本地 Docker 后端（惰性创建，首次 docker 实例启动时初始化）。
  DockerCliBackend? _dockerCli;

  /// Docker 实例状态轮询定时器。
  Timer? _dockerPollTimer;

  /// 当前选中的实例。
  ServerInstance? _selected;

  /// 当前选中的实例（可空）。
  ServerInstance? get selected => _selected;

  /// 本地 Docker 后端。
  DockerCliBackend get dockerCli => _dockerCli ??= DockerCliBackend();

  /// 探测本地 Docker 是否可用（供 UI 判断是否展示容器功能）。
  Future<ContainerEnvironmentInfo> dockerEnvironment() =>
      dockerCli.environment();

  /// 计算实例的 Docker 容器名：
  /// 优先取 [ContainerConfig.containerName]，否则由实例名净化 + id 后缀派生，
  /// 保证合法且唯一（docker 名称仅允许 [a-zA-Z0-9_.-]）。
  String containerNameFor(ServerInstance instance) {
    final configured = instance.container?.containerName;
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }
    final base = instance.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final suffix = instance.id.length >= 4
        ? instance.id.substring(instance.id.length - 4)
        : instance.id;
    return 'xmc-${base.isEmpty ? 'server' : base}-$suffix';
  }

  /// 由实例生成容器创建请求（卷默认挂载实例根目录到 /data）。
  CreateContainerRequest _containerRequestFor(ServerInstance instance) {
    final cfg = instance.container ?? const ContainerConfig();
    final volumes = cfg.volumes.isNotEmpty
        ? cfg.volumes
        : <String>['${instance.rootPath}:/data'];
    return CreateContainerRequest(
      name: containerNameFor(instance),
      image: cfg.image,
      ports: cfg.ports,
      volumes: volumes,
      env: cfg.env,
      restartPolicy: cfg.restartPolicy,
      memoryLimitMb: cfg.memoryLimitMb,
      cpus: cfg.cpus,
      diskLimitMb: cfg.diskLimitMb,
      workdir: cfg.workdir,
    );
  }

  /// 确保 Docker 状态轮询定时器运行（每 5 秒同步容器状态到实例状态）。
  void _ensureDockerPolling() {
    if (_dockerPollTimer != null) return;
    _dockerPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pollDockerStatuses());
    });
  }

  /// 轮询所有 Docker 实例的容器状态，同步到 [InstanceStatus]。
  Future<void> _pollDockerStatuses() async {
    try {
      final env = await dockerCli.environment();
      if (!env.available) return;
      final containers = await dockerCli.listContainers();
      var changed = false;
      for (final instance in _instances) {
        if (instance.runMode != RunMode.docker) continue;
        final name = containerNameFor(instance);
        final info = containers.where((c) => c.name == name).firstOrNull;
        final running = info?.isRunning ?? false;
        if (!running && instance.status.isActive) {
          instance.status = InstanceStatus.stopped;
          changed = true;
        } else if (running && instance.status == InstanceStatus.stopped) {
          instance.status = InstanceStatus.running;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {
      // 轮询失败静默忽略，下轮重试
    }
  }

  /// 下载线程数 (1-32)，控制多线程分片断点续传下载的并发数。
  int _downloadThreads = DownloadSettings.defaultThreads;

  /// 下载线程数 (只读视图)。
  int get downloadThreads => _downloadThreads;

  /// 设置当前选中的实例，变更后通知监听者。
  set selected(ServerInstance? value) {
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
  }

  /// 生成实例唯一标识：微秒时间戳的 36 进制串 + 随机后缀。
  String _generateId() {
    final random = Random();
    final suffix = random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  /// 按 id 查找内存中的实例。
  ServerInstance? _instanceById(String id) {
    for (final instance in _instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// 初始化：从持久化层加载实例列表与全局设置。
  ///
  /// 加载后实例状态均为 [InstanceStatus.stopped]（由反序列化处理）。
  /// 不在此处创建进程管理器；管理器在 [startInstance] 时按需创建。
  Future<void> init() async {
    _instances = await _store.loadInstances();
    _downloadThreads = await DownloadSettings.getThreads();
    notifyListeners();
  }

  /// 设置下载线程数并持久化。
  ///
  /// 自动 clamp 到 [DownloadSettings.minThreads] - [DownloadSettings.maxThreads]。
  Future<void> setDownloadThreads(int threads) async {
    final clamped = threads.clamp(
      DownloadSettings.minThreads,
      DownloadSettings.maxThreads,
    );
    if (_downloadThreads == clamped) return;
    _downloadThreads = clamped;
    await DownloadSettings.setThreads(clamped);
    notifyListeners();
  }

  /// 创建一个通过"导入目录"方式的实例。
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

  /// 创建一个通过"选择本地核心文件"方式的实例。
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

  /// 创建一个通过"下载核心"方式的实例。
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
      await manager.forceStop();
      manager.dispose();
    }
    // Docker 实例：尽力删除对应容器（容器不可达时忽略）。
    if (instance != null && instance.runMode == RunMode.docker) {
      try {
        await dockerCli.removeContainer(containerNameFor(instance), force: true);
      } catch (_) {}
    }
    await _store.removeInstance(id);
    _instances.removeWhere((e) => e.id == id);
    if (_selected?.id == id) {
      _selected = null;
    }
    if (deleteFiles && instance != null && instance.rootPath.isNotEmpty) {
      try {
        final dir = Directory(instance.rootPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (_) {}
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
    selected = _instanceById(id);
  }

  /// 为指定实例挂载进程退出监听。
  ///
  /// 当进程自然退出时，将实例状态置为 [InstanceStatus.stopped]、
  /// 移除并释放对应管理器，然后通知监听者。
  /// 在重启过程中（状态为 [InstanceStatus.restarting]）跳过处理，
  /// 由 [restartInstance] 在重启结束后重新挂载监听。
  void _watchExit(String id, ServerProcessManager manager) {
    final captured = manager;
    unawaited(
      captured.onExit.then((code) {
        final instance = _instanceById(id);
        if (instance == null) return;
        if (instance.status == InstanceStatus.restarting) {
          return;
        }
        instance.status = InstanceStatus.stopped;
        if (_managers[id] == captured) {
          _managers.remove(id);
          captured.dispose();
        }
        LogPersistence.instance.stopWatching(id);
        notifyListeners();
      }),
    );
  }

  /// 启动指定实例。
  ///
  /// 原生实例：按需创建 [ServerProcessManager]，置为启动中→启动进程→置为运行中，
  /// 并挂载退出监听；进程启动失败（如 java 未找到）时重置状态为已关闭并清理管理器。
  /// Docker 实例：容器不存在则先按 [ContainerConfig] 创建，再 `docker start`，
  /// 状态经 [_ensureDockerPolling] 轮询同步。
  Future<void> startInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    if (instance.status.isActive ||
        instance.status == InstanceStatus.restarting) {
      return;
    }

    if (instance.runMode == RunMode.docker) {
      await _startDockerInstance(instance);
      return;
    }

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
      instance.status = InstanceStatus.stopped;
      _managers.remove(id);
      manager.dispose();
      notifyListeners();
      rethrow;
    }

    LogPersistence.instance.startWatching(id, manager.logs);
    _watchExit(id, manager);

    instance.status = InstanceStatus.running;
    notifyListeners();
  }

  /// 以 Docker 容器方式启动实例：探测可用性 → 建容器（如需）→ 启动。
  Future<void> _startDockerInstance(ServerInstance instance) async {
    final env = await dockerCli.environment();
    if (!env.available) {
      throw ContainerBackendException(
        'Docker 不可用：${env.errorMessage ?? '未检测到 docker CLI，请先安装并启动 Docker'}',
      );
    }
    instance.status = InstanceStatus.starting;
    notifyListeners();
    try {
      final name = containerNameFor(instance);
      final containers = await dockerCli.listContainers();
      if (!containers.any((c) => c.name == name)) {
        await dockerCli.createContainer(_containerRequestFor(instance));
      }
      await dockerCli.startContainer(name);
      instance.status = InstanceStatus.running;
    } catch (e) {
      instance.status = InstanceStatus.stopped;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
    _ensureDockerPolling();
  }

  /// 优雅停止指定实例。
  ///
  /// 原生实例：向进程标准输入写入 `stop`，状态由 [_watchExit] 统一处理。
  /// Docker 实例：`docker stop`（优雅关停），状态由轮询器同步。
  /// 不在此处变更状态，实例保持活跃状态以供 UI 展示"强制停止"按钮。
  Future<void> stopInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    if (instance.runMode == RunMode.docker) {
      await dockerCli.stopContainer(containerNameFor(instance));
      return;
    }
    final manager = _managers[id];
    if (manager == null) return;
    await manager.stop();
  }

  /// 强制终止指定实例。
  ///
  /// 原生实例：`kill` 进程；Docker 实例：`docker kill`。
  /// 状态由 [_watchExit] / 轮询器统一翻转。
  Future<void> forceStopInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    if (instance.runMode == RunMode.docker) {
      await dockerCli.killContainer(containerNameFor(instance));
      return;
    }
    final manager = _managers[id];
    if (manager == null) return;
    await manager.forceStop();
  }

  /// 重启指定实例。
  ///
  /// 原生实例：置为重启中→stop→等待退出→start→置为运行中；
  /// restart 内部的 stop→onExit 会触发旧的退出监听（因状态为重启中而被跳过），
  /// 新进程启动后需重新注册管理器并挂载新的退出监听。
  /// Docker 实例：`docker restart`，状态由轮询器同步。
  /// 若重启过程中 start 失败，重置状态为已关闭并清理管理器。
  Future<void> restartInstance(String id) async {
    final instance = _instanceById(id);
    if (instance == null) return;

    if (instance.runMode == RunMode.docker) {
      instance.status = InstanceStatus.restarting;
      notifyListeners();
      try {
        await dockerCli.restartContainer(containerNameFor(instance));
        instance.status = InstanceStatus.running;
      } catch (e) {
        instance.status = InstanceStatus.stopped;
        notifyListeners();
        rethrow;
      }
      notifyListeners();
      return;
    }

    final manager = _managers[id];
    if (manager == null) return;

    instance.status = InstanceStatus.restarting;
    notifyListeners();

    try {
      await manager.restart();
    } catch (e) {
      instance.status = InstanceStatus.stopped;
      _managers.remove(id);
      manager.dispose();
      notifyListeners();
      rethrow;
    }

    _managers[id] = manager;
    _watchExit(id, manager);

    instance.status = InstanceStatus.running;
    notifyListeners();
  }

  /// 更新实例运行方式（原生 / Docker）并持久化。
  ///
  /// 切换到 Docker 时 [container] 为空则沿用现有配置或默认配置；
  /// 切换回原生时保留容器配置（便于用户再次切换）。
  Future<void> updateRunMode(
    String id,
    RunMode runMode,
    ContainerConfig? container,
  ) async {
    final instance = _instanceById(id);
    if (instance == null) return;
    instance.runMode = runMode;
    if (runMode == RunMode.docker) {
      instance.container = container ?? instance.container ?? ContainerConfig();
    }
    await _store.updateRunMode(id, instance.runMode, instance.container);
    notifyListeners();
  }

  /// 获取指定实例的进程管理器（可空）。
  ServerProcessManager? managerFor(String id) => _managers[id];

  /// 获取指定实例的日志流（可空）。
  ///
  /// Docker 实例返回基于 `docker logs` 轮询的流（每 2 秒取尾部增量）。
  Stream<String>? logsFor(String id) {
    final instance = _instanceById(id);
    if (instance == null) return null;
    if (instance.runMode == RunMode.docker) {
      return _dockerLogsStream(instance);
    }
    return _managers[id]?.logs;
  }

  /// Docker 日志轮询流：每 2 秒拉取容器日志尾部，只发出增量行。
  Stream<String> _dockerLogsStream(ServerInstance instance) {
    final name = containerNameFor(instance);
    var first = true;
    var watermark = '';
    return Stream.periodic(const Duration(seconds: 2), (_) => name)
        .asyncExpand((n) async* {
      try {
        final log = await dockerCli.containerLogs(n, tail: 200);
        final lines = log
            .split('\n')
            .map((e) => e.trimRight())
            .where((e) => e.isNotEmpty)
            .toList();
        if (lines.isEmpty) return;
        if (first) {
          first = false;
          watermark = lines.last;
          for (final line in lines) {
            yield line;
          }
          return;
        }
        final idx = lines.indexOf(watermark);
        final start = idx >= 0 ? idx + 1 : 0;
        if (start < lines.length) {
          watermark = lines.last;
          for (final line in lines.sublist(start)) {
            yield line;
          }
        }
      } catch (_) {
        // 容器不可达（未创建/已删除）时静默等待
      }
    });
  }

  /// 释放所有管理器资源。
  @override
  void dispose() {
    LogPersistence.instance.dispose();
    _dockerPollTimer?.cancel();
    for (final manager in _managers.values) {
      manager.dispose();
    }
    _managers.clear();
    super.dispose();
  }

  /// 向指定实例发送命令。
  ///
  /// 原生实例：写入进程标准输入；Docker 实例：`docker exec` 到容器内执行。
  /// 进程/容器未运行时为空操作。
  void sendCommand(String id, String command) {
    final instance = _instanceById(id);
    if (instance == null) return;
    if (instance.runMode == RunMode.docker) {
      unawaited(
        dockerCli
            .execInContainer(containerNameFor(instance), command)
            .catchError((_) {
          // 容器不可达时忽略
        }),
      );
      return;
    }
    _managers[id]?.sendCommand(command);
  }
}
