// 节点持久化服务
// 负责通过 DatabaseManager 将节点列表持久化到 SQLite 数据库（nodes 表）。
// 纯数据持久化层，状态管理由 NodeState 负责。

import '../models/node.dart';
import 'database_manager.dart';
import 'entity_store.dart';

/// 节点的本地持久化服务。
class NodeStore extends EntityStore<NodeInfo> {
  @override
  String get storeLabel => 'nodes';

  @override
  NodeInfo fromDbRow(Map<String, dynamic> row) {
    return NodeInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      type: NodeType.fromString(row['type'] as String? ?? 'node'),
      address: row['address'] as String? ?? '',
      apiKey: row['api_key'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  @override
  Map<String, dynamic> toDbRow(NodeInfo node) {
    return {
      'id': node.id,
      'name': node.name,
      'type': node.type.name,
      'address': node.address,
      'api_key': node.apiKey,
      'created_at': node.createdAt.toIso8601String(),
    };
  }

  @override
  String idOf(NodeInfo node) => node.id;

  @override
  Future<List<Map<String, dynamic>>> fetchAll() =>
      DatabaseManager.instance.getAllNodes();

  @override
  Future<void> insertRow(Map<String, dynamic> row) =>
      DatabaseManager.instance.insertNode(row);

  @override
  Future<void> deleteRow(String id) => DatabaseManager.instance.deleteNode(id);

  @override
  Future<void> updateRow(String id, Map<String, dynamic> row) =>
      DatabaseManager.instance.updateNode(id, row);

  /// 加载全部节点。
  Future<List<NodeInfo>> loadNodes() => loadAll();

  /// 添加节点并持久化。
  Future<NodeInfo> addNode(NodeInfo node) => add(node);

  /// 按 [id] 删除节点并持久化。
  Future<void> removeNode(String id) => remove(id);

  /// 更新节点字段并持久化。
  Future<void> updateNode(NodeInfo node) => update(node);
}
