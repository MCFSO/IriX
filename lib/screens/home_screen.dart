// 实例列表主页 + 左侧导航栏
// 左侧 NavigationRail 切换"实例列表"和"市场"

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/server_instance.dart';
import '../services/cluster_monitor.dart';
import '../services/db_page_settings.dart';
import '../services/download_settings.dart';
import '../services/management_mode_settings.dart';
import '../services/mcp_server.dart';
import '../state/app_state.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import 'ai_screen.dart';
import 'cluster_home_screen.dart';
import 'cluster_instances_screen.dart';
import 'database_screen.dart';
import 'frp_screen.dart';
import 'instance_detail_screen.dart';
import 'marketplace_screen.dart';
import 'nodes_screen.dart';
import 'onboarding_screen.dart';

/// 主页 — 左侧 NavigationRail + 右侧内容区。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  /// 是否已弹出 MCP 权限对话框（防止重复弹窗）。
  bool _mcpDialogOpen = false;

  @override
  void initState() {
    super.initState();
    McpServer.instance.attachState(context.read<AppState>());
    McpServer.instance.currentRequest.addListener(_onMcpRequest);
    _startMcpServer();
    // 若已处于多机模式，启动集群监控循环。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 测试环境跳过（监控循环的 Timer 会挂起导致测试失败）。
      if (Platform.environment['FLUTTER_TEST'] == 'true') return;
      final cluster = context.read<ClusterState>();
      if (cluster.mode == ManagementMode.multi) {
        ClusterMonitor.instance.start(context.read<NodeState>(), cluster);
      }
    });
  }

  @override
  void dispose() {
    McpServer.instance.currentRequest.removeListener(_onMcpRequest);
    super.dispose();
  }

  /// 若设置中启用了 MCP 则启动本地服务器。
  /// 测试环境下跳过（避免挂起 SQLite 定时器导致测试失败）。
  Future<void> _startMcpServer() async {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      await McpServer.instance.startIfEnabled();
    } catch (e) {
      debugPrint('MCP server start failed: $e');
    }
  }

  /// 外部 AI 通过 MCP 申请敏感操作时弹出全局授权对话框。
  void _onMcpRequest() {
    final request = McpServer.instance.currentRequest.value;
    if (request == null || _mcpDialogOpen) return;
    _mcpDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 申请执行敏感操作'),
        content: Text(
          '来自 ${request.clientName}\n\n${request.tool.describe(request.args)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              request.resolve(false);
              _mcpDialogOpen = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () {
              request.resolve(true);
              _mcpDialogOpen = false;
              Navigator.of(ctx).pop();
            },
            child: const Text('允许'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = context.watch<ClusterState>().mode == ManagementMode.multi;
    return Scaffold(
      body: Row(
        children: [
          // 左侧导航栏
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            destinations: multi ? _multiDestinations() : _singleDestinations(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // 右侧内容区
          Expanded(child: multi ? _buildMultiContent() : _buildContent()),
        ],
      ),
    );
  }

  /// 单机模式导航（默认 6 个标签）。
  List<NavigationRailDestination> _singleDestinations() => const [
    NavigationRailDestination(
      icon: Icon(Icons.storage_outlined),
      selectedIcon: Icon(Icons.storage),
      label: Text('实例'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.lan_outlined),
      selectedIcon: Icon(Icons.lan),
      label: Text('节点'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.store_outlined),
      selectedIcon: Icon(Icons.store),
      label: Text('市场'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.dns_outlined),
      selectedIcon: Icon(Icons.dns),
      label: Text('数据库'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy),
      label: Text('AI'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.hub_outlined),
      selectedIcon: Icon(Icons.hub),
      label: Text('FRP'),
    ),
  ];

  /// 多机模式导航（节点优先）。
  List<NavigationRailDestination> _multiDestinations() => const [
    NavigationRailDestination(
      icon: Icon(Icons.lan_outlined),
      selectedIcon: Icon(Icons.lan),
      label: Text('主页'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.storage_outlined),
      selectedIcon: Icon(Icons.storage),
      label: Text('实例'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.store_outlined),
      selectedIcon: Icon(Icons.store),
      label: Text('市场'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.dns_outlined),
      selectedIcon: Icon(Icons.dns),
      label: Text('数据库'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy),
      label: Text('AI'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.hub_outlined),
      selectedIcon: Icon(Icons.hub),
      label: Text('FRP'),
    ),
  ];

  /// 多机模式内容区。
  Widget _buildMultiContent() {
    switch (_selectedIndex) {
      case 0:
        return const ClusterHomeScreen();
      case 1:
        return const ClusterInstancesScreen();
      case 2:
        return const MarketplaceScreen();
      case 3:
        return const DatabaseScreen();
      case 4:
        return const AiScreen();
      case 5:
        return const FrpScreen();
      default:
        return const ClusterHomeScreen();
    }
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildInstancesPage();
      case 1:
        return const NodesScreen();
      case 2:
        return const MarketplaceScreen();
      case 3:
        return const DatabaseScreen();
      case 4:
        return const AiScreen();
      case 5:
        return const FrpScreen();
      default:
        return _buildInstancesPage();
    }
  }

  /// 实例列表页
  Widget _buildInstancesPage() {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final instances = state.instances;
        if (instances.isEmpty) {
          return const OnboardingScreen(embedded: true);
        }
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('IriX'),
              floating: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建实例',
                  onPressed: () =>
                      pushPage(context, (_) => const OnboardingScreen()),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '设置',
                  onPressed: () => showAppDialog<void>(
                    context,
                    (_) => const _SettingsDialog(),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.builder(
                itemCount: instances.length,
                itemBuilder: (context, index) {
                  final instance = instances[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InstanceCard(
                      instance: instance,
                      onTap: () {
                        state.selectInstance(instance.id);
                        pushPage(
                          context,
                          (_) => InstanceDetailScreen(instanceId: instance.id),
                        );
                      },
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

/// 实例圆角卡片。
///
/// 展示实例名称与状态标签（启动中/重启中/已关闭）。
class _InstanceCard extends StatelessWidget {
  const _InstanceCard({required this.instance, required this.onTap});

  final ServerInstance instance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.storage, size: 40, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(instance.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    _StatusChip(status: instance.status),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实例状态标签。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final InstanceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InstanceStatus.starting => Colors.orange,
      InstanceStatus.running => Colors.green,
      InstanceStatus.restarting => Colors.amber,
      InstanceStatus.stopped => Colors.grey,
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
}

/// 设置对话框 — 调节下载线程数。
///
/// 下载线程数控制多线程分片断点续传下载的并发数 (1-32)。
/// 修改即时生效并持久化 (SharedPreferences)。
class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _threads;
  late double _pageSize;
  late bool _multi;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _threads = state.downloadThreads.toDouble();
    _pageSize = DbPageSettings.pageSize.toDouble();
    _multi = context.read<ClusterState>().mode == ManagementMode.multi;
    _loading = false;
  }

  /// 切换管理模式，并启停集群监控循环。
  void _toggleMode(bool multi) {
    final cluster = context.read<ClusterState>();
    cluster.setMode(multi ? ManagementMode.multi : ManagementMode.single);
    if (multi) {
      ClusterMonitor.instance.start(context.read<NodeState>(), cluster);
    } else {
      ClusterMonitor.instance.stop();
    }
    setState(() => _multi = multi);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AlertDialog(content: CircularProgressIndicator());
    }
    return AlertDialog(
      title: const Text('设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 管理模式
          Row(
            children: [
              const Icon(Icons.lan_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '多机管理模式',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _multi ? '实例分布到多个节点，自动分配资源、崩溃迁移与数据同步' : '单机模式：实例在本机运行',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AppleSwitch(value: _multi, onChanged: _toggleMode),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '多机模式需至少 2 个节点，可在「主页」中添加。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 24),
          // 下载线程数
          Text(
            '下载线程数: ${_threads.round()}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Slider(
            value: _threads,
            min: DownloadSettings.minThreads.toDouble(),
            max: DownloadSettings.maxThreads.toDouble(),
            divisions:
                DownloadSettings.maxThreads - DownloadSettings.minThreads,
            label: '${_threads.round()}',
            onChanged: (v) => setState(() => _threads = v),
            onChangeEnd: (v) =>
                context.read<AppState>().setDownloadThreads(v.round()),
          ),
          const SizedBox(height: 4),
          Text(
            '多线程分片断点续传；服务端不支持 Range 时自动回退单线程。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // 数据库表格每页行数
          Text(
            '数据库每页行数: ${_pageSize.round()}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Slider(
            value: _pageSize,
            min: DbPageSettings.minPageSize.toDouble(),
            max: DbPageSettings.maxPageSize.toDouble(),
            divisions: DbPageSettings.maxPageSize - DbPageSettings.minPageSize,
            label: '${_pageSize.round()}',
            onChanged: (v) => setState(() => _pageSize = v),
            onChangeEnd: (v) => DbPageSettings.setPageSize(v.round()),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览数据库表数据时每页显示的行数。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
