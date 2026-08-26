// 远程文件管理器
// 浏览节点上某个实例的工作目录（MCSM / 本地节点同一套 API）：
// - 目录浏览（面包屑导航）
// - 上传 / 下载 / 新建文件 / 新建目录 / 编辑 / 重命名 / 删除 / 压缩 / 解压
// 文件管理已收归实例详情页（RemoteInstanceDetailScreen「文件」Tab），
// 以嵌入模式渲染并锁定单个实例（initialUuid）。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/node_ops.dart';
import '../models/remote.dart';
import '../services/node_api_client.dart';
import '../services/font_settings.dart';
import '../utils/apple_widgets.dart';

/// 远程文件管理器。
class RemoteFileManagerScreen extends StatefulWidget {
  const RemoteFileManagerScreen({
    super.key,
    required this.client,
    required this.daemonId,
    this.overview,
    this.initialUuid,
    this.embedded = false,
  });

  final NodeApiClient client;
  final String? daemonId;
  final OverviewData? overview;
  final String? initialUuid;

  /// 以嵌入模式渲染（不含 Scaffold/AppBar），用于实例详情页的「文件」Tab。
  final bool embedded;

  @override
  State<RemoteFileManagerScreen> createState() =>
      _RemoteFileManagerScreenState();
}

class _RemoteFileManagerScreenState extends State<RemoteFileManagerScreen> {
  String? _uuid;
  String _path = '/';
  List<RemoteFileEntry>? _entries;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _uuid = widget.initialUuid;
    _init();
  }

  Future<void> _init() async {
    final daemonId = widget.daemonId;
    if (daemonId == null || daemonId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无法确定守护进程 ID';
      });
      return;
    }
    try {
      // 已锁定实例（实例详情传入 initialUuid）时无需拉取实例列表；
      // 未指定时回退到守护进程的第一个实例。
      if (_uuid == null) {
        final instances = await widget.client.listInstances(daemonId: daemonId);
        if (!mounted) return;
        setState(() {
          _uuid = instances.isNotEmpty ? instances.first.uuid : null;
        });
      }
      setState(() => _loading = false);
      if (_uuid != null) {
        await _loadEntries();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      if (_uuid != null) {
        await _loadEntries();
      }
    }
  }

  Future<void> _loadEntries() async {
    final uuid = _uuid;
    if (uuid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client.listFiles(
        daemonId: widget.daemonId ?? '',
        uuid: uuid,
        target: _path,
      );
      if (!mounted) return;
      setState(() {
        _entries = data.items;
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

  /// 拼接路径。
  String _join(String segment) {
    if (_path == '/') return '/$segment';
    return '$_path/$segment';
  }

  /// 进入目录 / 打开文件。
  void _openEntry(RemoteFileEntry entry) {
    if (entry.isDirectory) {
      setState(() => _path = _join(entry.name));
      _loadEntries();
    } else {
      _showFileActions(entry);
    }
  }

  /// 面包屑点击。
  void _navigateTo(int index) {
    if (index < 0) {
      setState(() => _path = '/');
    } else {
      final parts = _path.split('/').where((e) => e.isNotEmpty).toList();
      setState(() => _path = '/${parts.sublist(0, index + 1).join('/')}');
    }
    _loadEntries();
  }

  Future<void> _mkdir() async {
    final name = await _promptText('新建文件夹', '文件夹名称');
    if (name == null || !mounted) return;
    try {
      await widget.client.mkdir(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        target: _join(name.trim()),
      );
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _touch() async {
    final name = await _promptText('新建文件', '文件名称');
    if (name == null || !mounted) return;
    try {
      await widget.client.touchFile(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        target: _join(name.trim()),
      );
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要上传的文件',
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ticket = await widget.client.uploadTicket(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        uploadDir: _path,
      );
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        await widget.client.directUpload(ticket: ticket, localPath: path);
      }
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(RemoteFileEntry entry) async {
    final target = _join(entry.name);
    setState(() => _busy = true);
    try {
      final ticket = await widget.client.downloadTicket(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        fileName: target,
      );
      final bytes = await widget.client.directDownload(ticket);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: entry.name,
      );
      if (savePath != null) {
        await _writeBytes(savePath, bytes);
        if (mounted) {
          _showSnack('已下载到 $savePath');
        }
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _edit(RemoteFileEntry entry) async {
    if (entry.size > 2 * 1024 * 1024) {
      _showError('文件过大（>2MB），请下载后编辑');
      return;
    }
    final target = _join(entry.name);
    String content;
    try {
      content = await widget.client.readFile(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        target: target,
      );
    } catch (e) {
      _showError(e.toString());
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController(text: content);
    final saved = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('编辑 ${entry.name}'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await widget.client.writeFile(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        target: target,
        text: controller.text,
      );
      _showSnack('已保存');
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _rename(RemoteFileEntry entry) async {
    final name = await _promptText(
      '重命名 ${entry.name}',
      '新名称',
      initial: entry.name,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await widget.client.moveFiles(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        targets: [
          [_join(entry.name), _join(name.trim())],
        ],
      );
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _compress(RemoteFileEntry entry) async {
    final zipName = await _promptText(
      '压缩 ${entry.name}',
      '压缩包文件名',
      initial: '${p.basenameWithoutExtension(entry.name)}.zip',
    );
    if (zipName == null || !mounted) return;
    try {
      await widget.client.compress(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        source: _join(zipName.trim()),
        targets: [_join(entry.name)],
      );
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _unzip(RemoteFileEntry entry) async {
    try {
      await widget.client.unzip(
        daemonId: widget.daemonId ?? '',
        uuid: _uuid ?? '',
        source: _join(entry.name),
        dest: _path,
      );
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _delete(RemoteFileEntry entry) async {
    final action = await showAppDialog<_DeleteChoice>(
      context,
      (_) => _DeleteDialog(name: entry.name, isDir: entry.isDirectory),
    );
    if (action == null || !mounted) return;
    try {
      final daemonId = widget.daemonId ?? '';
      final uuid = _uuid ?? '';
      if (action == _DeleteChoice.trash) {
        await widget.client.trashFiles(
          daemonId: daemonId,
          uuid: uuid,
          targets: [_join(entry.name)],
        );
      } else {
        await widget.client.deleteFiles(
          daemonId: daemonId,
          uuid: uuid,
          targets: [_join(entry.name)],
        );
      }
      await _loadEntries();
    } catch (e) {
      _showError(e.toString());
    }
  }

  /// 文件点击后的操作菜单。
  void _showFileActions(RemoteFileEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
              ),
              title: Text(entry.name),
              subtitle: Text(
                entry.isDirectory
                    ? '文件夹'
                    : '${_formatBytes(entry.size)} · ${entry.time}',
              ),
            ),
            const Divider(height: 1),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _download(entry);
                },
              ),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _edit(entry);
                },
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(ctx).pop();
                _rename(entry);
              },
            ),
            if (entry.name.toLowerCase().endsWith('.zip'))
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('解压到当前目录'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _unzip(entry);
                },
              ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('压缩为 ZIP'),
              onTap: () {
                Navigator.of(ctx).pop();
                _compress(entry);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _delete(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 通用文本输入对话框。
  Future<String?> _promptText(String title, String label, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showAppDialog<String>(
      context,
      (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  /// 打开节点端回收站视图（irix-node §4.6；不支持时提示）。
  Future<void> _openTrash(ThemeData theme) async {
    final daemonId = widget.daemonId ?? '';
    final uuid = _uuid ?? '';
    if (uuid.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteTrashView(
          client: widget.client,
          daemonId: daemonId,
          uuid: uuid,
        ),
      ),
    );
    // 回收站可能改动实例目录（恢复 / 清空），返回后刷新当前目录。
    if (mounted) await _loadEntries();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 初始加载阶段（尚未确定浏览的实例）显示全屏进度；
    // 已锁定实例时交由 _buildBody 内的加载/错误分支处理。
    if (_loading && _uuid == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final body = Column(
      children: [
        _buildToolbar(theme),
        const Divider(height: 1),
        Expanded(child: _buildBody(theme)),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('文件管理')),
      body: body,
    );
  }

  /// 顶部工具栏：路径 + 操作。
  Widget _buildToolbar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _breadcrumbChip(theme, '/', _path == '/', -1),
                      for (
                        var i = 0;
                        i < _path.split('/').where((e) => e.isNotEmpty).length;
                        i++
                      )
                        _breadcrumbChip(
                          theme,
                          _path
                              .split('/')
                              .where((e) => e.isNotEmpty)
                              .toList()[i],
                          i ==
                              _path
                                      .split('/')
                                      .where((e) => e.isNotEmpty)
                                      .length -
                                  1,
                          i,
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _loading ? null : _loadEntries,
              ),
              IconButton(
                icon: const Icon(Icons.upload_file_outlined),
                tooltip: '上传',
                onPressed: (_uuid == null || _busy) ? null : _upload,
              ),
              PopupMenuButton<String>(
                tooltip: '新建',
                onSelected: (value) {
                  if (value == 'mkdir') _mkdir();
                  if (value == 'touch') _touch();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'mkdir', child: Text('新建文件夹')),
                  PopupMenuItem(value: 'touch', child: Text('新建文件')),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: '回收站',
                onPressed: (_uuid == null || _busy)
                    ? null
                    : () => _openTrash(theme),
              ),
            ],
          ),
          if (_uuid == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '无法确定实例，无法进行文件管理',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _breadcrumbChip(
    ThemeData theme,
    String label,
    bool isCurrent,
    int index,
  ) {
    return InkWell(
      onTap: isCurrent ? null : () => _navigateTo(index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isCurrent
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isCurrent
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.primary,
          ),
        ),
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
                onPressed: _loadEntries,
              ),
            ],
          ),
        ),
      );
    }
    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '目录为空\n点击右上角上传或新建',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            leading: Icon(
              entry.isDirectory ? Icons.folder : _fileIcon(entry.name),
              color: entry.isDirectory
                  ? Colors.amber
                  : theme.colorScheme.primary,
            ),
            title: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              entry.isDirectory
                  ? '文件夹'
                  : '${_formatBytes(entry.size)} · ${entry.time}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onTap: () => _openEntry(entry),
            trailing: Icon(Icons.more_horiz, color: theme.colorScheme.outline),
            onLongPress: () => _showFileActions(entry),
          ),
        );
      },
    );
  }

  static IconData _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.jar') return Icons.inventory_2_outlined;
    if (ext == '.zip' || ext == '.rar' || ext == '.7z') {
      return Icons.archive_outlined;
    }
    if (ext == '.json' || ext == '.yml' || ext == '.yaml' || ext == '.toml') {
      return Icons.data_object;
    }
    if (ext == '.txt' || ext == '.log' || ext == '.md') {
      return Icons.description_outlined;
    }
    if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.gif') {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}

/// 删除对话框选项。
enum _DeleteChoice { trash, permanent }

/// 删除确认对话框：优先「移入回收站」，并提供「永久删除」。
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.name, required this.isDir});

  final String name;
  final bool isDir;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('删除「$name」？'),
      content: isDir ? const Text('将递归处理整个文件夹及其内容。') : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.permanent),
          child: const Text('永久删除'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_DeleteChoice.trash),
          child: const Text('移入回收站'),
        ),
      ],
    );
  }
}

/// 节点端回收站视图（irix-node §4.6，见 trash.go）。
///
/// 列出实例回收站内容，支持单条 / 全部恢复与永久清空。节点不支持
/// （MCSM / 旧版本）时 list 接口抛错，页面显示提示。
class RemoteTrashView extends StatefulWidget {
  const RemoteTrashView({
    super.key,
    required this.client,
    required this.daemonId,
    required this.uuid,
  });

  final NodeApiClient client;
  final String daemonId;
  final String uuid;

  @override
  State<RemoteTrashView> createState() => _RemoteTrashViewState();
}

class _RemoteTrashViewState extends State<RemoteTrashView> {
  List<TrashItem> _items = [];
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
      final items = await widget.client.trashList(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _restore(List<String> ids) async {
    try {
      await widget.client.trashRestore(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        ids: ids,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _empty(List<String> ids) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: const Text('永久删除回收站内容？'),
        content: const Text('将不可恢复地从节点删除，节点不支持时请谨慎。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.trashEmpty(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        ids: ids,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: '清空全部',
              onPressed: () => _empty(const []),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        '（回收站为空）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(item.name),
                          subtitle: Text(
                            '原路径：${item.originalPath} · '
                            '${_formatSize(item.size)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.restore),
                                tooltip: '恢复',
                                onPressed: () => _restore([item.id]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever),
                                tooltip: '永久删除',
                                onPressed: () => _empty([item.id]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(1)} ${units[i]}';
  }
}
