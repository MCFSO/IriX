// 原生插件管理页
//
// 展示从 Rust 插件宿主动态库（xmc_plugin_host）读取的插件列表，支持：
// - 安装插件包（zip，含风险提示）
// - 启用 / 禁用开关
// - 卸载
// - 详情页（manifest + README 预览）
//
// 插件的加载、事件分发、权限检查全部在 Rust 侧完成，本页只做 UI 与 FFI 调用。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/plugin_ffi.dart';
import '../services/plugin_service.dart';
import '../utils/apple_widgets.dart';

/// 插件管理主页面（列表）。
class PluginManagerScreen extends StatefulWidget {
  const PluginManagerScreen({super.key});

  @override
  State<PluginManagerScreen> createState() => _PluginManagerScreenState();
}

class _PluginManagerScreenState extends State<PluginManagerScreen> {
  bool _loading = true;
  List<PluginInfo> _plugins = [];
  String? _error;

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
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('安装失败: $e')));
    }
  }

  /// 打开插件详情页。
  void _openDetail(PluginInfo plugin) {
    pushPage(context, (_) => PluginDetailScreen(pluginId: plugin.id)).then((_) {
      // 详情页可能改动了启用状态 / 卸载，返回后刷新。
      _load();
    });
  }

  /// 切换启用 / 禁用。
  Future<void> _toggle(PluginInfo plugin, bool enabled) async {
    try {
      await PluginService.instance.toggle(plugin.id, enabled);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '安装插件',
            onPressed: _install,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
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
    if (_plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('尚未安装任何插件'),
            const SizedBox(height: 8),
            Text(
              '点击右上角 + 安装 .zip 插件包',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _plugins.length,
      itemBuilder: (context, index) {
        final plugin = _plugins[index];
        return _PluginCard(
          plugin: plugin,
          onTap: () => _openDetail(plugin),
          onToggle: (enabled) => _toggle(plugin, enabled),
        );
      },
    );
  }
}

/// 单个插件卡片。
class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.onTap,
    required this.onToggle,
  });

  final PluginInfo plugin;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusChip(theme, plugin);
    final interactive = plugin.isInteractive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.extension, size: 36, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plugin.name.isEmpty ? plugin.id : plugin.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'v${plugin.version}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (plugin.author.isNotEmpty)
                          Text(plugin.author, style: theme.textTheme.bodySmall),
                        status,
                      ],
                    ),
                    if (plugin.error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        plugin.error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppleSwitch(
                value: plugin.enabled,
                onChanged: interactive ? onToggle : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态标签。
Widget _statusChip(ThemeData theme, PluginInfo plugin) {
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
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

/// 插件详情页（manifest + README）。
class PluginDetailScreen extends StatefulWidget {
  const PluginDetailScreen({super.key, required this.pluginId});

  final String pluginId;

  @override
  State<PluginDetailScreen> createState() => _PluginDetailScreenState();
}

class _PluginDetailScreenState extends State<PluginDetailScreen> {
  bool _loading = true;
  PluginInfo? _plugin;
  String _readme = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final plugin = await PluginService.instance.detail(widget.pluginId);
      final readme = await PluginService.instance.readme(widget.pluginId);
      if (!mounted) return;
      setState(() {
        _plugin = plugin;
        _readme = readme;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    try {
      await PluginService.instance.toggle(widget.pluginId, enabled);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    }
  }

  Future<void> _uninstall() async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text(
          _plugin?.loaded == true ? '该插件已加载，卸载将在重启后生效。' : '确定卸载该插件吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await PluginService.instance.uninstall(widget.pluginId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('卸载失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _plugin?.name.isNotEmpty == true ? _plugin!.name : '插件详情',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final plugin = _plugin;
    if (plugin == null) {
      return const Center(child: Text('插件不存在'));
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 头部：名称 + 状态 + 开关
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name.isEmpty ? plugin.id : plugin.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'v${plugin.version}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (plugin.author.isNotEmpty)
                        Text(plugin.author, style: theme.textTheme.bodySmall),
                      _statusChip(theme, plugin),
                    ],
                  ),
                ],
              ),
            ),
            AppleSwitch(
              value: plugin.enabled,
              onChanged: plugin.isInteractive ? _toggle : null,
            ),
          ],
        ),
        if (plugin.error != null) ...[
          const SizedBox(height: 8),
          Text(
            '错误: ${plugin.error}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const Divider(height: 24),
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
        const SizedBox(height: 16),
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
        if (plugin.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section(theme, '描述', [Text(plugin.description)]),
        ],
        const SizedBox(height: 16),
        // 操作
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _uninstall,
            icon: const Icon(Icons.delete_outline),
            label: Text(plugin.pendingRestart ? '重启后卸载' : '卸载'),
          ),
        ),
        const SizedBox(height: 24),
        // README
        Text('README', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_readme.isEmpty)
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
