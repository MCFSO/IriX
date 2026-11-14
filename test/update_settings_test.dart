// 更新设置的持久化测试
//
// 覆盖：默认值、写入后读回、以及各 key 的实际名称（`update_*` 命名是对外契约，
// 设置页与启动自动检查都依赖它，改名会悄悄丢配置）。
//
// 分区渲染与开关交互见 test/update_screen_test.dart，提醒窗见
// test/update_dialog_test.dart。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/services/update_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_update_settings');
    await DatabaseManager.instance.init(
      dbPath: p.join(tempDir.path, 'test.db'),
      dataDir: tempDir.path,
    );
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('默认值：开启自动检查、不含预发布、无跳过版本', () async {
    expect(UpdateSettings.defaultAutoCheck, isTrue);
    expect(UpdateSettings.defaultIncludePrerelease, isFalse);
    expect(UpdateSettings.autoCheckInterval, const Duration(hours: 6));
    expect(await UpdateSettings.getAutoCheck(), isTrue);
    expect(await UpdateSettings.getIncludePrerelease(), isFalse);
    expect(await UpdateSettings.getSkippedVersion(), '');
    expect(await UpdateSettings.getLastCheckAtMs(), 0);
    expect(await UpdateSettings.getLastKnownLatest(), '');
  });

  test('写入后可读回', () async {
    await UpdateSettings.setAutoCheck(false);
    await UpdateSettings.setIncludePrerelease(true);
    await UpdateSettings.setSkippedVersion('1.4.0');
    await UpdateSettings.setLastCheckAtMs(1700000000000);
    await UpdateSettings.setLastKnownLatest('1.4.0');

    expect(await UpdateSettings.getAutoCheck(), isFalse);
    expect(await UpdateSettings.getIncludePrerelease(), isTrue);
    expect(await UpdateSettings.getSkippedVersion(), '1.4.0');
    expect(await UpdateSettings.getLastCheckAtMs(), 1700000000000);
    expect(await UpdateSettings.getLastKnownLatest(), '1.4.0');
  });

  test('设置存在 settings 表的 update_* key 下', () async {
    await UpdateSettings.setAutoCheck(false);
    expect(await DatabaseManager.instance.getSetting('update_auto_check'), '0');
    await UpdateSettings.setAutoCheck(true);
    expect(await DatabaseManager.instance.getSetting('update_auto_check'), '1');
    expect(
      await DatabaseManager.instance.getSetting('update_skipped_version'),
      '1.4.0',
    );
  });

  test('清除跳过版本', () async {
    await UpdateSettings.setSkippedVersion('1.5.0');
    expect(await UpdateSettings.getSkippedVersion(), '1.5.0');
    await UpdateSettings.setSkippedVersion('');
    expect(await UpdateSettings.getSkippedVersion(), '');
  });
}
