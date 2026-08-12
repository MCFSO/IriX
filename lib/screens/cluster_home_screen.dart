// 集群主页（多机模式首页）
// 展示各节点信息：在线状态、CPU/内存占用、该节点上运行的集群实例数与监控节点徽标。
// 右上角可直接「添加节点」；底部提示当前监控策略（≥3 指定监控 / 2 互相监控 / <2 不足）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../services/cluster_allocator.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/add_node_dialog.dart';
import 'nodes_screen.dart';

/// 集群主页。
class ClusterHomeScreen extends StatefulWidget {
  const ClusterHomeScreen({super.key});

  @override
  State<ClusterHomeScreen> createState() => _ClusterHomeScreenState();
}

class _ClusterHomeScreenState extends State<ClusterHomeScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.read<NodeState>().pingAll();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _addNode() async {
    final node = await showAddNodeDialog(context);
    if (node == null || !mounted) return;
    await context.read<NodeState>().pingNode(node.id);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NodeState, ClusterState>(
      builder: (context, nodeState, cluster, _) {
        final nodes = nodeState.nodes;
        final monitorId = cluster.monitorNodeId;
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('主页'),
              floating: true,
              actions: [
                IconButton(
                  icon: _refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: '刷新状态',
                  onPressed: _refreshing ? null : _refresh,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '添加节点',
                  onPressed: _addNode,
                ),
                const SizedBox(width: 4),
              ],
            ),
            if (nodes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('还没有节点，点击右上角 + 添加'),
                      const SizedBox(height: 8),
                      const Text(
                        '多机模式需要至少 2 个节点（MCSM 面板或 IriX 本地节点）',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: nodes.length,
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    final sys = cluster.resourceSnapshot[node.id];
                    final running = cluster.instances
                        .where((i) => i.nodeId == node.id)
                        .length;
                    return _ClusterNodeCard(
                      node: node,
                      online: nodeState.isOnline(node.id),
                      error: nodeState.errorOf(node.id),
                      system: sys,
                      instanceCount: running,
                      isMonitor: node.id == monitorId,
                      onTap: () => openNode(context, node.id),
                    );
                  },
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverToBoxAdapter(
                child: _monitorHint(nodes, cluster),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 底部监控策略提示。
  Widget _monitorHint(List<NodeInfo> nodes, ClusterState cluster) {
    final theme = Theme.of(context);
    final role = deriveMonitorRole(nodes);
    final String text = switch (role.strategy) {
      ClusterMonitorStrategy.monitor => '已指定监控节点：${_nodeName(nodes, role.monitorNodeId)}',
      ClusterMonitorStrategy.mutual => '节点互相监控',
      ClusterMonitorStrategy.noEligibleMonitor =>
        '节点 ≥3 台，但均为 MCSM，无可用监控节点（MCSM 不支持节点互联）',
      ClusterMonitorStrategy.insufficient => '至少需要 2 个节点才能形成集群',
    };
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }

  String _nodeName(List<NodeInfo> nodes, String? id) {
    if (id == null) return '—';
    for (final node in nodes) {
      if (node.id == id) return node.name;
    }
    return '—';
  }
}

/// 集群节点卡片（含资源占用与监控徽标）。
class _ClusterNodeCard extends StatelessWidget {
  const _ClusterNodeCard({
    required this.node,
    required this.online,
    required this.error,
    required this.system,
    required this.instanceCount,
    required this.isMonitor,
    required this.onTap,
  });

  final NodeInfo node;
  final bool online;
  final String? error;
  final OverviewSystem? system;
  final int instanceCount;
  final bool isMonitor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = node.type == NodeType.node;
    final cpu = system == null ? null : system!.cpuUsage * 100;
    final mem = system == null ? null : system!.memUsage * 100;
    return AppleCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (online
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest)
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLocal ? Icons.terminal : Icons.dns,
              color: online
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        node.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        node.type.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    if (isMonitor) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '监控',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      online ? Icons.circle : Icons.circle_outlined,
                      size: 8,
                      color: online ? Colors.green : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        online
                            ? (cpu == null && mem == null
                                  ? '在线'
                                  : 'CPU ${cpu?.toStringAsFixed(0)}% · 内存 ${mem?.toStringAsFixed(0)}%')
                            : (error ?? '离线'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: online
                              ? Colors.green
                              : theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (instanceCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '实例 $instanceCount 个',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
