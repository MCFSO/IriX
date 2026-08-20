// 集群容器管理页（多机模式「容器」导航项）
// 多机模式下统一的 Docker / Bastille 容器管理入口：
// - 左侧：节点列表（按平台显示运行时徽章 Docker / Bastille）；
// - 右侧：复用 ContainerEnvironmentPanel，按节点平台选择
//   NodeDockerBackend（Linux）或 NodeBastilleBackend（FreeBSD），
//   对节点容器环境进行全功能管理（Docker：容器/镜像/卷/网络；
//   Bastille：jail/发行/rdr/setup）。
//
// 客户端本身不支持 FreeBSD，Bastille 全部能力经远程 irix-node 暴露。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../services/container/container_backend.dart';
import '../services/container/node_container_backend.dart';
import '../services/node_api_client.dart';
import '../state/node_state.dart';
import '../widgets/add_node_dialog.dart';
import '../widgets/container_environment_panel.dart';

/// 集群容器管理页。
class ClusterContainerScreen extends StatefulWidget {
  const ClusterContainerScreen({super.key});

  @override
  State<ClusterContainerScreen> createState() => _ClusterContainerScreenState();
}

class _ClusterContainerScreenState extends State<ClusterContainerScreen> {
  /// 当前选中的节点 id。
  String? _selectedNodeId;

  /// 节点 overview 缓存（平台 / 守护进程信息，id → overview）。
  final Map<String, OverviewData> _overviews = {};

  /// overview 拉取中的节点。
  final Set<String> _loading = {};

  /// overview 拉取失败信息（id → 错误消息）。
  final Map<String, String> _overviewErrors = {};

  /// 容器后端缓存（节点 id → 后端，避免面板重建导致重复探测）。
  final Map<String, ContainerBackend> _backends = {};

  /// 顶部刷新中。
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  /// 刷新全部节点在线状态，并为在线节点预拉取 overview（平台 / 运行时）。
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final nodeState = context.read<NodeState>();
    await nodeState.pingAll();
    if (!mounted) return;
    final nodes = nodeState.nodes;
    if (nodes.isEmpty) {
      _selectedNodeId = null;
    } else if (_selectedNodeId == null ||
        !nodes.any((n) => n.id == _selectedNodeId)) {
      _selectedNodeId = nodes.first.id;
    }
    for (final node in nodes) {
      if (nodeState.isOnline(node.id)) {
        unawaited(_loadOverview(node));
      }
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  /// 拉取节点 overview（平台 + 守护进程）。
  Future<void> _loadOverview(NodeInfo node) async {
    if (_loading.contains(node.id) || _overviews.containsKey(node.id)) return;
    setState(() => _loading.add(node.id));
    try {
      final overview = await NodeApiClient.of(node).overview();
      _overviews[node.id] = overview;
      _overviewErrors.remove(node.id);
    } catch (e) {
      _overviewErrors[node.id] = e.toString();
    } finally {
      _loading.remove(node.id);
      if (mounted) setState(() {});
    }
  }

  /// 选择节点：必要时触发 overview 拉取。
  void _selectNode(NodeInfo node, bool online) {
    setState(() => _selectedNodeId = node.id);
    if (online && !_overviews.containsKey(node.id)) {
      unawaited(_loadOverview(node));
    }
  }

  /// 由 overview 解析守护进程 id（优先可用守护进程，与节点详情页一致）。
  String _daemonIdFor(OverviewData overview) {
    if (overview.remote.isEmpty) return '';
    final available = overview.remote.where((d) => d.available).toList();
    return (available.isNotEmpty ? available : overview.remote).first.uuid;
  }

  /// 平台 → 运行时提示（freebsd → Bastille，linux → Docker，未知 → null）。
  ContainerRuntime? _runtimeHint(String? platform) {
    final p = platform?.toLowerCase() ?? '';
    if (p == 'freebsd') return ContainerRuntime.bastille;
    if (p == 'linux') return ContainerRuntime.docker;
    return null;
  }

  /// 节点容器后端（按节点缓存）。
  ContainerBackend _backendFor(NodeInfo node, OverviewData overview) {
    return _backends.putIfAbsent(
      node.id,
      () => nodeContainerBackend(
        client: NodeApiClient.of(node),
        daemonId: _daemonIdFor(overview),
        platformHint: overview.system.platform,
      ),
    );
  }

  Future<void> _addNode() async {
    final node = await showAddNodeDialog(context);
    if (node == null || !mounted) return;
    final nodeState = context.read<NodeState>();
    await nodeState.pingNode(node.id);
    if (!mounted) return;
    setState(() => _selectedNodeId = node.id);
    if (nodeState.isOnline(node.id)) {
      unawaited(_loadOverview(node));
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final nodeState = context.watch<NodeState>();
    final nodes = nodeState.nodes;
    if (nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('还没有节点'),
            const SizedBox(height: 8),
            const Text(
              '添加 Linux 节点管理 Docker、添加 FreeBSD 节点管理 Bastille',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addNode,
              icon: const Icon(Icons.add),
              label: const Text('添加节点'),
            ),
          ],
        ),
      );
    }

    NodeInfo? selected;
    for (final n in nodes) {
      if (n.id == _selectedNodeId) {
        selected = n;
        break;
      }
    }
    selected ??= nodes.first;
    final overview = _overviews[selected.id];
    final online = nodeState.isOnline(selected.id);

    return Row(
      children: [
        // 左侧：节点列表
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  '节点',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: nodes.length,
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    return _buildNodeTile(nodeState, node, selected!);
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.add, size: 20),
                title: const Text('添加节点', style: TextStyle(fontSize: 13)),
                onTap: _addNode,
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧：选中节点的容器环境面板
        Expanded(child: _buildDetail(nodeState, selected, overview, online)),
      ],
    );
  }

  Widget _buildNodeTile(NodeState nodeState, NodeInfo node, NodeInfo selected) {
    final online = nodeState.isOnline(node.id);
    final overview = _overviews[node.id];
    final runtime = _runtimeHint(overview?.system.platform);
    return ListTile(
      selected: node.id == selected.id,
      onTap: () => _selectNode(node, online),
      leading: Icon(
        online ? Icons.dns_outlined : Icons.dns_outlined,
        color: online
            ? (runtime == ContainerRuntime.bastille
                  ? Colors.redAccent
                  : runtime == ContainerRuntime.docker
                        ? Colors.lightBlue
                        : Colors.green)
            : Colors.grey,
      ),
      title: Text(
        node.name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        online
            ? runtime == null
                  ? '在线 · 探测中…'
                  : '在线 · ${runtime.label}'
            : '离线',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: online && runtime != null
          ? _RuntimeBadge(runtime: runtime)
          : null,
    );
  }

  /// 右侧详情：面板 / 加载中 / 离线 / 错误。
  Widget _buildDetail(
    NodeState nodeState,
    NodeInfo node,
    OverviewData? overview,
    bool online,
  ) {
    if (!online) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '节点离线：${node.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (nodeState.errorOf(node.id) != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  nodeState.errorOf(node.id)!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (overview == null) {
      final error = _overviewErrors[node.id];
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error == null)
              const CircularProgressIndicator()
            else ...[
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _overviewErrors.remove(node.id);
                  unawaited(_loadOverview(node));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      );
    }
    final runtime = _runtimeHint(overview.system.platform);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              // 长节点名省略，窄窗口不溢出
              Flexible(
                child: Text(
                  node.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              if (runtime != null) _RuntimeBadge(runtime: runtime),
              const Spacer(),
              IconButton(
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshing ? null : _refresh,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ContainerEnvironmentPanel(
            key: ValueKey('container-panel-${node.id}'),
            backend: _backendFor(node, overview),
            nodeClient: NodeApiClient.of(node),
            daemonId: _daemonIdFor(overview),
          ),
        ),
      ],
    );
  }
}

/// 运行时徽章（Docker 蓝 / Bastille 红）。
class _RuntimeBadge extends StatelessWidget {
  const _RuntimeBadge({required this.runtime});

  final ContainerRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final color = runtime == ContainerRuntime.bastille
        ? Colors.redAccent
        : Colors.lightBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        runtime.label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
