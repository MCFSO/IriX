// 实例列表主页 + 左侧导航栏
// 左侧 NavigationRail 切换"实例列表"和"市场"

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/server_instance.dart';
import '../services/cluster_monitor.dart';
import '../services/database_manager.dart';
import '../services/db_page_settings.dart';
import '../services/download_settings.dart';
import '../services/font_settings.dart';
import '../services/locale_settings.dart';
import '../services/management_mode_settings.dart';
import '../services/mcp_server.dart';
import '../services/vault_settings.dart';
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
    // 单机模式 6 项、多机模式 8 项（多出「容器」「编排」）：
    // 从多机切回单机时把越界的选中索引收敛，避免 NavigationRail 越界。
    final index = multi ? _selectedIndex : _selectedIndex.clamp(0, 5);
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // 左侧导航栏
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (value) {
                  setState(() => _selectedIndex = value);
                },
                labelType: NavigationRailLabelType.all,
                destinations: multi
                    ? _multiDestinations(context)
                    : _singleDestinations(context),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              // 右侧内容区
              Expanded(
                child: multi ? _buildMultiContent(index) : _buildContent(index),
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

  /// 首次启动判定：设置未记录且无实例 → 展示向导。
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
  List<NavigationRailDestination> _singleDestinations(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      NavigationRailDestination(
        icon: const Icon(Icons.storage_outlined),
        selectedIcon: const Icon(Icons.storage),
        label: Text(l.home_navInstances),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.lan_outlined),
        selectedIcon: const Icon(Icons.lan),
        label: Text(l.home_navNodes),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.store_outlined),
        selectedIcon: const Icon(Icons.store),
        label: Text(l.home_navMarket),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.dns_outlined),
        selectedIcon: const Icon(Icons.dns),
        label: Text(l.home_navDatabase),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.smart_toy_outlined),
        selectedIcon: const Icon(Icons.smart_toy),
        label: Text(l.home_navAi),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.hub_outlined),
        selectedIcon: const Icon(Icons.hub),
        label: Text(l.home_navFrp),
      ),
    ];
  }

  /// 多机模式导航（节点优先，8 项）。
  List<NavigationRailDestination> _multiDestinations(BuildContext context) {
    final l = AppLocalizations.of(context);
    return [
      NavigationRailDestination(
        icon: const Icon(Icons.lan_outlined),
        selectedIcon: const Icon(Icons.lan),
        label: Text(l.home_navHome),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.storage_outlined),
        selectedIcon: const Icon(Icons.storage),
        label: Text(l.home_navInstances),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.inventory_2_outlined),
        selectedIcon: const Icon(Icons.inventory_2),
        label: Text(l.home_navContainers),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_customize_outlined),
        selectedIcon: const Icon(Icons.dashboard_customize),
        label: Text(l.home_navOrchestration),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.store_outlined),
        selectedIcon: const Icon(Icons.store),
        label: Text(l.home_navMarket),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.dns_outlined),
        selectedIcon: const Icon(Icons.dns),
        label: Text(l.home_navDatabase),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.smart_toy_outlined),
        selectedIcon: const Icon(Icons.smart_toy),
        label: Text(l.home_navAi),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.hub_outlined),
        selectedIcon: const Icon(Icons.hub),
        label: Text(l.home_navFrp),
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
                  onPressed: () => showSettingsDialog(context),
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

/// 打开全局设置对话框（单机 / 多机模式通用）。
Future<void> showSettingsDialog(BuildContext context) {
  return showAppDialog<void>(context, (_) => const SettingsDialog());
}

/// 设置对话框 — 管理模式、下载线程数、数据库每页行数、字体。
///
/// 修改即时生效并持久化到 SQLite `settings` 表。
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => SettingsDialogState();
}

class SettingsDialogState extends State<SettingsDialog> {
  late double _threads;
  late double _pageSize;
  late bool _multi;
  late bool _vaultEnabled;
  late String _uiFont;
  late String _terminalFont;
  late AppLanguage _language;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _threads = state.downloadThreads.toDouble();
    _pageSize = DbPageSettings.pageSize.toDouble();
    _multi = context.read<ClusterState>().mode == ManagementMode.multi;
    _vaultEnabled = VaultSettings.defaultEnabled;
    final fonts = FontSettings.instance;
    _uiFont = fonts.uiFamily;
    _terminalFont = fonts.terminalFamily;
    _language = LocaleSettings.instance.language;
    unawaited(_loadVaultEnabled());
  }

  /// 异步加载 Vault 开关状态（SQLite settings 表）。
  Future<void> _loadVaultEnabled() async {
    final enabled = await VaultSettings.isEnabled();
    if (!mounted) return;
    setState(() {
      _vaultEnabled = enabled;
      _loading = false;
    });
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
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const AlertDialog(content: CircularProgressIndicator());
    }
    return AlertDialog(
      title: Text(l.settings_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 界面语言
            Text(l.common_language,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<AppLanguage>(
              initialValue: _language,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                labelText: l.common_language,
              ),
              items: [
                for (final lang in LocaleSettings.options)
                  DropdownMenuItem(
                    value: lang,
                    child: Text(_languageLabel(l, lang)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _language = v);
                LocaleSettings.instance.setLanguage(v);
              },
            ),
            const Divider(height: 24),
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
                        l.settings_multiMode,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _multi
                            ? l.settings_multiModeOn
                            : l.settings_singleMode,
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
              l.settings_multiModeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            // Vault 加密保险库（客户端功能开关）
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.settings_vault,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _vaultEnabled ? l.settings_vaultOn : l.settings_vaultOff,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                AppleSwitch(
                  value: _vaultEnabled,
                  onChanged: (v) async {
                    setState(() => _vaultEnabled = v);
                    await VaultSettings.setEnabled(v);
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            // 下载线程数
            Text(
              l.settings_downloadThreads(_threads.round()),
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
              l.settings_downloadThreadsHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            // 数据库表格每页行数
            Text(
              l.settings_dbPageSize(_pageSize.round()),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Slider(
              value: _pageSize,
              min: DbPageSettings.minPageSize.toDouble(),
              max: DbPageSettings.maxPageSize.toDouble(),
              divisions:
                  DbPageSettings.maxPageSize - DbPageSettings.minPageSize,
              label: '${_pageSize.round()}',
              onChanged: (v) => setState(() => _pageSize = v),
              onChangeEnd: (v) => DbPageSettings.setPageSize(v.round()),
            ),
            const SizedBox(height: 4),
            Text(
              l.settings_dbPageSizeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 24),
            // 字体（UI 与终端分开管理）
            Text(l.settings_font,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              l.settings_fontHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _uiFont,
              decoration: InputDecoration(
                labelText: l.settings_uiFont,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final (value, label) in FontSettings.uiOptions)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _uiFont = v);
                FontSettings.instance.setUiFamily(v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _terminalFont,
              decoration: InputDecoration(
                labelText: l.settings_terminalFont,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final (value, label) in FontSettings.terminalOptions)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _terminalFont = v);
                FontSettings.instance.setTerminalFamily(v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              l.settings_fontFallbackHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_close),
        ),
      ],
    );
  }

  /// 语言下拉项的显示名（复用 common_language* 键）。
  String _languageLabel(AppLocalizations l, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.system:
        return l.common_languageSystem;
      case AppLanguage.zh:
        return l.common_languageChinese;
      case AppLanguage.en:
        return l.common_languageEnglish;
    }
  }
}
