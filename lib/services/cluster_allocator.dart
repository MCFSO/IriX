// 集群节点分配纯函数
// 依据节点资源快照选择最空闲节点，并推导监控节点指派规则。
// 纯 Dart、无 I/O，便于单元测试。

import '../models/node.dart';
import '../models/remote.dart';

/// 单个节点的分配评估结果。
class NodeAllocationScore {
  final String nodeId;

  /// 可用内存比例（越大越空闲），用于排序。
  final double freeRatio;

  const NodeAllocationScore(this.nodeId, this.freeRatio);
}

/// 从资源快照推导节点空闲程度（可用内存比例 0~1）。
///
/// [totalMem] / [freeMem] 单位一致（字节）；[memUsage] 为 0~1 的小数。
/// 优先用 freeMem/totalMem；缺失时退化为 1 - memUsage。
double freeMemoryRatio(OverviewSystem? sys) {
  if (sys == null) return 0;
  if (sys.totalMem > 0) {
    final ratio = sys.freeMem / sys.totalMem;
    return ratio.clamp(0.0, 1.0);
  }
  return (1 - sys.memUsage.clamp(0.0, 1.0));
}

/// 在 [candidateNodes] 中挑选最空闲节点用于放置实例。
///
/// 返回节点 id；若候选为空或全部无资源信息，返回 null。
/// [snapshot] 为 nodeId → 最近概览系统信息。
String? pickNodeForAllocation(
  List<NodeInfo> candidateNodes,
  Map<String, OverviewSystem> snapshot,
) {
  if (candidateNodes.isEmpty) return null;

  String? bestId;
  var bestRatio = -1.0;
  for (final node in candidateNodes) {
    final ratio = freeMemoryRatio(snapshot[node.id]);
    if (ratio > bestRatio) {
      bestRatio = ratio;
      bestId = node.id;
    }
  }
  return bestId;
}

/// 依据节点数量推导监控节点 id 与监控策略。
///
/// 返回 `(monitorNodeId, strategy)`：
/// - `nodes.length >= 3`：返回第一个节点作为监控节点，策略为 `monitor`。
/// - `nodes.length == 2`：互相监控，监控节点为空，策略为 `mutual`。
/// - `nodes.length < 2`：节点不足，策略为 `insufficient`。
({String? monitorNodeId, ClusterMonitorStrategy strategy}) deriveMonitorRole(
  List<NodeInfo> nodes,
) {
  if (nodes.length >= 3) {
    return (monitorNodeId: nodes.first.id, strategy: ClusterMonitorStrategy.monitor);
  }
  if (nodes.length == 2) {
    return (monitorNodeId: null, strategy: ClusterMonitorStrategy.mutual);
  }
  return (monitorNodeId: null, strategy: ClusterMonitorStrategy.insufficient);
}

/// 集群监控策略。
enum ClusterMonitorStrategy {
  /// ≥3 节点：指定单一监控节点。
  monitor('指定监控节点'),

  /// 2 节点：互相监控。
  mutual('互相监控'),

  /// <2 节点：节点不足。
  insufficient('节点不足');

  const ClusterMonitorStrategy(this.label);

  final String label;
}
