// 远程容器后端
// 经 NodeApiClient 调 irix-node 的 /api/container/*（Docker，Linux）与
// /api/bastille/*（Bastille，FreeBSD）端点，实现 ContainerBackend 接口。
//
// 服务端按 docs/container-support.md §3 的 API 约定实现；本文件同时是
// 字段契约的唯一 Dart 侧定义（响应字段名以本文件映射为准）。
//
// MCSM 面板无 /api/container/info，能力探测失败时回退到 §6 受限端点
// （镜像列表/构建 + 容器与网络只读列表），UI 上表现为「受限模式」。

import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../node_api_client.dart';
import 'container_backend.dart';

/// 按平台提示创建节点容器后端：
/// - [platformHint] 为 `freebsd` → Bastille 后端；
/// - 其余（linux / win32 / 未知）→ Docker 后端（irix-node 全功能，MCSM 自动回退受限模式）。
///
/// 最终运行时类型以 `GET /api/container/info` 的探测结果为准（面板内二次校验）。
ContainerBackend nodeContainerBackend({
  required NodeApiClient client,
  required String daemonId,
  String? platformHint,
}) {
  final platform = platformHint?.toLowerCase() ?? '';
  if (platform == 'freebsd') {
    return NodeBastilleBackend(client: client, daemonId: daemonId);
  }
  return NodeDockerBackend(client: client, daemonId: daemonId);
}

/// 基于 NodeApiClient 的远程容器后端（Docker / Bastille 共用逻辑基座）。
abstract class NodeContainerBackend implements ContainerBackend {
  NodeContainerBackend({required this.client, required this.daemonId});

  /// 节点 API 客户端。
  final NodeApiClient client;

  /// 守护进程 id（MCSM 面板多守护进程；irix-node 取 overview.remote 首个）。
  final String daemonId;

  /// 受限模式（MCSM 面板无 /api/container/info）：仅镜像构建与只读列表，
  /// 归档导出 / 导入等写入型能力不可用。
  @override
  bool get supportsArchiveTransfer => !restricted;

  /// Docker 节点无 Bastille 模板能力（由 [NodeBastilleBackend] 覆盖）。
  @override
  bool get supportsJailTemplates => false;

  @override
  Future<List<JailTemplate>> listJailTemplates() {
    throw const ContainerBackendException('jail 模板仅适用于 Bastille（bastille template）');
  }

  @override
  Future<String> applyJailTemplate(
    String idOrName,
    String template, {
    Map<String, String> args = const {},
  }) {
    throw const ContainerBackendException('jail 模板仅适用于 Bastille（bastille template）');
  }

  /// 长任务日志进度（GET /api/bastille/jobs/{jobId}）。
  ///
  /// 该端点在 irix-node 中读取的是**全局长任务表**（container.go 的
  /// `jobs`），镜像构建、Bastille bootstrap、模板应用共用同一张表，
  /// 因此 Docker / Bastille 两种运行时都可用。
  @override
  Future<JobLogProgress> jobProgress(String jobId) async {
    final progress = await client.bastilleJobProgress(jobId);
    return JobLogProgress(status: progress.status, log: progress.log);
  }

  /// 是否受限模式（MCSM 面板回退）。
  bool restricted = false;

  /// 环境缓存。
  ContainerEnvironmentInfo? _cachedEnvironment;

  /// 能力探测（各子类实现自己的探测逻辑）。
  Future<ContainerEnvironmentInfo> probe();

  @override
  Future<ContainerEnvironmentInfo> environment() async {
    if (_cachedEnvironment != null) return _cachedEnvironment!;
    _cachedEnvironment = await probe();
    return _cachedEnvironment!;
  }

  /// 清除环境缓存。
  void invalidateEnvironment() => _cachedEnvironment = null;
}

/// 远程 Docker 后端（irix-node / MCSM 面板）。
class NodeDockerBackend extends NodeContainerBackend {
  NodeDockerBackend({required super.client, required super.daemonId});

  @override
  ContainerRuntime get runtime => ContainerRuntime.docker;

  @override
  String get displayName => 'Docker';

  @override
  bool get isRemote => true;

  @override
  Future<ContainerEnvironmentInfo> probe() async {
    try {
      final info = await client.containerInfo();
      if (info != null) {
        return ContainerEnvironmentInfo(
          available: info['available'] as bool? ?? true,
          runtime: ContainerRuntime.fromString(info['runtime'] as String?),
          platform: info['platform'] as String?,
          version: info['version'] as String?,
          errorMessage: info['error'] as String?,
        );
      }
    } catch (_) {
      // irix-node 端点缺失 → 尝试 MCSM 受限端点
    }
    try {
      // MCSM §6：无 /api/container/info，探测镜像接口确认可用。
      await client.listImages(daemonId);
      restricted = true;
      return ContainerEnvironmentInfo(
        available: true,
        runtime: ContainerRuntime.docker,
        platform: null,
        version: null,
        errorMessage: 'MCSM 受限模式：仅镜像构建与只读列表',
      );
    } catch (_) {
      return const ContainerEnvironmentInfo(
        available: false,
        runtime: ContainerRuntime.docker,
        errorMessage: '节点不支持 Docker 环境',
      );
    }
  }

  // ==================== 生命周期 ====================

  @override
  Future<List<ContainerInfo>> listContainers() async {
    if (restricted) {
      // MCSM §6 容器列表（只读）。
      final rows = await client.listContainers(daemonId);
      return rows.map(_containerFromMcsm).toList();
    }
    final rows = await client.containerPs();
    return rows.map(_containerFromJson).toList();
  }

  ContainerInfo _containerFromJson(Map<String, dynamic> json) {
    return ContainerInfo(
      id: (json['id'] as String? ?? '').substring(0, 12),
      name: json['name'] as String? ?? '',
      image: json['image'] as String? ?? '',
      status: json['status'] as String? ?? '',
      state: json['state'] as String?,
      ports: (json['ports'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      restartPolicy: json['restartPolicy'] as String?,
    );
  }

  /// MCSM §6 容器条目字段映射（面板返回的键不确定，尽量兼容）。
  ContainerInfo _containerFromMcsm(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? json['Names']?.toString() ?? '';
    return ContainerInfo(
      id: json['id']?.toString() ?? json['Id']?.toString() ?? name,
      name: name,
      image: json['image']?.toString() ?? json['Image']?.toString() ?? '',
      status: json['status']?.toString() ?? json['State']?.toString() ?? '',
      state: json['State']?.toString(),
      ports: json['ports'] is List
          ? (json['ports'] as List).map((e) => e.toString()).toList()
          : [json['Ports']?.toString()].whereType<String>().toList(),
    );
  }

  @override
  Future<ContainerInfo> createContainer(CreateContainerRequest request) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持创建容器');
    }
    await client.containerCreate({
      'name': request.name,
      'image': request.image,
      'command': request.command,
      'ports': request.ports,
      'volumes': request.volumes,
      'env': request.env,
      'restartPolicy': request.restartPolicy,
      'memoryLimitMb': request.memoryLimitMb,
      'cpus': request.cpus,
      'diskLimitMb': request.diskLimitMb,
      'workdir': request.workdir,
    });
    return ContainerInfo(
      id: request.name,
      name: request.name,
      image: request.image,
      status: 'created',
      state: 'created',
    );
  }

  @override
  Future<void> startContainer(String idOrName) =>
      client.containerAction(idOrName, 'start');

  @override
  Future<void> stopContainer(String idOrName) =>
      client.containerAction(idOrName, 'stop');

  @override
  Future<void> restartContainer(String idOrName) =>
      client.containerAction(idOrName, 'restart');

  @override
  Future<void> killContainer(String idOrName) =>
      client.containerAction(idOrName, 'kill');

  @override
  Future<void> removeContainer(String idOrName, {bool force = false}) =>
      client.containerRemove(idOrName, force: force);

  @override
  Future<ContainerInfo> cloneContainer(
    String idOrName, {
    required String newName,
    String? ip,
  }) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持克隆容器');
    }
    await client.containerClone(idOrName, newName);
    return ContainerInfo(
      id: newName,
      name: newName,
      image: '',
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
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持资源限制');
    }
    if (diskLimitMb != null && diskLimitMb > 0) {
      throw const ContainerBackendException('Docker 磁盘上限需在创建容器时指定，不支持热更新');
    }
    await client.containerUpdateLimits(
      idOrName,
      memoryMb: memoryLimitMb,
      cpus: cpus,
    );
  }

  @override
  Future<void> execInContainer(String idOrName, String command) =>
      client.containerExec(idOrName, command);

  @override
  Future<String> containerLogs(String idOrName, {int? tail}) =>
      client.containerLogs(idOrName, tail: tail);

  @override
  Future<ContainerStats?> containerStats(String idOrName) async {
    try {
      final stats = await client.containerStats(idOrName);
      if (stats == null) return null;
      return ContainerStats(
        cpuPercent: (stats['cpuPercent'] as num?)?.toDouble(),
        memoryBytes: (stats['memoryBytes'] as num?)?.toInt(),
        memoryLimitBytes: (stats['memoryLimitBytes'] as num?)?.toInt(),
        netRxBytes: (stats['netRxBytes'] as num?)?.toInt(),
        netTxBytes: (stats['netTxBytes'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  // ==================== 镜像 ====================

  @override
  Future<List<ImageInfo>> listImages() async {
    if (restricted) {
      final rows = await client.listImages(daemonId);
      return rows.map(_imageFromMcsm).toList();
    }
    final rows = await client.imageList();
    return rows.map(_imageFromJson).toList();
  }

  ImageInfo _imageFromJson(Map<String, dynamic> json) {
    return ImageInfo(
      id: json['id'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? []).whereType<String>().toList(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  ImageInfo _imageFromMcsm(Map<String, dynamic> json) {
    return ImageInfo(
      id: json['id']?.toString() ?? json['Id']?.toString() ?? '',
      tags: [json['tag']?.toString() ?? json['Tag']?.toString() ?? '<none>'],
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> pullImage(String name) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持拉取镜像');
    }
    await client.imagePull(name);
  }

  @override
  Future<void> removeImage(String name) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持删除镜像');
    }
    await client.imageRemove(name);
  }

  @override
  Future<BuildJob> buildImage(
    String dockerfile,
    String name,
    String tag,
  ) async {
    final String jobId;
    if (restricted) {
      // MCSM 构建为同步发起，进度按镜像名查询。
      await client.createImage(
        daemonId: daemonId,
        dockerFile: dockerfile,
        name: name,
        tag: tag,
      );
      jobId = name;
    } else {
      jobId = await client.imageBuild(
        dockerfile: dockerfile,
        name: name,
        tag: tag,
      );
    }
    return BuildJob(jobId: jobId.isEmpty ? name : jobId);
  }

  @override
  Future<BuildProgress> buildProgress(String jobId) async {
    final Map<String, dynamic>? progress;
    if (restricted) {
      final map = await client.buildProgress(daemonId);
      // MCSM 进度键为镜像名，值为 -1/1/2。
      final statusCode = map[jobId] ?? map.values.firstOrNull ?? -1;
      progress = {
        'status': switch (statusCode) {
          1 => 'building',
          2 => 'done',
          _ => 'failed',
        },
        'log': <String>[],
        'image': jobId,
      };
    } else {
      progress = await client.imageBuildProgress(jobId);
    }
    if (progress == null) {
      return const BuildProgress(status: 'failed', log: ['构建进度不可用']);
    }
    return BuildProgress(
      status: progress['status'] as String? ?? 'building',
      log: (progress['log'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      imageTag: progress['image'] as String?,
    );
  }

  // ==================== 卷 / 网络 ====================

  @override
  Future<List<VolumeInfo>> listVolumes() async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持卷管理');
    }
    final rows = await client.volumeList();
    return rows.map((json) {
      return VolumeInfo(
        name: json['name'] as String? ?? '',
        driver: json['driver'] as String?,
        mountpoint: json['mountpoint'] as String?,
      );
    }).toList();
  }

  @override
  Future<void> removeVolume(String name) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持卷管理');
    }
    await client.volumeRemove(name);
  }

  @override
  Future<List<NetworkInfo>> listNetworks() async {
    final rows = restricted
        ? await client.listNetworks(daemonId)
        : await client.networkList();
    return rows.map((json) {
      return NetworkInfo(
        name: json['name']?.toString() ?? json['Name']?.toString() ?? '',
        driver: json['driver']?.toString() ?? json['Driver']?.toString(),
        subnet: json['subnet']?.toString(),
      );
    }).toList();
  }

  @override
  Future<void> addPortMapping(PortMappingRequest request) {
    throw const ContainerBackendException('Docker 端口映射在创建容器时指定');
  }

  @override
  Future<void> removePortMapping(PortMappingRequest request) {
    throw const ContainerBackendException('Docker 端口映射在创建容器时指定');
  }

  @override
  Future<List<PortMappingInfo>> listPortMappings() {
    throw const ContainerBackendException('Docker 端口映射不可热管理，请查看容器列表的端口列');
  }

  @override
  Future<BastilleSetupResult> setupEnvironment(BastilleSetupRequest request) {
    throw const ContainerBackendException(
      'bastille setup 仅适用于 Bastille，Docker 无需初始化网络设置',
    );
  }

  // ==================== Bastille 专属（Docker 无等效能力）====================

  @override
  Future<String> execOutput(String idOrName, String command) {
    throw const ContainerBackendException(
      'execOutput 仅适用于 Bastille（bastille cmd）',
    );
  }

  @override
  Future<String> runPkg(String idOrName, String action, List<String> packages) {
    throw const ContainerBackendException('软件包管理仅适用于 Bastille（bastille pkg）');
  }

  @override
  Future<List<JailMount>> listJailMounts(String idOrName) {
    throw const ContainerBackendException('挂载管理仅适用于 Bastille（bastille mount）');
  }

  @override
  Future<void> addJailMount(
    String idOrName, {
    String? src,
    required String dst,
    required String fstype,
    String? options,
    bool permanent = false,
  }) {
    throw const ContainerBackendException('挂载管理仅适用于 Bastille（bastille mount）');
  }

  @override
  Future<void> removeJailMount(String idOrName, String dst) {
    throw const ContainerBackendException('挂载管理仅适用于 Bastille（bastille umount）');
  }

  @override
  Future<JailFileList> listJailFiles(
    String idOrName, {
    String path = '/',
    int page = 1,
    int pageSize = 200,
  }) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<String> readJailFile(String idOrName, String path) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<void> writeJailFile(String idOrName, String path, String content) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<void> deleteJailFile(String idOrName, String path) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<void> jailMkdir(String idOrName, String path) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<void> jailTouch(String idOrName, String path) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<void> uploadJailFile(String idOrName, String dir, String localPath) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<List<int>> downloadJailFile(String idOrName, String path) {
    throw const ContainerBackendException('Jail 文件管理仅适用于 Bastille');
  }

  @override
  Future<Map<String, String>> getJailConfig(String idOrName) {
    throw const ContainerBackendException(
      'jail 设置编辑仅适用于 Bastille（bastille config）',
    );
  }

  @override
  Future<void> setJailConfig(String idOrName, String key, String value) {
    throw const ContainerBackendException(
      'jail 设置编辑仅适用于 Bastille（bastille config）',
    );
  }

  @override
  Future<void> removeJailConfig(String idOrName, String key) {
    throw const ContainerBackendException(
      'jail 设置编辑仅适用于 Bastille（bastille config）',
    );
  }

  @override
  Future<String> startJailRun(
    String idOrName, {
    required String command,
    String? cwd,
    bool watch = false,
  }) {
    throw const ContainerBackendException('容器内运行仅适用于 Bastille（bastille cmd）');
  }

  @override
  Future<JailRunStatus> jailRunStatus(
    String idOrName,
    String sessionId, {
    int? tail,
    int? since,
  }) {
    throw const ContainerBackendException('容器内运行仅适用于 Bastille（bastille cmd）');
  }

  @override
  Future<void> jailRunStdin(String idOrName, String sessionId, String input) {
    throw const ContainerBackendException('容器内运行仅适用于 Bastille（bastille cmd）');
  }

  @override
  Future<void> stopJailRun(String idOrName, String sessionId) {
    throw const ContainerBackendException('容器内运行仅适用于 Bastille（bastille cmd）');
  }

  @override
  Future<void> cleanupJailRun(String idOrName, String sessionId) {
    throw const ContainerBackendException('容器内运行仅适用于 Bastille（bastille cmd）');
  }

  // ==================== 导入 / 导出（容器归档 → 镜像）====================

  /// 导出容器为本地归档（irix-node `POST /api/container/{id}/export`）。
  ///
  /// 链路：
  /// ① 服务端执行 `docker export` 把容器写成 tar 落在节点同步区 `.exports/`，
  ///    并返回**目录范围下载票据**（`{password, addr, fileName}`）；
  /// ② 用票据直连 `/download/{password}/.exports/xxx.tar` 下载到本机
  ///    容器归档目录（Rust 下载器，多线程）。
  ///
  /// 返回本地归档路径 —— 与 Bastille 后端返回宿主机归档路径的语义一致：
  /// 调用方拿到的是「可直接用于 [importContainer] 的归档路径」。
  @override
  Future<String> exportContainer(String idOrName) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持容器导出');
    }
    final ticket = await client.containerExport(idOrName);
    if (ticket.password.isEmpty || ticket.fileName.isEmpty) {
      throw const ContainerBackendException('节点未返回导出票据（容器不存在或导出失败）');
    }
    final dir = Directory(await AppPaths.instance.containerExportsRoot());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final localPath = p.join(dir.path, p.basename(ticket.fileName));
    try {
      // 归档可能很大：走直连票据 + 多线程分片下载，progress 不做 UI 展示。
      await client.directDownloadToFile(ticket, localPath, (_, _) {}, threads: 4);
    } catch (e) {
      throw ContainerBackendException('容器导出下载失败: $e');
    }
    return localPath;
  }

  /// 从本地归档导入镜像并创建容器。
  ///
  /// irix-node 的 `POST /api/image/import` 语义是「**同步区归档** → `docker
  /// import`」，因此归档必须先进入节点同步区：
  /// ① 申请同步区上传票据（`POST /api/cluster/files/upload`，`upload_dir=/`）；
  /// ② 直连上传（`POST /upload/{password}`，multipart 字段 `file`）；
  /// ③ `POST /api/image/import` 导入为镜像；
  /// ④ 用该镜像创建容器并返回（与 Bastille 导入直接产出 jail 的语义对齐）。
  ///
  /// [release] 在 Docker 后端下语义为**目标镜像名**（可含 tag），留空时由
  /// 归档文件名推导；[force] 无对应语义（Docker 导入不做校验和验证）。
  @override
  Future<ContainerInfo> importContainer(
    String archivePath, {
    String? release,
    bool force = false,
  }) async {
    if (restricted) {
      throw const ContainerBackendException('MCSM 受限模式不支持镜像导入');
    }
    final file = File(archivePath);
    if (!await file.exists()) {
      throw ContainerBackendException('归档不存在: $archivePath');
    }
    final fileName = p.basename(archivePath);
    final imageName = (release != null && release.trim().isNotEmpty)
        ? release.trim()
        : _imageNameFrom(fileName);

    // ① + ② 上传到节点同步区根目录（image/import 以同步区为根解析 fileName）。
    try {
      final ticket = await client.clusterUploadTicket('');
      await client.directUpload(ticket: ticket, localPath: archivePath);
    } on NodeApiException catch (e) {
      throw ContainerBackendException('归档上传到节点同步区失败: ${e.message}');
    }

    // ③ docker import。
    try {
      await client.imageImport(fileName: fileName, name: imageName);
    } on NodeApiException catch (e) {
      throw ContainerBackendException('镜像导入失败: ${e.message}');
    }

    // ④ 用导入的镜像创建容器，返回可管理的容器对象。
    return createContainer(
      CreateContainerRequest(name: _containerNameFrom(imageName), image: imageName),
    );
  }

  /// 由归档文件名推导镜像名：去扩展名，清理非法字符（镜像名仅允许
  /// 小写字母 / 数字 / `.` `_` `-` `/` `:`）。
  static String _imageNameFrom(String fileName) {
    final base = p.basenameWithoutExtension(fileName).toLowerCase();
    final cleaned = base.replaceAll(RegExp(r'[^a-z0-9._\-/]'), '-');
    return cleaned.isEmpty ? 'imported-image:latest' : cleaned;
  }

  /// 由镜像名推导容器名（去掉 tag，附时间后缀避免重名）。
  static String _containerNameFrom(String imageName) {
    final repo = imageName.split(':').first;
    final short = repo.split('/').last.replaceAll(RegExp(r'[^a-zA-Z0-9_.\-]'), '-');
    final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${short.isEmpty ? 'container' : short}-$suffix';
  }
}

/// 远程 Bastille 后端（irix-node,FreeBSD）。
class NodeBastilleBackend extends NodeContainerBackend {
  NodeBastilleBackend({required super.client, required super.daemonId});

  @override
  ContainerRuntime get runtime => ContainerRuntime.bastille;

  @override
  String get displayName => 'Bastille';

  @override
  bool get isRemote => true;

  @override
  Future<ContainerEnvironmentInfo> probe() async {
    try {
      final info = await client.containerInfo();
      if (info != null) {
        return ContainerEnvironmentInfo(
          available: info['available'] as bool? ?? true,
          runtime: ContainerRuntime.fromString(info['runtime'] as String?),
          platform: info['platform'] as String?,
          version: info['version'] as String?,
          errorMessage: info['error'] as String?,
        );
      }
    } catch (_) {}
    return const ContainerEnvironmentInfo(
      available: false,
      runtime: ContainerRuntime.bastille,
      errorMessage: '节点不支持 Bastille 环境',
    );
  }

  // ==================== 生命周期 ====================

  @override
  Future<List<ContainerInfo>> listContainers() async {
    final rows = await client.bastilleJails();
    return rows.map((json) {
      return ContainerInfo(
        id: json['name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        image: json['release'] as String? ?? json['image'] as String? ?? '',
        status: json['status'] as String? ?? '',
        state: json['state'] as String?,
        ports: (json['ports'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  Future<ContainerInfo> createContainer(CreateContainerRequest request) async {
    await client.bastilleJailCreate({
      'name': request.name,
      'release': request.image,
      'ip': request.ip,
      'type': request.jailType ?? request.restartPolicy ?? 'thin',
      'vnet': request.vnetMode,
      'interface': request.vnetInterface,
      'volumes': request.volumes,
      'workdir': request.workdir,
      'memoryLimitMb': request.memoryLimitMb,
      'cpus': request.cpus,
      'diskLimitMb': request.diskLimitMb,
    });
    // Bastille 端口映射在创建后经 rdr 应用。
    for (final port in request.ports) {
      final match = RegExp(r'^(\d+):(\d+)$').firstMatch(port);
      if (match == null) continue;
      await client.bastilleRdr(
        jail: request.name,
        proto: 'tcp',
        hostPort: int.parse(match.group(1)!),
        jailPort: int.parse(match.group(2)!),
      );
    }
    return ContainerInfo(
      id: request.name,
      name: request.name,
      image: request.image,
      status: 'created',
      state: 'created',
    );
  }

  @override
  Future<void> startContainer(String idOrName) =>
      client.bastilleJailAction(idOrName, 'start');

  @override
  Future<void> stopContainer(String idOrName) =>
      client.bastilleJailAction(idOrName, 'stop');

  @override
  Future<void> restartContainer(String idOrName) =>
      client.bastilleJailAction(idOrName, 'restart');

  @override
  Future<void> killContainer(String idOrName) =>
      client.bastilleJailAction(idOrName, 'stop');

  @override
  Future<void> removeContainer(String idOrName, {bool force = false}) async {
    // bastille destroy 摧毁运行中的 jail 需 -a（--auto）：
    // force=true 时经 query 参数下发，服务端执行 `bastille destroy -y [-a] <jail>`。
    await client.bastilleJailAction(idOrName, 'destroy', force: force);
  }

  @override
  Future<ContainerInfo> cloneContainer(
    String idOrName, {
    required String newName,
    String? ip,
  }) async {
    await client.bastilleJailClone(jail: idOrName, newName: newName, ip: ip);
    return ContainerInfo(
      id: newName,
      name: newName,
      image: '',
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
    await client.bastilleJailLimits(
      idOrName,
      memoryMb: memoryLimitMb,
      cpus: cpus,
      diskMb: diskLimitMb,
    );
  }

  @override
  Future<void> execInContainer(String idOrName, String command) =>
      client.bastilleJailCmd(idOrName, command);

  @override
  Future<String> containerLogs(String idOrName, {int? tail}) =>
      client.bastilleJailConsole(idOrName, tail: tail);

  @override
  Future<ContainerStats?> containerStats(String idOrName) async => null;

  // ==================== 镜像 / 模板 ====================

  /// Bastille 支持 jail 模板（`bastille template`）。
  @override
  bool get supportsJailTemplates => true;

  /// 节点上可用的模板（GET /api/bastille/templates，模板目录树 NAMESPACE/NAME）。
  @override
  Future<List<JailTemplate>> listJailTemplates() async {
    final rows = await client.bastilleTemplates();
    return rows.map(JailTemplate.fromJson).toList();
  }

  /// 应用模板到 jail（POST /api/bastille/templates/apply），返回长任务 id。
  ///
  /// [args] 由服务端以 `KEY=VALUE` 注入模板进程环境变量；进度用
  /// [jobProgress] 轮询（模板脚本可能耗时较久）。
  @override
  Future<String> applyJailTemplate(
    String idOrName,
    String template, {
    Map<String, String> args = const {},
  }) async {
    final jobId = await client.bastilleTemplateApply(
      jail: idOrName,
      template: template,
      args: args,
    );
    if (jobId.isEmpty) {
      throw const ContainerBackendException('节点未返回模板任务 id');
    }
    return jobId;
  }

  @override
  Future<List<ImageInfo>> listImages() async {
    final rows = await client.bastilleReleases();
    return rows.map((json) {
      return ImageInfo(
        id: json['name'] as String? ?? '',
        tags: ['${json['name']}:${json['version'] ?? 'RELEASE'}'],
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
    }).toList();
  }

  @override
  /// bootstrap 发行版（`bastille bootstrap`）。
  ///
  /// 服务端以长任务执行并返回 jobId：用 `GET /api/bastille/jobs/{jobId}`
  /// 轮询真实状态与日志 —— 失败时立即抛出并带回日志尾部（旧实现只轮询
  /// 发行版列表，失败要等到 120 次超时才结束且丢失原因）。
  @override
  Future<void> pullImage(String name) async {
    final jobId = await client.bastilleBootstrap(name);
    if (jobId.isEmpty) {
      return; // 服务端未返回任务 id：视为已提交，交由列表刷新确认。
    }
    // bootstrap 需拉取发行版，耗时可能到分钟级：最多轮询 300 次 × 2s。
    for (var attempt = 0; attempt < 300; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      JobLogProgress progress;
      try {
        progress = await jobProgress(jobId);
      } catch (_) {
        // 任务表已过期 / 节点短暂不可用：回退到列表探测，不再阻塞。
        return;
      }
      if (progress.isDone) return;
      if (progress.isFailed) {
        final tail = progress.tailLog(8);
        throw ContainerBackendException(
          tail.isEmpty ? 'bootstrap $name 失败' : 'bootstrap $name 失败:\n$tail',
        );
      }
    }
    throw ContainerBackendException('bootstrap $name 超时（任务仍在运行）');
  }

  @override
  Future<void> removeImage(String name) async {
    throw const ContainerBackendException('Bastille 不支持删除已 bootstrap 的发行版');
  }

  @override
  Future<BuildJob> buildImage(String dockerfile, String name, String tag) {
    throw const ContainerBackendException(
      'Bastille 使用模板而非镜像构建：请用 Bastillefile（见模板管理）',
    );
  }

  @override
  Future<BuildProgress> buildProgress(String jobId) {
    throw const ContainerBackendException('Bastille 无镜像构建任务');
  }

  // ==================== 卷 / 网络 ====================

  @override
  Future<List<VolumeInfo>> listVolumes() async {
    throw const ContainerBackendException('Bastille 挂载经 MOUNT 模板管理');
  }

  @override
  Future<void> removeVolume(String name) async {
    throw const ContainerBackendException('Bastille 挂载经 MOUNT 模板管理');
  }

  @override
  Future<List<NetworkInfo>> listNetworks() async {
    throw const ContainerBackendException('Bastille 网络经 jail 配置管理');
  }

  @override
  Future<void> addPortMapping(PortMappingRequest request) => client.bastilleRdr(
    jail: request.container,
    proto: request.proto,
    hostPort: request.hostPort,
    jailPort: request.containerPort,
  );

  @override
  Future<void> removePortMapping(PortMappingRequest request) =>
      client.bastilleRdrRemove(
        jail: request.container,
        proto: request.proto,
        hostPort: request.hostPort,
        jailPort: request.containerPort,
      );

  @override
  Future<List<PortMappingInfo>> listPortMappings() async {
    final rows = await client.bastilleRdrList();
    return rows.map((json) {
      return PortMappingInfo(
        container: json['jail']?.toString() ?? '',
        proto: json['proto']?.toString() ?? 'tcp',
        hostPort: (json['hostPort'] as num?)?.toInt() ?? 0,
        containerPort: (json['jailPort'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  // ==================== 导入 / 导出 ====================

  @override
  Future<String> exportContainer(String idOrName) =>
      client.bastilleJailExport(idOrName);

  @override
  Future<ContainerInfo> importContainer(
    String archivePath, {
    String? release,
    bool force = false,
  }) async {
    final name = await client.bastilleJailImport(
      file: archivePath,
      release: release,
      force: force,
    );
    return ContainerInfo(
      id: name,
      name: name,
      image: release ?? '',
      status: 'created',
      state: 'created',
    );
  }

  // ==================== 环境初始化（bastille setup）====================

  @override
  Future<BastilleSetupResult> setupEnvironment(
    BastilleSetupRequest request,
  ) async {
    final result = await client.bastilleSetup(request.toJson());
    return BastilleSetupResult(
      ok: result?['ok'] as bool? ?? true,
      detail: result?['detail'] as String?,
    );
  }

  // ==================== Bastille 专属（jail 内运行 / 软件包 / 挂载 / 设置）====================

  @override
  Future<String> execOutput(String idOrName, String command) =>
      client.bastilleJailCmdOutput(idOrName, command);

  @override
  Future<String> runPkg(
    String idOrName,
    String action,
    List<String> packages,
  ) => client.bastilleJailPkg(idOrName, action: action, packages: packages);

  @override
  Future<List<JailMount>> listJailMounts(String idOrName) async {
    final rows = await client.bastilleJailMounts(idOrName);
    return rows.map((json) {
      return JailMount(
        dst: json['dst']?.toString() ?? '',
        src: json['src']?.toString(),
        fstype: json['fstype']?.toString() ?? 'nullfs',
        options: json['options']?.toString(),
        permanent: json['permanent'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<void> addJailMount(
    String idOrName, {
    String? src,
    required String dst,
    required String fstype,
    String? options,
    bool permanent = false,
  }) => client.bastilleJailMountAdd(
    idOrName,
    src: src,
    dst: dst,
    fstype: fstype,
    options: options,
    permanent: permanent,
  );

  @override
  Future<void> removeJailMount(String idOrName, String dst) =>
      client.bastilleJailMountRemove(idOrName, dst);

  // ==================== Jail 文件管理 ====================

  @override
  Future<JailFileList> listJailFiles(
    String idOrName, {
    String path = '/',
    int page = 1,
    int pageSize = 200,
  }) async {
    final data = await client.bastilleJailFiles(
      idOrName,
      path: path,
      page: page,
      pageSize: pageSize,
    );
    return JailFileList.fromJson(data);
  }

  @override
  Future<String> readJailFile(String idOrName, String path) =>
      client.bastilleJailFileContent(idOrName, path);

  @override
  Future<void> writeJailFile(String idOrName, String path, String content) =>
      client.writeBastilleJailFile(idOrName, path, content);

  @override
  Future<void> deleteJailFile(String idOrName, String path) =>
      client.deleteBastilleJailFile(idOrName, path);

  @override
  Future<void> jailMkdir(String idOrName, String path) =>
      client.bastilleJailMkdir(idOrName, path);

  @override
  Future<void> jailTouch(String idOrName, String path) =>
      client.bastilleJailTouch(idOrName, path);

  @override
  Future<void> uploadJailFile(String idOrName, String dir, String localPath) =>
      client.bastilleJailFileUpload(idOrName, dir, localPath);

  @override
  Future<List<int>> downloadJailFile(String idOrName, String path) =>
      client.bastilleJailFileDownload(idOrName, path);

  @override
  Future<Map<String, String>> getJailConfig(String idOrName) async {
    final config = await client.bastilleJailConfig(idOrName);
    return config.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  @override
  Future<void> setJailConfig(String idOrName, String key, String value) =>
      client.bastilleJailConfigSet(idOrName, key, value);

  @override
  Future<void> removeJailConfig(String idOrName, String key) =>
      client.bastilleJailConfigRemove(idOrName, key);

  @override
  Future<String> startJailRun(
    String idOrName, {
    required String command,
    String? cwd,
    bool watch = false,
  }) => client.bastilleJailRun(
    idOrName,
    command: command,
    cwd: cwd,
    watch: watch,
  );

  @override
  Future<JailRunStatus> jailRunStatus(
    String idOrName,
    String sessionId, {
    int? tail,
    int? since,
  }) async {
    final status = await client.bastilleJailRunStatus(
      idOrName,
      sessionId,
      tail: tail,
      since: since,
    );
    if (status == null) {
      return JailRunStatus(running: false, exitCode: null, log: '');
    }
    return JailRunStatus(
      running: status['running'] as bool? ?? false,
      exitCode: (status['exitCode'] as num?)?.toInt(),
      offset: (status['offset'] as num?)?.toInt() ?? 0,
      log: status['log']?.toString() ?? '',
    );
  }

  @override
  Future<void> jailRunStdin(String idOrName, String sessionId, String input) =>
      client.bastilleJailRunStdin(idOrName, sessionId, input);

  @override
  Future<void> stopJailRun(String idOrName, String sessionId) =>
      client.bastilleJailRunStop(idOrName, sessionId);

  @override
  Future<void> cleanupJailRun(String idOrName, String sessionId) =>
      client.bastilleJailRunCleanup(idOrName, sessionId);
}
