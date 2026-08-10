// 节点管理页
// 左侧导航栏「节点」对应的页面：
// - 节点卡片以每行两个的网格展示（点击进入对应节点的管理界面）
// - 右上角 + 添加节点（类型 → 名称 → Key 三步向导）
// - 卡片菜单支持重命名 / 删除 / 刷新在线状态

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../services/node_daemon_launcher.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/add_node_dialog.dart';
import 'node_detail_screen.dart';

/// 节点管理页。
class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  bool _pinging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  /// 探测全部节点在线状态。
  Future<void> _refresh() async {
    setState(() => _pinging = true);
    await context.read<NodeState>().pingAll();
    if (mounted) setState(() => _pinging = false);
  }

  Future<void> _addNode() async {
    final node = await showAddNodeDialog(context);
    if (node == null || !mounted) return;
    final ok = await context.read<NodeState>().pingNode(node.id);
    if (!mounted) return;
    if (ok) {
      openNode(context, node.id);
    }
  }

  /// 打开节点管理界面。
  void _openNode(NodeInfo node) {
    context.read<NodeState>().selectNode(node.id);
    pushPage(context, (_) => NodeDetailScreen(nodeId: node.id));
  }

  Future<void> _rename(NodeInfo node) async {
    final controller = TextEditingController(text: node.name);
    final name = await showAppDialog<String>(
      context,
      (_) => AlertDialog(
        title: const Text('重命名节点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '节点名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && mounted) {
      await context.read<NodeState>().renameNode(node.id, name);
    }
  }

  Future<void> _delete(NodeInfo node) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除节点「${node.name}」？'),
        content: const Text('仅删除本地保存的节点信息，不会影响服务器上的数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NodeState>().removeNode(node.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NodeState>(
      builder: (context, state, _) {
        final nodes = state.nodes;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text('节点'),
                floating: true,
                actions: [
                  IconButton(
                    icon: _pinging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: '刷新状态',
                    onPressed: _pinging ? null : _refresh,
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
                          'MCSM：连接 MCSManager 面板\nNode：本地 Go 语言节点（node/ 目录）',
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
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 2.6,
                        ),
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      return _NodeCard(
                        node: node,
                        online: state.isOnline(node.id),
                        error: state.errorOf(node.id),
                        onTap: () => _openNode(node),
                        onRename: () => _rename(node),
                        onDelete: () => _delete(node),
                      );
                    },
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    NodeDaemonLauncher.isRunning
                        ? '本地节点守护进程正在运行'
                        : '提示：Node 类型节点需要先运行 node/ 目录构建的 irix-node 服务',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 节点卡片。
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.online,
    required this.error,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final NodeInfo node;
  final bool online;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = node.type == NodeType.node;
    return AppleCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  (online
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
                    const SizedBox(width: 8),
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
                        online ? '在线' : (error ?? '离线'),
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
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: theme.colorScheme.outline,
              size: 18,
            ),
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  onRename();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 供其他页面跳转到指定节点的管理界面。
void openNode(BuildContext context, String nodeId) {
  context.read<NodeState>().selectNode(nodeId);
  pushPage(context, (_) => NodeDetailScreen(nodeId: nodeId));
}
