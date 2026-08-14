// 本地 Docker 后端
// 通过 spawn `docker` CLI 实现 ContainerBackend（Windows/macOS/Linux 通用）。
// 命令输出统一加 `--format '{{json .}}'` 逐行解析为 JSON。
//
// 本文件为纯 Dart（仅 dart:io），不依赖 Flutter，便于单测：
// DockerCli 的 run 函数可注入 fake，测试仅验证参数组装与输出解析。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'container_backend.dart';

/// docker CLI 进程结果（含退出码）。
typedef DockerRunResult = ({int exitCode, String stdout, String stderr});

/// docker 命令执行函数签名，便于测试注入。
///
/// [timeout] 为可空：闭包实现可省略，由 [DockerCli.run] 兜底为默认超时。
typedef DockerCommandRunner =
    Future<DockerRunResult> Function(
      List<String> args, {
      String? stdin,
      Duration? timeout,
    });

/// 低层 docker CLI 封装：参数组装 + JSON 行解析。
class DockerCli {
  DockerCli({this.runner, this.dockerBinary = 'docker'});

  /// 命令执行器（默认走 Process.run，测试时注入 fake）。
  final DockerCommandRunner? runner;

  /// docker 可执行文件名/路径。
  final String dockerBinary;

  /// 默认超时：普通命令 30s，构建等长任务不设限。
  static const Duration _timeout = Duration(seconds: 30);

  /// 执行 docker 命令；退出码非 0 时抛出 [ContainerBackendException]。
  Future<DockerRunResult> run(
    List<String> args, {
    String? stdin,
    bool check = true,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _timeout;
    final result =
        await (runner?.call(args, stdin: stdin, timeout: effectiveTimeout) ??
            _runProcess(args, stdin: stdin, timeout: effectiveTimeout));
    if (check && result.exitCode != 0) {
      final err = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      throw ContainerBackendException('docker ${args.join(' ')} 失败：$err');
    }
    return result;
  }

  Future<DockerRunResult> _runProcess(
    List<String> args, {
    String? stdin,
    required Duration timeout,
  }) async {
    final process = await Process.start(dockerBinary, args);
    if (stdin != null) {
      process.stdin.write(stdin);
    }
    await process.stdin.close();
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(timeout);
    return (exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  /// 解析 `--format '{{json .}}'` 输出为对象列表（每行一个 JSON）。
  List<Map<String, dynamic>> parseJsonLines(String stdout) {
    final result = <Map<String, dynamic>>[];
    for (final line in LineSplitter.split(stdout)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } catch (_) {
        // 忽略无法解析的行（如警告输出）
      }
    }
    return result;
  }
}

/// 本地 Docker 容器后端。
///
/// 通过 [environment] 探测 docker CLI 可用性；不可用时所有操作抛异常，
/// UI 层应根据 [environment] 的 available 决定是否展示容器功能。
class DockerCliBackend implements ContainerBackend {
  DockerCliBackend({DockerCli? cli}) : _cli = cli ?? DockerCli();

  final DockerCli _cli;

  /// 本地 CLI 后端，非远程。
  @override
  bool get isRemote => false;

  @override
  ContainerRuntime get runtime => ContainerRuntime.docker;

  @override
  String get displayName => 'Docker';

  /// 环境缓存（环境探测一次，避免每次页面进入都 spawn 进程）。
  ContainerEnvironmentInfo? _cachedEnvironment;

  /// 构建任务表：jobId → 任务状态。
  static final Map<String, _LocalBuildTask> _buildTasks = {};

  @override
  Future<ContainerEnvironmentInfo> environment() async {
    if (_cachedEnvironment != null) return _cachedEnvironment!;
    try {
      final result = await _cli.run([
        'version',
        '--format',
        '{{json .}}',
      ], timeout: const Duration(seconds: 5));
      final serverRows = _cli.parseJsonLines(result.stdout);
      final server = serverRows.isNotEmpty ? serverRows.last['Server'] : null;
      final version = server is Map
          ? (server['Version']?.toString() ??
                (server['ApiVersion']?.toString()))
          : null;
      _cachedEnvironment = ContainerEnvironmentInfo(
        available: result.exitCode == 0 && server != null,
        runtime: ContainerRuntime.docker,
        platform: _hostPlatform(),
        version: version,
        errorMessage: result.exitCode == 0 && server == null
            ? 'Docker 服务未运行，请先启动 Docker Desktop'
            : null,
      );
    } catch (e) {
      _cachedEnvironment = ContainerEnvironmentInfo(
        available: false,
        runtime: ContainerRuntime.docker,
        platform: _hostPlatform(),
        errorMessage: '未检测到 Docker CLI：$e',
      );
    }
    return _cachedEnvironment!;
  }

  /// 清除环境缓存（docker 安装/启动状态变化后重新探测）。
  void invalidateEnvironment() => _cachedEnvironment = null;

  String _hostPlatform() {
    if (Platform.isWindows) return 'win32';
    if (Platform.isMacOS) return 'darwin';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  // ==================== 生命周期 ====================

  @override
  Future<List<ContainerInfo>> listContainers() async {
    final result = await _cli.run(['ps', '-a', '--format', '{{json .}}']);
    return _cli.parseJsonLines(result.stdout).map(_containerFromJson).toList();
  }

  ContainerInfo _containerFromJson(Map<String, dynamic> json) {
    return ContainerInfo(
      id: (json['Id'] as String? ?? '').substring(0, 12),
      name: _firstJsonListString(json['Names']) ?? '',
      image: json['Image'] as String? ?? '',
      status: json['Status'] as String? ?? '',
      state: json['State'] as String? ?? '',
      ports: (json['Ports'] as String? ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      createdAt: _parseJsonDate(json['CreatedAt']),
    );
  }

  @override
  Future<ContainerInfo> createContainer(CreateContainerRequest request) async {
    final args = <String>['create'];
    if (request.name.isNotEmpty) {
      args.addAll(['--name', request.name]);
    }
    for (final port in request.ports) {
      args.addAll(['-p', port]);
    }
    for (final volume in request.volumes) {
      args.addAll(['-v', volume]);
    }
    request.env.forEach((key, value) => args.addAll(['-e', '$key=$value']));
    if (request.restartPolicy != null && request.restartPolicy!.isNotEmpty) {
      args.addAll(['--restart', request.restartPolicy!]);
    }
    if (request.memoryLimitMb != null && request.memoryLimitMb! > 0) {
      args.addAll(['-m', '${request.memoryLimitMb}m']);
    }
    if (request.cpus != null && request.cpus! > 0) {
      args.addAll(['--cpus', '${request.cpus}']);
    }
    if (request.diskLimitMb != null && request.diskLimitMb! > 0) {
      // 依赖存储驱动支持（overlay2 on xfs / devicemapper 等），不支持时 docker 报错。
      args.addAll(['--storage-opt', 'size=${request.diskLimitMb}m']);
    }
    if (request.workdir != null && request.workdir!.trim().isNotEmpty) {
      args.addAll(['-w', request.workdir!.trim()]);
    }
    args.add(request.image);
    if (request.command != null && request.command!.trim().isNotEmpty) {
      args.addAll(request.command!.trim().split(RegExp(r'\s+')));
    }
    await _cli.run(args);
    return ContainerInfo(
      id: request.name,
      name: request.name,
      image: request.image,
      status: 'created',
      state: 'created',
    );
  }

  @override
  Future<void> startContainer(String idOrName) async {
    await _cli.run(['start', idOrName]);
  }

  @override
  Future<void> stopContainer(String idOrName) async {
    await _cli.run(['stop', idOrName], timeout: const Duration(seconds: 60));
  }

  @override
  Future<void> restartContainer(String idOrName) async {
    await _cli.run(['restart', idOrName], timeout: const Duration(seconds: 60));
  }

  @override
  Future<void> killContainer(String idOrName) async {
    await _cli.run(['kill', idOrName], timeout: const Duration(seconds: 30));
  }

  @override
  Future<void> removeContainer(String idOrName, {bool force = false}) async {
    await _cli.run([
      'rm',
      if (force) '-f',
      idOrName,
    ], timeout: const Duration(seconds: 60));
  }

  @override
  Future<ContainerInfo> cloneContainer(
    String idOrName, {
    required String newName,
    String? ip,
  }) async {
    // Docker 无原生 clone：commit 当前容器状态为临时镜像，再按新名称创建。
    final tag =
        'xmc-clone-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    await _cli.run(['commit', idOrName, '$newName:$tag']);
    await _cli.run(['create', '--name', newName, '$newName:$tag']);
    return ContainerInfo(
      id: newName,
      name: newName,
      image: '$newName:$tag',
      status: 'created',
      state: 'created',
    );
  }

  @override
  Future<void> updateContainerLimits(
    String idOrName, {
    int? memoryLimitMb,
    int? cpus,
    int? diskLimitMb,
  }) async {
    if (diskLimitMb != null && diskLimitMb > 0) {
      throw const ContainerBackendException(
        'Docker 磁盘上限需在创建容器时通过 --storage-opt 指定，不支持热更新',
      );
    }
    final hasMemory = memoryLimitMb != null && memoryLimitMb > 0;
    final hasCpus = cpus != null && cpus > 0;
    if (!hasMemory && !hasCpus) return;
    await _cli.run([
      'update',
      if (hasMemory) '-m',
      if (hasMemory) '${memoryLimitMb}m',
      if (hasCpus) '--cpus',
      if (hasCpus) '$cpus',
      idOrName,
    ], timeout: const Duration(seconds: 60));
  }

  @override
  Future<void> execInContainer(String idOrName, String command) async {
    if (command.trim().isEmpty) return;
    // 经 sh -c 执行，避免命令中的空格/管道被拆散。
    await _cli.run(['exec', idOrName, 'sh', '-c', command]);
  }

  @override
  Future<String> containerLogs(String idOrName, {int? tail}) async {
    final result = await _cli.run([
      'logs',
      if (tail != null) '--tail',
      if (tail != null) '$tail',
      idOrName,
    ]);
    return result.stdout;
  }

  @override
  Future<ContainerStats?> containerStats(String idOrName) async {
    try {
      final result = await _cli.run([
        'stats',
        '--no-stream',
        '--format',
        '{{json .}}',
        idOrName,
      ], timeout: const Duration(seconds: 10));
      final rows = _cli.parseJsonLines(result.stdout);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final memUsage = _parseMemory(row['MemUsage']?.toString());
      final netIo = _parseNetBytes(row['NetIO']?.toString());
      return ContainerStats(
        cpuPercent: _parsePercent(row['CPUPerc']),
        memoryBytes: memUsage.$1,
        memoryLimitBytes: memUsage.$2,
        netRxBytes: netIo.$1,
        netTxBytes: netIo.$2,
      );
    } on ContainerBackendException {
      return null; // 容器未运行等场景静默返回 null
    }
  }

  // ==================== 镜像 ====================

  @override
  Future<List<ImageInfo>> listImages() async {
    final result = await _cli.run(['images', '--format', '{{json .}}']);
    return _cli.parseJsonLines(result.stdout).map((json) {
      return ImageInfo(
        id: (json['Id'] as String? ?? '').substring(0, 12),
        tags: [
          if ((json['Repository'] as String? ?? '').isNotEmpty)
            '${json['Repository']}:${json['Tag'] ?? 'latest'}',
        ],
        sizeBytes: _parseSizeBytes(json['Size']),
        createdAt: _parseJsonDate(json['CreatedAt']),
      );
    }).toList();
  }

  @override
  Future<void> pullImage(String name) async {
    await _cli.run(['pull', name], timeout: const Duration(minutes: 10));
  }

  @override
  Future<void> removeImage(String name) async {
    await _cli.run(['rmi', name]);
  }

  @override
  Future<BuildJob> buildImage(
    String dockerfile,
    String name,
    String tag,
  ) async {
    final jobId =
        'build-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final task = _LocalBuildTask();
    _buildTasks[jobId] = task;
    // 后台执行：stdin 提供 Dockerfile（等价 MCSM 的 dockerFile 构建）。
    unawaited(_runBuildInBackground(jobId, dockerfile, name, tag));
    return BuildJob(jobId: jobId);
  }

  Future<void> _runBuildInBackground(
    String jobId,
    String dockerfile,
    String name,
    String tag,
  ) async {
    final task = _buildTasks[jobId]!;
    try {
      final process = await Process.start('docker', [
        'build',
        '-t',
        '$name:$tag',
        '-',
      ]);
      process.stdin.write(dockerfile);
      await process.stdin.close();
      // 并发消费 stdout/stderr，避免管道写满导致死锁。
      await Future.wait([
        _collectLines(process.stdout, task.log),
        _collectLines(process.stderr, task.log),
      ]);
      final code = await process.exitCode;
      task.status = code == 0 ? 'done' : 'failed';
      task.imageTag = '$name:$tag';
    } catch (e) {
      task.status = 'failed';
      task.log.add('构建异常：$e');
    } finally {
      // 任务完成后保留日志一段时间，便于 UI 轮询读取。
      Timer(const Duration(minutes: 5), () => _buildTasks.remove(jobId));
    }
  }

  Future<void> _collectLines(
    Stream<List<int>> stream,
    List<String> target,
  ) async {
    await for (final chunk in stream.transform(utf8.decoder)) {
      for (final line in LineSplitter.split(chunk)) {
        if (line.trim().isNotEmpty) {
          target.add(line);
        }
      }
    }
  }

  @override
  Future<BuildProgress> buildProgress(String jobId) async {
    final task = _buildTasks[jobId];
    if (task == null) {
      return const BuildProgress(status: 'failed', log: ['任务不存在或已过期']);
    }
    return BuildProgress(
      status: task.status,
      log: List<String>.of(task.log),
      imageTag: task.imageTag,
    );
  }

  // ==================== 卷 / 网络 ====================

  @override
  Future<List<VolumeInfo>> listVolumes() async {
    final result = await _cli.run(['volume', 'ls', '--format', '{{json .}}']);
    return _cli.parseJsonLines(result.stdout).map((json) {
      return VolumeInfo(
        name: json['Name'] as String? ?? '',
        driver: json['Driver'] as String?,
        mountpoint: json['Mountpoint'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> removeVolume(String name) async {
    await _cli.run(['volume', 'rm', name]);
  }

  @override
  Future<List<NetworkInfo>> listNetworks() async {
    final result = await _cli.run(['network', 'ls', '--format', '{{json .}}']);
    return _cli.parseJsonLines(result.stdout).map((json) {
      return NetworkInfo(
        name: json['Name'] as String? ?? '',
        driver: json['Driver'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> addPortMapping(PortMappingRequest request) {
    throw ContainerBackendException('Docker 端口映射在创建容器时通过 -p 指定');
  }

  @override
  Future<void> removePortMapping(PortMappingRequest request) {
    throw ContainerBackendException('Docker 端口映射在创建容器时通过 -p 指定');
  }

  @override
  Future<List<PortMappingInfo>> listPortMappings() {
    throw ContainerBackendException('Docker 端口映射不可热管理，请查看容器列表的端口列');
  }

  // ==================== Bastille 专属能力（Docker 无等效命令）====================

  @override
  Future<BastilleSetupResult> setupEnvironment(BastilleSetupRequest request) {
    throw ContainerBackendException(
      'bastille setup 仅适用于 Bastille，Docker 无需初始化网络设置',
    );
  }

  @override
  Future<String> exportContainer(String idOrName) {
    throw ContainerBackendException(
      'Docker 不支持容器归档导出，可改用镜像保存（docker commit/push）',
    );
  }

  @override
  Future<ContainerInfo> importContainer(
    String archivePath, {
    String? release,
    bool force = false,
  }) {
    throw ContainerBackendException('Docker 不支持容器归档导入，可改用镜像导入（docker load）');
  }

  // ==================== 解析工具 ====================

  /// 取 JSON 数组字段的首个字符串元素（docker ps Names）。
  String? _firstJsonListString(dynamic value) {
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  DateTime? _parseJsonDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// 解析 "1.23%" → 1.23。
  double? _parsePercent(String? raw) {
    if (raw == null) return null;
    final value = double.tryParse(raw.replaceAll('%', '').trim());
    return value;
  }

  /// 解析 "123MiB / 2GiB" → (使用, 上限) 字节数。
  (int?, int?) _parseMemory(String? raw) {
    if (raw == null) return (null, null);
    final parts = raw.split('/').map((e) => e.trim()).toList();
    if (parts.isEmpty) return (null, null);
    final used = _parseByteSize(parts.first);
    final limit = parts.length > 1 ? _parseByteSize(parts[1]) : null;
    return (used, limit);
  }

  /// 解析 "1.5kB / 2.3MB" → (rx, tx) 字节数。
  (int?, int?) _parseNetBytes(String? raw) {
    if (raw == null) return (null, null);
    final parts = raw.split('/').map((e) => e.trim()).toList();
    if (parts.isEmpty) return (null, null);
    return (_parseByteSize(parts.first), _parseByteSize(parts.last));
  }

  /// 解析 "1.23GiB" / "512MiB" / "1.5kB" → 字节数。
  int? _parseByteSize(String raw) {
    final match = RegExp(r'^([\d.]+)\s*([a-zA-Z]*)').firstMatch(raw.trim());
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    final unit = match.group(2)?.toLowerCase() ?? '';
    final multiplier = switch (unit) {
      'kb' || 'k' => 1000,
      'mb' || 'm' => 1000 * 1000,
      'gb' || 'g' => 1000 * 1000 * 1000,
      'tb' || 't' => 1000 * 1000 * 1000 * 1000,
      'kib' => 1024,
      'mib' => 1024 * 1024,
      'gib' => 1024 * 1024 * 1024,
      'tib' => 1024 * 1024 * 1024 * 1024,
      'b' => 1,
      _ => 1,
    };
    return (value * multiplier).round();
  }

  /// 解析镜像 Size 字符串 "123MB" 或 "1.23GB"。
  int _parseSizeBytes(dynamic raw) {
    if (raw is num) return raw.toInt();
    return _parseByteSize(raw?.toString() ?? '') ?? 0;
  }
}

/// 本地构建任务状态。
class _LocalBuildTask {
  _LocalBuildTask();

  /// building | done | failed。
  String status = 'building';

  /// 累计输出行。
  final List<String> log = [];

  /// 完成后的镜像标签。
  String? imageTag;
}
