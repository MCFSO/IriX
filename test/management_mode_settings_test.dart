// 管理模式设置测试
// 验证默认单机模式、切换持久化与监控节点设置。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/services/management_mode_settings.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_mode_test');
    await DatabaseManager.instance.init(
      dbPath: p.join(tempDir.path, 'test.db'),
      dataDir: tempDir.path,
    );
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('未设置时默认单机模式', () async {
    expect(await ManagementModeSettings.getMode(), ManagementMode.single);
    expect(await ManagementModeSettings.getMonitorNodeId(), isNull);
  });

  test('切换多机模式并持久化', () async {
    await ManagementModeSettings.setMode(ManagementMode.multi);
    expect(await ManagementModeSettings.getMode(), ManagementMode.multi);

    await ManagementModeSettings.setMonitorNodeId('n-abc');
    expect(await ManagementModeSettings.getMonitorNodeId(), 'n-abc');

    await ManagementModeSettings.setMonitorNodeId(null);
    expect(await ManagementModeSettings.getMonitorNodeId(), isNull);
  });
}
