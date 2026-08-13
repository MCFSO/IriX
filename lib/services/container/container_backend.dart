// 容器后端抽象
// 统一描述 Docker / Bastille 的容器能力，供实例管理页面使用。
// 上层 UI 只依赖本接口，不感知底层是 Docker 还是 Bastille。
//
// 实现：
// - DockerCliBackend      本地：spawn `docker` CLI（Windows/macOS/Linux）
// - NodeDockerBackend     远程：经 NodeApiClient 调 irix-node /api/container/*
// - NodeBastilleBackend   远程：经 NodeApiClient 调 irix-node /api/bastille/*
//
// 本文件为纯 Dart，不依赖 Flutter，便于单测。

/// 容器运行时类型。
enum ContainerRuntime {
  docker('Docker'),
  bastille('Bastille');

  const ContainerRuntime(this.label);

  /// 显示名称。
  final String label;

  /// 从字符串反序列化，未知值回退为 [docker]。
  static ContainerRuntime fromString(String? value) {
    if (value == 'bastille') return ContainerRuntime.bastille;
    return ContainerRuntime.docker;
  }
}

/// 容器后端异常。
class ContainerBackendException implements Exception {
  const ContainerBackendException(this.message);

  /// 错误消息。
  final String message;

  @override
  String toString() => message;
}

/// 环境信息（能力探测结果）。
class ContainerEnvironmentInfo {
  const ContainerEnvironmentInfo({
    required this.available,
    this.runtime,
    this.platform,
    this.version,
    this.errorMessage,
  });

  /// 后端是否可用（docker CLI 存在 / 节点支持）。
  final bool available;

  /// 运行时类型（可用时非空）。
  final ContainerRuntime? runtime;

  /// 节点平台（linux / freebsd / win32 / darwin）。
  final String? platform;

  /// 版本号。
  final String? version;

  /// 不可用原因。
  final String? errorMessage;
}

/// 容器信息。
class ContainerInfo {
  const ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    this.state,
    this.ports = const [],
    this.createdAt,
    this.restartPolicy,
  });

  /// 容器 id / jail 名。
  final String id;

  /// 名称。
  final String name;

  /// 镜像 / 发行版。
  final String image;

  /// 状态（running / exited / restarting / 或 Bastille 的 up/down）。
  final String status;

  /// 细粒度状态（Bastille 扩展用）。
  final String? state;

  /// 端口映射，例如 "0.0.0.0:25565->25565/tcp"。
  final List<String> ports;

  /// 创建时间。
  final DateTime? createdAt;

  /// 重启策略。
  final String? restartPolicy;

  /// 是否处于运行状态。
  bool get isRunning => status.toLowerCase().contains('up') ||
      status.toLowerCase() == 'running';

  /// 是否处于重启状态。
  bool get isRestarting => status.toLowerCase().contains('restarting');
}

/// 镜像信息。
class ImageInfo {
  const ImageInfo({
    required this.id,
    required this.tags,
    required this.sizeBytes,
    this.createdAt,
  });

  /// 镜像 id（短 id）。
  final String id;

  /// 标签列表（可能为空 —— 悬空镜像）。
  final List<String> tags;

  /// 大小（字节）。
  final int sizeBytes;

  /// 创建时间。
  final DateTime? createdAt;

  /// 主要标签，无标签时返回 `<none>`。
  String get displayTag => tags.isNotEmpty ? tags.first : '<none>';
}

/// 卷信息。
class VolumeInfo {
  const VolumeInfo({
    required this.name,
    this.driver,
    this.mountpoint,
  });

  final String name;
  final String? driver;
  final String? mountpoint;
}

/// 网络信息。
class NetworkInfo {
  const NetworkInfo({required this.name, this.driver, this.subnet});

  final String name;
  final String? driver;
  final String? subnet;
}

/// 容器资源统计。
class ContainerStats {
  const ContainerStats({
    this.cpuPercent,
    this.memoryBytes,
    this.memoryLimitBytes,
    this.netRxBytes,
    this.netTxBytes,
  });

  /// CPU 使用百分比（0~100+，多核可超 100）。
  final double? cpuPercent;

  /// 内存使用（字节）。
  final int? memoryBytes;

  /// 内存上限（字节）。
  final int? memoryLimitBytes;

  /// 内存使用百分比（0~1），无法计算时为 null。
  double? get memoryPercent {
    if (memoryBytes == null || memoryLimitBytes == null || memoryLimitBytes == 0) {
      return null;
    }
    return memoryBytes! / memoryLimitBytes!;
  }

  final int? netRxBytes;
  final int? netTxBytes;
}

/// 镜像构建任务。
class BuildJob {
  const BuildJob({required this.jobId});

  /// 任务 id，用于轮询进度。
  final String jobId;
}

/// 构建进度快照。
class BuildProgress {
  const BuildProgress({
    required this.status,
    this.log = const [],
    this.imageTag,
  });

  /// building | done | failed。
  final String status;

  /// 增量日志行。
  final List<String> log;

  /// 构建完成后的镜像标签。
  final String? imageTag;

  bool get isDone => status == 'done' || status == 'failed';
}

/// 创建容器请求。
class CreateContainerRequest {
  const CreateContainerRequest({
    required this.name,
    required this.image,
    this.command,
    this.ports = const [],
    this.volumes = const [],
    this.env = const {},
    this.restartPolicy,
    this.memoryLimitMb,
    this.cpus,
    this.ip,
    this.jailType,
    this.vnet,
  });

  /// 容器名 / jail 名。
  final String name;

  /// 镜像 / 发行版（如 `itzg/minecraft-server:latest`、`14.2-RELEASE`）。
  final String image;

  /// 启动命令（可选，覆盖镜像默认）。
  final String? command;

  /// 端口映射，例如 "25565:25565"（Bastille 经 rdr 应用）。
  final List<String> ports;

  /// 卷挂载，例如 "/host:/container"。
  final List<String> volumes;

  /// 环境变量。
  final Map<String, String> env;

  /// 重启策略（Docker）／ jail 类型（Bastille 为 thin/thick/clone/empty/linux 时见 [jailType]）。
  final String? restartPolicy;

  /// 内存上限（MB）。
  final int? memoryLimitMb;

  /// CPU 核数限制。
  final int? cpus;

  /// Bastille：jail 的 IP 地址（如 192.168.1.50/24）。
  final String? ip;

  /// Bastille：jail 类型（thin/thick/clone/empty/linux）。
  final String? jailType;

  /// Bastille：是否启用 VNET（宿主网卡 -V / 桥接 -B）。
  final bool? vnet;
}

/// 端口映射请求（Bastille rdr）。
class PortMappingRequest {
  const PortMappingRequest({
    required this.container,
    required this.proto,
    required this.hostPort,
    required this.containerPort,
  });

  final String container;
  final String proto; // tcp | udp
  final int hostPort;
  final int containerPort;
}

/// 容器后端统一接口。
abstract class ContainerBackend {
  /// 运行时类型。
  ContainerRuntime get runtime;

  /// 显示名称（'Docker' / 'Bastille'）。
  String get displayName;

  /// 是否远程后端（经节点 API）。
  bool get isRemote;

  /// 能力探测：检查后端是否可用。
  ///
  /// 不可用时 [ContainerEnvironmentInfo.available] 为 false，
  /// 并附带 [ContainerEnvironmentInfo.errorMessage] 说明原因。
  Future<ContainerEnvironmentInfo> environment();

  // ==================== 容器生命周期 ====================

  /// 容器 / jail 列表。
  Future<List<ContainerInfo>> listContainers();

  /// 创建容器 / jail（不启动）。
  Future<ContainerInfo> createContainer(CreateContainerRequest request);

  /// 启动。
  Future<void> startContainer(String idOrName);

  /// 优雅停止。
  Future<void> stopContainer(String idOrName);

  /// 重启。
  Future<void> restartContainer(String idOrName);

  /// 强制终止（Docker 为 `docker kill`；Bastille 回退为优雅停止）。
  Future<void> killContainer(String idOrName);

  /// 删除（[force] 时先强制终止）。
  Future<void> removeContainer(String idOrName, {bool force = false});

  /// 容器内执行命令（用于发送 MC 控制台指令）。
  Future<void> execInContainer(String idOrName, String command);

  /// 容器日志（尾部 [tail] 行）。
  Future<String> containerLogs(String idOrName, {int? tail});

  /// 资源统计。
  Future<ContainerStats?> containerStats(String idOrName);

  // ==================== 镜像 / 发行版 ====================

  /// 镜像 / 已 bootstrap 发行版列表。
  Future<List<ImageInfo>> listImages();

  /// 拉取镜像 / bootstrap 发行版。
  Future<void> pullImage(String name);

  /// 删除镜像。
  Future<void> removeImage(String name);

  /// 构建镜像，返回任务 id（进度经 [buildProgress] 轮询）。
  Future<BuildJob> buildImage(String dockerfile, String name, String tag);

  /// 查询构建进度。
  Future<BuildProgress> buildProgress(String jobId);

  // ==================== 卷 ====================

  /// 卷列表。
  Future<List<VolumeInfo>> listVolumes();

  /// 删除卷。
  Future<void> removeVolume(String name);

  // ==================== 网络 / 端口映射 ====================

  /// 网络列表。
  Future<List<NetworkInfo>> listNetworks();

  /// 添加端口映射（Bastille rdr；Docker 在 create 时指定）。
  Future<void> addPortMapping(PortMappingRequest request);

  /// 移除端口映射（Bastille rdr）。
  Future<void> removePortMapping(PortMappingRequest request);
}
