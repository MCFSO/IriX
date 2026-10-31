// 实例 JVM / Java 设置的持久化测试
//
// 覆盖：
// - 新库（v9）写入与读回 memory_auto / memory_mb / jvm_preset / java_* 字段
// - 旧库（v8，仅有 java_* 列）升级到 v9 时补齐 memory 列，且旧数据默认
//   「自动分配 + 无优化预设」（保持原有行为）

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:irix/models/jvm_preset.dart';
import 'package:irix/models/server_instance.dart';
import 'package:irix/services/database_manager.dart';
import 'package:irix/services/instance_store.dart';

ServerInstance buildInstance(String id) => ServerInstance(
  id: id,
  name: '测试实例',
  rootPath: '/data/$id',
  coreFilePath: '/data/$id/paper.jar',
  startCommand: 'java -jar paper.jar nogui',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('新库 v9', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('irix_jvm_store');
      await DatabaseManager.instance.init(
        dbPath: p.join(tempDir.path, 'new.db'),
        dataDir: tempDir.path,
      );
    });

    tearDownAll(() async {
      await DatabaseManager.instance.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('JVM 设置写入后可读回', () async {
      final store = InstanceStore();
      await store.addInstance(buildInstance('a'));

      await store.updateJvmSettings(
        'a',
        memoryAuto: false,
        memoryMb: 6144,
        jvmPreset: JvmPreset.aikar,
      );

      final loaded = await store.loadInstances();
      final instance = loaded.firstWhere((e) => e.id == 'a');
      expect(instance.memoryAuto, isFalse);
      expect(instance.memoryMb, 6144);
      expect(instance.jvmPreset, JvmPreset.aikar);
    });

    test('Java 选择写入后可读回', () async {
      final store = InstanceStore();
      await store.addInstance(buildInstance('b'));

      await store.updateJavaSelection(
        'b',
        InstanceJavaMode.custom,
        '/opt/jdk-17/bin/java',
      );

      final loaded = await store.loadInstances();
      final instance = loaded.firstWhere((e) => e.id == 'b');
      expect(instance.javaMode, InstanceJavaMode.custom);
      expect(instance.javaBinary, '/opt/jdk-17/bin/java');
    });
  });

  group('从 v8 升级到 v9', () {
    late Directory tempDir;
    late String dbPath;

    setUpAll(() async {
      sqfliteFfiInit();
      tempDir = await Directory.systemTemp.createTemp('irix_migrate_v8');
      dbPath = p.join(tempDir.path, 'legacy.db');

      // 手工构造 v8 库：servers 表已有 java_*，但没有 memory_* / jvm_preset。
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE servers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                root_path TEXT NOT NULL,
                core_file_path TEXT NOT NULL,
                start_command TEXT NOT NULL,
                core_type TEXT,
                core_version TEXT,
                run_mode TEXT NOT NULL DEFAULT 'native',
                container_config TEXT,
                java_mode TEXT NOT NULL DEFAULT 'auto',
                java_binary TEXT,
                created_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      await db.insert('servers', {
        'id': 'legacy',
        'name': '旧实例',
        'root_path': '/data/legacy',
        'core_file_path': '/data/legacy/paper.jar',
        'start_command': 'java -Xmx1024M -jar paper.jar nogui',
        'run_mode': 'native',
        'created_at': '2026-01-01T00:00:00.000',
      });
      await db.close();

      await DatabaseManager.instance.init(
        dbPath: dbPath,
        dataDir: tempDir.path,
      );
    });

    tearDownAll(() async {
      await DatabaseManager.instance.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('升级后旧实例默认为手动 + 未设置（等于升级前行为）', () async {
      final loaded = await InstanceStore().loadInstances();
      final instance = loaded.firstWhere((e) => e.id == 'legacy');
      expect(instance.memoryAuto, isFalse);
      expect(instance.memoryMb, isNull);
      expect(instance.jvmPreset, JvmPreset.none);
      expect(instance.javaMode, InstanceJavaMode.auto);
    });

    test('升级后的库可以写入新字段', () async {
      await InstanceStore().updateJvmSettings(
        'legacy',
        memoryAuto: false,
        memoryMb: 3072,
        jvmPreset: JvmPreset.aikar,
      );
      final loaded = await InstanceStore().loadInstances();
      final instance = loaded.firstWhere((e) => e.id == 'legacy');
      expect(instance.memoryAuto, isFalse);
      expect(instance.memoryMb, 3072);
      expect(instance.jvmPreset, JvmPreset.aikar);
    });
  });
}
