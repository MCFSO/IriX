// 集群实例数据模型
// 多机管理模式下、运行在某个节点上的远程实例（MCSM / IriX 实例）。
// 与本地 ServerInstance 不同：集群实例的生命周期由协调器驱动，
// 支持资源分配、崩溃迁移与增量同步。纯 Dart 模型，不依赖 Flutter。

import 'dart:convert';

/// 集群实例数据模型。
///
/// 记录一个分布在节点上的远程实例：所在节点、守护进程、远端实例 uuid、
/// 工作目录与启动命令，以及崩溃次数与最近同步时间等集群运行期元数据。
class ClusterInstance {
  /// 本地唯一标识。
  final String id;

  /// 实例名称（可变）。
  String name;

  /// 当前所在节点 id。
  String nodeId;

  /// 当前所在守护进程 id（MCSM 面板可能多守护进程；IriX 节点取 overview.remote 首个）。
  String daemonId;

  /// 远端实例 uuid。
  String remoteUuid;

  /// 远端工作目录（服务器上的绝对路径）。
  String cwd;

  /// 启动命令，例如 `java -Xmx2G -jar server.jar nogui`。
  String startCommand;

  /// 连续崩溃次数（正常启动或迁移成功后重置）。
  int crashCount;

  /// 最近一次增量同步时间（可空，未同步过为 null）。
  DateTime? lastSyncedAt;

  /// 创建时间。
  final DateTime createdAt;

  /// 创建一个集群实例。
  ClusterInstance({
    required this.id,
    required this.name,
    required this.nodeId,
    required this.daemonId,
    required this.remoteUuid,
    required this.cwd,
    required this.startCommand,
    this.crashCount = 0,
    this.lastSyncedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 显示名称（与 [name] 相同），便于 UI 统一调用。
  String get displayName => name;

  /// 序列化为 JSON 字符串。
  String toJson() => jsonEncode({
    'id': id,
    'name': name,
    'nodeId': nodeId,
    'daemonId': daemonId,
    'remoteUuid': remoteUuid,
    'cwd': cwd,
    'startCommand': startCommand,
    'crashCount': crashCount,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  });

  /// 从 JSON 字符串反序列化。
  factory ClusterInstance.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return ClusterInstance(
      id: map['id'] as String,
      name: map['name'] as String,
      nodeId: map['nodeId'] as String,
      daemonId: map['daemonId'] as String? ?? '',
      remoteUuid: map['remoteUuid'] as String? ?? '',
      cwd: map['cwd'] as String? ?? '',
      startCommand: map['startCommand'] as String? ?? '',
      crashCount: (map['crashCount'] as num?)?.toInt() ?? 0,
      lastSyncedAt: map['lastSyncedAt'] == null
          ? null
          : DateTime.parse(map['lastSyncedAt'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  /// 复制并覆盖部分字段。
  ClusterInstance copyWith({
    String? name,
    String? nodeId,
    String? daemonId,
    String? remoteUuid,
    String? cwd,
    String? startCommand,
    int? crashCount,
    DateTime? lastSyncedAt,
  }) {
    return ClusterInstance(
      id: id,
      name: name ?? this.name,
      nodeId: nodeId ?? this.nodeId,
      daemonId: daemonId ?? this.daemonId,
      remoteUuid: remoteUuid ?? this.remoteUuid,
      cwd: cwd ?? this.cwd,
      startCommand: startCommand ?? this.startCommand,
      crashCount: crashCount ?? this.crashCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      createdAt: createdAt,
    );
  }
}
