// 集群主页（多机模式首页）
// 只展示信息：顶部聚合网络折线图 + 各节点信息卡
// （节点名称 / 类型 / 系统名称与版本 / CPU / 内存 / 磁盘 / 网络）。
// CPU、内存点击跳节点概览；悬停显示精确数值。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../services/cluster_allocator.dart';
import '../services/cluster_monitor.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/add_node_dialog.dart';
import '../widgets/network_line_chart.dart';
import 'home_screen.dart' show showSettingsDialog;
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
    await ClusterMonitor.instance.refreshNow();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _addNode() async {
    final node = await showAddNodeDialog(context);
    if (node == null || !mounted) return;
    await context.read<NodeState>().pingNode(node.id);
    await ClusterMonitor.instance.refreshNow();
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
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '设置',
                  onPressed: () => showSettingsDialog(context),
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
            else ...[
              SliverToBoxAdapter(
                child: _NetworkChartCard(history: cluster.networkHistory),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverList.builder(
                  itemCount: nodes.length,
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    final sys = cluster.resourceSnapshot[node.id];
                    return _ClusterNodeCard(
                      node: node,
                      online: nodeState.isOnline(node.id),
                      error: nodeState.errorOf(node.id),
                      system: sys,
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

/// 顶部聚合网络折线图卡片。
class _NetworkChartCard extends StatelessWidget {
  const _NetworkChartCard({required this.history});

  final List<NetworkSample> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = history.isNotEmpty ? history.last : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AppleCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('网络吞吐（所有节点）', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (latest != null)
                  Text(
                    '↓ ${_fmtRate(latest.download)}  ↑ ${_fmtRate(latest.upload)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            NetworkLineChart(samples: history),
          ],
        ),
      ),
    );
  }
}

/// 集群节点信息卡。
class _ClusterNodeCard extends StatelessWidget {
  const _ClusterNodeCard({
    required this.node,
    required this.online,
    required this.error,
    required this.system,
    required this.isMonitor,
    required this.onTap,
  });

  final NodeInfo node;
  final bool online;
  final String? error;
  final OverviewSystem? system;
  final bool isMonitor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = node.type == NodeType.node;
    final sys = system;

    final cpu = sys == null ? null : sys.cpuUsage * 100;
    final mem = sys == null ? null : sys.memUsage * 100;
    final disk = (sys != null && sys.hasDisk) ? sys.diskUsage * 100 : null;
    final net =
        (sys != null && sys.hasNetwork)
            ? _fmtRate(sys.networkDownload + sys.networkUpload)
            : null;

    String systemName = '—';
    String? systemVersion;
    if (sys != null) {
      if (sys.type.isNotEmpty) {
        systemName = sys.type;
      } else if (sys.platform.isNotEmpty) {
        systemName = sys.platform;
      }
      if (sys.systemVersion.isNotEmpty) systemVersion = sys.systemVersion;
    }

    return AppleCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
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
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        node.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _badge(
                      theme,
                      node.type.label,
                      theme.colorScheme.secondaryContainer,
                      theme.colorScheme.onSecondaryContainer,
                    ),
                    if (isMonitor) ...[
                      const SizedBox(width: 6),
                      _badge(
                        theme,
                        '监控',
                        theme.colorScheme.primary,
                        theme.colorScheme.onPrimary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                online ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: online ? Colors.green : theme.colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text(
                online ? '在线' : '离线',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: online ? Colors.green : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            systemVersion == null
                ? '系统：$systemName'
                : '系统：$systemName · $systemVersion',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!online && error != null) ...[
            const SizedBox(height: 2),
            Text(
              error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                theme: theme,
                icon: Icons.speed,
                label: 'CPU',
                value: cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%',
                tooltip: cpu == null ? null : 'CPU ${cpu.toStringAsFixed(1)}%',
                onTap: onTap,
              ),
              _StatItem(
                theme: theme,
                icon: Icons.memory,
                label: '内存',
                value: mem == null ? '—' : '${mem.toStringAsFixed(0)}%',
                tooltip: mem == null
                    ? null
                    : '内存 ${mem.toStringAsFixed(1)}%${_memDetail(sys)}',
                onTap: onTap,
              ),
              _StatItem(
                theme: theme,
                icon: Icons.storage,
                label: '磁盘',
                value: disk == null ? '—' : '${disk.toStringAsFixed(0)}%',
                tooltip: disk == null ? null : '磁盘 ${disk.toStringAsFixed(1)}%${_diskDetail(sys)}',
              ),
              _StatItem(
                theme: theme,
                icon: Icons.swap_vert,
                label: '网络',
                value: net ?? '—',
                tooltip: (sys != null && sys.hasNetwork)
                    ? '↓ ${_fmtRate(sys.networkDownload)}  ↑ ${_fmtRate(sys.networkUpload)}'
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  static String _memDetail(OverviewSystem? sys) {
    if (sys == null || sys.totalMem <= 0) return '';
    return '（${_fmtBytes(sys.totalMem - sys.freeMem)} / ${_fmtBytes(sys.totalMem)}）';
  }

  static String _diskDetail(OverviewSystem? sys) {
    if (sys == null || sys.diskTotal <= 0) return '';
    return '（${_fmtBytes(sys.diskUsed)} / ${_fmtBytes(sys.diskTotal)}）';
  }
}

/// 单个指标块（悬停 Tooltip，可选点击）。
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.theme,
    required this.icon,
    required this.label,
    required this.value,
    required this.tooltip,
    this.onTap,
  });

  final ThemeData theme;
  final IconData icon;
  final String label;
  final String value;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }
    if (tooltip != null && tooltip!.isNotEmpty) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return Expanded(child: content);
  }
}

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${units[i]}';
}

String _fmtRate(double v) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var x = v;
  var i = 0;
  while (x >= 1024 && i < units.length - 1) {
    x /= 1024;
    i++;
  }
  return '${x.toStringAsFixed(1)} ${units[i]}';
}
