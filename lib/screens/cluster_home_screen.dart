// 集群主页（多机模式首页）
// 顶部节点管理卡片网格（⋮ 菜单重命名 / 删除，点击卡片不进入详情），
// 下方聚合网络折线图 + 节点资源总览表。
// 资源总览将所有节点的 CPU / 内存 / 磁盘 并排列出，一眼可见全部节点的
// 占用情况（按使用率着色：绿 <70% / 黄 70~90% / 红 ≥90%），
// 底部附带内存 / 磁盘跨节点合计。不使用单机管理模式的节点管理界面。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/remote.dart';
import '../services/cluster_allocator.dart';
import '../services/cluster_monitor.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/add_node_dialog.dart';
import '../widgets/network_line_chart.dart';
import '../widgets/node_card_grid.dart';
import 'home_screen.dart' show showSettingsDialog;

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

  /// 多机模式不进入节点详情，仅通过卡片 ⋮ 菜单重命名 / 删除。
  Future<void> _rename(NodeInfo node) async {
    final name = await showRenameNodeDialog(context, node);
    if (name != null && name.trim().isNotEmpty && mounted) {
      await context.read<NodeState>().renameNode(node.id, name);
    }
  }

  Future<void> _delete(NodeInfo node) async {
    final confirmed = await showDeleteNodeConfirmDialog(context, node);
    if (confirmed == true && mounted) {
      await context.read<NodeState>().removeNode(node.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NodeState, ClusterState>(
      builder: (context, nodeState, cluster, _) {
        final l = AppLocalizations.of(context);
        final nodes = nodeState.nodes;
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(l.clusterHome_title),
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
                  tooltip: l.clusterHome_refreshStatus,
                  onPressed: _refreshing ? null : _refresh,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l.clusterHome_addNode,
                  onPressed: _addNode,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l.common_settings,
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
                      Text(l.clusterHome_noNodes),
                      const SizedBox(height: 8),
                      Text(
                        l.clusterHome_noNodesHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              NodeCardGrid(
                nodes: nodes,
                onlineOf: nodeState.isOnline,
                errorOf: nodeState.errorOf,
                onTapNode: null, // 多机模式不进入节点详情
                onRenameNode: _rename,
                onDeleteNode: _delete,
              ),
              SliverToBoxAdapter(
                child: _NetworkChartCard(history: cluster.networkHistory),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ResourceOverviewCard(
                    nodes: nodes,
                    nodeState: nodeState,
                    snapshots: cluster.resourceSnapshot,
                    monitorNodeId: cluster.monitorNodeId,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(child: _monitorHint(nodes, cluster)),
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
    final l = AppLocalizations.of(context);
    final role = deriveMonitorRole(nodes);
    final String text = switch (role.strategy) {
      ClusterMonitorStrategy.monitor =>
        l.clusterHome_monitorAssigned(_nodeName(nodes, role.monitorNodeId)),
      ClusterMonitorStrategy.mutual => l.clusterHome_monitorMutual,
      ClusterMonitorStrategy.noEligibleMonitor =>
        l.clusterHome_monitorNoEligible,
      ClusterMonitorStrategy.insufficient => l.clusterHome_monitorInsufficient,
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
    final l = AppLocalizations.of(context);
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
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l.clusterHome_networkThroughput, style: theme.textTheme.titleSmall),
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

/// 节点资源总览卡：所有节点的 CPU / 内存 / 磁盘 统一对比显示。
class _ResourceOverviewCard extends StatelessWidget {
  const _ResourceOverviewCard({
    required this.nodes,
    required this.nodeState,
    required this.snapshots,
    required this.monitorNodeId,
  });

  final List<NodeInfo> nodes;
  final NodeState nodeState;
  final Map<String, OverviewSystem> snapshots;
  final String? monitorNodeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // 跨节点合计（内存 / 磁盘可累加；CPU 只做简单平均）。
    var totalMem = 0;
    var usedMem = 0;
    var totalDisk = 0;
    var usedDisk = 0;
    var cpuSum = 0.0;
    var cpuCount = 0;
    for (final node in nodes) {
      final sys = snapshots[node.id];
      if (sys == null || !nodeState.isOnline(node.id)) continue;
      totalMem += sys.totalMem;
      usedMem += sys.totalMem - sys.freeMem;
      totalDisk += sys.diskTotal;
      usedDisk += sys.diskUsed;
      cpuSum += sys.cpuUsage * 100;
      cpuCount++;
    }

    return AppleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(l.clusterHome_resourceOverview, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                l.clusterHome_nodeCount(nodes.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 表头
          Row(
            children: [
              Expanded(flex: 5, child: _headerLabel(theme, l.clusterHome_colNode)),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _headerLabel(theme, l.clusterHome_colCpu)),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _headerLabel(theme, l.clusterHome_colMemory)),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: _headerLabel(theme, l.clusterHome_colDisk)),
            ],
          ),
          _rowDivider(theme),
          for (var i = 0; i < nodes.length; i++) ...[
            if (i > 0) _rowDivider(theme),
            _NodeResourceRow(
              node: nodes[i],
              online: nodeState.isOnline(nodes[i].id),
              error: nodeState.errorOf(nodes[i].id),
              system: snapshots[nodes[i].id],
              isMonitor: nodes[i].id == monitorNodeId,
            ),
          ],
          if (nodes.isNotEmpty) ...[
            _rowDivider(theme),
            // 合计行
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    l.clusterHome_total,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Text(
                    cpuCount == 0
                        ? '—'
                        : '平均 ${(cpuSum / cpuCount).toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Text(
                    totalMem == 0
                        ? '—'
                        : '${_fmtBytes(usedMem)} / ${_fmtBytes(totalMem)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Text(
                    totalDisk == 0
                        ? '—'
                        : '${_fmtBytes(usedDisk)} / ${_fmtBytes(totalDisk)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _rowDivider(ThemeData theme) {
    return Divider(
      height: 16,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
    );
  }
}

/// 资源总览中的单行：节点信息 + CPU / 内存 / 磁盘 占用。
class _NodeResourceRow extends StatelessWidget {
  const _NodeResourceRow({
    required this.node,
    required this.online,
    required this.error,
    required this.system,
    required this.isMonitor,
  });

  final NodeInfo node;
  final bool online;
  final String? error;
  final OverviewSystem? system;
  final bool isMonitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final sys = system;
    final hasData = online && sys != null;

    final cpu = hasData ? sys.cpuUsage * 100 : null;
    final mem = hasData ? sys.memUsage * 100 : null;
    final disk = hasData && sys.hasDisk ? sys.diskUsage * 100 : null;

    String systemName = '—';
    String systemVersion = '';
    if (sys != null) {
      if (sys.type.isNotEmpty) {
        systemName = sys.type;
      } else if (sys.platform.isNotEmpty) {
        systemName = sys.platform;
      }
      systemVersion = sys.systemVersion;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 节点名称列
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      l.clusterHome_monitor,
                      theme.colorScheme.primary,
                      theme.colorScheme.onPrimary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                online
                    ? l.clusterHome_systemInfo(
                        systemName,
                        systemVersion.isEmpty ? '' : ' · $systemVersion',
                      )
                    : (error ?? l.node_offline),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: online
                      ? theme.colorScheme.onSurfaceVariant
                      : (error != null
                            ? theme.colorScheme.error
                            : theme.colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: _metricCell(
            theme,
            cpu,
            tooltip: cpu == null
                ? null
                : l.clusterHome_cpuTooltip(cpu.toStringAsFixed(1)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: _metricCell(
            theme,
            mem,
            detail: _memDetail(sys),
            tooltip: mem == null
                ? null
                : l.clusterHome_memoryTooltip(
                    mem.toStringAsFixed(1),
                    _memDetail(sys),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: _metricCell(
            theme,
            disk,
            detail: _diskDetail(sys),
            tooltip: disk == null
                ? null
                : l.clusterHome_diskTooltip(
                    disk.toStringAsFixed(1),
                    _diskDetail(sys),
                  ),
          ),
        ),
      ],
    );
  }

  /// 单个指标的单元格：百分比 + 用量条（悬停显示精确值）。
  Widget _metricCell(
    ThemeData theme,
    double? percent, {
    String? detail,
    String? tooltip,
  }) {
    final pct = percent;
    Widget cell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (detail != null && detail.isNotEmpty)
              Flexible(
                child: Text(
                  detail,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (pct == null)
          const SizedBox(height: 8)
        else
          _UsageBar(fraction: pct / 100, color: _usageColor(theme, pct)),
      ],
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      cell = Tooltip(message: tooltip, child: cell);
    }
    return cell;
  }
}

/// 使用率进度条（按比例填充）。
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

Widget _badge(ThemeData theme, String text, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: bg.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg)),
  );
}

/// 按使用率返回警示色：<70% 绿 / 70~90% 黄 / ≥90% 红。
Color _usageColor(ThemeData theme, double pct) {
  if (pct >= 90) return theme.colorScheme.error;
  if (pct >= 70) return Colors.amber;
  return Colors.green;
}

String _memDetail(OverviewSystem? sys) {
  if (sys == null || sys.totalMem <= 0) return '';
  return '${_fmtBytes(sys.totalMem - sys.freeMem)} / ${_fmtBytes(sys.totalMem)}';
}

String _diskDetail(OverviewSystem? sys) {
  if (sys == null || sys.diskTotal <= 0) return '';
  return '${_fmtBytes(sys.diskUsed)} / ${_fmtBytes(sys.diskTotal)}';
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
