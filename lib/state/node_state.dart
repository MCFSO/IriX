// 节点状态管理层
// 汇总节点列表、当前选中节点与在线状态，作为 UI 与持久化层之间的桥梁。
// 通过 ChangeNotifier 向 UI 暴露响应式状态。

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/node.dart';
import '../services/node_api_client.dart';
import '../services/node_store.dart';

/// 节点全局状态。
class NodeState extends ChangeNotifier {
  /// 节点持久化服务。
  final NodeStore _store = NodeStore();

  /// 当前已加载的节点列表。
  List<NodeInfo> _nodes = [];

  /// 当前选中的节点 id。
  String? _selectedNodeId;

  /// 节点在线状态（id → 是否可达）。
  final Map<String, bool> _online = {};

  /// 节点最近一次连接错误消息（id → 消息）。
  final Map<String, String> _errors = {};

  /// 当前节点列表（只读视图）。
  List<NodeInfo> get nodes => List.unmodifiable(_nodes);

  /// 当前选中的节点（可空）。
  NodeInfo? get selectedNode {
    if (_selectedNodeId == null) return null;
    for (final node in _nodes) {
      if (node.id == _selectedNodeId) return node;
    }
    return null;
  }

  /// 当前选中节点 id（可空）。
  String? get selectedNodeId => _selectedNodeId;

  /// 节点是否在线。
  bool isOnline(String id) => _online[id] ?? false;

  /// 节点最近一次连接错误消息（可空）。
  String? errorOf(String id) => _errors[id];

  /// 生成节点唯一标识。
  String _generateId() {
    final random = Random();
    final suffix = random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return 'n-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  /// 初始化：加载持久化节点列表并选中第一个节点。
  Future<void> init() async {
    _nodes = await _store.loadNodes();
    if (_nodes.isNotEmpty && _selectedNodeId == null) {
      _selectedNodeId = _nodes.first.id;
    }
    notifyListeners();
  }

  /// 为指定节点创建 API 客户端。
  NodeApiClient clientFor(NodeInfo node) => NodeApiClient.of(node);

  /// 选中指定 id 的节点。
  void selectNode(String id) {
    if (_selectedNodeId == id) return;
    _selectedNodeId = id;
    notifyListeners();
  }

  /// 探测单个节点在线状态并记录错误消息。
  Future<bool> pingNode(String id) async {
    final node = _nodeById(id);
    if (node == null) return false;
    bool ok = false;
    String? error;
    try {
      await clientFor(node).overview();
      ok = true;
    } catch (e) {
      error = e.toString();
    }
    _online[id] = ok;
    if (error == null) {
      _errors.remove(id);
    } else {
      _errors[id] = error;
    }
    notifyListeners();
    return ok;
  }

  /// 探测全部节点。
  Future<void> pingAll() async {
    for (final node in _nodes) {
      await pingNode(node.id);
    }
  }

  /// 添加节点并持久化，随后自动选中。
  Future<NodeInfo> addNode({
    required String name,
    required NodeType type,
    required String address,
    String apiKey = '',
  }) async {
    final node = NodeInfo(
      id: _generateId(),
      name: name.trim().isEmpty ? (type.label) : name.trim(),
      type: type,
      address: address,
      apiKey: apiKey.trim(),
    );
    await _store.addNode(node);
    _nodes.add(node);
    _selectedNodeId = node.id;
    notifyListeners();
    return node;
  }

  /// 重命名节点并持久化。
  Future<void> renameNode(String id, String newName) async {
    final node = _nodeById(id);
    if (node == null || newName.trim().isEmpty) return;
    final updated = node.copyWith(name: newName.trim());
    await _store.updateNode(updated);
    final index = _nodes.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _nodes[index] = updated;
    }
    notifyListeners();
  }

  /// 更新节点连接信息并持久化。
  Future<void> updateNodeConnection(
    String id, {
    required String address,
    required String apiKey,
  }) async {
    final node = _nodeById(id);
    if (node == null) return;
    final updated = node.copyWith(address: address, apiKey: apiKey);
    await _store.updateNode(updated);
    final index = _nodes.indexWhere((e) => e.id == id);
    if (index >= 0) {
      _nodes[index] = updated;
    }
    notifyListeners();
  }

  /// 删除节点：清理选中状态与在线状态，并持久化。
  Future<void> removeNode(String id) async {
    await _store.removeNode(id);
    _nodes.removeWhere((e) => e.id == id);
    _online.remove(id);
    _errors.remove(id);
    if (_selectedNodeId == id) {
      _selectedNodeId = _nodes.isNotEmpty ? _nodes.first.id : null;
    }
    notifyListeners();
  }

  NodeInfo? _nodeById(String id) {
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }
}
