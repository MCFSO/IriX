// 集群状态测试
// 验证集群实例的增删、崩溃计数、节点位置更新与持久化往返。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/state/cluster_state.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_cluster_test');
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

  setUp(() async {
    // 清理上一个测试遗留的集群实例，保证各测试相互独立。
    final rows = await DatabaseManager.instance.getAllClusterInstances();
    for (final row in rows) {
      await DatabaseManager.instance.deleteClusterInstance(row['id'] as String);
    }
  });

  test('首次启动集群实例列表为空', () async {
    final state = ClusterState();
    await state.init();
    expect(state.instances, isEmpty);
    expect(state.mode, isNotNull);
  });

  test('添加集群实例并持久化', () async {
    final state = ClusterState();
    await state.init();

    final added = await state.addInstance(
      name: '生存服',
      nodeId: 'node-a',
      daemonId: 'daemon-a',
      remoteUuid: 'uuid-1',
      cwd: '/data/survival',
      startCommand: 'java -Xmx2G -jar server.jar nogui',
    );
    expect(state.instances.length, 1);
    expect(added.crashCount, 0);

    // 重载验证持久化
    final state2 = ClusterState();
    await state2.init();
    expect(state2.instances.length, 1);
    final found = state2.instanceById(added.id);
    expect(found, isNotNull);
    expect(found!.nodeId, 'node-a');
    expect(found.remoteUuid, 'uuid-1');
    expect(found.crashCount, 0);
  });

  test('崩溃计数、迁移位置更新与清零', () async {
    final state = ClusterState();
    await state.init();
    final added = await state.addInstance(
      name: '生存服',
      nodeId: 'node-a',
      daemonId: 'daemon-a',
      remoteUuid: 'uuid-1',
      cwd: '/data/survival',
      startCommand: 'java -Xmx2G -jar server.jar nogui',
    );

    expect(await state.incrementCrash(added.id), 1);
    expect(await state.incrementCrash(added.id), 2);

    await state.updatePlacement(
      added.id,
      nodeId: 'node-b',
      daemonId: 'daemon-b',
      remoteUuid: 'uuid-2',
    );
    await state.resetCrash(added.id);

    final updated = state.instanceById(added.id)!;
    expect(updated.nodeId, 'node-b');
    expect(updated.remoteUuid, 'uuid-2');
    expect(updated.crashCount, 0);

    // 持久化验证
    final state2 = ClusterState();
    await state2.init();
    final persisted = state2.instanceById(added.id)!;
    expect(persisted.nodeId, 'node-b');
    expect(persisted.remoteUuid, 'uuid-2');
    expect(persisted.crashCount, 0);
  });

  test('删除集群实例', () async {
    final state = ClusterState();
    await state.init();
    final added = await state.addInstance(
      name: '临时',
      nodeId: 'node-a',
      daemonId: 'daemon-a',
      remoteUuid: 'uuid-x',
      cwd: '/tmp',
      startCommand: 'echo hi',
    );
    await state.removeInstance(added.id);
    expect(state.instances, isEmpty);
  });
}
