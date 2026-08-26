// 节点管理界面
// 点击节点卡片后进入的页面，按节点类型展示功能标签页：
// - 概览：主机信息 / 资源占用 / 实例统计（两类型均有 API）
// - 实例：实例列表与启动/停止/重启/强制终止（两类型均有 API）
// - 容器：Docker / Bastille 容器环境全功能管理（irix-node 全功能，MCSM 受限回退）
// - 用户：用户管理（仅 MCSM 面板提供 API）
// 文件管理已收归实例详情页（RemoteInstanceDetailScreen「文件」Tab），此处不再提供。
// "只显示 API 有的功能"：MCSM 侧仅展示文档中带 API 的能力。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/node_ops.dart';
import '../models/remote.dart';
import '../services/container/node_container_backend.dart';
import '../services/node_api_client.dart';
import '../services/node_daemon_launcher.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../utils/docker_visibility.dart';
import '../widgets/container_environment_panel.dart';
import 'remote_instance_detail_screen.dart';

/// 节点管理界面。
class NodeDetailScreen extends StatefulWidget {
  const NodeDetailScreen({super.key, required this.nodeId});

  final String nodeId;

  @override
  State<NodeDetailScreen> createState() => _NodeDetailScreenState();
}

class _NodeDetailScreenState extends State<NodeDetailScreen> {
  NodeInfo? _node;
  NodeApiClient? _client;
  OverviewData? _overview;
  bool _loading = true;
  String? _error;

  /// 当前使用的守护进程（有多个时由实例/文件标签页切换）。
  String? _daemonId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = context.read<NodeState>();
    NodeInfo? node;
    for (final n in state.nodes) {
      if (n.id == widget.nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) {
      setState(() {
        _loading = false;
        _error = '节点不存在或已被删除';
      });
      return;
    }
    final client = NodeApiClient.of(node);
    OverviewData? overview;
    try {
      overview = await client.overview();
    } catch (e) {
      overview = null;
      _error ??= e.toString();
    }
    if (!mounted) return;
    setState(() {
      _node = node;
      _client = client;
      _overview = overview;
      _loading = false;
      if (overview != null && overview.remote.isNotEmpty) {
        // 优先选择可用守护进程
        final available = overview.remote.where((d) => d.available).toList();
        _daemonId =
            (available.isNotEmpty ? available : overview.remote).first.uuid;
      }
    });
  }

  Future<void> _refreshOverview() async {
    final client = _client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final overview = await client.overview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 按节点类型确定标签页。
  ///
  /// 「容器」标签页展示节点容器环境的全功能管理（Docker / Bastille 按节点平台），
  /// 节点在线即展示；平台不支持时面板呈现不可用状态与原因。
  List<({String label, IconData icon, Widget child})> _tabs(NodeInfo node) {
    final client = _client!;
    final daemonId = _daemonId;
    final overview = _overview;
    final tabs = <({String label, IconData icon, Widget child})>[
      (
        label: '概览',
        icon: Icons.monitor_heart_outlined,
        child: _OverviewTab(
          node: node,
          client: client,
          overview: overview,
          onRetry: _refreshOverview,
        ),
      ),
      (
        label: '实例',
        icon: Icons.storage_outlined,
        child: _InstancesTab(
          node: node,
          client: client,
          overview: overview,
          initialDaemonId: daemonId,
        ),
      ),
    ];
    // 容器环境管理（Docker 全功能 / Bastille 全功能，按节点平台选后端）。
    // 节点在线即展示；平台不支持时面板呈现不可用状态与原因。
    if (overview != null) {
      tabs.add((
        label: '容器',
        icon: Icons.inventory_2,
        child: ContainerEnvironmentPanel(
          backend: nodeContainerBackend(
            client: client,
            daemonId: daemonId ?? '',
            platformHint: overview.system.platform,
          ),
          nodeClient: client,
          daemonId: daemonId ?? '',
        ),
      ));
    }
    // MCSM 面板额外提供用户管理 API
    if (node.type == NodeType.mcsm) {
      tabs.add((
        label: '用户',
        icon: Icons.people_outline,
        child: _UsersTab(client: client, daemonId: daemonId),
      ));
    }
    // IriX 本地节点额外提供运维 API（Java 运行时 / 目录导入 / 核心下载 /
    // 节点负载 / 审计日志，见 node_api_client 新增方法组）。
    if (node.type == NodeType.node) {
      tabs.add((
        label: '运维',
        icon: Icons.build_outlined,
        child: NodeOpsTab(client: client, daemonId: daemonId),
      ));
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final node = _node;
    if (node == null || _client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('节点')),
        body: Center(child: Text(_error ?? '未知错误')),
      );
    }
    final tabs = _tabs(node);
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(node.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _refreshOverview,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            _buildStatusBar(node),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final tab in tabs)
                  Tab(icon: Icon(tab.icon), text: tab.label),
              ],
            ),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.child]),
            ),
          ],
        ),
      ),
    );
  }

  /// 节点在线状态提示条。
  Widget _buildStatusBar(NodeInfo node) {
    final theme = Theme.of(context);
    final online = _overview != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: online
          ? Colors.green.withValues(alpha: 0.12)
          : theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(
            online ? Icons.circle : Icons.error_outline,
            size: 12,
            color: online ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              online ? '节点在线 · ${node.address}' : '节点离线：${_error ?? '无法连接'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: online ? Colors.green : theme.colorScheme.error,
              ),
            ),
          ),
          if (!online && node.type == NodeType.node)
            TextButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('启动本地节点'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _launchLocalDaemon,
            ),
        ],
      ),
    );
  }

  /// 启动本地 Go 守护进程。
  Future<void> _launchLocalDaemon() async {
    final node = _node;
    if (node == null) return;
    final uri = Uri.tryParse(node.address);
    if (uri == null || (uri.host != '127.0.0.1' && uri.host != 'localhost')) {
      showAppDialog<void>(
        context,
        (_) => AlertDialog(
          title: const Text('无法启动'),
          content: Text('「${node.name}」不是本地地址，请确认 irix-node 已在该服务器上运行。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    final port = uri.port;
    final result = await NodeDaemonLauncher.ensureRunning(
      address: node.address,
      port: port,
    );
    if (!mounted) return;
    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 4),
      ),
    );
    if (result.launched) {
      await _refreshOverview();
      if (!mounted) return;
      await context.read<NodeState>().pingNode(node.id);
    }
  }
}

// ==================== 概览标签页 ====================

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.node,
    required this.client,
    required this.overview,
    required this.onRetry,
  });

  final NodeInfo node;
  final NodeApiClient client;
  final OverviewData? overview;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = overview;
    if (data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '无法获取节点信息\n${client.baseUrl}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: onRetry,
            ),
          ],
        ),
      );
    }

    final sys = data.system;
    final totalGb = sys.totalMem / (1024 * 1024 * 1024);
    final freeGb = sys.freeMem / (1024 * 1024 * 1024);
    final usedGb = totalGb - freeGb;
    final memPercent = totalGb > 0 ? usedGb / totalGb * 100 : 0.0;
    final uptime = sys.uptime;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
          title: '主机信息',
          icon: Icons.computer,
          rows: [
            ('主机名', sys.hostname.isEmpty ? '—' : sys.hostname),
            ('系统', sys.type.isEmpty ? '—' : '${sys.type} / ${sys.release}'),
            ('平台', sys.platform.isEmpty ? '—' : sys.platform),
            ('运行时间', _formatUptime(uptime)),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: '资源占用',
          icon: Icons.memory,
          rows: [
            (
              '内存',
              totalGb > 0
                  ? '${usedGb.toStringAsFixed(1)} / ${totalGb.toStringAsFixed(1)} GB（${memPercent.toStringAsFixed(1)}%）'
                  : '—',
            ),
            (
              'CPU',
              data.system.cpuUsage > 0
                  ? '${(data.system.cpuUsage * 100).toStringAsFixed(1)}%'
                  : '—',
            ),
            (
              '节点进程内存',
              data.process.memory > 0 ? _formatBytes(data.process.memory) : '—',
            ),
            ('节点版本', data.version.isEmpty ? '—' : data.version),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: '实例统计',
          icon: Icons.storage,
          rows: [
            ('守护进程', data.remote.isEmpty ? '—' : '${data.remote.length} 个'),
            for (final daemon in data.remote)
              (
                daemon.displayName,
                '运行 ${daemon.runningInstances} / 共 ${daemon.totalInstances}',
              ),
          ],
        ),
        if (data.remote.length > 1) ...[
          const SizedBox(height: 12),
          _InfoCard(
            title: '守护进程列表',
            icon: Icons.dns_outlined,
            rows: [
              for (final daemon in data.remote)
                (
                  daemon.displayName,
                  '${daemon.available ? '在线' : '离线'} · ${daemon.version.isEmpty ? '版本未知' : daemon.version} · '
                      '${daemon.ip.isNotEmpty ? daemon.ip : '—'}:${daemon.port}',
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _formatUptime(double seconds) {
    if (seconds <= 0) return '—';
    final totalMinutes = seconds ~/ 60;
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;
    if (days > 0) return '$days 天 $hours 小时';
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    return '$minutes 分钟';
  }

  static String _formatBytes(int bytes) {
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
}

/// 概览信息卡片。
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final (key, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 实例标签页 ====================

/// 实例状态标签（与本地实例样式保持一致）。
Widget remoteStatusChip(BuildContext context, RemoteStatus status) {
  final color = switch (status) {
    RemoteStatus.running => Colors.green,
    RemoteStatus.starting => Colors.orange,
    RemoteStatus.stopping => Colors.amber,
    RemoteStatus.busy => Colors.red,
    RemoteStatus.stopped => Colors.grey,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(status.label, style: TextStyle(color: color, fontSize: 12)),
  );
}

class _InstancesTab extends StatefulWidget {
  const _InstancesTab({
    required this.node,
    required this.client,
    required this.overview,
    required this.initialDaemonId,
  });

  final NodeInfo node;
  final NodeApiClient client;
  final OverviewData? overview;
  final String? initialDaemonId;

  @override
  State<_InstancesTab> createState() => _InstancesTabState();
}

class _InstancesTabState extends State<_InstancesTab> {
  String? _daemonId;
  List<RemoteInstance>? _instances;
  bool _loading = true;
  String? _error;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    final daemons = widget.overview?.remote ?? [];
    _daemonId =
        widget.initialDaemonId ??
        (daemons.isNotEmpty ? daemons.first.uuid : null);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final daemonId = _daemonId;
    if (daemonId == null || daemonId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无法确定守护进程 ID，请检查节点连接';
      });
      return;
    }
    try {
      final instances = await widget.client.listInstances(daemonId: daemonId);
      if (!mounted) return;
      setState(() {
        _instances = instances;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _action(RemoteInstance instance, RemoteAction action) async {
    final daemonId = _daemonId;
    if (daemonId == null) return;
    setState(() => _actionError = null);
    try {
      await widget.client.instanceAction(
        uuid: instance.uuid,
        daemonId: daemonId,
        action: action,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.toString());
    }
  }

  Future<void> _create() async {
    final daemonId = _daemonId;
    if (daemonId == null) return;
    final showDocker = shouldShowDockerSettings(
      nodePlatform: widget.overview?.system.platform,
    );
    final result = await showAppDialog<_CreateInstanceResult?>(
      context,
      (_) => _CreateInstanceDialog(showDocker: showDocker),
    );
    if (result == null || !mounted) return;
    try {
      await widget.client.createInstance(
        daemonId: daemonId,
        config: InstanceConfig(
          nickname: result.nickname,
          startCommand: result.startCommand,
          stopCommand: 'stop',
          cwd: result.cwd,
          processType: result.processType,
          docker: result.docker,
          createDatetime: DateTime.now().millisecondsSinceEpoch,
        ).toJson(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.toString());
    }
  }

  void _openDetail(RemoteInstance instance) {
    pushPage<void>(
      context,
      (_) => RemoteInstanceDetailScreen(
        node: widget.node,
        client: widget.client,
        daemonId: _daemonId ?? '',
        initialInstance: instance,
        nodePlatform: widget.overview?.system.platform,
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daemons = widget.overview?.remote ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              if (daemons.length > 1) ...[
                Icon(Icons.dns, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _daemonId,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final d in daemons)
                      DropdownMenuItem(
                        value: d.uuid,
                        child: Text(d.displayName),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _daemonId = value);
                    _load();
                  },
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  daemons.length > 1
                      ? '选择守护进程后管理其实例'
                      : '共 ${_instances?.length ?? 0} 个实例',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _create,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建实例'),
              ),
            ],
          ),
        ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _actionError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Expanded(child: _buildList(theme)),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    final instances = _instances ?? [];
    if (instances.isEmpty) {
      return Center(
        child: Text(
          '暂无实例\n点击右上角「新建实例」创建',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: instances.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final instance = instances[index];
        return _RemoteInstanceCard(
          instance: instance,
          onTap: () => _openDetail(instance),
          onStart: () => _action(instance, RemoteAction.start),
          onStop: () => _action(instance, RemoteAction.stop),
          onRestart: () => _action(instance, RemoteAction.restart),
          onKill: () => _action(instance, RemoteAction.kill),
        );
      },
    );
  }
}

/// 远程实例卡片。
class _RemoteInstanceCard extends StatelessWidget {
  const _RemoteInstanceCard({
    required this.instance,
    required this.onTap,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onKill,
  });

  final RemoteInstance instance;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = instance.status;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.storage,
                    size: 24,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      instance.config.nickname.isEmpty
                          ? instance.uuid
                          : instance.config.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  remoteStatusChip(context, status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                instance.config.cwd.isEmpty ? '工作目录未知' : instance.config.cwd,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (instance.currentPlayers >= 0) ...[
                const SizedBox(height: 2),
                Text(
                  '在线玩家 ${instance.currentPlayers} / ${instance.maxPlayers}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionButton(
                    icon: Icons.play_arrow,
                    label: '启动',
                    color: Colors.green,
                    onPressed: status == RemoteStatus.stopped ? onStart : null,
                  ),
                  _ActionButton(
                    icon: Icons.stop,
                    label: '停止',
                    color: Colors.orange,
                    onPressed: status.isActive ? onStop : null,
                  ),
                  _ActionButton(
                    icon: Icons.restart_alt,
                    label: '重启',
                    color: Colors.blue,
                    onPressed: status.isActive ? onRestart : null,
                  ),
                  _ActionButton(
                    icon: Icons.power_settings_new,
                    label: '强杀',
                    color: Colors.red,
                    onPressed: status.isActive ? onKill : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 小操作按钮。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: onPressed == null ? null : color),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        disabledForegroundColor: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}

// ==================== 用户标签页（MCSM 面板）====================

/// 用户管理：列表 / 创建 / 权限修改 / 删除。
class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.client, required this.daemonId});

  final NodeApiClient client;
  final String? daemonId;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<RemoteUser>? _users;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client.listUsers(page: 1, pageSize: 100);
      if (!mounted) return;
      setState(() {
        _users = data.users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final result = await showAppDialog<(String, String, int)?>(
      context,
      (_) => const _CreateUserDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await widget.client.createUser(
        username: result.$1,
        password: result.$2,
        permission: result.$3,
      );
      await _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _setPermission(RemoteUser user, int permission) async {
    try {
      await widget.client.updateUser(
        config: {...user.toConfigJson(), 'permission': permission},
      );
      await _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _delete(RemoteUser user) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除用户「${user.userName}」？'),
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
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.deleteUsers([user.uuid]);
      await _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '用户管理（面板 API）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _create,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('新建用户'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildList(theme)),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    final users = _users ?? [];
    if (users.isEmpty) {
      return Center(child: Text('暂无用户', style: theme.textTheme.bodyMedium));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = users[index];
        final isAdmin = user.permission == 10;
        final isBanned = user.permission == -1;
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: CircleAvatar(
              radius: 18,
              child: Text(user.userName.isEmpty ? '?' : user.userName[0]),
            ),
            title: Text(user.userName),
            subtitle: Text(
              '注册 ${user.registerTime.isEmpty ? '—' : user.registerTime}\n'
              '实例 ${user.instances.length} 个',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isBanned
                                ? Colors.red
                                : isAdmin
                                ? Colors.blue
                                : Colors.grey)
                            .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isBanned ? '已禁用' : (isAdmin ? '管理员' : '普通用户'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isBanned
                          ? Colors.red
                          : isAdmin
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'admin':
                        _setPermission(user, 10);
                      case 'user':
                        _setPermission(user, 1);
                      case 'ban':
                        _setPermission(user, -1);
                      case 'unban':
                        _setPermission(user, 1);
                      case 'delete':
                        _delete(user);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!isAdmin)
                      const PopupMenuItem(value: 'admin', child: Text('设为管理员')),
                    if (isAdmin)
                      const PopupMenuItem(value: 'user', child: Text('设为普通用户')),
                    if (!isBanned)
                      const PopupMenuItem(value: 'ban', child: Text('禁用')),
                    if (isBanned)
                      const PopupMenuItem(value: 'unban', child: Text('解除禁用')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 新建用户对话框。
class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  int _permission = 1;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建用户'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _permission,
              decoration: const InputDecoration(
                labelText: '权限',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('普通用户')),
                DropdownMenuItem(value: 10, child: Text('管理员')),
                DropdownMenuItem(value: -1, child: Text('禁用')),
              ],
              onChanged: (v) => setState(() => _permission = v ?? 1),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _username.text.trim();
            final pass = _password.text.trim();
            if (name.isEmpty || pass.isEmpty) return;
            Navigator.of(context).pop((name, pass, _permission));
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 新建远程实例的结果。
class _CreateInstanceResult {
  final String nickname;
  final String cwd;
  final String startCommand;
  final String processType;
  final InstanceDockerConfig docker;

  const _CreateInstanceResult({
    required this.nickname,
    required this.cwd,
    required this.startCommand,
    required this.processType,
    required this.docker,
  });
}

/// 新建远程实例对话框。
///
/// [showDocker] 为 false 时不显示进程类型选择与 Docker 配置
/// （客户端 Windows + 节点 Windows 的情况，见 shouldShowDockerSettings）。
class _CreateInstanceDialog extends StatefulWidget {
  const _CreateInstanceDialog({required this.showDocker});

  final bool showDocker;

  @override
  State<_CreateInstanceDialog> createState() => _CreateInstanceDialogState();
}

class _CreateInstanceDialogState extends State<_CreateInstanceDialog> {
  late final TextEditingController _name;
  late final TextEditingController _cwd;
  late final TextEditingController _command;

  // Docker 配置
  String _processType = 'universal';
  final _dockerImage = TextEditingController(text: 'mcsm-ubuntu:22.04');
  final _dockerMemory = TextEditingController(text: '1024');
  final _dockerPorts = TextEditingController(text: '25565:25565/tcp');
  final _dockerVolumes = TextEditingController();
  final _dockerContainerName = TextEditingController();
  String _networkMode = 'bridge';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _cwd = TextEditingController();
    _command = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _cwd.dispose();
    _command.dispose();
    _dockerImage.dispose();
    _dockerMemory.dispose();
    _dockerPorts.dispose();
    _dockerVolumes.dispose();
    _dockerContainerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('新建实例'),
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
              if (widget.showDocker) ...[
                const SizedBox(height: 16),
                const Divider(),
                DropdownButtonFormField<String>(
                  initialValue: _processType,
                  decoration: const InputDecoration(
                    labelText: '进程类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'universal',
                      child: Text('通用（直接运行进程）'),
                    ),
                    DropdownMenuItem(
                      value: 'docker',
                      child: Text('Docker（容器内运行）'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _processType = v ?? 'universal'),
                ),
                if (_processType == 'docker') ..._buildDockerFields(theme),
              ],
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
              _CreateInstanceResult(
                nickname: name,
                cwd: cwd,
                startCommand: command,
                processType: _processType,
                docker: _buildDockerConfig(),
              ),
            );
          },
          child: const Text('创建'),
        ),
      ],
    );
  }

  /// Docker 配置字段（进程类型为 docker 时显示）。
  List<Widget> _buildDockerFields(ThemeData theme) {
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _dockerImage,
        decoration: const InputDecoration(
          labelText: 'Docker 镜像（如 mcsm-ubuntu:22.04）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _dockerMemory,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '内存限制（MB）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _networkMode,
              decoration: const InputDecoration(
                labelText: '网络模式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'bridge', child: Text('bridge')),
                DropdownMenuItem(value: 'host', child: Text('host')),
                DropdownMenuItem(value: 'none', child: Text('none')),
              ],
              onChanged: (v) => setState(() => _networkMode = v ?? 'bridge'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerPorts,
        decoration: const InputDecoration(
          labelText: '端口映射（逗号分隔，如 25565:25565/tcp）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerVolumes,
        decoration: const InputDecoration(
          labelText: '额外挂载卷（逗号分隔，如 /data:/data）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerContainerName,
        decoration: const InputDecoration(
          labelText: '容器名称（可留空自动生成）',
          border: OutlineInputBorder(),
        ),
      ),
    ];
  }

  InstanceDockerConfig _buildDockerConfig() {
    List<String> split(String value) => value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return InstanceDockerConfig(
      containerName: _dockerContainerName.text.trim(),
      image: _dockerImage.text.trim().isEmpty
          ? 'mcsm-ubuntu:22.04'
          : _dockerImage.text.trim(),
      memory: int.tryParse(_dockerMemory.text.trim()) ?? 1024,
      ports: split(_dockerPorts.text),
      extraVolumes: split(_dockerVolumes.text),
      networkMode: _networkMode,
    );
  }
}

extension on RemoteStatus {
  bool get isActive =>
      this == RemoteStatus.running ||
      this == RemoteStatus.starting ||
      this == RemoteStatus.stopping;
}

// ==================== IriX 节点运维（Java / 导入 / 核心下载 / 负载 / 审计）====================

/// IriX 本地节点「运维」标签页：Java 运行时管理、从目录导入实例、
/// 下载核心到实例、节点负载状态、审计日志查看。仅 irix-node 支持。
class NodeOpsTab extends StatefulWidget {
  const NodeOpsTab({super.key, required this.client, this.daemonId});

  final NodeApiClient client;
  final String? daemonId;

  @override
  State<NodeOpsTab> createState() => _NodeOpsTabState();
}

class _NodeOpsTabState extends State<NodeOpsTab> {
  // ---- Java 运行时 ----
  List<JavaRuntime> _javas = [];
  JavaRuntime? _defaultJava;
  bool _javaLoading = true;
  bool _javaBusy = false;
  String? _javaStatus;
  String? _javaError;
  Timer? _javaInstallPoll;

  // ---- 审计日志 ----
  bool _auditLoading = false;

  @override
  void initState() {
    super.initState();
    _loadJavas();
  }

  @override
  void dispose() {
    _cancelJavaPoll();
    super.dispose();
  }

  // ==================== Java 运行时 ====================

  Future<void> _loadJavas() async {
    setState(() {
      _javaLoading = true;
      _javaError = null;
    });
    try {
      final result = await widget.client.javaRuntimes();
      if (!mounted) return;
      setState(() {
        _javas = result.all;
        _defaultJava = result.defaultRuntime;
        _javaLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _javaError = e.toString();
        _javaLoading = false;
      });
    }
  }

  /// 安装指定大版本 JDK（任务化，轮询进度）。
  Future<void> _installJava(int major) async {
    if (_javaBusy) return;
    _cancelJavaPoll();
    setState(() {
      _javaBusy = true;
      _javaStatus = '安装 JDK $major 中…';
      _javaError = null;
    });
    try {
      final jobId = await widget.client.installJava(major);
      _javaInstallPoll = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) async {
          try {
            final p = await widget.client.javaInstallProgress(jobId);
            if (!mounted) return;
            setState(() => _javaStatus = p.message.isEmpty ? p.status : p.message);
            if (p.isDone) {
              _cancelJavaPoll();
              if (!mounted) return;
              setState(() {
                _javaBusy = false;
                _javaStatus = null;
              });
              await _loadJavas();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('JDK $major 安装完成')),
                );
              }
            } else if (p.isFailed) {
              _cancelJavaPoll();
              if (!mounted) return;
              setState(() {
                _javaBusy = false;
                _javaStatus = null;
                _javaError = 'JDK $major 安装失败';
              });
            }
          } catch (e) {
            _cancelJavaPoll();
            if (!mounted) return;
            setState(() {
              _javaBusy = false;
              _javaStatus = null;
              _javaError = e.toString();
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _javaBusy = false;
        _javaStatus = null;
        _javaError = e.toString();
      });
    }
  }

  Future<void> _uninstallJava(int major) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('卸载 JDK $major？'),
        content: const Text('将从节点 {data}/jdk 删除该版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.uninstallJava(major);
      await _loadJavas();
    } catch (e) {
      if (!mounted) return;
      setState(() => _javaError = e.toString());
    }
  }

  void _cancelJavaPoll() {
    _javaInstallPoll?.cancel();
    _javaInstallPoll = null;
  }

  // ==================== 从目录导入实例 ====================

  Future<void> _importInstance() async {
    final daemonId = widget.daemonId ?? '';
    if (daemonId.isEmpty) return;
    final result = await showAppDialog<({String path, String nickname})?>(
      context,
      (_) => const _ImportInstanceDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final uuid = await widget.client.importInstance(
        daemonId: daemonId,
        path: result.path,
        nickname: result.nickname,
      );
      if (!mounted) return;
      if (uuid.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入实例 $uuid，请在「实例」标签页查看')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入失败')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  // ==================== 下载核心到实例 ====================

  Future<void> _downloadCore() async {
    final result =
        await showAppDialog<({String uuid, String url, String fileName, String? sha512})?>(
      context,
      (_) => const _DownloadCoreDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final jobId = await widget.client.downloadCore(
        uuid: result.uuid,
        url: result.url,
        fileName: result.fileName,
        sha512: result.sha512,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已开始下载核心（任务 $jobId），进度见节点日志')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('核心下载失败：$e')),
      );
    }
  }

  // ==================== 节点负载 ====================

  Future<void> _showLoad() async {
    setState(() => _auditLoading = true);
    try {
      final load = await widget.client.nodeLoad();
      if (!mounted) return;
      final cpuBusy = ((load['cpuBusy'] as num?) ?? 0).toDouble() * 100;
      final rows = <(String, String)>[
        ('状态', '${load['state'] ?? '—'}'),
        ('GOMAXPROCS', '${load['gomaxprocs'] ?? '—'}'),
        ('GC 百分比', '${load['gcPercent'] ?? '—'}'),
        ('CPU 占用', '${cpuBusy.toStringAsFixed(1)}%'),
        ('goroutine 数', '${load['goroutines'] ?? '—'}'),
        ('堆内存', '${load['heapAlloc'] ?? '—'}'),
        ('CPU 核数', '${load['numCPU'] ?? '—'}'),
      ];
      await showAppDialog<void>(
        context,
        (_) => _NodeInfoDialog(title: '节点负载', rows: rows),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取负载失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  // ==================== 审计日志 ====================

  Future<void> _showAudit() async {
    setState(() => _auditLoading = true);
    try {
      final log = await widget.client.auditLog(tail: 200);
      if (!mounted) return;
      await showAppDialog<void>(
        context,
        (_) => _AuditLogDialog(log: log),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取审计日志失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _opsCard(
          theme,
          title: '从目录导入实例',
          description: '指定节点侧已存在的服务端目录，节点扫描特征后创建实例。',
          icon: Icons.drive_folder_upload_outlined,
          trailing: FilledButton.icon(
            icon: const Icon(Icons.download_for_offline, size: 18),
            label: const Text('导入'),
            onPressed: _importInstance,
          ),
        ),
        const SizedBox(height: 12),
        _opsCard(
          theme,
          title: '下载服务端核心到实例',
          description: '节点直连 URL 下载核心 jar 到实例根目录（支持 sha512 校验）。',
          icon: Icons.download_outlined,
          trailing: FilledButton.icon(
            icon: const Icon(Icons.cloud_download, size: 18),
            label: const Text('下载核心'),
            onPressed: _downloadCore,
          ),
        ),
        const SizedBox(height: 12),
        _buildJavaCard(theme),
        const SizedBox(height: 12),
        _opsCard(
          theme,
          title: '节点负载',
          description: '守护进程自身负载调谐状态（idle/normal/busy、GOMAXPROCS、GC）。',
          icon: Icons.speed_outlined,
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: const Text('查看'),
            onPressed: _auditLoading ? null : _showLoad,
          ),
        ),
        const SizedBox(height: 12),
        _opsCard(
          theme,
          title: '审计日志',
          description: '记录每一次 API 请求（来源 IP、方法、路径、状态码、耗时）。',
          icon: Icons.history_edu_outlined,
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('查看'),
            onPressed: _auditLoading ? null : _showAudit,
          ),
        ),
      ],
    );
  }

  Widget _buildJavaCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.coffee_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Java 运行时', style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '刷新',
                  onPressed: _javaBusy ? null : _loadJavas,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '检测节点上的 Java 安装；可安装 Adoptium JDK 到 {data}/jdk。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_javaLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_javas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '（未检测到 Java 运行时）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final rt in _javas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        rt == _defaultJava
                            ? Icons.check_circle
                            : Icons.coffee_outlined,
                        size: 16,
                        color: rt == _defaultJava ? Colors.green : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'JDK ${rt.major} · ${rt.version} · ${rt.vendor}${rt.available ? '' : '（不可用）'}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (rt.major > 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: '卸载',
                          visualDensity: VisualDensity.compact,
                          onPressed: _javaBusy ? null : () => _uninstallJava(rt.major),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [8, 11, 17, 21, 25]
                  .map(
                    (major) => OutlinedButton(
                      onPressed: _javaBusy ? null : () => _installJava(major),
                      child: Text('安装 JDK $major'),
                    ),
                  )
                  .toList(),
            ),
            if (_javaBusy) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _javaStatus ?? '处理中…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (_javaError != null) ...[
              const SizedBox(height: 8),
              Text(
                _javaError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _opsCard(
    ThemeData theme, {
    required String title,
    required String description,
    required IconData icon,
    required Widget trailing,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// 导入实例对话框（节点侧路径 + 实例名）。
class _ImportInstanceDialog extends StatefulWidget {
  const _ImportInstanceDialog();

  @override
  State<_ImportInstanceDialog> createState() => _ImportInstanceDialogState();
}

class _ImportInstanceDialogState extends State<_ImportInstanceDialog> {
  final _pathController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    Navigator.of(context).pop((path: path, nickname: _nameController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('从目录导入实例'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: '节点侧目录绝对路径',
                hintText: '如 /home/mc/server',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '实例名（可空，默认取目录名）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('导入')),
      ],
    );
  }
}

/// 下载核心对话框（实例 UUID + URL + 文件名 + sha512）。
class _DownloadCoreDialog extends StatefulWidget {
  const _DownloadCoreDialog();

  @override
  State<_DownloadCoreDialog> createState() => _DownloadCoreDialogState();
}

class _DownloadCoreDialogState extends State<_DownloadCoreDialog> {
  final _uuidController = TextEditingController();
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _shaController = TextEditingController();

  @override
  void dispose() {
    _uuidController.dispose();
    _urlController.dispose();
    _nameController.dispose();
    _shaController.dispose();
    super.dispose();
  }

  void _submit() {
    final uuid = _uuidController.text.trim();
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    if (uuid.isEmpty || url.isEmpty || name.isEmpty) return;
    final sha = _shaController.text.trim();
    Navigator.of(context).pop((
      uuid: uuid,
      url: url,
      fileName: name,
      sha512: sha.isEmpty ? null : sha,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('下载服务端核心'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _uuidController,
                decoration: const InputDecoration(
                  labelText: '目标实例 UUID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: '下载链接 (http/https)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '文件名（如 server.jar）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _shaController,
                decoration: const InputDecoration(
                  labelText: 'sha512 校验（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('开始下载')),
      ],
    );
  }
}

/// 通用信息对话框（键值对行）。
class _NodeInfoDialog extends StatelessWidget {
  const _NodeInfoDialog({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (k, v) in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        k,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(v, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 审计日志查看对话框。
class _AuditLogDialog extends StatelessWidget {
  const _AuditLogDialog({required this.log});

  final String log;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('审计日志（最近 200 行）'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: SingleChildScrollView(
          child: SelectableText(
            log.isEmpty ? '（无审计日志）' : log,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
