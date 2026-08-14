// 集群实例管理页（多机模式第 2 页）
// 列出分布在节点上的集群实例：名称、所在节点、状态、崩溃次数、最近同步时间。
// 支持新建（按资源自动分配或手动选节点）、启动、优雅停止 + 增量同步、手动迁移。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cluster_instance.dart';
import '../models/node.dart';
import '../models/remote.dart';
import '../services/cluster_monitor.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import 'node_detail_screen.dart' show remoteStatusChip;
import 'remote_instance_detail_screen.dart';

/// 集群实例管理页。
class ClusterInstancesScreen extends StatefulWidget {
  const ClusterInstancesScreen({super.key});

  @override
  State<ClusterInstancesScreen> createState() => _ClusterInstancesScreenState();
}

class _ClusterInstancesScreenState extends State<ClusterInstancesScreen> {
  /// 实例最近远程状态缓存（instanceId → 状态）。
  final Map<String, RemoteStatus> _statuses = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadStatuses();
    });
  }

  Future<void> _loadStatuses() async {
    final nodeState = context.read<NodeState>();
    final cluster = context.read<ClusterState>();
    for (final instance in cluster.instances) {
      NodeInfo? node;
      for (final n in nodeState.nodes) {
        if (n.id == instance.nodeId) {
          node = n;
          break;
        }
      }
      if (node == null) continue;
      try {
        final remote = await nodeState
            .clientFor(node)
            .getInstance(
              uuid: instance.remoteUuid,
              daemonId: instance.daemonId,
            );
        if (!mounted) return;
        setState(() => _statuses[instance.id] = remote.status);
      } catch (_) {
        // 忽略：保持上次状态或默认关闭。
      }
    }
  }

  Future<void> _create() async {
    final nodeState = context.read<NodeState>();
    final result = await showAppDialog<_CreateClusterResult?>(
      context,
      (_) => _CreateClusterDialog(nodes: nodeState.nodes),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ClusterMonitor.instance.createWithAllocation(
        name: result.name,
        cwd: result.cwd,
        startCommand: result.startCommand,
        nodeId: result.nodeId,
      );
      await _loadStatuses();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(ClusterInstance instance) async {
    setState(() => _busy = true);
    try {
      await ClusterMonitor.instance.startInstance(instance);
      await _loadStatuses();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(ClusterInstance instance) async {
    setState(() => _busy = true);
    try {
      await ClusterMonitor.instance.gracefulStopAndSync(instance);
      await _loadStatuses();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _migrate(ClusterInstance instance) async {
    final nodeState = context.read<NodeState>();
    final candidates = nodeState.nodes
        .where((n) => n.id != instance.nodeId)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有其它节点可迁移')));
      return;
    }
    String? targetId = candidates.first.id;
    if (candidates.length > 1) {
      targetId = await showAppDialog<String>(
        context,
        (_) => _TargetNodeDialog(nodes: candidates),
      );
    }
    if (targetId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ClusterMonitor.instance.migrateTo(instance, targetNodeId: targetId);
      await _loadStatuses();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDetail(ClusterInstance instance) async {
    final nodeState = context.read<NodeState>();
    NodeInfo? node;
    for (final n in nodeState.nodes) {
      if (n.id == instance.nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) return;
    final targetNode = node;
    final client = nodeState.clientFor(targetNode);
    RemoteInstance remote;
    try {
      remote = await client.getInstance(
        uuid: instance.remoteUuid,
        daemonId: instance.daemonId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开详情: $e')));
      return;
    }
    // 取节点平台（决定详情页是否展示容器 Tab：Docker / Bastille）。
    String? nodePlatform;
    try {
      nodePlatform = (await client.overview()).system.platform;
    } catch (_) {
      nodePlatform = null;
    }
    if (!mounted) return;
    await pushPage<void>(
      context,
      (_) => RemoteInstanceDetailScreen(
        node: targetNode,
        client: client,
        daemonId: instance.daemonId,
        initialInstance: remote,
        nodePlatform: nodePlatform,
      ),
    );
    await _loadStatuses();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NodeState, ClusterState>(
      builder: (context, nodeState, cluster, _) {
        final instances = cluster.instances;
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('实例管理'),
              floating: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  onPressed: _busy ? null : _loadStatuses,
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建实例'),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (instances.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.storage_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('暂无集群实例，点击右上角「新建实例」'),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.builder(
                  itemCount: instances.length,
                  itemBuilder: (context, index) {
                    final instance = instances[index];
                    final nodeName = nodeState.nodes
                        .where((n) => n.id == instance.nodeId)
                        .map((n) => n.name)
                        .firstOrNull;
                    final status =
                        _statuses[instance.id] ?? RemoteStatus.stopped;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ClusterInstanceCard(
                        instance: instance,
                        nodeName: nodeName ?? instance.nodeId,
                        status: status,
                        onTap: () => _openDetail(instance),
                        onStart: () => _start(instance),
                        onStop: () => _stop(instance),
                        onMigrate: () => _migrate(instance),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 集群实例卡片。
class _ClusterInstanceCard extends StatelessWidget {
  const _ClusterInstanceCard({
    required this.instance,
    required this.nodeName,
    required this.status,
    required this.onTap,
    required this.onStart,
    required this.onStop,
    required this.onMigrate,
  });

  final ClusterInstance instance;
  final String nodeName;
  final RemoteStatus status;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onMigrate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive =
        status == RemoteStatus.running ||
        status == RemoteStatus.starting ||
        status == RemoteStatus.stopping;
    final synced = instance.lastSyncedAt;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.storage,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instance.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '节点：$nodeName',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  remoteStatusChip(context, status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '崩溃 $instance.crashCount 次 · 上次同步 ${synced == null ? '—' : _fmtTime(synced)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: isActive ? null : onStart,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('启动'),
                  ),
                  TextButton.icon(
                    onPressed: isActive ? onStop : null,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('停止'),
                  ),
                  TextButton.icon(
                    onPressed: isActive ? null : onMigrate,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('迁移'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 新建集群实例对话框结果。
class _CreateClusterResult {
  final String name;
  final String cwd;
  final String startCommand;
  final String? nodeId;

  const _CreateClusterResult({
    required this.name,
    required this.cwd,
    required this.startCommand,
    this.nodeId,
  });
}

/// 新建集群实例对话框。
class _CreateClusterDialog extends StatefulWidget {
  const _CreateClusterDialog({required this.nodes});

  final List<NodeInfo> nodes;

  @override
  State<_CreateClusterDialog> createState() => _CreateClusterDialogState();
}

class _CreateClusterDialogState extends State<_CreateClusterDialog> {
  final _name = TextEditingController();
  final _cwd = TextEditingController();
  final _command = TextEditingController();
  String? _nodeId; // null = 自动分配

  @override
  void dispose() {
    _name.dispose();
    _cwd.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建集群实例'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '实例名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cwd,
                decoration: const InputDecoration(
                  labelText: '工作目录（服务器上的绝对路径）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _command,
                decoration: const InputDecoration(
                  labelText: '启动命令（如 java -Xmx2G -jar server.jar nogui）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _nodeId,
                decoration: const InputDecoration(
                  labelText: '节点',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('自动（按资源分配）'),
                  ),
                  for (final node in widget.nodes)
                    DropdownMenuItem<String?>(
                      value: node.id,
                      child: Text(node.name),
                    ),
                ],
                onChanged: (v) => setState(() => _nodeId = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final cwd = _cwd.text.trim();
            final command = _command.text.trim();
            if (name.isEmpty || cwd.isEmpty || command.isEmpty) return;
            Navigator.of(context).pop(
              _CreateClusterResult(
                name: name,
                cwd: cwd,
                startCommand: command,
                nodeId: _nodeId,
              ),
            );
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 目标节点选择对话框。
class _TargetNodeDialog extends StatelessWidget {
  const _TargetNodeDialog({required this.nodes});

  final List<NodeInfo> nodes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择迁移目标节点'),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final node in nodes)
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(node.name),
                onTap: () => Navigator.of(context).pop(node.id),
              ),
          ],
        ),
      ),
    );
  }
}
