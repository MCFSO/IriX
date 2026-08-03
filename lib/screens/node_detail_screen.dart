// 节点管理界面
// 点击节点卡片后进入的页面，按节点类型展示功能标签页：
// - 概览：主机信息 / 资源占用 / 实例统计（两类型均有 API）
// - 实例：实例列表与启动/停止/重启/强制终止（两类型均有 API）
// - 文件：实例文件管理器（两类型均有 API）
// - 用户：用户管理（仅 MCSM 面板提供 API）
// - Docker：镜像/容器/网络（仅 MCSM 面板提供 API）
// "只显示 API 有的功能"：MCSM 侧仅展示文档中带 API 的能力。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../services/node_api_client.dart';
import '../services/node_daemon_launcher.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../utils/docker_visibility.dart';
import 'remote_file_manager_screen.dart';
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
        _daemonId = (available.isNotEmpty ? available : overview.remote).first.uuid;
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
  /// Docker 相关能力（实例 Docker 配置 / Docker 环境管理）不占用独立标签页，
  /// 而是并入「实例」管理内，并按客户端/节点平台决定是否显示
  /// （见 shouldShowDockerSettings）。
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
      (
        label: '文件',
        icon: Icons.folder_outlined,
        child: RemoteFileManagerScreen(
          nodeId: node.id,
          client: client,
          overview: overview,
          daemonId: daemonId,
          allowInstanceSwitch: true,
        ),
      ),
    ];
    // MCSM 面板额外提供用户管理 API（Docker 已并入实例管理，按平台显示）
    if (node.type == NodeType.mcsm) {
      tabs.add((
        label: '用户',
        icon: Icons.people_outline,
        child: _UsersTab(client: client, daemonId: daemonId),
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
              child: TabBarView(
                children: [for (final tab in tabs) tab.child],
              ),
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
              online
                  ? '节点在线 · ${node.address}'
                  : '节点离线：${_error ?? '无法连接'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: online
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
            ),
          ),
          if (!online && node.type == NodeType.node)
            TextButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('启动本地节点'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
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
              data.process.memory > 0
                  ? _formatBytes(data.process.memory)
                  : '—',
            ),
            ('节点版本', data.version.isEmpty ? '—' : data.version),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: '实例统计',
          icon: Icons.storage,
          rows: [
            (
              '守护进程',
              data.remote.isEmpty ? '—' : '${data.remote.length} 个',
            ),
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
                      child: Text(
                        value,
                        style: theme.textTheme.bodySmall,
                      ),
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
    _daemonId = widget.initialDaemonId ??
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

  /// 打开 Docker 环境管理（镜像 / 容器 / 网络）。
  void _openDockerEnv() {
    pushPage<void>(
      context,
      (_) => _DockerEnvScreen(
        client: widget.client,
        daemonId: _daemonId ?? '',
      ),
    );
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
                      DropdownMenuItem(value: d.uuid, child: Text(d.displayName)),
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
              if (shouldShowDockerSettings(
                nodePlatform: widget.overview?.system.platform,
              ))
                IconButton(
                  icon: const Icon(Icons.view_in_ar_outlined),
                  tooltip: 'Docker 环境（镜像/容器/网络）',
                  onPressed: _loading ? null : _openDockerEnv,
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
                instance.config.cwd.isEmpty
                    ? '工作目录未知'
                    : instance.config.cwd,
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
        disabledForegroundColor:
            Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isBanned
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
                      color: isBanned ? Colors.red : isAdmin ? Colors.blue : Colors.grey,
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

// ==================== Docker 环境（并入实例管理，按平台显示）====================

/// Docker 环境管理：镜像 / 容器 / 网络（只读展示 + 构建镜像）。
/// 由「实例」标签页的 Docker 按钮进入（客户端 Windows + 节点 Windows 时不显示）。
class _DockerEnvScreen extends StatefulWidget {
  const _DockerEnvScreen({required this.client, required this.daemonId});

  final NodeApiClient client;
  final String daemonId;

  @override
  State<_DockerEnvScreen> createState() => _DockerEnvScreenState();
}

class _DockerEnvScreenState extends State<_DockerEnvScreen> {
  int _subIndex = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _containers = [];
  List<Map<String, dynamic>> _networks = [];
  Map<String, int> _progress = {};

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
    final daemonId = widget.daemonId;
    try {
      final images = await widget.client.listImages(daemonId);
      final containers = await widget.client.listContainers(daemonId);
      final networks = await widget.client.listNetworks(daemonId);
      if (!mounted) return;
      setState(() {
        _images = images;
        _containers = containers;
        _networks = networks;
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

  Future<void> _buildImage() async {
    final result = await showAppDialog<(String, String, String)?>(
      context,
      (_) => const _BuildImageDialog(),
    );
    if (result == null || !mounted) return;
    final daemonId = widget.daemonId;
    try {
      await widget.client.createImage(
        daemonId: daemonId,
        dockerFile: result.$3,
        name: result.$1,
        tag: result.$2,
      );
      _pollProgress();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _pollProgress() async {
    final daemonId = widget.daemonId;
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final progress = await widget.client.buildProgress(daemonId);
        if (!mounted) return;
        setState(() => _progress = progress);
        final done = progress.values.every((v) => v != 1);
        if (done) {
          await _load();
          return;
        }
      } catch (_) {
        return;
      }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Docker 环境')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '镜像 / 容器 / 网络（面板 API）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (_progress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _progress.entries
                          .map((e) =>
                              '${e.key}: ${e.value == 2 ? '完成' : e.value == 1 ? '构建中' : '失败'}')
                          .join(', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  onPressed: _loading ? null : _load,
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _buildImage,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('构建镜像'),
                ),
              ],
            ),
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('镜像'), icon: Icon(Icons.image_outlined, size: 16)),
              ButtonSegment(value: 1, label: Text('容器'), icon: Icon(Icons.view_in_ar, size: 16)),
              ButtonSegment(value: 2, label: Text('网络'), icon: Icon(Icons.hub_outlined, size: 16)),
            ],
            selected: {_subIndex},
            onSelectionChanged: (s) => setState(() => _subIndex = s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
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
    return switch (_subIndex) {
      0 => _dockerList(theme, _images, _imageRow),
      1 => _dockerList(theme, _containers, _containerRow),
      _ => _dockerList(theme, _networks, _networkRow),
    };
  }

  Widget _dockerList(
    ThemeData theme,
    List<Map<String, dynamic>> items,
    Widget Function(Map<String, dynamic>) rowBuilder,
  ) {
    if (items.isEmpty) {
      return Center(child: Text('暂无数据', style: theme.textTheme.bodyMedium));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: rowBuilder(item),
          ),
        );
      },
    );
  }

  /// 镜像行：Repository:Tag / ID / Size。
  Widget _imageRow(Map<String, dynamic> image) {
    final repoTags = (image['RepoTags'] as List<dynamic>? ?? []).cast<String>();
    final repoTag = repoTags.isNotEmpty ? repoTags.first : 'unknown:latest';
    final id = (image['Id'] as String? ?? '').replaceFirst('sha256:', '');
    final size = (image['Size'] as num?)?.toInt() ?? 0;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.image_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                repoTag,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'ID: ${id.length > 12 ? id.substring(0, 12) : id} · 大小: ${_formatBytes(size)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 容器行：Name / Image / State / Ports。
  Widget _containerRow(Map<String, dynamic> container) {
    final names = (container['Names'] as List<dynamic>? ?? [])
        .map((e) => e.toString().replaceFirst('/', ''))
        .toList();
    final image = container['Image'] as String? ?? '—';
    final state = container['State'] as String? ?? '—';
    final ports = (container['Ports'] as List<dynamic>? ?? [])
        .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
        .map((p) => p['PublicPort'] != null
            ? '${p['IP'] ?? ''}:${p['PublicPort']}->${p['PrivatePort']}/${p['Type'] ?? ''}'
            : '${p['PrivatePort']}/${p['Type'] ?? ''}')
        .join(', ');
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.view_in_ar,
              size: 18,
              color: state == 'running' ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                names.isNotEmpty ? names.join(', ') : '未命名容器',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (state == 'running' ? Colors.green : Colors.grey)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                state,
                style: TextStyle(
                  fontSize: 11,
                  color: state == 'running' ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '镜像: $image${ports.isEmpty ? '' : '\n端口: $ports'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 网络行：Name / Driver / Scope。
  Widget _networkRow(Map<String, dynamic> network) {
    final name = network['Name'] as String? ?? '—';
    final driver = network['Driver'] as String? ?? '—';
    final scope = network['Scope'] as String? ?? '—';
    final id = (network['Id'] as String? ?? '');
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.hub_outlined, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
        Text(
          '$driver · $scope${id.isNotEmpty ? ' · ${id.substring(0, 12)}' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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

/// 构建镜像对话框。
class _BuildImageDialog extends StatefulWidget {
  const _BuildImageDialog();

  @override
  State<_BuildImageDialog> createState() => _BuildImageDialogState();
}

class _BuildImageDialogState extends State<_BuildImageDialog> {
  final _name = TextEditingController(text: 'mcsm-custom');
  final _tag = TextEditingController(text: 'latest');
  final _dockerFile = TextEditingController(
    text: 'FROM mcsm-ubuntu:22.04\n\n# 在此编写 Dockerfile 内容',
  );

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    _dockerFile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('构建镜像'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '镜像名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _tag,
                    decoration: const InputDecoration(
                      labelText: '标签',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dockerFile,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Dockerfile 内容',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
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
            final name = _name.text.trim();
            final tag = _tag.text.trim();
            final dockerFile = _dockerFile.text;
            if (name.isEmpty || tag.isEmpty || dockerFile.isEmpty) return;
            Navigator.of(context).pop((name, tag, dockerFile));
          },
          child: const Text('开始构建'),
        ),
      ],
    );
  }
}

extension on RemoteStatus {
  bool get isActive =>
      this == RemoteStatus.running ||
      this == RemoteStatus.starting ||
      this == RemoteStatus.stopping;
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
                    DropdownMenuItem(value: 'universal', child: Text('通用（直接运行进程）')),
                    DropdownMenuItem(value: 'docker', child: Text('Docker（容器内运行）')),
                  ],
                  onChanged: (v) => setState(() => _processType = v ?? 'universal'),
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
            Navigator.of(context).pop(_CreateInstanceResult(
              nickname: name,
              cwd: cwd,
              startCommand: command,
              processType: _processType,
              docker: _buildDockerConfig(),
            ));
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
