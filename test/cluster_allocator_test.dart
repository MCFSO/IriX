// 集群节点分配纯函数测试
// 验证最空闲节点挑选与监控节点指派规则。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/node.dart';
import 'package:irix/models/remote.dart';
import 'package:irix/services/cluster_allocator.dart';

NodeInfo _node(String id) => NodeInfo(
  id: id,
  name: id,
  type: NodeType.node,
  address: 'http://127.0.0.1:12346',
  apiKey: '',
);

NodeInfo _mcsm(String id) => NodeInfo(
  id: id,
  name: id,
  type: NodeType.mcsm,
  address: 'http://127.0.0.1:23333',
  apiKey: 'key',
);

OverviewSystem _sys({int totalMem = 0, int freeMem = 0, double memUsage = 0}) {
  return OverviewSystem(
    totalMem: totalMem,
    freeMem: freeMem,
    memUsage: memUsage,
  );
}

void main() {
  test('pickNodeForAllocation 选择内存最空闲节点', () {
    final nodes = [_node('a'), _node('b'), _node('c')];
    final snapshot = {
      'a': _sys(totalMem: 100, freeMem: 10, memUsage: 0.9),
      'b': _sys(totalMem: 100, freeMem: 60, memUsage: 0.4),
      'c': _sys(totalMem: 100, freeMem: 30, memUsage: 0.7),
    };
    expect(pickNodeForAllocation(nodes, snapshot), 'b');
  });

  test('pickNodeForAllocation 缺少资源信息时退化为 memUsage', () {
    final nodes = [_node('a'), _node('b')];
    final snapshot = {'a': _sys(memUsage: 0.9), 'b': _sys(memUsage: 0.2)};
    expect(pickNodeForAllocation(nodes, snapshot), 'b');
  });

  test('pickNodeForAllocation 候选为空返回 null', () {
    expect(pickNodeForAllocation([], {}), isNull);
  });

  test('deriveMonitorRole：≥3 节点指定首个 irix-node 为监控节点', () {
    final role = deriveMonitorRole([_node('a'), _node('b'), _node('c')]);
    expect(role.strategy, ClusterMonitorStrategy.monitor);
    expect(role.monitorNodeId, 'a');
  });

  test('deriveMonitorRole：监控节点必须是 irix-node（跳过 MCSM）', () {
    final role = deriveMonitorRole([_mcsm('a'), _mcsm('b'), _node('c')]);
    expect(role.strategy, ClusterMonitorStrategy.monitor);
    expect(role.monitorNodeId, 'c');
  });

  test('deriveMonitorRole：≥3 节点但全为 MCSM → 无可用监控节点', () {
    final role = deriveMonitorRole([_mcsm('a'), _mcsm('b'), _mcsm('c')]);
    expect(role.strategy, ClusterMonitorStrategy.noEligibleMonitor);
    expect(role.monitorNodeId, isNull);
  });

  test('deriveMonitorRole：2 节点互相监控', () {
    final role = deriveMonitorRole([_node('a'), _node('b')]);
    expect(role.strategy, ClusterMonitorStrategy.mutual);
    expect(role.monitorNodeId, isNull);
  });

  test('deriveMonitorRole：不足 2 节点', () {
    final role = deriveMonitorRole([_node('a')]);
    expect(role.strategy, ClusterMonitorStrategy.insufficient);
    expect(role.monitorNodeId, isNull);
  });

  test('pickMigrationTarget：优先 irix-node 目标', () {
    final nodes = [_mcsm('a'), _node('b'), _mcsm('c')];
    final snapshot = {
      'a': _sys(totalMem: 100, freeMem: 90, memUsage: 0.1),
      'b': _sys(totalMem: 100, freeMem: 30, memUsage: 0.7),
      'c': _sys(totalMem: 100, freeMem: 80, memUsage: 0.2),
    };
    // MCSM 'a' 最空闲，但迁移目标应优先 irix-node 'b'。
    expect(pickMigrationTarget(nodes, snapshot), 'b');
  });

  test('pickMigrationTarget：无 irix-node 时退回 MCSM 中最空闲者', () {
    final nodes = [_mcsm('a'), _mcsm('b')];
    final snapshot = {
      'a': _sys(totalMem: 100, freeMem: 20, memUsage: 0.8),
      'b': _sys(totalMem: 100, freeMem: 60, memUsage: 0.4),
    };
    expect(pickMigrationTarget(nodes, snapshot), 'b');
  });
}
