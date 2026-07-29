// 回收站界面
// 展示已删除文件的列表，支持恢复和永久删除操作。
// 数据层使用本地 xmc_trash/trash_meta.json 持久化。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class TrashEntry {
  final String id;
  final String originalPath;
  final String fileName;
  final int size;
  final DateTime deletedAt;

  const TrashEntry({
    required this.id,
    required this.originalPath,
    required this.fileName,
    required this.size,
    required this.deletedAt,
  });

  factory TrashEntry.create({
    required String originalPath,
    required String fileName,
    required int size,
  }) {
    return TrashEntry(
      id: const Uuid().v4(),
      originalPath: originalPath,
      fileName: fileName,
      size: size,
      deletedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalPath': originalPath,
        'fileName': fileName,
        'size': size,
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
        id: json['id'] as String,
        originalPath: json['originalPath'] as String,
        fileName: json['fileName'] as String,
        size: json['size'] as int,
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );

  int get remainingDays {
    final deadline = deletedAt.add(const Duration(days: 7));
    final diff = deadline.difference(DateTime.now());
    return max(0, diff.inDays);
  }

  bool get isExpired => remainingDays <= 0;
}

class TrashStore {
  final String rootPath;

  const TrashStore({required this.rootPath});

  String get trashDir => p.join(rootPath, 'xmc_trash');
  String get metaPath => p.join(trashDir, 'trash_meta.json');

  Future<List<TrashEntry>> listEntries() async {
    try {
      final file = File(metaPath);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => TrashEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TrashStore listEntries error: $e');
      return [];
    }
  }

  Future<void> _saveEntries(List<TrashEntry> entries) async {
    final dir = Directory(trashDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await File(metaPath).writeAsString(encoded);
  }

  Future<void> addEntry(TrashEntry entry) async {
    final entries = await listEntries();
    entries.add(entry);
    await _saveEntries(entries);
  }

  Future<void> removeEntry(String id) async {
    final entries = await listEntries();
    entries.removeWhere((e) => e.id == id);
    await _saveEntries(entries);
  }

  Future<void> purgeAll() async {
    await _saveEntries([]);
  }

  Future<void> autoClean() async {
    final entries = await listEntries();
    entries.removeWhere((e) => e.isExpired);
    await _saveEntries(entries);
  }
}

class TrashView extends StatefulWidget {
  final String rootPath;

  const TrashView({super.key, required this.rootPath});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  late final TrashStore _store;
  List<TrashEntry>? _entries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _store = TrashStore(rootPath: widget.rootPath);
    _refresh();
  }

  Future<void> _refresh() async {
    await _store.autoClean();
    final entries = await _store.listEntries();
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _restore(TrashEntry entry) async {
    try {
      final trashFilePath = p.join(_store.trashDir, entry.fileName);
      final trashFile = File(trashFilePath);
      if (await trashFile.exists()) {
        final originalDir = Directory(p.dirname(entry.originalPath));
        if (!await originalDir.exists()) {
          await originalDir.create(recursive: true);
        }
        await trashFile.copy(entry.originalPath);
        await trashFile.delete();
      }
      await _store.removeEntry(entry.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已恢复 "${entry.fileName}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: $e')),
        );
      }
    }
  }

  Future<void> _permanentlyDelete(TrashEntry entry) async {
    try {
      final trashFilePath = p.join(_store.trashDir, entry.fileName);
      final trashFile = File(trashFilePath);
      if (await trashFile.exists()) {
        await trashFile.delete();
      }
      await _store.removeEntry(entry.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已永久删除 "${entry.fileName}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _purgeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('确定要永久删除回收站中的所有文件吗？此操作不可撤销。'),
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
      final entries = await _store.listEntries();
      for (final entry in entries) {
        final trashFilePath = p.join(_store.trashDir, entry.fileName);
        final trashFile = File(trashFilePath);
        if (await trashFile.exists()) {
          await trashFile.delete();
        }
      }
      await _store.purgeAll();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回收站已清空')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e')),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _remainingLabel(int days) {
    if (days <= 0) return '即将删除';
    return '$days 天后永久删除';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_entries != null && _entries!.isNotEmpty)
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

    if (_entries == null || _entries!.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _entries!.length,
      itemBuilder: (context, index) {
        final entry = _entries![index];
        return _TrashEntryCard(
          entry: entry,
          onRestore: () => _restore(entry),
          onDelete: () => _permanentlyDelete(entry),
          formatSize: _formatSize,
          remainingLabel: _remainingLabel,
        );
      },
    );
  }
}

class _TrashEntryCard extends StatelessWidget {
  const _TrashEntryCard({
    required this.entry,
    required this.onRestore,
    required this.onDelete,
    required this.formatSize,
    required this.remainingLabel,
  });

  final TrashEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final String Function(int) formatSize;
  final String Function(int) remainingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = entry.remainingDays;
    final isExpiring = remaining <= 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.delete_outline,
              color: Colors.red.shade400,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fileName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.originalPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        formatSize(entry.size),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        remainingLabel(remaining),
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpiring
                              ? Colors.red
                              : theme.colorScheme.outline,
                          fontWeight:
                              isExpiring ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: theme.colorScheme.outline,
              ),
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
