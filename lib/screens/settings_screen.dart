// 全局设置页面
//
// 由原 HomeScreen 内的 SettingsDialog（弹窗）迁移而来，改为左侧分区列表 +
// 右侧详情的整页布局，便于承载 Java 管理这类内容较多的分区。
//
// 分区：
//   通用      —— 界面语言、管理模式、Vault、开发者模式
//   外观      —— UI 字体、终端字体
//   下载      —— 下载线程数
//   数据库    —— 表格每页行数
//   Java 管理 —— 移植自 HMCL 的 Java 运行时管理（JavaManagementSection）
//   软件更新  —— OTA：当前版本、自动检查开关、手动检查更新
//
// 所有修改即时生效并持久化到 SQLite settings 表（与原弹窗行为一致）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/app_version.dart';
import '../services/cluster_monitor.dart';
import '../services/db_page_settings.dart';
import '../services/developer_settings.dart';
import '../services/dev_log.dart';
import '../services/download_settings.dart';
import '../services/font_settings.dart';
import '../services/locale_settings.dart';
import '../services/management_mode_settings.dart';
import '../services/plugin_view_settings.dart';
import '../services/time_service.dart';
import '../services/update_service.dart';
import '../services/update_settings.dart';
import '../services/vault_settings.dart';
import '../state/app_state.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/java_management_section.dart';
import '../widgets/update_dialog.dart';

/// 设置分区。
enum SettingsSection {
  general('通用', Icons.tune),
  appearance('外观', Icons.palette_outlined),
  download('下载', Icons.download_outlined),
  plugins('插件', Icons.extension_outlined),
  database('数据库', Icons.table_chart_outlined),
  java('Java 管理', Icons.coffee_outlined),
  update('软件更新', Icons.system_update_alt);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 全局设置页面。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialSection = SettingsSection.general,
  });

  /// 初始分区（便于从其它入口直达 Java 管理）。
  final SettingsSection initialSection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).settings_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 窄窗口下分区列表收窄为图标栏，避免挤压内容区。
          final compact = constraints.maxWidth < 820;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionRail(
                section: _section,
                compact: compact,
                onSelect: (s) => setState(() => _section = s),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: _buildSection(theme, _section),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(ThemeData theme, SettingsSection section) {
    switch (section) {
      case SettingsSection.general:
        return const _GeneralSection();
      case SettingsSection.appearance:
        return const _AppearanceSection();
      case SettingsSection.download:
        return const _DownloadSection();
      case SettingsSection.plugins:
        return const _PluginsSection();
      case SettingsSection.database:
        return const _DatabaseSection();
      case SettingsSection.java:
        return _JavaSection();
      case SettingsSection.update:
        return const _UpdateSection();
    }
  }
}

/// 设置分区列表（左侧）。
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.section,
    required this.compact,
    required this.onSelect,
  });

  final SettingsSection section;
  final bool compact;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: compact ? 64 : 200,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: ListView(
        children: [
          for (final s in SettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SectionItem(
                section: s,
                selected: s == section,
                compact: compact,
                onTap: () => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个分区项 —— 图标与文字并列（横向）。
class _SectionItem extends StatelessWidget {
  const _SectionItem({
    required this.section,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final SettingsSection section;
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
            vertical: 12,
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(section.icon, size: 20, color: color),
              // 图标与文字并列；紧凑模式下仅显示图标。
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
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

// === 通用 ===

class _GeneralSection extends StatefulWidget {
  const _GeneralSection();

  @override
  State<_GeneralSection> createState() => _GeneralSectionState();
}

class _GeneralSectionState extends State<_GeneralSection> {
  late AppLanguage _language;
  late bool _multi;
  late bool _vaultEnabled;
  late bool _devEnabled;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _language = LocaleSettings.instance.language;
    _multi = context.read<ClusterState>().mode == ManagementMode.multi;
    _vaultEnabled = VaultSettings.defaultEnabled;
    _devEnabled = false;
    unawaited(_loadToggles());
  }

  /// 异步加载 Vault 与开发者模式开关状态（SQLite settings 表）。
  Future<void> _loadToggles() async {
    final vault = await VaultSettings.isEnabled();
    final dev = await DeveloperSettings.isEnabled();
    if (!mounted) return;
    setState(() {
      _vaultEnabled = vault;
      _devEnabled = dev;
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
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.common_language),
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

        const Divider(height: 32),

        // 管理模式
        _ToggleRow(
          icon: Icons.lan_outlined,
          title: l.settings_multiMode,
          subtitle: _multi ? l.settings_multiModeOn : l.settings_singleMode,
          value: _multi,
          onChanged: _toggleMode,
        ),
        const SizedBox(height: 8),
        Text(l.settings_multiModeHint, style: theme.textTheme.bodySmall),

        const Divider(height: 32),

        // Vault 加密保险库
        _ToggleRow(
          icon: Icons.shield_outlined,
          title: l.settings_vault,
          subtitle: _vaultEnabled ? l.settings_vaultOn : l.settings_vaultOff,
          value: _vaultEnabled,
          onChanged: (v) async {
            setState(() => _vaultEnabled = v);
            await VaultSettings.setEnabled(v);
          },
        ),

        const Divider(height: 32),

        // 开发者模式
        _ToggleRow(
          icon: Icons.bug_report_outlined,
          title: l.settings_developer,
          subtitle: _devEnabled
              ? l.settings_developerOn
              : l.settings_developerOff,
          value: _devEnabled,
          onChanged: (v) async {
            setState(() => _devEnabled = v);
            await DeveloperSettings.setEnabled(v);
            await DevLog.instance.refreshEnabled();
          },
        ),
        const SizedBox(height: 8),
        Text(l.settings_developerHint, style: theme.textTheme.bodySmall),
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

// === 外观 ===

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late String _uiFont;
  late String _terminalFont;

  @override
  void initState() {
    super.initState();
    final fonts = FontSettings.instance;
    _uiFont = fonts.uiFamily;
    _terminalFont = fonts.terminalFamily;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.settings_font),
        Text(l.settings_fontHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
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
        const SizedBox(height: 12),
        Text(l.settings_fontFallbackHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// === 下载 ===

class _DownloadSection extends StatefulWidget {
  const _DownloadSection();

  @override
  State<_DownloadSection> createState() => _DownloadSectionState();
}

class _DownloadSectionState extends State<_DownloadSection> {
  late double _threads;

  @override
  void initState() {
    super.initState();
    _threads = context.read<AppState>().downloadThreads.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.settings_downloadThreads(_threads.round())),
        Slider(
          value: _threads,
          min: DownloadSettings.minThreads.toDouble(),
          max: DownloadSettings.maxThreads.toDouble(),
          divisions: DownloadSettings.maxThreads - DownloadSettings.minThreads,
          label: '${_threads.round()}',
          onChanged: (v) => setState(() => _threads = v),
          onChangeEnd: (v) =>
              context.read<AppState>().setDownloadThreads(v.round()),
        ),
        Text(l.settings_downloadThreadsHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// === 插件 ===

/// 插件/Mod 列表的展示设置（懒加载批量）。
class _PluginsSection extends StatefulWidget {
  const _PluginsSection();

  @override
  State<_PluginsSection> createState() => _PluginsSectionState();
}

class _PluginsSectionState extends State<_PluginsSection> {
  /// 当前每次加载条数；null 表示仍在读取持久化值。
  double? _batch;

  @override
  void initState() {
    super.initState();
    PluginViewSettings.getBatchSize().then((value) {
      if (mounted) setState(() => _batch = value.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final batch = _batch;

    if (batch == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.settings_pluginsBatchSize(batch.round())),
        Slider(
          value: batch,
          min: PluginViewSettings.minBatchSize.toDouble(),
          max: PluginViewSettings.maxBatchSize.toDouble(),
          divisions:
              (PluginViewSettings.maxBatchSize -
                  PluginViewSettings.minBatchSize) ~/
              PluginViewSettings.batchSizeStep,
          label: '${batch.round()}',
          onChanged: (v) => setState(() => _batch = v),
          onChangeEnd: (v) => PluginViewSettings.setBatchSize(v.round()),
        ),
        Text(l.settings_pluginsBatchSizeHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// === 数据库 ===

class _DatabaseSection extends StatefulWidget {
  const _DatabaseSection();

  @override
  State<_DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends State<_DatabaseSection> {
  late double _pageSize;

  @override
  void initState() {
    super.initState();
    _pageSize = DbPageSettings.pageSize.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.settings_dbPageSize(_pageSize.round())),
        Slider(
          value: _pageSize,
          min: DbPageSettings.minPageSize.toDouble(),
          max: DbPageSettings.maxPageSize.toDouble(),
          divisions: DbPageSettings.maxPageSize - DbPageSettings.minPageSize,
          label: '${_pageSize.round()}',
          onChanged: (v) => setState(() => _pageSize = v),
          onChangeEnd: (v) => DbPageSettings.setPageSize(v.round()),
        ),
        Text(l.settings_dbPageSizeHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// === Java 管理 ===

class _JavaSection extends StatelessWidget {
  const _JavaSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Java 运行时管理'),
        Text(
          '扫描本机已安装的 Java，管理 IriX 安装的 JDK，或手动添加/禁用指定 Java。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        const JavaManagementSection(),
      ],
    );
  }
}

// === 软件更新（OTA）===

/// 软件更新分区：当前版本、自动检查开关、预发布开关、手动检查更新。
///
/// 检查 / 下载 / 安装的实现在 [UpdateService]，提示窗与启动提醒共用
/// [showUpdateDialog]。
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  bool _loading = true;
  bool _autoCheck = UpdateSettings.defaultAutoCheck;
  bool _includePrerelease = UpdateSettings.defaultIncludePrerelease;
  bool _checking = false;
  int _lastCheckAtMs = 0;
  String _lastKnownLatest = '';
  String _skippedVersion = '';
  String? _status;
  String? _error;

  /// 设置里填的自定义更新源（空 = 用构建期内置源 / GitHub 官方）。
  String _feedUrl = '';

  /// 更新源输入框（用户手动填 Cloudflare Worker 地址）。
  late final TextEditingController _feedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _feedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final autoCheck = await UpdateSettings.getAutoCheck();
    final includePre = await UpdateSettings.getIncludePrerelease();
    final lastCheck = await UpdateSettings.getLastCheckAtMs();
    final latest = await UpdateSettings.getLastKnownLatest();
    final skipped = await UpdateSettings.getSkippedVersion();
    final feed = await UpdateSettings.getFeedUrl();
    if (!mounted) return;
    setState(() {
      _autoCheck = autoCheck;
      _includePrerelease = includePre;
      _lastCheckAtMs = lastCheck;
      _lastKnownLatest = latest;
      _skippedVersion = skipped;
      _feedUrl = feed;
      if (_feedController.text != feed) _feedController.text = feed;
      _loading = false;
    });
  }

  /// 当前实际生效的更新源（列表第一个）。
  String get _effectiveFeed => UpdateService.feedCandidates(
    configured: _feedUrl,
  ).first;

  /// 保存自定义更新源（空 = 恢复默认）。
  Future<void> _saveFeed(String value) async {
    final l = AppLocalizations.of(context);
    final normalized = UpdateService.normalizeFeedUrl(value);
    await UpdateSettings.setFeedUrl(normalized);
    if (!mounted) return;
    setState(() {
      _feedUrl = normalized;
      _feedController.text = normalized;
      _status = l.settings_updateFeedSaved;
      _error = null;
    });
  }

  /// 运行中的实例数（更新会重启应用，用它提示风险）。
  int get _runningInstances => context
      .read<AppState>()
      .instances
      .where((i) => i.status.isActive)
      .length;

  Future<void> _check() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _error = null;
      _status = null;
    });
    try {
      final info = await UpdateService.instance.checkForUpdates(
        includePrerelease: _includePrerelease,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _lastCheckAtMs = TimeService.instance.nowUnixMs();
        _lastKnownLatest = info?.version.toString() ?? _lastKnownLatest;
        _status = info == null
            ? l.settings_updateUpToDate(kIrixAppVersionLabel)
            : l.settings_updateFound(info.versionLabel);
      });
      if (info != null) {
        final result = await showUpdateDialog(
          context,
          info: info,
          runningInstances: _runningInstances,
          manual: true,
        );
        if (!mounted) return;
        if (result == UpdateDialogResult.skipped) {
          setState(() => _skippedVersion = info.version.toString());
        }
      }
      await _load();
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.message;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '$e';
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final checkedText = _lastCheckAtMs <= 0
        ? l.settings_updateNeverChecked
        : l.settings_updateLastChecked(
            DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(DateTime.fromMillisecondsSinceEpoch(_lastCheckAtMs)),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(l.settings_update),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.settings_updateVersionLine(
                  kIrixAppVersionLabel,
                  '${UpdateService.platformTag}/${UpdateService.archTag}',
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(checkedText, style: theme.textTheme.bodySmall),
        if (_lastKnownLatest.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            l.settings_updateLatestKnown('v$_lastKnownLatest'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_skippedVersion.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.settings_updateSkipped('v$_skippedVersion'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await UpdateService.instance.clearSkippedVersion();
                  if (!mounted) return;
                  setState(() => _skippedVersion = '');
                },
                child: Text(l.settings_updateClearSkip),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),
        Row(
          children: [
            AppleButton(
              onPressed: _checking ? null : _check,
              child: Text(
                _checking
                    ? l.settings_updateChecking
                    : l.settings_updateCheckNow,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => UpdateService.instance.openReleasePage(),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l.settings_updateOpenReleases),
            ),
            if (_checking) ...[
              const SizedBox(width: 16),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(
            _status!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          SelectableText(
            l.settings_updateError(_error!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],

        const Divider(height: 32),

        // 更新源：默认为构建期内置源 → GitHub 官方 Releases；
        // 填 Cloudflare Worker 地址可加速检查与安装包下载。
        Text(
          l.settings_updateFeed,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _feedController,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: UpdateService.defaultFeedUrl,
                  prefixIcon: const Icon(Icons.cloud_queue, size: 18),
                ),
                onSubmitted: (v) => unawaited(_saveFeed(v)),
              ),
            ),
            const SizedBox(width: 8),
            AppleButton(
              onPressed: () => _saveFeed(_feedController.text),
              child: Text(l.settings_updateFeedSave),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _feedUrl.isEmpty
                  ? null
                  : () {
                      _feedController.text = '';
                      unawaited(_saveFeed(''));
                    },
              child: Text(l.settings_updateFeedReset),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l.settings_updateFeedHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        SelectableText(
          l.settings_updateFeedCurrent(_effectiveFeed),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const Divider(height: 32),

        _ToggleRow(
          icon: Icons.autorenew,
          title: l.settings_updateAutoCheck,
          subtitle: l.settings_updateAutoCheckHint(
            '${UpdateSettings.autoCheckInterval.inHours}',
          ),
          value: _autoCheck,
          onChanged: (v) async {
            setState(() => _autoCheck = v);
            await UpdateSettings.setAutoCheck(v);
          },
        ),

        const Divider(height: 32),

        _ToggleRow(
          icon: Icons.science_outlined,
          title: l.settings_updateIncludePrerelease,
          subtitle: l.settings_updateIncludePrereleaseHint,
          value: _includePrerelease,
          onChanged: (v) async {
            setState(() => _includePrerelease = v);
            await UpdateSettings.setIncludePrerelease(v);
          },
        ),

        const SizedBox(height: 16),
        Text(l.settings_updateHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          _installHint(l),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 各平台的安装能力说明（Windows 可全自动，macOS 需用户拖拽）。
  String _installHint(AppLocalizations l) {
    if (Platform.isWindows) return l.settings_updateInstallHintWindows;
    if (Platform.isMacOS) return l.settings_updateInstallHintMacos;
    return l.settings_updateInstallHintLinux;
  }
}

// === 通用小组件 ===

/// 分区标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 图标 + 标题/副标题 + 开关 的一行（与原设置弹窗的排版一致）。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        AppleSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
