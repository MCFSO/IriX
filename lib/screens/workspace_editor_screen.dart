import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/font_settings.dart';
import '../services/trash_store.dart';
import '../services/workspace_file_codec.dart';
import '../utils/apple_widgets.dart';
import '../utils/code_highlight.dart';

class WorkspaceEditorScreen extends StatefulWidget {
  const WorkspaceEditorScreen({
    super.key,
    required this.rootPath,
    this.initialFilePath,
  });

  final String rootPath;
  final String? initialFilePath;

  @override
  State<WorkspaceEditorScreen> createState() => _WorkspaceEditorScreenState();
}

class _EditorDocument {
  _EditorDocument(this.path, this.content, this.modified, this.size)
    : controller = HighlightTextEditingController(
        text: content.text,
        fileName: content.isHex ? null : path,
      ),
      savedText = content.text;

  String path;
  final WorkspaceFileContent content;
  final HighlightTextEditingController controller;
  String savedText;
  DateTime modified;
  int size;

  bool get dirty => controller.text != savedText;
  void dispose() => controller.dispose();
}

class _WorkspaceEditorScreenState extends State<WorkspaceEditorScreen> {
  final List<_EditorDocument> _documents = [];
  final Set<String> _expanded = {};
  final ScrollController _gutterScroll = ScrollController();
  _EditorDocument? _active;
  late String _selectedFolder;
  bool _busy = false;
  bool _showExplorer = true;
  int _refreshKey = 0;

  String get _root => p.normalize(p.absolute(widget.rootPath));

  @override
  void initState() {
    super.initState();
    _selectedFolder = _root;
    _expanded.add(_root);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.initialFilePath;
      if (initial != null && mounted) _openFile(initial);
    });
  }

  @override
  void dispose() {
    for (final doc in _documents) {
      doc.dispose();
    }
    _gutterScroll.dispose();
    super.dispose();
  }

  bool _withinRoot(String path) {
    final relative = p.relative(p.normalize(p.absolute(path)), from: _root);
    return relative == '.' ||
        (!p.isAbsolute(relative) &&
            relative != '..' &&
            !relative.startsWith('..${p.separator}'));
  }

  Future<void> _openFile(String path) async {
    if (!_withinRoot(path)) return;
    if (_busy) return;
    final open = _documents
        .where((doc) => p.equals(doc.path, path))
        .firstOrNull;
    if (open != null) {
      setState(() => _active = open);
      return;
    }
    setState(() => _busy = true);
    try {
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FileSystemException('不支持通过符号链接编辑实例目录外的文件');
      }
      final file = File(path);
      final bytes = await file.readAsBytes();
      final stat = await file.stat();
      final doc = _EditorDocument(
        path,
        WorkspaceFileContent.decode(bytes),
        stat.modified,
        stat.size,
      );
      doc.controller.addListener(() {
        if (mounted && _documents.contains(doc)) setState(() {});
      });
      if (!mounted) {
        doc.dispose();
        return;
      }
      setState(() {
        _documents.add(doc);
        _active = doc;
        _selectedFolder = p.dirname(path);
        _expandParents(path);
        if (MediaQuery.sizeOf(context).width < 700) _showExplorer = false;
      });
    } catch (e) {
      _error('无法打开文件：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _expandParents(String path) {
    var dir = p.dirname(path);
    while (_withinRoot(dir)) {
      _expanded.add(dir);
      if (p.equals(dir, _root)) break;
      dir = p.dirname(dir);
    }
  }

  Future<bool> _confirmDiscard(_EditorDocument doc) async {
    if (!doc.dirty) return true;
    return await showAppDialog<bool>(
          context,
          (_) => AlertDialog(
            title: Text('关闭 ${p.basename(doc.path)}？'),
            content: const Text('此文件有未保存的修改。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _close(_EditorDocument doc) async {
    if (!await _confirmDiscard(doc) || !mounted) return;
    setState(() {
      final index = _documents.indexOf(doc);
      _documents.remove(doc);
      if (_active == doc) {
        _active = _documents.isEmpty
            ? null
            : _documents[index.clamp(0, _documents.length - 1)];
      }
    });
    doc.dispose();
  }

  Future<bool> _confirmExit() async {
    for (final doc in List<_EditorDocument>.of(_documents)) {
      if (!await _confirmDiscard(doc)) return false;
      if (!mounted) return false;
    }
    return true;
  }

  Future<void> _save(_EditorDocument doc) async {
    if (_busy || !doc.dirty) return;
    final textToSave = doc.controller.text;
    List<int> bytes;
    try {
      bytes = doc.content.encode(textToSave);
    } catch (e) {
      _error('内容格式有误：$e');
      return;
    }
    setState(() => _busy = true);
    try {
      final file = File(doc.path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw const FileSystemException('文件已不存在');
      }
      if (stat.modified != doc.modified || stat.size != doc.size) {
        if (!mounted) return;
        final overwrite = await showAppDialog<bool>(
          context,
          (_) => AlertDialog(
            title: const Text('文件已在别处修改'),
            content: Text('${p.basename(doc.path)} 的磁盘内容已变化。仍要用当前编辑内容覆盖吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('覆盖保存'),
              ),
            ],
          ),
        );
        if (overwrite != true) return;
      }
      await file.writeAsBytes(bytes, flush: true);
      final updated = await file.stat();
      if (!mounted) return;
      setState(() {
        doc.savedText = textToSave;
        doc.modified = updated.modified;
        doc.size = updated.size;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存 ${p.basename(doc.path)}')));
    } catch (e) {
      _error('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String title, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    try {
      final name = await showAppDialog<String>(
        context,
        (_) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (name == null) return null;
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          p.basename(name) != name ||
          name.contains('/') ||
          name.contains('\\')) {
        _error('请输入不含路径分隔符的有效名称');
        return null;
      }
      return name;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _create({required bool folder}) async {
    final name = await _askName(folder ? '新建文件夹' : '新建文件');
    if (name == null || !mounted) return;
    final path = p.join(_selectedFolder, name);
    try {
      if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
        throw const FileSystemException('名称已存在');
      }
      if (folder) {
        await Directory(path).create();
      } else {
        await File(path).create();
      }
      if (!mounted) return;
      setState(() {
        _expanded.add(_selectedFolder);
        _refreshKey++;
      });
      if (!folder) await _openFile(path);
    } catch (e) {
      _error('创建失败：$e');
    }
  }

  Future<void> _rename(FileSystemEntity entity) async {
    if (p.equals(entity.path, _root)) return;
    final name = await _askName('重命名', initial: p.basename(entity.path));
    if (name == null || !mounted || name == p.basename(entity.path)) return;
    final target = p.join(p.dirname(entity.path), name);
    try {
      if (await FileSystemEntity.type(target) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('名称已存在');
      }
      await entity.rename(target);
      if (!mounted) return;
      setState(() {
        for (final doc in _documents) {
          if (p.equals(doc.path, entity.path) ||
              p.isWithin(entity.path, doc.path)) {
            doc.path = p.join(target, p.relative(doc.path, from: entity.path));
            doc.controller.fileName = doc.content.isHex ? null : doc.path;
          }
        }
        if (p.equals(_selectedFolder, entity.path) ||
            p.isWithin(entity.path, _selectedFolder)) {
          _selectedFolder = p.join(
            target,
            p.relative(_selectedFolder, from: entity.path),
          );
        }
        _expanded.remove(entity.path);
        if (entity is Directory) _expanded.add(target);
        _refreshKey++;
      });
    } catch (e) {
      _error('重命名失败：$e');
    }
  }

  Future<void> _delete(FileSystemEntity entity) async {
    if (p.equals(entity.path, _root)) return;
    final affected = _documents
        .where(
          (doc) =>
              p.equals(doc.path, entity.path) ||
              p.isWithin(entity.path, doc.path),
        )
        .toList();
    if (affected.any((doc) => doc.dirty)) {
      _error('请先保存或关闭此目录中未保存的文件');
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除 ${p.basename(entity.path)}？'),
        content: const Text('文件会移到此实例的回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await TrashStore().moveToTrash(_root, entity);
      if (!mounted) return;
      setState(() {
        for (final doc in affected) {
          _documents.remove(doc);
          doc.dispose();
        }
        if (!_documents.contains(_active)) _active = _documents.lastOrNull;
        if (p.equals(_selectedFolder, entity.path) ||
            p.isWithin(entity.path, _selectedFolder)) {
          _selectedFolder = p.dirname(entity.path);
        }
        _refreshKey++;
      });
    } catch (e) {
      _error('删除失败：$e');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<FileSystemEntity> _children(String path) {
    try {
      final items = Directory(path)
          .listSync(followLinks: false)
          .where((entity) => entity is File || entity is Directory)
          .where(
            (entity) =>
                !p.equals(path, _root) ||
                p.basename(entity.path) != 'xmc_trash',
          )
          .toList();
      items.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      return items;
    } catch (_) {
      return [];
    }
  }

  Widget _treeNode(String path, int depth, {bool root = false}) {
    final expanded = _expanded.contains(path);
    final isFolder = root || Directory(path).existsSync();
    final selected = isFolder
        ? p.equals(path, _selectedFolder)
        : p.equals(path, _active?.path ?? '');
    final name = root ? p.basename(_root) : p.basename(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (isFolder) {
              setState(() {
                _selectedFolder = path;
                if (!_expanded.add(path)) _expanded.remove(path);
              });
            } else {
              _openFile(path);
            }
          },
          onSecondaryTapUp: root
              ? null
              : (details) => _fileMenu(details.globalPosition, path, isFolder),
          child: Container(
            height: 29,
            padding: EdgeInsets.only(left: 8 + depth * 14, right: 8),
            color: selected ? const Color(0xFF27443F) : null,
            child: Row(
              children: [
                Icon(
                  isFolder
                      ? (expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right)
                      : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isFolder
                      ? const Color(0xFFD5AA69)
                      : const Color(0xFF8BA5A0),
                ),
                const SizedBox(width: 5),
                if (isFolder) ...[
                  const Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: Color(0xFFD5AA69),
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (!isFolder &&
                    _documents.any(
                      (doc) => p.equals(doc.path, path) && doc.dirty,
                    ))
                  const Icon(Icons.circle, size: 7, color: Color(0xFFD5AA69)),
              ],
            ),
          ),
        ),
        if (isFolder && expanded)
          for (final child in _children(path)) _treeNode(child.path, depth + 1),
      ],
    );
  }

  Future<void> _fileMenu(Offset position, String path, bool folder) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (!folder) const PopupMenuItem(value: 'open', child: Text('打开')),
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'delete', child: Text('移到回收站')),
      ],
    );
    if (!mounted || choice == null) return;
    final entity = folder ? Directory(path) : File(path);
    switch (choice) {
      case 'open':
        await _openFile(path);
      case 'rename':
        await _rename(entity);
      case 'delete':
        await _delete(entity);
    }
  }

  Widget _editor(_EditorDocument doc) {
    final text = doc.controller.text;
    final count = '\n'.allMatches(text).length + 1;
    const lineHeight = 20.0;
    final font = FontSettings.instance.terminalFamily;
    return Column(
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: const Color(0xFF1C2A2A),
          child: Text(
            p.relative(doc.path, from: _root),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFFACBCB8)),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Container(
                width: 52,
                color: const Color(0xFF162222),
                child: ListView.builder(
                  controller: _gutterScroll,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12),
                  itemCount: count,
                  itemExtent: lineHeight,
                  itemBuilder: (_, index) => Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: font,
                          fontSize: 12,
                          color: const Color(0xFF69817D),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (_gutterScroll.hasClients) {
                      final target = notification.metrics.pixels.clamp(
                        0.0,
                        _gutterScroll.position.maxScrollExtent,
                      );
                      if (_gutterScroll.offset != target) {
                        _gutterScroll.jumpTo(target);
                      }
                    }
                    return false;
                  },
                  child: TextField(
                    key: ValueKey(doc.path),
                    controller: doc.controller,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: font,
                      fontSize: 13,
                      height: lineHeight / 13,
                      color: const Color(0xFFE0EAE5),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _active;
    final compact = MediaQuery.sizeOf(context).width < 700;
    return PopScope(
      canPop: !_documents.any((item) => item.dirty),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) Navigator.pop(context);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (_active != null) _save(_active!);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (_active != null) _save(_active!);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF142020),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1B2A29),
              title: Text(
                compact ? '编辑器' : '文件编辑器',
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                if (compact) ...[
                  IconButton(
                    onPressed: () =>
                        setState(() => _showExplorer = !_showExplorer),
                    tooltip: _showExplorer ? '显示编辑器' : '显示资源管理器',
                    icon: Icon(
                      _showExplorer ? Icons.code : Icons.folder_outlined,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '文件操作',
                    enabled: !_busy,
                    onSelected: (value) {
                      switch (value) {
                        case 'file':
                          _create(folder: false);
                        case 'folder':
                          _create(folder: true);
                        case 'refresh':
                          setState(() => _refreshKey++);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'file', child: Text('新建文件')),
                      PopupMenuItem(value: 'folder', child: Text('新建文件夹')),
                      PopupMenuItem(value: 'refresh', child: Text('刷新')),
                    ],
                  ),
                  IconButton(
                    onPressed: doc != null && doc.dirty && !_busy
                        ? () => _save(doc)
                        : null,
                    tooltip: '保存',
                    icon: const Icon(Icons.save_outlined),
                  ),
                ] else ...[
                  IconButton(
                    onPressed: _busy ? null : () => _create(folder: false),
                    tooltip: '新建文件',
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => _create(folder: true),
                    tooltip: '新建文件夹',
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _refreshKey++),
                    tooltip: '刷新文件树',
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: doc != null && doc.dirty && !_busy
                        ? () => _save(doc)
                        : null,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            body: Row(
              children: [
                if (!compact || _showExplorer)
                  Container(
                    width: compact ? MediaQuery.sizeOf(context).width : 240,
                    color: const Color(0xFF192827),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 13, 8, 10),
                          child: Text(
                            '资源管理器',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9DAEAA),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            key: ValueKey(_refreshKey),
                            children: [_treeNode(_root, 0, root: true)],
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            p.basename(_selectedFolder),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8BA5A0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!compact) const VerticalDivider(width: 1),
                if (!compact || !_showExplorer)
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 38,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final item in _documents)
                                InkWell(
                                  onTap: () => setState(() => _active = item),
                                  child: Container(
                                    width: 168,
                                    padding: const EdgeInsets.only(left: 12),
                                    decoration: BoxDecoration(
                                      color: item == doc
                                          ? const Color(0xFF203332)
                                          : const Color(0xFF192827),
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.07,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.basename(item.path),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        if (item.dirty)
                                          const Icon(
                                            Icons.circle,
                                            size: 7,
                                            color: Color(0xFFD5AA69),
                                          ),
                                        IconButton(
                                          onPressed: () => _close(item),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 15,
                                          ),
                                          tooltip: '关闭',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 30,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: doc == null
                              ? const Center(
                                  child: Text(
                                    '从左侧选择文件开始编辑',
                                    style: TextStyle(color: Color(0xFF9DAEAA)),
                                  ),
                                )
                              : _editor(doc),
                        ),
                        Container(
                          height: 26,
                          color: const Color(0xFF24534C),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  doc == null ? _root : doc.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              if (_busy)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              if (doc != null)
                                Text(
                                  doc.content.isHex
                                      ? 'HEX · 每两位一个字节'
                                      : doc.content.encoding.name.toUpperCase(),
                                  style: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
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
