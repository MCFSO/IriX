// Java 管理界面（移植自 HMCL ui/main/JavaManagementPage.java）
//
// 对应 HMCL 的工具栏与列表：
//   刷新            ⇐ JavaManager::refresh
//   下载安装        ⇐ JavaDownloadDialog（复用 JdkInstaller + Adoptium）
//   添加            ⇐ onAddJava（选择 java 可执行文件 / java home）
//   已禁用管理      ⇐ JavaRestorePage（恢复被禁用的 Java）
//
// 列表项复刻 HMCL JavaItemCell：
//   左侧大版本数字徽标 + 标题「厂商 JDK/JRE 版本」+ 副标题（可执行文件路径）
//   + 架构标签；右侧「在文件管理器中打开」与「卸载/禁用」按钮。
//   受管安装显示 DELETE_FOREVER（真卸载），系统安装显示 DELETE（禁用）。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/java_runtime.dart';
import '../services/java/java_service.dart';
import '../services/jdk_installer.dart';
import '../utils/apple_widgets.dart';

/// Java 管理分区（嵌入全局设置页）。
class JavaManagementSection extends StatefulWidget {
  const JavaManagementSection({super.key});

  @override
  State<JavaManagementSection> createState() => _JavaManagementSectionState();
}

class _JavaManagementSectionState extends State<JavaManagementSection> {
  final _service = JavaService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    // 首次挂载时惰性扫描（HMCL initialize()）。
    _service.ensureInitialized();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runtimes = _service.runtimes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(theme),
        const SizedBox(height: 16),
        if (_service.isLoading && runtimes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_service.error != null && runtimes.isEmpty)
          _buildMessage(
            theme,
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            text: '扫描 Java 失败：${_service.error}',
          )
        else if (runtimes.isEmpty)
          _buildMessage(
            theme,
            icon: Icons.coffee_outlined,
            color: theme.colorScheme.outline,
            text: '未检测到任何 Java 运行时\n可点击「下载安装」或「添加」手动指定',
          )
        else
          ...runtimes.map((r) => _JavaTile(runtime: r)),
        if (_service.disabled.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildDisabledPanel(theme),
        ],
      ],
    );
  }

  /// 工具栏：刷新 / 下载安装 / 添加 / 已禁用管理。
  Widget _buildToolbar(ThemeData theme) {
    final disabledCount = _service.disabled.length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _toolbarButton(
          icon: Icons.refresh,
          label: '刷新',
          onPressed: _service.isLoading
              ? null
              : () => _service.refresh(useCache: false),
        ),
        _toolbarButton(
          icon: Icons.download,
          label: '下载安装',
          onPressed: _onInstallJava,
        ),
        _toolbarButton(icon: Icons.add, label: '添加', onPressed: _onAddJava),
        _toolbarButton(
          icon: Icons.format_list_bulleted,
          label: disabledCount > 0 ? '已禁用管理 ($disabledCount)' : '已禁用管理',
          onPressed: disabledCount > 0 ? _onShowDisabled : null,
        ),
      ],
    );
  }

  /// 工具栏按钮（图标与文字并列，风格与 AppleButton 一致）。
  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return AppleButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  /// 空态 / 错误态提示。
  Widget _buildMessage(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 被禁用的 Java 恢复面板（对应 HMCL JavaRestorePage）。
  Widget _buildDisabledPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, size: 18),
              const SizedBox(width: 8),
              Text('已禁用的 Java', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '这些 Java 已被排除在检测之外，可恢复后重新参与选择。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final path in _service.disabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      path,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _service.enable(path),
                    child: const Text('恢复'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 手动添加：选择 java 可执行文件或 JDK 目录（HMCL onAddJava 走文件选择器）。
  Future<void> _onAddJava() async {
    final l = '选择 Java 可执行文件或 JDK 目录';
    String? picked;
    try {
      // 优先尝试选择 java 可执行文件（HMCL 同款扩展名过滤）。
      picked = await FilePicker.platform
          .pickFiles(dialogTitle: l, type: FileType.any)
          .then((r) => r?.files.single.path);
    } catch (_) {
      picked = null;
    }

    if (picked == null) {
      // 用户取消文件选择时，退化为选择目录（HMCL 支持拖入目录）。
      try {
        picked = await FilePicker.platform.getDirectoryPath(dialogTitle: l);
      } catch (_) {
        picked = null;
      }
    }

    if (picked == null || !mounted) return;

    final runtime = await _service.addByPath(picked);
    if (!mounted) return;

    if (runtime == null) {
      _showSnack('添加失败：${_service.lastAddError ?? '未知错误'}', isError: true);
    } else {
      _showSnack('已添加 ${runtime.displayTitle}');
    }
  }

  /// 下载安装：输入大版本 → 走 JdkInstaller（Adoptium）。
  Future<void> _onInstallJava() async {
    final controller = TextEditingController(text: '21');
    final version = await showAppDialog<String>(
      context,
      (ctx) => AlertDialog(
        title: const Text('下载安装 Java'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入要安装的 Java 大版本（8 / 11 / 17 / 21 / 25）'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: '大版本',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '将从 Eclipse Temurin（Adoptium）下载对应平台的 JDK，'
              '安装到应用的 java 目录下。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );

    if (version == null || version.isEmpty || !mounted) return;
    if (int.tryParse(version) == null) {
      _showSnack('请输入有效的版本号', isError: true);
      return;
    }

    // 下载进度对话框（无取消，Adoptium 下载通常较快）。
    final progress = ValueNotifier<double>(0);
    unawaitedShowProgress(progress, version);

    try {
      await JdkInstaller.instance.install(
        version,
        onProgress: (p) => progress.value = p,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('Java $version 安装完成');
      // 受管安装落盘后重新扫描以纳入列表。
      await _service.refresh(useCache: false);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('安装失败：$e', isError: true);
    }
  }

  /// 弹出进度对话框（独立于设置页，便于安装期间继续浏览）。
  void unawaitedShowProgress(ValueNotifier<double> progress, String version) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('正在安装 Java $version'),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppleProgressIndicator(value: value > 0 ? value : null),
                const SizedBox(height: 10),
                Text('已下载 ${(value * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 已禁用管理（HMCL 的 JavaRestorePage 是一个独立页；此处滚动到面板）。
  void _onShowDisabled() {
    final l = _service.disabled.toList();
    if (l.isEmpty) return;
    showAppDialog<void>(
      context,
      (ctx) => AlertDialog(
        title: const Text('已禁用的 Java'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final path in l)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    path,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      _service.enable(path);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('恢复'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

/// 单个 Java 运行时列表项（复刻 HMCL JavaItemCell）。
class _JavaTile extends StatelessWidget {
  const _JavaTile({required this.runtime});

  final JavaRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isManaged = runtime.isManaged;
    final version = runtime.parsedVersion;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 大版本数字徽标（HMCL 用 32x32 Label 显示 parsedVersion）。
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                version >= 0 ? '$version' : '?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          runtime.displayTitle,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 架构标签 + 受管标记。
                      _tag(theme, runtime.architecture.displayName),
                      if (isManaged) ...[
                        const SizedBox(width: 6),
                        _tag(theme, '受管', color: theme.colorScheme.primary),
                      ],
                      if (!runtime.isCompatibleWithHost) ...[
                        const SizedBox(width: 6),
                        _tag(theme, '不兼容', color: theme.colorScheme.error),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    runtime.binary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 在文件管理器中打开（HMCL onReveal）。
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: '在文件管理器中打开',
              onPressed: () => _reveal(runtime),
            ),
            // 卸载（受管）或禁用（系统安装）。
            IconButton(
              icon: Icon(
                isManaged ? Icons.delete_forever : Icons.delete_outline,
                size: 20,
              ),
              tooltip: isManaged ? '卸载' : '禁用',
              onPressed: () => _onRemove(context, runtime),
            ),
          ],
        ),
      ),
    );
  }

  /// 小标签。
  Widget _tag(ThemeData theme, String text, {Color? color}) {
    final c = color ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: c)),
    );
  }

  /// 在系统文件管理器中定位（HMCL onReveal：优先打开 java home）。
  static void _reveal(JavaRuntime java) {
    final home = java.javaHome;
    final target = Directory(home).existsSync() ? home : java.binary;
    try {
      if (Platform.isWindows) {
        // 受管/系统 JDK 目录统一用资源管理器打开。
        Process.run('explorer', [target]);
      } else if (Platform.isMacOS) {
        Process.run('open', [target]);
      } else {
        Process.run('xdg-open', [target]);
      }
    } catch (_) {
      // 打开失败不影响主流程（无桌面环境等）。
    }
  }

  /// 卸载 / 禁用（HMCL onRemove）。
  static Future<void> _onRemove(BuildContext context, JavaRuntime java) async {
    final isManaged = java.isManaged;
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(isManaged ? '卸载 Java' : '禁用 Java'),
        content: Text(
          isManaged
              ? '将从磁盘删除该受管 Java 安装：\n\n${java.binary}\n\n此操作不可撤销。'
              : '将把该 Java 从检测列表中排除（不删除磁盘文件）：\n\n'
                    '${java.binary}\n\n可在「已禁用管理」中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isManaged ? '卸载' : '禁用'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (isManaged) {
      final ok = await JavaService.instance.uninstall(java);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '已卸载 ${java.displayTitle}' : '卸载失败：非受管安装'),
          ),
        );
      }
    } else {
      await JavaService.instance.disable(java);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已禁用 ${java.displayTitle}')));
      }
    }
  }
}
