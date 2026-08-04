// 节点状态测试
// 验证初始化、添加/重命名/删除与持久化逻辑。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/models/node.dart';
import 'package:irix/services/database_manager.dart';
import 'package:irix/state/node_state.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_node_test');
    await DatabaseManager.instance.init(
      dbPath: p.join(tempDir.path, 'test.db'),
      dataDir: tempDir.path,
    );
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('首次启动节点列表为空，不创建默认节点', () async {
    final state = NodeState();
    await state.init();

    expect(state.nodes.length, 0);
    expect(state.selectedNode, isNull);
    expect(state.selectedNodeId, isNull);
  });

  test('添加节点后持久化并可重命名、删除', () async {
    final state = NodeState();
    await state.init();

    final added = await state.addNode(
      name: '我的面板',
      type: NodeType.mcsm,
      address: 'http://192.168.1.5:23333',
      apiKey: 'test-key',
    );
    expect(state.nodes.length, 1);
    expect(added.type, NodeType.mcsm);
    expect(state.selectedNodeId, added.id);

    // 重载状态验证持久化
    final state2 = NodeState();
    await state2.init();
    expect(state2.nodes.length, 1);
    final found = state2.nodes.firstWhere((n) => n.id == added.id);
    expect(found.address, 'http://192.168.1.5:23333');
    expect(found.apiKey, 'test-key');

    await state2.renameNode(added.id, '新名字');
    final renamed = state2.nodes.firstWhere((n) => n.id == added.id);
    expect(renamed.name, '新名字');

    await state2.removeNode(added.id);
    expect(state2.nodes.length, 0);
    expect(state2.selectedNode, isNull);
  });
}
