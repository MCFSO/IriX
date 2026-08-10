// 节点持久化服务
// 负责通过 DatabaseManager 将节点列表持久化到 SQLite 数据库（nodes 表）。
// 纯数据持久化层，状态管理由 NodeState 负责。

import 'package:flutter/foundation.dart';

import '../models/node.dart';
import '../services/database_manager.dart';

/// 节点的本地持久化服务。
class NodeStore {
  /// 内存缓存：首次加载后保留，避免每次操作都重新查询数据库。
  List<NodeInfo>? _cache;

  /// 将数据库行记录转换为 [NodeInfo]。
  NodeInfo _fromDbRow(Map<String, dynamic> row) {
    return NodeInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      type: NodeType.fromString(row['type'] as String? ?? 'node'),
      address: row['address'] as String? ?? '',
      apiKey: row['api_key'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// 将 [NodeInfo] 转换为数据库行记录。
  Map<String, dynamic> _toDbRow(NodeInfo node) {
    return {
      'id': node.id,
      'name': node.name,
      'type': node.type.name,
      'address': node.address,
      'api_key': node.apiKey,
      'created_at': node.createdAt.toIso8601String(),
    };
  }

  /// 加载全部节点。
  Future<List<NodeInfo>> loadNodes() async {
    if (_cache != null) {
      return List<NodeInfo>.of(_cache!);
    }
    try {
      final rows = await DatabaseManager.instance.getAllNodes();
      _cache = rows.map(_fromDbRow).toList();
      return List<NodeInfo>.of(_cache!);
    } catch (e) {
      debugPrint('Failed to load nodes: $e');
      return _cache ?? [];
    }
  }

  /// 添加节点并持久化。
  Future<NodeInfo> addNode(NodeInfo node) async {
    try {
      await DatabaseManager.instance.insertNode(_toDbRow(node));
      _cache?.add(node);
      return node;
    } catch (e) {
      debugPrint('Failed to add node: $e');
      return node;
    }
  }

  /// 按 [id] 删除节点并持久化。
  Future<void> removeNode(String id) async {
    try {
      await DatabaseManager.instance.deleteNode(id);
      _cache?.removeWhere((e) => e.id == id);
    } catch (e) {
      debugPrint('Failed to remove node: $e');
    }
  }

  /// 更新节点字段并持久化。
  Future<void> updateNode(NodeInfo node) async {
    try {
      await DatabaseManager.instance.updateNode(node.id, _toDbRow(node));
      if (_cache != null) {
        final index = _cache!.indexWhere((e) => e.id == node.id);
        if (index >= 0) {
          _cache![index] = node;
        }
      }
    } catch (e) {
      debugPrint('Failed to update node ${node.id}: $e');
    }
  }
}
