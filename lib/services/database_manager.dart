import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _firstIntValue(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return 0;
  return (rows.first.values.first as int?) ?? 0;
}

class DatabaseManager {
  static final DatabaseManager instance = DatabaseManager._();
  DatabaseManager._();

  static const String _dbName = 'irix.db';
  static const int _dbVersion = 5;

  Database? _db;

  /// 应用数据目录（数据库文件与旧 JSON 迁移源所在目录）。
  String? _dataDir;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    throw StateError('Database not initialized. Call init() first.');
  }

  Future<void> init({String? dbPath, String? dataDir}) async {
    sqfliteFfiInit();
    String baseDir;
    if (dataDir != null) {
      baseDir = dataDir;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      baseDir = dir.path;
    }
    _dataDir = baseDir;
    final path = dbPath ?? p.join(baseDir, _dbName);

    _db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );

    await migrateFromJsonIfNeeded();
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        root_path TEXT NOT NULL,
        core_file_path TEXT NOT NULL,
        start_command TEXT NOT NULL,
        core_type TEXT,
        core_version TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE trash_items (
        id TEXT PRIMARY KEY,
        root_path TEXT NOT NULL,
        original_path TEXT NOT NULL,
        trash_path TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_trash_root_path ON trash_items(root_path)');
    batch.execute('''
      CREATE TABLE config_annotations (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE db_connections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT,
        password TEXT,
        database_name TEXT,
        use_ssl INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE nodes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        address TEXT NOT NULL,
        api_key TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE cluster_instances (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        node_id TEXT NOT NULL,
        daemon_id TEXT NOT NULL,
        remote_uuid TEXT NOT NULL,
        cwd TEXT NOT NULL,
        start_command TEXT NOT NULL,
        crash_count INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE cluster_sync_manifest (
        instance_id TEXT NOT NULL,
        rel_path TEXT NOT NULL,
        size INTEGER NOT NULL,
        mtime TEXT NOT NULL,
        PRIMARY KEY (instance_id, rel_path)
      )
    ''');
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS db_connections (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          host TEXT NOT NULL,
          port INTEGER NOT NULL,
          username TEXT,
          password TEXT,
          database_name TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS nodes (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          address TEXT NOT NULL,
          api_key TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      // 远程数据库连接增加 SSL 开关列。
      final cols = await db.rawQuery('PRAGMA table_info(db_connections)');
      final hasSsl = cols.any((c) => c['name'] == 'use_ssl');
      if (!hasSsl) {
        await db.execute(
          'ALTER TABLE db_connections ADD COLUMN use_ssl INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
    if (oldVersion < 5) {
      // 多机管理模式：集群实例与增量同步清单。
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cluster_instances (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          node_id TEXT NOT NULL,
          daemon_id TEXT NOT NULL,
          remote_uuid TEXT NOT NULL,
          cwd TEXT NOT NULL,
          start_command TEXT NOT NULL,
          crash_count INTEGER NOT NULL DEFAULT 0,
          last_synced_at TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cluster_sync_manifest (
          instance_id TEXT NOT NULL,
          rel_path TEXT NOT NULL,
          size INTEGER NOT NULL,
          mtime TEXT NOT NULL,
          PRIMARY KEY (instance_id, rel_path)
        )
      ''');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // === servers 表 ===

  Future<List<Map<String, dynamic>>> getAllServers() async {
    try {
      final db = await _database;
      return await db.query('servers');
    } catch (e) {
      debugPrint('Failed to get all servers: $e');
      return [];
    }
  }

  Future<void> insertServer(Map<String, dynamic> server) async {
    try {
      final db = await _database;
      await db.insert(
        'servers',
        server,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Failed to insert server: $e');
    }
  }

  Future<void> updateServer(String id, Map<String, dynamic> data) async {
    try {
      final db = await _database;
      await db.update('servers', data, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to update server: $e');
    }
  }

  Future<void> deleteServer(String id) async {
    try {
      final db = await _database;
      await db.delete('servers', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to delete server: $e');
    }
  }

  // === trash_items 表 ===

  Future<List<Map<String, dynamic>>> getTrashItems(String rootPath) async {
    try {
      final db = await _database;
      return await db.query(
        'trash_items',
        where: 'root_path = ?',
        whereArgs: [rootPath],
      );
    } catch (e) {
      debugPrint('Failed to get trash items: $e');
      return [];
    }
  }

  /// 获取所有实例的回收站条目。
  Future<List<Map<String, dynamic>>> getAllTrashItems() async {
    try {
      final db = await _database;
      return await db.query('trash_items', orderBy: 'deleted_at DESC');
    } catch (e) {
      debugPrint('Failed to get all trash items: $e');
      return [];
    }
  }

  Future<void> insertTrashItem(Map<String, dynamic> item) async {
    try {
      final db = await _database;
      await db.insert(
        'trash_items',
        item,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Failed to insert trash item: $e');
    }
  }

  Future<void> deleteTrashItem(String id) async {
    try {
      final db = await _database;
      await db.delete('trash_items', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to delete trash item: $e');
    }
  }

  Future<void> deleteAllTrashItems(String rootPath) async {
    try {
      final db = await _database;
      await db.delete(
        'trash_items',
        where: 'root_path = ?',
        whereArgs: [rootPath],
      );
    } catch (e) {
      debugPrint('Failed to delete all trash items: $e');
    }
  }

  /// 清空所有实例的回收站元数据。
  Future<void> purgeAllTrashItems() async {
    try {
      final db = await _database;
      await db.delete('trash_items');
    } catch (e) {
      debugPrint('Failed to purge all trash items: $e');
    }
  }

  // === config_annotations 表 ===

  Future<Map<String, String>> getAllAnnotations() async {
    try {
      final db = await _database;
      final rows = await db.query('config_annotations');
      return {
        for (final row in rows) row['key'] as String: row['value'] as String,
      };
    } catch (e) {
      debugPrint('Failed to get all annotations: $e');
      return {};
    }
  }

  Future<void> insertAnnotation(String key, String value) async {
    try {
      final db = await _database;
      await db.insert('config_annotations', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('Failed to insert annotation: $e');
    }
  }

  Future<void> deleteAllAnnotations() async {
    try {
      final db = await _database;
      await db.delete('config_annotations');
    } catch (e) {
      debugPrint('Failed to delete all annotations: $e');
    }
  }

  // === db_connections 表 ===

  Future<List<Map<String, dynamic>>> getAllDbConnections() async {
    try {
      final db = await _database;
      return await db.query('db_connections');
    } catch (e) {
      debugPrint('Failed to get all db connections: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDbConnection(String id) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'db_connections',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      debugPrint('Failed to get db connection $id: $e');
      return null;
    }
  }

  Future<void> insertDbConnection(Map<String, dynamic> conn) async {
    try {
      final db = await _database;
      await db.insert(
        'db_connections',
        conn,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Failed to insert db connection: $e');
    }
  }

  Future<void> updateDbConnection(String id, Map<String, dynamic> data) async {
    try {
      final db = await _database;
      await db.update('db_connections', data, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to update db connection $id: $e');
    }
  }

  Future<void> deleteDbConnection(String id) async {
    try {
      final db = await _database;
      await db.delete('db_connections', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to delete db connection $id: $e');
    }
  }

  // === nodes 表 ===

  Future<List<Map<String, dynamic>>> getAllNodes() async {
    try {
      final db = await _database;
      return await db.query('nodes', orderBy: 'created_at ASC');
    } catch (e) {
      debugPrint('Failed to get all nodes: $e');
      return [];
    }
  }

  Future<void> insertNode(Map<String, dynamic> node) async {
    try {
      final db = await _database;
      await db.insert(
        'nodes',
        node,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Failed to insert node: $e');
    }
  }

  Future<void> updateNode(String id, Map<String, dynamic> data) async {
    try {
      final db = await _database;
      await db.update('nodes', data, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to update node $id: $e');
    }
  }

  Future<void> deleteNode(String id) async {
    try {
      final db = await _database;
      await db.delete('nodes', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to delete node $id: $e');
    }
  }

  // === cluster_instances 表 ===

  Future<List<Map<String, dynamic>>> getAllClusterInstances() async {
    try {
      final db = await _database;
      return await db.query('cluster_instances', orderBy: 'created_at ASC');
    } catch (e) {
      debugPrint('Failed to get all cluster instances: $e');
      return [];
    }
  }

  Future<void> insertClusterInstance(Map<String, dynamic> instance) async {
    try {
      final db = await _database;
      await db.insert(
        'cluster_instances',
        instance,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Failed to insert cluster instance: $e');
    }
  }

  Future<void> updateClusterInstance(
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final db = await _database;
      await db.update(
        'cluster_instances',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('Failed to update cluster instance $id: $e');
    }
  }

  Future<void> deleteClusterInstance(String id) async {
    try {
      final db = await _database;
      await db.delete('cluster_instances', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('Failed to delete cluster instance $id: $e');
    }
  }

  // === cluster_sync_manifest 表 ===

  Future<List<Map<String, dynamic>>> getSyncManifest(String instanceId) async {
    try {
      final db = await _database;
      return await db.query(
        'cluster_sync_manifest',
        where: 'instance_id = ?',
        whereArgs: [instanceId],
      );
    } catch (e) {
      debugPrint('Failed to get sync manifest for $instanceId: $e');
      return [];
    }
  }

  /// 整体替换某集群实例的同步清单（先删后插，事务化）。
  Future<void> replaceSyncManifest(
    String instanceId,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final db = await _database;
      await db.transaction((txn) async {
        await txn.delete(
          'cluster_sync_manifest',
          where: 'instance_id = ?',
          whereArgs: [instanceId],
        );
        for (final row in rows) {
          await txn.insert(
            'cluster_sync_manifest',
            {'instance_id': instanceId, ...row},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      debugPrint('Failed to replace sync manifest for $instanceId: $e');
    }
  }

  Future<void> deleteSyncManifest(String instanceId) async {
    try {
      final db = await _database;
      await db.delete(
        'cluster_sync_manifest',
        where: 'instance_id = ?',
        whereArgs: [instanceId],
      );
    } catch (e) {
      debugPrint('Failed to delete sync manifest for $instanceId: $e');
    }
  }

  // === settings 表 ===

  Future<String?> getSetting(String key) async {
    try {
      final db = await _database;
      final rows = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (e) {
      debugPrint('Failed to get setting $key: $e');
      return null;
    }
  }

  Future<void> setSetting(String key, String value) async {
    try {
      final db = await _database;
      await db.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('Failed to set setting $key: $e');
    }
  }

  Future<int?> getIntSetting(String key) async {
    final value = await getSetting(key);
    if (value == null) return null;
    return int.tryParse(value);
  }

  Future<void> setIntSetting(String key, int value) async {
    await setSetting(key, value.toString());
  }

  // === 旧数据迁移 ===

  Future<void> migrateFromJsonIfNeeded() async {
    try {
      final baseDir =
          _dataDir ?? (await getApplicationDocumentsDirectory()).path;
      final db = await _database;

      final instancesFile = File(p.join(baseDir, 'instances.json'));
      if (await instancesFile.exists()) {
        final count = _firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM servers'),
        );
        if (count == 0) {
          final content = await instancesFile.readAsString();
          if (content.trim().isNotEmpty) {
            final list = jsonDecode(content) as List<dynamic>;
            final batch = db.batch();
            for (final item in list) {
              final map = item as Map<String, dynamic>;
              batch.insert('servers', {
                'id': map['id'] ?? '',
                'name': map['name'] ?? '',
                'root_path': map['rootPath'] ?? '',
                'core_file_path': map['coreFilePath'] ?? '',
                'start_command': map['startCommand'] ?? '',
                'core_type': map['coreType'],
                'core_version': map['coreVersion'],
                'created_at':
                    map['createdAt'] ?? DateTime.now().toIso8601String(),
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await batch.commit(noResult: true);
            debugPrint('Migrated ${list.length} instances from instances.json');
          }
        }
      }

      final servers = await db.query('servers');
      for (final server in servers) {
        final rootPath = server['root_path'] as String;
        final trashMetaPath = p.join(rootPath, 'xmc_trash', 'trash_meta.json');
        final trashMetaFile = File(trashMetaPath);
        if (await trashMetaFile.exists()) {
          final existingCount = _firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) AS c FROM trash_items WHERE root_path = ?',
              [rootPath],
            ),
          );
          if (existingCount == 0) {
            final content = await trashMetaFile.readAsString();
            if (content.trim().isNotEmpty) {
              final list = jsonDecode(content) as List<dynamic>;
              final batch = db.batch();
              for (final item in list) {
                final map = item as Map<String, dynamic>;
                batch.insert('trash_items', {
                  'id': map['id'] ?? '',
                  'root_path': rootPath,
                  'original_path': map['originalPath'] ?? '',
                  'trash_path': map['trashPath'] ?? '',
                  'deleted_at':
                      map['deletedAt'] ?? DateTime.now().toIso8601String(),
                }, conflictAlgorithm: ConflictAlgorithm.replace);
              }
              await batch.commit(noResult: true);
              debugPrint('Migrated ${list.length} trash items for $rootPath');
            }
          }
        }
      }

      final annotationsFile = File(p.join(baseDir, 'config_annotations.json'));
      if (await annotationsFile.exists()) {
        final count = _firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM config_annotations'),
        );
        if (count == 0) {
          final content = await annotationsFile.readAsString();
          if (content.trim().isNotEmpty) {
            final map = jsonDecode(content) as Map<String, dynamic>;
            final batch = db.batch();
            for (final entry in map.entries) {
              batch.insert('config_annotations', {
                'key': entry.key,
                'value': entry.value.toString(),
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
            await batch.commit(noResult: true);
            debugPrint(
              'Migrated ${map.length} config annotations from config_annotations.json',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Migration from JSON failed: $e');
    }
  }
}
