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
  bool get isRunning =>
      status.toLowerCase().contains('up') || status.toLowerCase() == 'running';

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
  const VolumeInfo({required this.name, this.driver, this.mountpoint});

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
    if (memoryBytes == null ||
        memoryLimitBytes == null ||
        memoryLimitBytes == 0) {
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
    this.diskLimitMb,
    this.workdir,
    this.ip,
    this.jailType,
    this.vnetMode,
    this.vnetInterface,
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

  /// 磁盘占用上限（MB）。
  /// Docker：`--storage-opt size=`（依赖存储驱动）；Bastille：ZFS 数据集配额。
  final int? diskLimitMb;

  /// 容器内工作目录（Docker `-w`；Bastille 设置 `exec.start` 的 cwd）。
  /// 用于「数据存储目录挂载后强制工作目录」场景。
  final String? workdir;

  /// Bastille：jail 的 IP 地址（如 192.168.1.50/24）。
  /// Bastille 的 NAME / RELEASE / IP 均为显式声明参数（VNET 时须含子网掩码）。
  final String? ip;

  /// Bastille：jail 类型（thin/thick/clone/empty/linux）。
  /// 对应 `bastille create`：thin 为默认（无标志），thick=-T，clone=-C，empty=-E，linux=-L。
  final String? jailType;

  /// Bastille：VNET 模式（`bastille create` 的 -V / -B）：
  /// - `none`：不使用 VNET（默认，共享宿主网络 / NAT）
  /// - `vnet`：-V，[vnetInterface] 必须是物理网卡
  /// - `bridge`：-B，[vnetInterface] 必须是已存在的桥接网卡
  final String? vnetMode;

  /// Bastille：VNET 的 INTERFACE 位置参数（-V 时为物理网卡，-B 时为桥接网卡）。
  final String? vnetInterface;
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

/// 端口映射条目（rdr 列表）。
class PortMappingInfo {
  const PortMappingInfo({
    required this.container,
    required this.proto,
    required this.hostPort,
    required this.containerPort,
  });

  /// jail 名。
  final String container;

  /// tcp | udp。
  final String proto;

  /// 宿主机端口。
  final int hostPort;

  /// jail 内端口。
  final int containerPort;

  /// 展示字符串，如 `tcp 25565 -> 25565`。
  String get display => '$proto $hostPort -> $containerPort';
}

/// Bastille 环境初始化请求（`bastille setup`）。
///
/// 官方用法：`bastille setup [-y] [bridge|linux|loopback|netgraph|firewall|shared|storage|vnet]`。
/// 不带选项运行 = 自动配置 loopback + firewall + storage。
///
/// [mode] 对应 setup 模式：
/// - `firewall`：配置 PF 防火墙（rdr 端口转发的前提），可选 [extIf]（外网网卡）；
/// - `vnet`：配置 VNET 网络（-V），可选 [extIf]/[tunIf]/[addr]（部分版本为交互式）；
/// - `bridge`：配置桥接网卡（-B 桥接 VNET）；
/// - `shared`：将指定网卡设为共享接口（create 未指定接口时的默认），需 [extIf]；
/// - `linux`：初始化 Linuxulator（Linux Jail 前提，`bastille setup linux`）；
/// - `default`：不带选项的自动配置（loopback + firewall + storage）。
class BastilleSetupRequest {
  const BastilleSetupRequest({
    required this.mode,
    this.extIf,
    this.tunIf,
    this.addr,
  });

  /// firewall | vnet | bridge | shared | linux | default。
  final String mode;

  /// 外网网卡（firewall / vnet / shared）。
  final String? extIf;

  /// 桥接网卡名（vnet，如 bastille0）。
  final String? tunIf;

  /// 网段（vnet，如 10.99.0.0/24）。
  final String? addr;

  /// 转为节点 API 请求体。
  Map<String, dynamic> toJson() => {
    'mode': mode,
    if (extIf != null && extIf!.isNotEmpty) 'extIf': extIf,
    if (tunIf != null && tunIf!.isNotEmpty) 'tunIf': tunIf,
    if (addr != null && addr!.isNotEmpty) 'addr': addr,
  };
}

/// Bastille 初始化结果。
class BastilleSetupResult {
  const BastilleSetupResult({required this.ok, this.detail});

  final bool ok;

  /// 命令输出摘要（供 UI 展示）。
  final String? detail;
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

  /// 克隆容器 / jail（[newName] 为新名称，[ip] 为新 IP，可选）。
  ///
  /// Docker：`docker commit` + 按新名称 `docker create`；
  /// Bastille：`bastille clone <source> <newName>`（thin 克隆）。
  Future<ContainerInfo> cloneContainer(
    String idOrName, {
    required String newName,
    String? ip,
  });

  /// 容器内执行命令（用于发送 MC 控制台指令）。
  Future<void> execInContainer(String idOrName, String command);

  /// 容器日志（尾部 [tail] 行）。
  Future<String> containerLogs(String idOrName, {int? tail});

  /// 资源统计。
  Future<ContainerStats?> containerStats(String idOrName);

  /// 更新运行中容器的资源限制。
  ///
  /// Docker：`docker update -m --cpus`（磁盘上限需创建时指定，不支持热更新）；
  /// Bastille：内存 → `bastille limits <jail> add memoryuse <N>M`（rctl）；
  /// CPU 核数 → `bastille limits <jail> cpu 0..N-1`（cpuset，由服务端换算 CPU 列表）；
  /// 磁盘 → ZFS 数据集配额（`zfs set quota`，Bastille 无内建磁盘限额命令）。
  Future<void> updateContainerLimits(
    String idOrName, {
    int? memoryLimitMb,
    int? cpus,
    int? diskLimitMb,
  });

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

  // ==================== 导入 / 导出（Bastille）====================

  /// 导出容器 / jail 为归档（`bastille export`），返回宿主机上的归档路径。
  ///
  /// Docker 不支持容器归档导出（可用镜像替代），抛 [ContainerBackendException]。
  Future<String> exportContainer(String idOrName);

  /// 从归档导入容器 / jail（`bastille import [option(s)] FILE [RELEASE]`）。
  ///
  /// [archivePath] 为宿主机上的归档路径；[release] 指定导入到哪个发行版
  /// （可选，默认按归档内名称）；[force] 跳过校验和验证（-f）。
  Future<ContainerInfo> importContainer(
    String archivePath, {
    String? release,
    bool force = false,
  });

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

  /// 端口映射列表（Bastille rdr 规则；Docker 不支持热管理）。
  Future<List<PortMappingInfo>> listPortMappings();

  // ==================== 环境初始化（Bastille）====================

  /// 容器软件设置初始化（`bastille setup`）：
  /// 网络设置（firewall / vnet / bridge / shared）与 Linux Jail（linux）初始化，
  /// 以及不带选项的一键默认配置（default）。
  ///
  /// Docker 无等效命令，抛 [ContainerBackendException]。
  Future<BastilleSetupResult> setupEnvironment(BastilleSetupRequest request);
}
