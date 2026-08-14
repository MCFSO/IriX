// 远程容器后端
// 经 NodeApiClient 调 irix-node 的 /api/container/*（Docker，Linux）与
// /api/bastille/*（Bastille，FreeBSD）端点，实现 ContainerBackend 接口。
//
// 服务端按 docs/container-support.md §3 的 API 约定实现；本文件同时是
// 字段契约的唯一 Dart 侧定义（响应字段名以本文件映射为准）。
//
// MCSM 面板无 /api/container/info，能力探测失败时回退到 §6 受限端点
// （镜像列表/构建 + 容器与网络只读列表），UI 上表现为「受限模式」。

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

  @override
  Future<String> exportContainer(String idOrName) {
    throw const ContainerBackendException('Docker 不支持容器归档导出，可改用镜像保存');
  }

  @override
  Future<ContainerInfo> importContainer(
    String archivePath, {
    String? release,
    bool force = false,
  }) {
    throw const ContainerBackendException('Docker 不支持容器归档导入，可改用镜像导入');
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
  Future<void> pullImage(String name) async {
    final jobId = await client.bastilleBootstrap(name);
    if (jobId.isNotEmpty) {
      // 任务式 bootstrap：轮询发行版列表直到出现。
      var attempts = 0;
      while (attempts < 120) {
        attempts++;
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final releases = await client.bastilleReleases();
          if (releases.any(
            (r) =>
                (r['name']?.toString() ?? '').contains(name) ||
                (r['version']?.toString() ?? '').contains(name),
          )) {
            return;
          }
        } catch (_) {
          return; // 探测失败不再阻塞
        }
      }
    }
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
}
