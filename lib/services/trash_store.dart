// 回收站持久化服务
// 管理 xmc_trash 目录下的文件移动与 trash_meta.json 元数据。
// 同时被 file_manager_screen.dart 与 trash_view.dart 引用，
// 因此提取为独立服务文件以避免循环导入。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
}

class TrashStore {
  static const String _trashDirName = 'xmc_trash';
  static const String _metaFileName = 'trash_meta.json';

  String _trashDir(String rootPath) => p.join(rootPath, _trashDirName);

  String _metaFilePath(String rootPath) =>
      p.join(_trashDir(rootPath), _metaFileName);

  String _generateId() {
    final random = Random();
    final suffix =
        random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  Future<List<TrashItem>> _loadMeta(String rootPath) async {
    final file = File(_metaFilePath(rootPath));
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => TrashItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Failed to load trash meta: $e');
      return [];
    }
  }

  Future<void> _saveMeta(String rootPath, List<TrashItem> items) async {
    final dir = Directory(_trashDir(rootPath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_metaFilePath(rootPath));
    await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
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

    final items = await _loadMeta(rootPath);
    items.add(TrashItem(
      id: id,
      originalPath: entity.path,
      trashPath: trashPath,
      deletedAt: DateTime.now(),
    ));
    await _saveMeta(rootPath, items);
  }

  Future<void> restoreItem(String rootPath, String id) async {
    final items = await _loadMeta(rootPath);
    final item = items.where((e) => e.id == id).firstOrNull;
    if (item == null) return;

    final trashEntry = FileSystemEntity.typeSync(item.trashPath);
    if (trashEntry == FileSystemEntityType.notFound) {
      items.removeWhere((e) => e.id == id);
      await _saveMeta(rootPath, items);
      return;
    }

    final target = File(item.trashPath);
    await target.rename(item.originalPath);

    items.removeWhere((e) => e.id == id);
    await _saveMeta(rootPath, items);
  }

  Future<void> permanentlyDelete(String rootPath, String id) async {
    final items = await _loadMeta(rootPath);
    final item = items.where((e) => e.id == id).firstOrNull;
    if (item == null) return;

    final entry = FileSystemEntity.typeSync(item.trashPath);
    if (entry != FileSystemEntityType.notFound) {
      final target = FileSystemEntity.typeSync(item.trashPath)
              == FileSystemEntityType.directory
          ? Directory(item.trashPath)
          : File(item.trashPath);
      await target.delete(recursive: true);
    }

    items.removeWhere((e) => e.id == id);
    await _saveMeta(rootPath, items);
  }

  Future<List<TrashItem>> getTrashItems(String rootPath) async {
    return _loadMeta(rootPath);
  }

  Future<void> emptyTrash(String rootPath) async {
    final items = await _loadMeta(rootPath);
    for (final item in items) {
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
    await _saveMeta(rootPath, []);
  }
}
