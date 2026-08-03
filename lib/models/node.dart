// 节点数据模型
// 定义 IriX 客户端可管理的"节点"（远程 MCSM 面板或本地 Go 守护进程），
// 以及持久化序列化逻辑。纯 Dart 模型，不依赖 Flutter。

import 'dart:convert';

/// 节点类型。
enum NodeType {
  /// MCSManager 面板节点（远程，使用面板 API Key）。
  mcsm('MCSM', 'MCSManager 面板'),

  /// IriX 本地节点（Go 语言守护进程，见项目根目录 node/）。
  node('Node', 'IriX 本地节点');

  const NodeType(this.label, this.description);

  /// 显示名称。
  final String label;

  /// 类型说明。
  final String description;

  /// 从数据库字符串反序列化。
  static NodeType fromString(String value) {
    for (final t in NodeType.values) {
      if (t.name == value) return t;
    }
    return NodeType.node;
  }
}

/// 节点数据模型。
///
/// 描述单个可管理节点：类型、显示名称、API 地址与 API 密钥。
/// 运行时在线状态不持久化，由 NodeState 维护。
class NodeInfo {
  /// 节点唯一标识。
  final String id;

  /// 节点名称（可变，便于重命名）。
  String name;

  /// 节点类型（MCSM 面板 / IriX 本地节点）。
  final NodeType type;

  /// API 基地址，例如 `http://127.0.0.1:12346` 或 `http://192.168.1.5:23333`。
  String address;

  /// API 密钥（MCSM 面板为用户 API Key；本地节点默认为空）。
  String apiKey;

  /// 节点创建时间。
  final DateTime createdAt;

  /// 创建一个节点。
  NodeInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.apiKey,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    address = _normalizeAddress(address);
  }

  /// 去除地址末尾多余的斜杠。
  static String _normalizeAddress(String address) {
    var a = address.trim();
    while (a.endsWith('/')) {
      a = a.substring(0, a.length - 1);
    }
    return a;
  }

  /// 序列化为 JSON，用于本地持久化。
  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'type': type.name,
        'address': address,
        'apiKey': apiKey,
        'createdAt': createdAt.toIso8601String(),
      });

  /// 从 JSON 字符串反序列化。
  factory NodeInfo.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    return NodeInfo(
      id: map['id'] as String,
      name: map['name'] as String,
      type: NodeType.fromString(map['type'] as String? ?? 'node'),
      address: map['address'] as String? ?? '',
      apiKey: map['apiKey'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  /// 复制并覆盖部分字段。
  NodeInfo copyWith({String? name, String? address, String? apiKey}) {
    return NodeInfo(
      id: id,
      name: name ?? this.name,
      type: type,
      address: address ?? this.address,
      apiKey: apiKey ?? this.apiKey,
      createdAt: createdAt,
    );
  }
}
