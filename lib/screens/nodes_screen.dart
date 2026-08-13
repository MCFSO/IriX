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
import '../widgets/node_card_grid.dart';
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
                NodeCardGrid(
                  nodes: nodes,
                  onlineOf: state.isOnline,
                  errorOf: state.errorOf,
                  onTapNode: _openNode,
                  onRenameNode: _rename,
                  onDeleteNode: _delete,
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

/// 供其他页面跳转到指定节点的管理界面。
void openNode(BuildContext context, String nodeId) {
  context.read<NodeState>().selectNode(nodeId);
  pushPage(context, (_) => NodeDetailScreen(nodeId: nodeId));
}
