// 原生插件管理页（左右分栏：左侧列表 + 右侧详情）
//
// 展示从 Rust 插件宿主动态库（xmc_plugin_host）读取的插件列表：
// - 右上角「+」安装插件包（zip，含风险提示）
// - 左侧列表选中插件，右侧显示描述 / 元数据 / 权限 / README
// - 右侧详情内删除插件（同时保留启用开关）
//
// 插件未选中时右侧显示占位提示，避免空白面板。
// 插件的加载、事件分发、权限检查全部在 Rust 侧完成，本页只做 UI 与 FFI 调用。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/plugin_ffi.dart';
import '../services/plugin_service.dart';
import '../utils/apple_widgets.dart';

/// 插件管理主页面（左列表 + 右详情）。
///
/// [embedded] 为 true 时作为内容区嵌入主页（不显示返回按钮），
/// 供左侧边栏导航使用；为 false 时作为独立页面压栈。
class PluginManagerScreen extends StatefulWidget {
  const PluginManagerScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PluginManagerScreen> createState() => _PluginManagerScreenState();
}

class _PluginManagerScreenState extends State<PluginManagerScreen> {
  bool _loading = true;
  List<PluginInfo> _plugins = [];
  String? _error;

  /// 当前选中的插件 id（null 表示未选中）。
  String? _selectedId;

  /// 右侧详情数据（选中后加载）。
  PluginInfo? _detail;
  String _readme = '';
  bool _detailLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plugins = await PluginService.instance.list();
      if (!mounted) return;
      setState(() {
        _plugins = plugins;
        _loading = false;
        // 保持原选中项；若已不存在（被卸载）则清空右侧详情。
        if (_selectedId != null && !plugins.any((p) => p.id == _selectedId)) {
          _selectedId = null;
          _detail = null;
          _readme = '';
        }
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 选中插件并加载右侧详情。
  Future<void> _select(PluginInfo plugin) async {
    setState(() {
      _selectedId = plugin.id;
      _detail = plugin;
      _readme = '';
      _detailLoading = true;
    });

    try {
      final detail = await PluginService.instance.detail(plugin.id);
      final readme = await PluginService.instance.readme(plugin.id);
      // 期间用户可能已切到别的插件，丢弃过期结果。
      if (!mounted || _selectedId != plugin.id) return;
      setState(() {
        _detail = detail ?? plugin;
        _readme = readme;
        _detailLoading = false;
      });
    } on Exception catch (e) {
      if (!mounted || _selectedId != plugin.id) return;
      setState(() => _detailLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载详情失败: $e')));
    }
  }

  /// 安装插件包流程：选 zip -> 风险提示 -> 安装 -> 刷新。
  Future<void> _install() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!mounted) return;

    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('安装原生插件'),
        content: const Text(
          '原生插件运行在宿主进程内，没有沙箱隔离，可访问你的系统与数据。'
          '仅安装来源可信的插件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('我了解风险，继续安装'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await PluginService.instance.install(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warning == null
                ? '插件安装成功: ${result.id}'
                : '已安装 ${result.id}，但加载失败: ${result.warning}',
          ),
        ),
      );
      await _load();
      // 安装后自动选中新插件，右侧直接展示其描述。
      final installed = _plugins.where((p) => p.id == result.id).firstOrNull;
      if (installed != null && mounted) await _select(installed);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('安装失败: $e')));
    }
  }

  /// 切换启用 / 禁用。
  Future<void> _toggle(PluginInfo plugin, bool enabled) async {
    try {
      await PluginService.instance.toggle(plugin.id, enabled);
      await _load();
      // 同步刷新右侧详情，让状态标签立即更新。
      final refreshed = _plugins.where((p) => p.id == plugin.id).firstOrNull;
      if (refreshed != null && mounted) await _select(refreshed);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    }
  }

  /// 卸载（删除）插件 —— 从右侧详情触发。
  Future<void> _uninstall(PluginInfo plugin) async {
    final loaded = plugin.loaded;
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除插件'),
        content: Text(
          loaded
              ? '「${plugin.name.isEmpty ? plugin.id : plugin.name}」已加载，'
                    '删除将在重启后生效。\n\n确定删除吗？'
              : '确定删除「${plugin.name.isEmpty ? plugin.id : plugin.name}」吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(plugin.pendingRestart ? '重启后删除' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await PluginService.instance.uninstall(plugin.id);
      if (!mounted) return;
      // 清空右侧详情并刷新列表（卸载正常表现为列表少一项）。
      setState(() {
        _selectedId = null;
        _detail = null;
        _readme = '';
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loaded ? '已标记删除，重启后生效' : '已删除 ${plugin.id}')),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) {
      // 嵌入主页内容区：用 Column 自带头部（无返回按钮）。
      return Column(
        children: [
          _buildEmbeddedHeader(),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(appBar: _buildAppBar(), body: body);
  }

  /// 顶部操作按钮（添加插件 / 刷新）。
  List<Widget> _headerActions() => [
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: '添加插件',
      onPressed: _install,
    ),
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: '刷新',
      onPressed: _load,
    ),
    const SizedBox(width: 4),
  ];

  /// 独立页面用的 AppBar。
  PreferredSizeWidget _buildAppBar() =>
      AppBar(title: const Text('插件'), actions: _headerActions());

  /// 嵌入内容区用的头部（普通 Widget，含标题与右上角操作）。
  Widget _buildEmbeddedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Text(
            '插件',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ..._headerActions(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 左右分栏：左列表 + 右详情。窄窗口下详情改为覆盖/仅列表。
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        if (narrow) {
          // 窄窗口：未选中时全宽列表；选中后全宽详情（可返回列表）。
          return _selectedId == null
              ? _buildList()
              : _buildDetailPane(showBack: true);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 300, child: _buildList()),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _buildDetailPane()),
          ],
        );
      },
    );
  }

  /// 左侧插件列表。
  Widget _buildList() {
    if (_plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('尚未安装任何插件'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '点击右上角 + 安装 .zip 插件包',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: _plugins.length,
      itemBuilder: (context, index) {
        final plugin = _plugins[index];
        return _PluginListTile(
          plugin: plugin,
          selected: plugin.id == _selectedId,
          onTap: () => _select(plugin),
        );
      },
    );
  }

  /// 右侧详情面板。
  Widget _buildDetailPane({bool showBack = false}) {
    final plugin = _detail;
    if (plugin == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '从左侧选择一个插件查看详情',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 头部：名称 + 状态 + 开关（窄窗口多一个返回列表按钮）
        Row(
          children: [
            if (showBack)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回列表',
                onPressed: () => setState(() {
                  _selectedId = null;
                  _detail = null;
                  _readme = '';
                }),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name.isEmpty ? plugin.id : plugin.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'v${plugin.version}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (plugin.author.isNotEmpty)
                        Text(plugin.author, style: theme.textTheme.bodySmall),
                      pluginStatusChip(theme, plugin),
                    ],
                  ),
                ],
              ),
            ),
            AppleSwitch(
              value: plugin.enabled,
              onChanged: plugin.isInteractive
                  ? (v) => _toggle(plugin, v)
                  : null,
            ),
          ],
        ),
        if (plugin.error != null) ...[
          const SizedBox(height: 10),
          Text(
            '错误: ${plugin.error}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const Divider(height: 28),

        // 描述（用户最先看到的部分）
        _section(theme, '描述', [
          Text(plugin.description.isEmpty ? '该插件未提供描述' : plugin.description),
        ]),
        const SizedBox(height: 18),

        // 元数据
        _section(theme, '元数据', [
          _kv('ID', plugin.id),
          _kv('类型', plugin.type),
          _kv('入口', plugin.entry),
          _kv(
            '最低宿主版本',
            plugin.minAppVersion.isEmpty ? '不限' : plugin.minAppVersion,
          ),
        ]),
        const SizedBox(height: 18),

        // 权限
        _section(theme, '权限', [
          if (plugin.permissions.isEmpty)
            Text('未声明权限', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final perm in plugin.permissions) _permChip(theme, perm),
              ],
            ),
        ]),
        const SizedBox(height: 24),

        // 删除（用户要求：在描述部分内可直接删除该插件）
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _uninstall(plugin),
            icon: const Icon(Icons.delete_outline),
            label: Text(plugin.pendingRestart ? '重启后删除' : '删除插件'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // README
        Text('README', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_detailLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_readme.isEmpty)
          Text('该插件未提供 README', style: theme.textTheme.bodySmall)
        else
          MarkdownBody(
            data: _readme,
            styleSheet: MarkdownStyleSheet.fromTheme(theme),
          ),
      ],
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(key, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _permChip(ThemeData theme, String perm) {
    final color = theme.colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        perm,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 左侧列表项（选中态高亮）。
class _PluginListTile extends StatelessWidget {
  const _PluginListTile({
    required this.plugin,
    required this.selected,
    required this.onTap,
  });

  final PluginInfo plugin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = plugin.name.isEmpty ? plugin.id : plugin.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.extension,
                  size: 22,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : null,
                          color: selected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'v${plugin.version}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: pluginStatusChip(theme, plugin)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态标签（列表与详情共用）。
Widget pluginStatusChip(ThemeData theme, PluginInfo plugin) {
  final (label, color) = switch (plugin.status) {
    'loaded' => ('已启用', Colors.green),
    'disabled' => ('已禁用', Colors.grey),
    'not_supported' => ('平台不支持', Colors.orange),
    'error' => ('错误', theme.colorScheme.error),
    'pending_restart' => ('重启生效', Colors.amber),
    'crashed' => ('已崩溃', theme.colorScheme.error),
    _ => (plugin.status, Colors.grey),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}
