// 插件列表懒加载设置的持久化测试
//
// 覆盖：默认 10 条、写入后读回、越界 clamp、非法值向下对齐到 5 的倍数。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/services/plugin_view_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_plugin_view');
    await DatabaseManager.instance.init(
      dbPath: p.join(tempDir.path, 'test.db'),
      dataDir: tempDir.path,
    );
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('未设置时默认每次 10 条', () async {
    expect(await PluginViewSettings.getBatchSize(), 10);
    expect(PluginViewSettings.defaultBatchSize, 10);
  });

  test('写入后可读回', () async {
    await PluginViewSettings.setBatchSize(20);
    expect(await PluginViewSettings.getBatchSize(), 20);
  });

  test('越界值 clamp 到 5-50', () async {
    await PluginViewSettings.setBatchSize(1);
    expect(await PluginViewSettings.getBatchSize(), 5);

    await PluginViewSettings.setBatchSize(500);
    expect(await PluginViewSettings.getBatchSize(), 50);
  });

  test('非 5 的倍数向下对齐', () async {
    await PluginViewSettings.setBatchSize(17);
    // 17 → 15
    expect(await PluginViewSettings.getBatchSize(), 15);
  });
}
