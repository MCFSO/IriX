// 服务器实例数据模型
// 定义 Minecraft 服务器实例的核心数据结构、运行状态枚举与持久化序列化逻辑。
// 本文件为纯 Dart 模型，不依赖 Flutter，仅使用 dart:convert 完成 JSON 编解码。

import 'dart:convert';

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

  /// 状态的中文展示标签。
  ///
  /// [starting] 显示"启动中"，[running] 显示"运行中"，
  /// 便于用户区分服务器是正在启动还是已成功运行。
  String get label => switch (this) {
    InstanceStatus.starting => '启动中',
    InstanceStatus.running => '运行中',
    InstanceStatus.restarting => '重启中',
    InstanceStatus.stopped => '已关闭',
  };

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
    'createdAt': createdAt.toIso8601String(),
  });

  /// 从 JSON 字符串反序列化构建 [ServerInstance]。
  ///
  /// [status] 始终初始化为 [InstanceStatus.stopped]，
  /// 即使原数据中曾存在该字段也会被忽略。
  factory ServerInstance.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return ServerInstance(
      id: map['id'] as String,
      name: map['name'] as String,
      rootPath: map['rootPath'] as String,
      coreFilePath: map['coreFilePath'] as String,
      startCommand: map['startCommand'] as String,
      coreType: map['coreType'] as String?,
      coreVersion: map['coreVersion'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
