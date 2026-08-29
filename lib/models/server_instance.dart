// 服务器实例数据模型
// 定义 Minecraft 服务器实例的核心数据结构、运行状态枚举与持久化序列化逻辑。
// 本文件为纯 Dart 模型，不依赖 Flutter，仅使用 dart:convert 完成 JSON 编解码。

import 'dart:convert';

import '../services/locale_settings.dart';

/// 实例的运行方式。
///
/// - [native]：原生进程（java 直接运行，默认）。
/// - [docker]：运行在 Docker 容器中，启停 / 控制台走容器运行时。
enum RunMode {
  native('原生进程', 'Native process'),
  docker('Docker 容器', 'Docker container');

  const RunMode(this.labelZh, this.labelEn);

  /// 中文展示标签。
  final String labelZh;

  /// 英文展示标签。
  final String labelEn;

  /// 展示标签（随语言设置切换）。
  String get label =>
      LocaleSettings.instance.localeCode == 'en' ? labelEn : labelZh;

  /// 从数据库 / JSON 字符串反序列化，未知值回退为 [native]。
  static RunMode fromString(String? value) {
    for (final mode in RunMode.values) {
      if (mode.name == value) return mode;
    }
    return RunMode.native;
  }
}

/// Docker 容器运行配置（[ServerInstance.runMode] 为 [RunMode.docker] 时生效）。
///
/// 纯数据对象，序列化逻辑与 [ServerInstance] 保持一致。
class ContainerConfig {
  /// 容器镜像，例如 `itzg/minecraft-server:latest`。
  final String image;

  /// 容器名称；为 null 时由实例名派生。
  final String? containerName;

  /// 端口映射，例如 `["25565:25565"]`（宿主机端口:容器端口）。
  final List<String> ports;

  /// 卷挂载，例如 `["/path/to/instance:/data"]`。
  /// 为空时运行期默认挂载 `<实例根目录>:/data`。
  final List<String> volumes;

  /// 环境变量。
  final Map<String, String> env;

  /// 重启策略：`no` | `on-failure[:N]` | `always` | `unless-stopped`。
  final String? restartPolicy;

  /// 内存上限（MB），对应 `-m`。
  final int? memoryLimitMb;

  /// CPU 限制（核数），对应 `--cpus`。
  final int? cpus;

  /// 磁盘占用上限（MB），对应 `--storage-opt size=`（依赖存储驱动）。
  final int? diskLimitMb;

  /// 容器内工作目录（`-w`）。用于「数据目录挂载后强制工作目录」：
  /// 实例目录挂载到 /data 时设 `/data`，保证服务端进程在数据目录内启动。
  final String? workdir;

  const ContainerConfig({
    this.image = 'itzg/minecraft-server:latest',
    this.containerName,
    this.ports = const ['25565:25565'],
    this.volumes = const [],
    this.env = const {},
    this.restartPolicy,
    this.memoryLimitMb,
    this.cpus,
    this.diskLimitMb,
    this.workdir,
  });

  /// 序列化为 JSON 字符串。
  String toJson() => jsonEncode({
    'image': image,
    'containerName': containerName,
    'ports': ports,
    'volumes': volumes,
    'env': env,
    'restartPolicy': restartPolicy,
    'memoryLimitMb': memoryLimitMb,
    'cpus': cpus,
    'diskLimitMb': diskLimitMb,
    'workdir': workdir,
  });

  /// 从 JSON 反序列化；字段缺失时使用默认值，保证旧数据兼容。
  ///
  /// 注意：ports 字段缺失（`{}` 等旧数据）时回退到默认映射 `['25565:25565']`；
  /// 显式存了空列表表示用户清空了端口。
  factory ContainerConfig.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return ContainerConfig(
      image: map['image'] as String? ?? 'itzg/minecraft-server:latest',
      containerName: map['containerName'] as String?,
      ports: map.containsKey('ports')
          ? (map['ports'] as List<dynamic>).whereType<String>().toList()
          : const ['25565:25565'],
      volumes: (map['volumes'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      env: (map['env'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      restartPolicy: map['restartPolicy'] as String?,
      memoryLimitMb: (map['memoryLimitMb'] as num?)?.toInt(),
      cpus: (map['cpus'] as num?)?.toInt(),
      diskLimitMb: (map['diskLimitMb'] as num?)?.toInt(),
      workdir: map['workdir'] as String?,
    );
  }

  /// 复制并覆盖部分字段。
  ContainerConfig copyWith({
    String? image,
    String? containerName,
    List<String>? ports,
    List<String>? volumes,
    Map<String, String>? env,
    String? restartPolicy,
    int? memoryLimitMb,
    int? cpus,
    int? diskLimitMb,
    String? workdir,
    bool clearContainerName = false,
    bool clearRestartPolicy = false,
    bool clearMemory = false,
    bool clearCpus = false,
    bool clearDiskLimit = false,
    bool clearWorkdir = false,
  }) {
    return ContainerConfig(
      image: image ?? this.image,
      containerName: clearContainerName
          ? null
          : (containerName ?? this.containerName),
      ports: ports ?? this.ports,
      volumes: volumes ?? this.volumes,
      env: env ?? this.env,
      restartPolicy: clearRestartPolicy
          ? null
          : (restartPolicy ?? this.restartPolicy),
      memoryLimitMb: clearMemory ? null : (memoryLimitMb ?? this.memoryLimitMb),
      cpus: clearCpus ? null : (cpus ?? this.cpus),
      diskLimitMb: clearDiskLimit ? null : (diskLimitMb ?? this.diskLimitMb),
      workdir: clearWorkdir ? null : (workdir ?? this.workdir),
    );
  }

  /// 校验配置合法性，返回错误消息；合法时返回 null。
  String? validate() {
    final en = LocaleSettings.instance.localeCode == 'en';
    if (image.trim().isEmpty) {
      return en ? 'Image cannot be empty' : '镜像不能为空';
    }
    for (final port in ports) {
      if (!RegExp(
        r'^(\d+(-\d+)?)(:(\d+(-\d+)?))?(/(tcp|udp))?$',
      ).hasMatch(port)) {
        return en
            ? 'Invalid port mapping: $port (expected host:container)'
            : '端口映射格式错误：$port（应为 宿主机:容器端口）';
      }
    }
    for (final volume in volumes) {
      if (!volume.contains(':')) {
        return en
            ? 'Invalid volume mount: $volume (expected hostPath:containerPath)'
            : '卷挂载格式错误：$volume（应为 宿主机路径:容器路径）';
      }
    }
    return null;
  }
}

/// 服务器实例的运行状态枚举。
///
/// 对应实例卡片上展示的四种状态标签：
/// - 启动中：服务器正在执行启动流程
/// - 运行中：服务器已正常启动并运行
/// - 重启中：服务器正在执行关闭并重新启动的流程
/// - 已关闭：服务器当前未运行
enum InstanceStatus {
  /// 启动中：服务器正在执行启动流程。
  starting,

  /// 运行中：服务器已正常启动并运行。
  running,

  /// 重启中：服务器正在关闭并重新启动。
  restarting,

  /// 已关闭：服务器当前未运行。
  stopped;

  /// 状态的展示标签（随语言设置切换）。
  ///
  /// [starting] 显示"启动中"，[running] 显示"运行中"，
  /// 便于用户区分服务器是正在启动还是已成功运行。
  String get label {
    final en = LocaleSettings.instance.localeCode == 'en';
    return switch (this) {
      InstanceStatus.starting => en ? 'Starting' : '启动中',
      InstanceStatus.running => en ? 'Running' : '运行中',
      InstanceStatus.restarting => en ? 'Restarting' : '重启中',
      InstanceStatus.stopped => en ? 'Stopped' : '已关闭',
    };
  }

  /// 服务器是否处于活跃（启动中或运行中）状态。
  ///
  /// 用于判断“启动/重启/停止”按钮的可用性等场景。
  bool get isActive =>
      this == InstanceStatus.starting || this == InstanceStatus.running;
}

/// Minecraft 服务器实例数据模型。
///
/// 描述单个服务器实例的核心信息：根目录、核心文件、启动命令等。
/// 该模型为纯数据对象，不包含任何进程管理或 IO 逻辑。
class ServerInstance {
  /// 实例唯一标识。
  final String id;

  /// 实例名称（可变，便于后续重命名）。
  String name;

  /// 服务器根目录路径。
  String rootPath;

  /// 核心 .jar 文件路径（可为相对或绝对路径）。
  String coreFilePath;

  /// 完整启动命令字符串，例如 'java -Xmx2G -jar server.jar nogui'。
  String startCommand;

  /// 服务端核心类型，例如 'Paper'、'Vanilla'。
  /// 对于通过“导入目录”方式创建的实例可能为 null。
  String? coreType;

  /// 服务端核心版本，例如 '1.20.1'。
  /// 对于通过“导入目录”方式创建的实例可能为 null。
  String? coreVersion;

  /// 运行方式：原生进程或 Docker 容器。
  RunMode runMode;

  /// Docker 容器配置（[runMode] 为 [RunMode.docker] 时有效）。
  ContainerConfig? container;

  /// 当前运行状态（可变，默认为 [InstanceStatus.stopped]）。
  ///
  /// 注意：该字段不会被持久化，加载时始终重置为 [InstanceStatus.stopped]。
  InstanceStatus status;

  /// 实例创建时间。
  final DateTime createdAt;

  /// 创建一个服务器实例。
  ///
  /// [id]、[name]、[rootPath]、[coreFilePath]、[startCommand] 为必填参数；
  /// [coreType]、[coreVersion] 为可选参数；
  /// [runMode] 默认为 [RunMode.native]，[container] 默认 null；
  /// [status] 默认为 [InstanceStatus.stopped]；
  /// [createdAt] 默认为当前时间。
  ServerInstance({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.coreFilePath,
    required this.startCommand,
    this.coreType,
    this.coreVersion,
    this.runMode = RunMode.native,
    this.container,
    this.status = InstanceStatus.stopped,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 实例的显示名称（与 [name] 相同），便于 UI 统一调用。
  String get displayName => name;

  /// 将实例序列化为 JSON 字符串，用于本地持久化。
  ///
  /// 注意：[status] 不会被序列化，加载时始终重置为 [InstanceStatus.stopped]。
  String toJson() => jsonEncode({
    'id': id,
    'name': name,
    'rootPath': rootPath,
    'coreFilePath': coreFilePath,
    'startCommand': startCommand,
    'coreType': coreType,
    'coreVersion': coreVersion,
    'runMode': runMode.name,
    'container': container?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  });

  /// 从 JSON 字符串反序列化构建 [ServerInstance]。
  ///
  /// [status] 始终初始化为 [InstanceStatus.stopped]，
  /// 即使原数据中曾存在该字段也会被忽略。
  /// [runMode] / [container] 字段缺失时回退为原生运行，兼容旧数据。
  factory ServerInstance.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    final containerJson = map['container'] as String?;
    return ServerInstance(
      id: map['id'] as String,
      name: map['name'] as String,
      rootPath: map['rootPath'] as String,
      coreFilePath: map['coreFilePath'] as String,
      startCommand: map['startCommand'] as String,
      coreType: map['coreType'] as String?,
      coreVersion: map['coreVersion'] as String?,
      runMode: RunMode.fromString(map['runMode'] as String?),
      container: containerJson == null || containerJson.isEmpty
          ? null
          : ContainerConfig.fromJson(containerJson),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
