// 回收站持久化服务
// 管理 xmc_trash 目录下的文件移动与 SQLite 元数据。
// 同时被 file_manager_screen.dart 与 trash_view.dart 引用，
// 因此提取为独立服务文件以避免循环导入。

import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/database_manager.dart';

class TrashItem {
  final String id;
  final String originalPath;
  final String trashPath;
  final DateTime deletedAt;

  const TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashPath,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalPath': originalPath,
        'trashPath': trashPath,
        'deletedAt': deletedAt.toIso8601String(),
      };

  factory TrashItem.fromJson(Map<String, dynamic> map) => TrashItem(
        id: map['id'] as String,
        originalPath: map['originalPath'] as String,
        trashPath: map['trashPath'] as String,
        deletedAt: DateTime.parse(map['deletedAt'] as String),
      );

  static TrashItem fromDbRow(Map<String, dynamic> row) => TrashItem(
        id: row['id'] as String,
        originalPath: row['original_path'] as String,
        trashPath: row['trash_path'] as String,
        deletedAt: DateTime.parse(row['deleted_at'] as String),
      );

  Map<String, dynamic> toDbRow(String rootPath) => {
        'id': id,
        'root_path': rootPath,
        'original_path': originalPath,
        'trash_path': trashPath,
        'deleted_at': deletedAt.toIso8601String(),
      };
}

class TrashStore {
  static const String _trashDirName = 'xmc_trash';

  String _trashDir(String rootPath) => p.join(rootPath, _trashDirName);

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final suffix = (now % (1 << 20)).toRadixString(36).padLeft(4, '0');
    return '${now.toRadixString(36)}-$suffix';
  }

  Future<void> moveToTrash(
    String rootPath,
    FileSystemEntity entity,
  ) async {
    final trashDir = _trashDir(rootPath);
    final dir = Directory(trashDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final id = _generateId();
    final name = p.basename(entity.path);
    final trashPath = p.join(trashDir, '$id-$name');

    await entity.rename(trashPath);

    final item = TrashItem(
      id: id,
      originalPath: entity.path,
      trashPath: trashPath,
      deletedAt: DateTime.now(),
    );
    await DatabaseManager.instance.insertTrashItem(item.toDbRow(rootPath));
  }

  Future<void> restoreItem(String rootPath, String id) async {
    final items = await DatabaseManager.instance.getTrashItems(rootPath);
    final itemRow =
        items.where((e) => (e['id'] as String?) == id).firstOrNull;
    if (itemRow == null) return;

    final item = TrashItem.fromDbRow(itemRow);

    final trashEntry = FileSystemEntity.typeSync(item.trashPath);
    if (trashEntry == FileSystemEntityType.notFound) {
      await DatabaseManager.instance.deleteTrashItem(id);
      return;
    }

    final target = File(item.trashPath);
    await target.rename(item.originalPath);

    await DatabaseManager.instance.deleteTrashItem(id);
  }

  Future<void> permanentlyDelete(String rootPath, String id) async {
    final items = await DatabaseManager.instance.getTrashItems(rootPath);
    final itemRow =
        items.where((e) => (e['id'] as String?) == id).firstOrNull;
    if (itemRow == null) return;

    final item = TrashItem.fromDbRow(itemRow);

    final entry = FileSystemEntity.typeSync(item.trashPath);
    if (entry != FileSystemEntityType.notFound) {
      final target = entry == FileSystemEntityType.directory
          ? Directory(item.trashPath)
          : File(item.trashPath);
      await target.delete(recursive: true);
    }

    await DatabaseManager.instance.deleteTrashItem(id);
  }

  Future<List<TrashItem>> getTrashItems(String rootPath) async {
    final rows = await DatabaseManager.instance.getTrashItems(rootPath);
    return rows.map(TrashItem.fromDbRow).toList();
  }

  Future<void> emptyTrash(String rootPath) async {
    final rows = await DatabaseManager.instance.getTrashItems(rootPath);
    for (final row in rows) {
      final item = TrashItem.fromDbRow(row);
      final entry = FileSystemEntity.typeSync(item.trashPath);
      if (entry != FileSystemEntityType.notFound) {
        final target = entry == FileSystemEntityType.directory
            ? Directory(item.trashPath)
            : File(item.trashPath);
        try {
          await target.delete(recursive: true);
        } catch (_) {}
      }
    }
    await DatabaseManager.instance.deleteAllTrashItems(rootPath);
  }
}
