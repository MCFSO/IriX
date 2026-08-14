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

/// 依据节点数量与类型推导监控节点 id 与监控策略。
///
/// 监控节点必须是 irix-node（MCSM 无法节点互联，不能承担监控 / 资源同步角色）。
/// 返回 `(monitorNodeId, strategy)`：
/// - `nodes.length >= 3` 且存在 irix-node：指定第一个 irix-node 为监控节点，策略 `monitor`。
/// - `nodes.length >= 3` 但全部为 MCSM：无可用监控节点，策略 `noEligibleMonitor`。
/// - `nodes.length == 2`：互相监控，监控节点为空，策略 `mutual`。
/// - `nodes.length < 2`：节点不足，策略 `insufficient`。
({String? monitorNodeId, ClusterMonitorStrategy strategy}) deriveMonitorRole(
  List<NodeInfo> nodes,
) {
  if (nodes.length >= 3) {
    for (final node in nodes) {
      if (node.type == NodeType.node) {
        return (
          monitorNodeId: node.id,
          strategy: ClusterMonitorStrategy.monitor,
        );
      }
    }
    return (
      monitorNodeId: null,
      strategy: ClusterMonitorStrategy.noEligibleMonitor,
    );
  }
  if (nodes.length == 2) {
    return (monitorNodeId: null, strategy: ClusterMonitorStrategy.mutual);
  }
  return (monitorNodeId: null, strategy: ClusterMonitorStrategy.insufficient);
}

/// 挑选迁移目标节点：优先 irix-node（完整能力），无 irix-node 时退回 MCSM。
///
/// MCSM 无法节点互联，属于「受限」节点；只有在没有 irix-node 可选时才作为迁移目标。
String? pickMigrationTarget(
  List<NodeInfo> candidateNodes,
  Map<String, OverviewSystem> snapshot,
) {
  final irix = <NodeInfo>[];
  for (final node in candidateNodes) {
    if (node.type == NodeType.node) irix.add(node);
  }
  final pool = irix.isNotEmpty ? irix : candidateNodes;
  return pickNodeForAllocation(pool, snapshot);
}

/// 集群监控策略。
enum ClusterMonitorStrategy {
  /// ≥3 节点且存在 irix-node：指定单一 irix-node 为监控节点。
  monitor('指定监控节点'),

  /// 2 节点：互相监控。
  mutual('互相监控'),

  /// <2 节点：节点不足。
  insufficient('节点不足'),

  /// ≥3 节点但全部为 MCSM：无可用监控节点。
  noEligibleMonitor('无可用监控节点');

  const ClusterMonitorStrategy(this.label);

  final String label;
}
