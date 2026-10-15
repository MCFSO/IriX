// 实例列表主页 + 左侧导航栏
// 左侧为自绘侧边栏（图标与文字并列），切换各功能页与全局设置

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/server_instance.dart';
import '../services/cluster_monitor.dart';
import '../services/database_manager.dart';
import '../services/management_mode_settings.dart';
import '../services/mcp_server.dart';
import '../state/app_state.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/first_run_wizard.dart';
import 'ai_screen.dart';
import 'cluster_home_screen.dart';
import 'cluster_instances_screen.dart';
import 'cluster_container_screen.dart';
import 'cluster_orchestration_screen.dart';
import 'database_screen.dart';
import 'frp_screen.dart';
import 'instance_detail_screen.dart';
import 'marketplace_screen.dart';
import 'nbt_editor_screen.dart';
import 'nodes_screen.dart';
import 'onboarding_screen.dart';
import 'plugins_screen.dart';
import 'settings_screen.dart';

/// 主页 — 左侧 NavigationRail + 右侧内容区。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  /// 内容区是否显示全局设置（侧边栏底部入口）。
  bool _showSettings = false;

  /// 是否已弹出 MCP 权限对话框（防止重复弹窗）。
  bool _mcpDialogOpen = false;

  /// 首次启动引导向导是否展示。
  bool _wizardVisible = false;

  @override
  void initState() {
    super.initState();
    McpServer.instance.attachState(context.read<AppState>());
    McpServer.instance.currentRequest.addListener(_onMcpRequest);
    _startMcpServer();
    // 首次启动：无实例且未完成/跳过过引导时，展示线性引导向导。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowFirstRunWizard();
    });
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
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.home_mcpRequestTitle),
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
            child: Text(l.home_mcpDeny),
          ),
          FilledButton(
            onPressed: () {
              request.resolve(true);
              _mcpDialogOpen = false;
              Navigator.of(ctx).pop();
            },
            child: Text(l.home_mcpAllow),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = context.watch<ClusterState>().mode == ManagementMode.multi;
    // 单机 7 项 / 多机 9 项（多机多出「容器」「编排」，插件固定为最后一项）。
    // 从多机切回单机时按「插件是否选中」重定位索引，避免同一索引指向不同页面。
    final destinations = multi
        ? _multiDestinations(context)
        : _singleDestinations(context);
    final index = _resolveIndex(multi, destinations.length);
    // 记录本次模式，供下次（可能已切换模式）的 _resolveIndex 推断索引含义。
    _lastModeWasMulti = multi;

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // 左侧导航栏（自绘：图标与文字并列）
              LayoutBuilder(
                builder: (context, constraints) {
                  // 窄窗口收起文字，仅保留图标，避免内容区被挤压。
                  final compact = constraints.maxWidth < 720;
                  return _Sidebar(
                    destinations: destinations,
                    selectedIndex: index,
                    showSettings: _showSettings,
                    compact: compact,
                    onSelect: (value) {
                      setState(() {
                        _showSettings = false;
                        _selectedIndex = value;
                      });
                    },
                    onOpenSettings: () => setState(() => _showSettings = true),
                  );
                },
              ),
              const VerticalDivider(thickness: 1, width: 1),
              // 右侧内容区
              Expanded(
                child: _showSettings
                    ? const SettingsScreen()
                    : (multi
                          ? _buildMultiContent(index)
                          : _buildContent(index)),
              ),
            ],
          ),
          // 首次启动引导（变暗 30% + 阻断点击）
          if (_wizardVisible)
            FirstRunWizardOverlay(
              onSkip: () => _dismissWizard('skipped'),
              onFinish: (goFrp) => _dismissWizard('done', goFrp: goFrp),
            ),
        ],
      ),
    );
  }

  /// 把 [_selectedIndex] 收敛到当前模式的目的地范围内。
  ///
  /// 两种模式的项数与顺序不同（多机多出「容器」「编排」），但「插件」在两边
  /// 都是最后一项。切换模式时按「是否选中最后一项（插件）」重定位，
  /// 使插件页在切换后仍指向插件，而不是被 clamp 成别的页面。
  int _resolveIndex(bool multi, int length) {
    final maxIndex = length - 1;
    if (multi) {
      // 单机索引 6 = 插件 → 多机索引 8 = 插件。
      // 其余单机索引（0..5）与多机前段不完全对应，只做越界收敛。
      if (_lastIndexWasPlugin) return maxIndex;
      return _selectedIndex.clamp(0, maxIndex);
    }
    // 切回单机：多机索引 8 是插件，映射到单机最后一项。
    if (_selectedIndex == 8) return maxIndex;
    return _selectedIndex.clamp(0, maxIndex);
  }

  /// 上一次 build 时是否选中了「插件」项（用于跨模式保持选中）。
  bool get _lastIndexWasPlugin {
    final wasMulti = _lastModeWasMulti;
    return wasMulti ? _selectedIndex == 8 : _selectedIndex == 6;
  }

  /// 上一次 build 的管理模式（用于推断索引含义）。
  bool _lastModeWasMulti = false;

  Future<void> _maybeShowFirstRunWizard() async {
    final done = await DatabaseManager.instance.getSetting('first_run_wizard');
    if (done != null || !mounted) return;
    if (context.read<AppState>().instances.isNotEmpty) {
      // 已有实例（老用户升级）：直接标记完成，不打扰
      await DatabaseManager.instance.setSetting('first_run_wizard', 'done');
      return;
    }
    setState(() => _wizardVisible = true);
  }

  /// 关闭向导并持久化状态；[goFrp] 为 true 时跳转 FRP 页面。
  Future<void> _dismissWizard(String value, {bool goFrp = false}) async {
    await DatabaseManager.instance.setSetting('first_run_wizard', value);
    if (!mounted) return;
    setState(() {
      _wizardVisible = false;
      if (goFrp) {
        final multi = context.read<ClusterState>().mode == ManagementMode.multi;
        _selectedIndex = multi ? 7 : 5;
      }
    });
  }

  /// 单机模式导航（默认 6 个标签）。
  List<NavItem> _singleDestinations(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      NavItem(
        icon: Icons.storage_outlined,
        selectedIcon: Icons.storage,
        label: l.home_navInstances,
      ),
      NavItem(
        icon: Icons.lan_outlined,
        selectedIcon: Icons.lan,
        label: l.home_navNodes,
      ),
      NavItem(
        icon: Icons.store_outlined,
        selectedIcon: Icons.store,
        label: l.home_navMarket,
      ),
      NavItem(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns,
        label: l.home_navDatabase,
      ),
      NavItem(
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy,
        label: l.home_navAi,
      ),
      NavItem(
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub,
        label: l.home_navFrp,
      ),
      NavItem(
        icon: Icons.extension_outlined,
        selectedIcon: Icons.extension,
        label: '插件',
      ),
    ];
  }

  /// 多机模式导航（节点优先，8 项）。
  List<NavItem> _multiDestinations(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      NavItem(
        icon: Icons.lan_outlined,
        selectedIcon: Icons.lan,
        label: l.home_navHome,
      ),
      NavItem(
        icon: Icons.storage_outlined,
        selectedIcon: Icons.storage,
        label: l.home_navInstances,
      ),
      NavItem(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: l.home_navContainers,
      ),
      NavItem(
        icon: Icons.dashboard_customize_outlined,
        selectedIcon: Icons.dashboard_customize,
        label: l.home_navOrchestration,
      ),
      NavItem(
        icon: Icons.store_outlined,
        selectedIcon: Icons.store,
        label: l.home_navMarket,
      ),
      NavItem(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns,
        label: l.home_navDatabase,
      ),
      NavItem(
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy,
        label: l.home_navAi,
      ),
      NavItem(
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub,
        label: l.home_navFrp,
      ),
      NavItem(
        icon: Icons.extension_outlined,
        selectedIcon: Icons.extension,
        label: '插件',
      ),
    ];
  }

  /// 多机模式内容区。
  Widget _buildMultiContent(int index) {
    switch (index) {
      case 0:
        return const ClusterHomeScreen();
      case 1:
        return const ClusterInstancesScreen();
      case 2:
        return const ClusterContainerScreen();
      case 3:
        return const ClusterOrchestrationScreen();
      case 4:
        return const MarketplaceScreen();
      case 5:
        return const DatabaseScreen();
      case 6:
        return const AiScreen();
      case 7:
        return const FrpScreen();
      case 8:
        return const PluginManagerScreen(embedded: true);
      default:
        return const ClusterHomeScreen();
    }
  }

  Widget _buildContent(int index) {
    switch (index) {
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
      case 6:
        return const PluginManagerScreen(embedded: true);
      default:
        return _buildInstancesPage();
    }
  }

  /// 实例列表页
  Widget _buildInstancesPage() {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final l = AppLocalizations.of(context);
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
                  tooltip: l.home_newInstance,
                  onPressed: () =>
                      pushPage(context, (_) => const OnboardingScreen()),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: l.common_settings,
                  // 跳转到左侧边栏的「设置」（保持侧边栏选中态一致）。
                  onPressed: () => setState(() => _showSettings = true),
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
            const SliverToBoxAdapter(child: _ToolsRow()),
          ],
        );
      },
    );
  }
}

/// 主页底部工具入口（NBT 编辑器等）。
///
/// 注：插件管理已移入左侧边栏，此处不再重复提供入口。
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _ToolTile(
            icon: Icons.edit_note,
            label: l.home_nbtEditor,
            onTap: () => pushPage(context, (_) => const NbtEditorScreen()),
          ),
        ],
      ),
    );
  }
}

/// 单个工具磁贴。
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
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

/// 打开全局设置页（单机 / 多机模式通用）。
///
/// 保留原函数名以兼容既有调用方（如 [ClusterHomeScreen]），
/// 但行为由「弹出对话框」改为「跳转到设置页」。
Future<void> showSettingsDialog(BuildContext context) {
  return pushPage<void>(context, (_) => const SettingsScreen());
}

/// 侧边栏导航项（图标 + 文字）。
class NavItem {
  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 自绘左侧导航栏。
///
/// 与 [NavigationRail] 的关键差异：每项为横向 Row，
/// **图标与文字并列**（而非图标在上、文字在下）；
/// 底部固定「设置」入口，与其余功能项视觉一致。
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.showSettings,
    required this.compact,
    required this.onSelect,
    required this.onOpenSettings,
  });

  final List<NavItem> destinations;
  final int selectedIndex;
  final bool showSettings;
  final bool compact;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Container(
      width: compact ? 64 : 200,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Column(
        children: [
          // 顶部品牌区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(Icons.dns, size: 22, color: theme.colorScheme.primary),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  Text(
                    'IriX',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // 功能项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _SidebarItem(
                      icon: destinations[i].icon,
                      selectedIcon: destinations[i].selectedIcon,
                      label: destinations[i].label,
                      selected: !showSettings && i == selectedIndex,
                      compact: compact,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
          // 底部：全局设置入口（图标与文字并列）。
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: _SidebarItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              label: l.common_settings,
              selected: showSettings,
              compact: compact,
              onTap: onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个侧边栏项 —— 图标与文字横向并列。
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 12,
            vertical: 11,
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(selected ? selectedIcon : icon, size: 20, color: color),
              // 图标与文字并列；紧凑模式（窄窗口）下仅显示图标。
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
