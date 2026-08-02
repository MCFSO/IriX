// 回收站界面（统一视图）
// 默认汇总所有实例的回收站条目，按实例分组展示；
// 传入 rootPath 时仅展示该实例的回收站条目。
// 支持恢复、永久删除与清空。数据层使用 SQLite trash_items 表。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/trash_store.dart';

class TrashView extends StatefulWidget {
  /// 仅查看指定实例（根目录）的回收站；为 null 时查看全部实例。
  final String? rootPath;

  const TrashView({super.key, this.rootPath});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  final TrashStore _store = TrashStore();

  /// 按实例根目录分组的回收站条目。
  Map<String, List<TrashItem>>? _groups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final Map<String, List<TrashItem>> groups;
    final scope = widget.rootPath;
    if (scope != null) {
      groups = {scope: await _store.getTrashItems(scope)};
    } else {
      groups = await _store.getAllTrashItems();
    }
    for (final items in groups.values) {
      items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => _instanceLabel(a).compareTo(_instanceLabel(b)));
    final sorted = <String, List<TrashItem>>{};
    for (final key in sortedKeys) {
      sorted[key] = groups[key]!;
    }
    setState(() {
      _groups = sorted;
      _loading = false;
    });
  }

  /// 实例显示名：根目录的目录名。
  String _instanceLabel(String rootPath) {
    final name = p.basename(p.normalize(rootPath));
    return name.isEmpty ? rootPath : name;
  }

  Future<void> _restore(String rootPath, TrashItem item) async {
    try {
      await _store.restoreItem(rootPath, item.id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已恢复 "${p.basename(item.originalPath)}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
    }
  }

  Future<void> _permanentlyDelete(String rootPath, TrashItem item) async {
    try {
      await _store.permanentlyDelete(rootPath, item.id);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已永久删除 "${p.basename(item.originalPath)}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  Future<void> _purgeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text(
          widget.rootPath == null
              ? '确定要永久删除所有实例回收站中的文件吗？此操作不可撤销。'
              : '确定要永久删除该实例回收站中的所有文件吗？此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final scope = widget.rootPath;
      if (scope != null) {
        await _store.emptyTrash(scope);
      } else {
        await _store.emptyAllTrash();
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回收站已清空')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清空失败: $e')));
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final dayDiff = today.difference(day).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (dayDiff == 0) return '今天 $hh:$mm';
    if (dayDiff == 1) return '昨天 $hh:$mm';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count =
        _groups?.values.fold<int>(0, (sum, items) => sum + items.length) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (count > 0)
            TextButton.icon(
              onPressed: _purgeAll,
              icon: const Icon(Icons.delete_sweep, size: 20),
              label: const Text('清空回收站'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = _groups ?? const {};

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '回收站为空',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Icon(Icons.storage, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_instanceLabel(entry.key)} · ${entry.value.length} 项',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          for (final item in entry.value)
            _TrashEntryCard(
              item: item,
              onRestore: () => _restore(entry.key, item),
              onDelete: () => _permanentlyDelete(entry.key, item),
              formatDate: _formatDate,
            ),
        ],
      ],
    );
  }
}

class _TrashEntryCard extends StatelessWidget {
  const _TrashEntryCard({
    required this.item,
    required this.onRestore,
    required this.onDelete,
    required this.formatDate,
  });

  final TrashItem item;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final String Function(DateTime) formatDate;

  bool get _isDirectory =>
      FileSystemEntity.typeSync(item.trashPath) ==
      FileSystemEntityType.directory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              _isDirectory ? Icons.folder_outlined : Icons.insert_drive_file,
              color: _isDirectory ? Colors.amber.shade700 : Colors.red.shade400,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basename(item.originalPath),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.originalPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '删除于 ${formatDate(item.deletedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: theme.colorScheme.outline),
              onSelected: (value) {
                switch (value) {
                  case 'restore':
                    onRestore();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text('恢复'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('永久删除'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
