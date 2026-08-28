import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/trash_store.dart';
import '../utils/apple_widgets.dart';
import 'archive_viewer_screen.dart';
import 'nbt_editor_screen.dart';
import 'text_editor_dialog.dart';
import 'trash_view.dart';

class FileManagerScreen extends StatefulWidget {
  final String rootPath;
  const FileManagerScreen({required this.rootPath, super.key});

  const FileManagerScreen.withTaskManager({
    required this.rootPath,
    required dynamic taskManager,
    super.key,
  });

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

enum _SortColumn { name, size, date }

class _FileManagerScreenState extends State<FileManagerScreen> {
  String _currentPath = '';
  ({String path, bool isCut})? _clipboard;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};
  List<FileSystemEntity> _entries = [];
  _SortColumn _sortBy = _SortColumn.name;
  bool _sortAsc = true;
  final TrashStore _trashStore = TrashStore();

  String get _rootPath => widget.rootPath;

  @override
  void initState() {
    super.initState();
    _currentPath = _rootPath;
    _refresh();
  }

  @override
  void didUpdateWidget(FileManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _currentPath = widget.rootPath;
      _refresh();
    }
  }

  void _refresh() {
    final dir = Directory(_currentPath);
    if (!dir.existsSync()) {
      setState(() => _entries = []);
      return;
    }
    final list = dir.listSync(recursive: false);

    list.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;

      int cmp;
      switch (_sortBy) {
        case _SortColumn.name:
          cmp = p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase());
          break;
        case _SortColumn.size:
          final aSize = a is File ? a.lengthSync() : 0;
          final bSize = b is File ? b.lengthSync() : 0;
          cmp = aSize.compareTo(bSize);
          break;
        case _SortColumn.date:
          cmp = a.statSync().modified.compareTo(b.statSync().modified);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });

    setState(() => _entries = list);
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
      _selectionMode = false;
      _selectedPaths.clear();
    });
    _refresh();
  }

  void _navigateUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) _navigateTo(parent);
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _onItemLongPress(FileSystemEntity entity) {
    if (!_selectionMode) {
      setState(() => _selectionMode = true);
    }
    _toggleSelection(entity.path);
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _onSortChanged(_SortColumn column) {
    setState(() {
      if (_sortBy == column) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = column;
        _sortAsc = true;
      }
    });
    _refresh();
  }

  Future<void> _handleDelete(Iterable<String> paths) async {
    final pathList = paths.toList();
    if (pathList.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 ${pathList.length} 个项目？\n文件将移至回收站，7天后自动删除'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    int count = 0;
    for (final filePath in pathList) {
      try {
        final entity =
            FileSystemEntity.typeSync(filePath) ==
                FileSystemEntityType.directory
            ? Directory(filePath)
            : File(filePath);
        await _trashStore.moveToTrash(_rootPath, entity);
        count++;
      } catch (_) {}
    }

    if (!mounted) return;
    _exitSelectionMode();
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 $count 个文件')));
  }

  Future<void> _handleRename(String oldPath) async {
    final name = p.basename(oldPath);
    final controller = TextEditingController(text: name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == name) return;

    try {
      final newPath = p.join(p.dirname(oldPath), newName);
      final isDir =
          FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory;
      await (isDir ? Directory(oldPath) : File(oldPath)).rename(newPath);
      if (_selectedPaths.contains(oldPath)) {
        _selectedPaths.remove(oldPath);
        _selectedPaths.add(newPath);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
    }
    if (!mounted) return;
    _refresh();
  }

  Future<void> _handleNewFolder() async {
    final controller = TextEditingController(text: '新文件夹');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    try {
      await Directory(p.join(_currentPath, name)).create();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建文件夹失败: $e')));
    }
    if (!mounted) return;
    _refresh();
  }

  Future<void> _handleNewFile() async {
    final controller = TextEditingController(text: '新文件.txt');
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final filePath = p.join(_currentPath, name);
      await File(filePath).create();
      if (!mounted) return;
      _refresh();
      showTextEditor(context, filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建文件失败: $e')));
    }
  }

  void _handleCopy(FileSystemEntity entity) {
    setState(() => _clipboard = (path: entity.path, isCut: false));
  }

  void _handleCut(FileSystemEntity entity) {
    setState(() => _clipboard = (path: entity.path, isCut: true));
  }

  Future<void> _handlePaste() async {
    if (_clipboard == null) return;
    final src = _clipboard!.path;
    final srcName = p.basename(src);
    final dest = p.join(_currentPath, srcName);

    if (src == dest) return;

    try {
      if (_clipboard!.isCut) {
        FileSystemEntity.typeSync(src) == FileSystemEntityType.directory
            ? Directory(src).rename(dest)
            : File(src).rename(dest);
      } else {
        final srcIsDir =
            FileSystemEntity.typeSync(src) == FileSystemEntityType.directory;
        if (srcIsDir) {
          await _copyDirectory(Directory(src), Directory(dest));
        } else {
          await File(src).copy(dest);
        }
      }
      setState(() {
        if (_clipboard!.isCut) _clipboard = null;
      });
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_clipboard == null ? '已移动' : '已复制')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    final entities = source.listSync(recursive: false);
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(destination.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, name));
      }
    }
  }

  void _openTextEditor(String filePath) {
    showTextEditor(context, filePath);
  }

  void _showProperties(FileSystemEntity entity) {
    final stat = entity.statSync();
    final isDir = entity is Directory;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.basename(entity.path)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propRow('类型', isDir ? '文件夹' : '文件'),
            _propRow('路径', entity.path),
            if (!isDir) _propRow('大小', _formatSize(stat.size)),
            _propRow('修改时间', _formatDate(stat.modified)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  IconData _fileIcon(FileSystemEntity entity) {
    if (entity is Directory) return Icons.folder;
    final ext = p.extension(entity.path).toLowerCase();
    switch (ext) {
      case '.jar':
        return Icons.emoji_food_beverage;
      case '.json':
      case '.json5':
        return Icons.data_object;
      case '.yml':
      case '.yaml':
      case '.ini':
        return Icons.settings;
      case '.properties':
      case '.toml':
      case '.conf':
      case '.cfg':
        return Icons.tune;
      case '.txt':
      case '.log':
      case '.md':
      case '.csv':
        return Icons.description;
      case '.zip':
      case '.gz':
      case '.tar':
      case '.rar':
      case '.7z':
        return Icons.archive;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.bmp':
      case '.ico':
      case '.webp':
        return Icons.image;
      case '.lua':
      case '.js':
      case '.ts':
      case '.py':
      case '.java':
      case '.dart':
      case '.sh':
      case '.bash':
      case '.xml':
      case '.html':
      case '.css':
      case '.sql':
        return Icons.code;
      case '.lock':
        return Icons.lock;
      case '.bat':
      case '.cmd':
      case '.ps1':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 判断是否为二进制文件（不可用文本编辑器打开）。
  bool _isBinaryFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.bmp',
      '.ico',
      '.webp',
      '.db',
      '.sqlite',
      '.dat',
      '.bin',
      '.class',
      '.nbt',
      '.mca',
      '.mcr',
      '.gz',
      '.tar',
      '.rar',
      '.7z',
      '.mp3',
      '.wav',
      '.ogg',
      '.mp4',
      '.avi',
      '.dll',
      '.so',
      '.dylib',
      '.exe',
    }.contains(ext);
  }

  List<String> _pathSegments() {
    final rel = p.relative(_currentPath, from: _rootPath);
    if (rel == '.') return [p.basename(_rootPath)];
    final rootName = p.basename(_rootPath);
    return [rootName, ...rel.replaceAll('\\', '/').split('/')];
  }

  Future<void> _showContextMenu(
    Offset position, {
    FileSystemEntity? target,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final overlayRect = Rect.fromPoints(
      overlay.localToGlobal(Offset.zero),
      overlay.localToGlobal(overlay.size.bottomRight(Offset.zero)),
    );

    final items = <PopupMenuEntry<String>>[];
    if (target != null) {
      final ext = p.extension(target.path).toLowerCase();
      items.addAll([
        if (ext == '.jar' || ext == '.zip')
          PopupMenuItem(
            value: 'open',
            child: _menuItem(Icons.folder_open, '打开'),
          ),
        if (ext == '.nbt')
          PopupMenuItem(
            value: 'nbtEdit',
            child: _menuItem(Icons.edit_note, '用 NBT 编辑器打开'),
          ),
        PopupMenuItem(value: 'copy', child: _menuItem(Icons.copy, '复制')),
        PopupMenuItem(value: 'cut', child: _menuItem(Icons.cut, '剪切')),
        PopupMenuItem(
          value: 'delete',
          child: _menuItem(Icons.delete, '删除', color: Colors.red),
        ),
        PopupMenuItem(value: 'rename', child: _menuItem(Icons.edit, '重命名')),
        if (target is! Directory && !_isBinaryFile(target.path))
          PopupMenuItem(
            value: 'editConfig',
            child: _menuItem(Icons.text_snippet, '编辑'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'properties',
          child: _menuItem(Icons.info_outline, '属性'),
        ),
      ]);
    } else {
      items.addAll([
        PopupMenuItem(
          value: 'paste',
          enabled: _clipboard != null,
          child: _menuItem(Icons.paste, '粘贴'),
        ),
        PopupMenuItem(
          value: 'newFolder',
          child: _menuItem(Icons.create_new_folder, '新建文件夹'),
        ),
        PopupMenuItem(
          value: 'newFile',
          child: _menuItem(Icons.note_add, '新建文件'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'refresh', child: _menuItem(Icons.refresh, '刷新')),
      ]);
    }

    final navigator = Navigator.of(context);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        overlayRect,
      ),
      items: items,
    );
    if (value == null || !mounted) return;
    if (target != null) {
      switch (value) {
        case 'open':
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ArchiveViewerScreen(filePath: target.path),
            ),
          );
        case 'copy':
          _handleCopy(target);
        case 'cut':
          _handleCut(target);
        case 'delete':
          _handleDelete([target.path]);
        case 'rename':
          _handleRename(target.path);
        case 'editConfig':
          _openTextEditor(target.path);
        case 'nbtEdit':
          try {
            final bytes = await File(target.path).readAsBytes();
            navigator.push(
              MaterialPageRoute(
                builder: (_) => NbtEditorScreen(
                  initialBytes: bytes,
                  initialFileName: p.basename(target.path),
                ),
              ),
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('打开 NBT 失败：$e')),
              );
            }
          }
        case 'properties':
          _showProperties(target);
      }
    } else {
      switch (value) {
        case 'paste':
          _handlePaste();
        case 'newFolder':
          _handleNewFolder();
        case 'newFile':
          _handleNewFile();
        case 'refresh':
          _refresh();
      }
    }
  }

  Widget _menuItem(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildBreadcrumbBar(),
        _buildToolbar(),
        const Divider(height: 1),
        Expanded(child: _buildSplitView()),
        const Divider(height: 1),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildBreadcrumbBar() {
    final segments = _pathSegments();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: '上级目录',
              onPressed: _currentPath != _rootPath ? _navigateUp : null,
              visualDensity: VisualDensity.compact,
            ),
            ...List.generate(segments.length, (i) {
              final isLast = i == segments.length - 1;
              final path = _buildPath(i);
              return Row(
                children: [
                  Text(
                    ' / ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  GestureDetector(
                    onTap: isLast ? null : () => _navigateTo(path),
                    child: Text(
                      segments[i],
                      style: TextStyle(
                        fontWeight: isLast
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isLast
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: isLast ? null : TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  String _buildPath(int index) {
    final segments = _pathSegments();
    if (index == 0) return _rootPath;
    final subPath = segments.sublist(1, index + 1).join('/');
    return p.join(_rootPath, subPath);
  }

  Widget _buildToolbar() {
    final selectedCount = _selectedPaths.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: _exitSelectionMode,
            ),
            Text('已选择 $selectedCount 项'),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制',
              onPressed: selectedCount == 1
                  ? () {
                      final path = _selectedPaths.first;
                      final entity =
                          FileSystemEntity.typeSync(path) ==
                              FileSystemEntityType.directory
                          ? Directory(path)
                          : File(path);
                      _handleCopy(entity);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.cut),
              tooltip: '剪切',
              onPressed: selectedCount == 1
                  ? () {
                      final path = _selectedPaths.first;
                      final entity =
                          FileSystemEntity.typeSync(path) ==
                              FileSystemEntityType.directory
                          ? Directory(path)
                          : File(path);
                      _handleCut(entity);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: '删除',
              onPressed: selectedCount > 0
                  ? () => _handleDelete(_selectedPaths)
                  : null,
            ),
            const SizedBox(width: 8),
            const VerticalDivider(),
          ],
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: '粘贴',
            onPressed: _clipboard != null ? _handlePaste : null,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: '新建文件夹',
            onPressed: _handleNewFolder,
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            tooltip: '新建文件',
            onPressed: _handleNewFile,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '属性',
            onPressed: selectedCount == 1
                ? () {
                    final path = _selectedPaths.first;
                    final entity =
                        FileSystemEntity.typeSync(path) ==
                            FileSystemEntityType.directory
                        ? Directory(path)
                        : File(path);
                    _showProperties(entity);
                  }
                : null,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '回收站',
            onPressed: () =>
                pushPage(context, (_) => TrashView(rootPath: _rootPath)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildSplitView() {
    return Row(
      children: [
        SizedBox(width: 200, child: _buildDirectoryTree()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildFileList()),
      ],
    );
  }

  Widget _buildDirectoryTree() {
    return _DirectoryTree(
      rootPath: _rootPath,
      currentPath: _currentPath,
      onNavigate: _navigateTo,
    );
  }

  Widget _buildFileList() {
    return Column(
      children: [
        _buildColumnHeaders(),
        Expanded(
          child: GestureDetector(
            onSecondaryTapUp: (details) {
              _showContextMenu(details.globalPosition);
            },
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: _entries.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 64),
                        Center(child: Text('此文件夹为空')),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) =>
                          _buildFileRow(_entries[index]),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeaders() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(flex: 3, child: _sortHeader('名称', _SortColumn.name)),
          Expanded(flex: 1, child: _sortHeader('大小', _SortColumn.size)),
          Expanded(flex: 2, child: _sortHeader('修改时间', _SortColumn.date)),
        ],
      ),
    );
  }

  Widget _sortHeader(String label, _SortColumn column) {
    final isActive = _sortBy == column;
    return GestureDetector(
      onTap: () => _onSortChanged(column),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          if (isActive)
            Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
            ),
        ],
      ),
    );
  }

  Widget _buildFileRow(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final stat = entity.statSync();
    final sizeStr = isDir ? '' : _formatSize(stat.size);
    final timeStr = _formatRelativeTime(stat.modified);
    final isSelected = _selectedPaths.contains(entity.path);
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(details.globalPosition, target: entity);
      },
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleSelection(entity.path);
          } else if (isDir) {
            _navigateTo(entity.path);
          } else {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.jar' || ext == '.zip') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArchiveViewerScreen(filePath: entity.path),
                ),
              );
            } else if (!_isBinaryFile(entity.path)) {
              _openTextEditor(entity.path);
            }
          }
        },
        onLongPress: () => _onItemLongPress(entity),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              if (_selectionMode)
                GestureDetector(
                  onTap: () => _toggleSelection(entity.path),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    _fileIcon(entity),
                    size: 20,
                    color: isDir ? Colors.amber[400] : Colors.grey[400],
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  sizeStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final theme = Theme.of(context);
    final clipText = _clipboard != null
        ? '${_clipboard!.isCut ? "已剪切" : "已复制"}: ${p.basename(_clipboard!.path)}'
        : '剪贴板为空';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Text('${_entries.length} 个项目', style: const TextStyle(fontSize: 12)),
          if (_selectionMode) ...[
            const SizedBox(width: 16),
            Text(
              '已选择 ${_selectedPaths.length} 项',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
          ],
          const Spacer(),
          Text(clipText, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _DirectoryTree extends StatefulWidget {
  final String rootPath;
  final String currentPath;
  final ValueChanged<String> onNavigate;

  const _DirectoryTree({
    required this.rootPath,
    required this.currentPath,
    required this.onNavigate,
  });

  @override
  State<_DirectoryTree> createState() => _DirectoryTreeState();
}

class _DirectoryTreeState extends State<_DirectoryTree> {
  final Set<String> _expandedPaths = {};

  @override
  void initState() {
    super.initState();
    _expandToPath(widget.currentPath);
  }

  @override
  void didUpdateWidget(_DirectoryTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPath != widget.currentPath) {
      _expandToPath(widget.currentPath);
    }
  }

  void _expandToPath(String path) {
    var current = path;
    while (current != widget.rootPath && current.isNotEmpty) {
      _expandedPaths.add(current);
      current = p.dirname(current);
    }
    _expandedPaths.add(widget.rootPath);
    setState(() {});
  }

  List<FileSystemEntity> _subDirectories(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return [];
      return dir.listSync(recursive: false).whereType<Directory>().toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [_buildTreeNode(widget.rootPath, 0)],
    );
  }

  Widget _buildTreeNode(String path, int depth) {
    final isExpanded = _expandedPaths.contains(path);
    final isCurrent = path == widget.currentPath;
    final theme = Theme.of(context);
    final children = _subDirectories(path);
    final hasChildren = children.isNotEmpty;
    final name = p.basename(path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            widget.onNavigate(path);
            setState(() {
              if (_expandedPaths.contains(path)) {
                _expandedPaths.remove(path);
              } else {
                _expandedPaths.add(path);
              }
            });
          },
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + depth * 16.0,
              right: 8,
              top: 4,
              bottom: 4,
            ),
            color: isCurrent
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                : null,
            child: Row(
              children: [
                if (hasChildren)
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: theme.colorScheme.outline,
                  )
                else
                  const SizedBox(width: 16),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: Colors.amber[400],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((child) => _buildTreeNode(child.path, depth + 1)),
      ],
    );
  }
}
