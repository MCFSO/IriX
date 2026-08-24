// ProcessRegistry 单元测试
// 覆盖：PID 登记的写入/读取/清除、JSON 往返，以及存活检测
// （不存在的 PID 应判定为不存活）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/services/process_registry.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_registry_test');
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

  test('记录、读取与清除（JSON 往返）', () async {
    const record = RunningProcessRecord(
      pid: 4242,
      imageName: 'java.exe',
      startedAt: '2026-01-01T00:00:00',
    );
    await ProcessRegistry.record('instance-a', record);

    final read = await ProcessRegistry.read('instance-a');
    expect(read, isNotNull);
    expect(read!.pid, 4242);
    expect(read.imageName, 'java.exe');
    expect(read.startedAt, '2026-01-01T00:00:00');

    await ProcessRegistry.clear('instance-a');
    expect(await ProcessRegistry.read('instance-a'), isNull);
  });

  test('无登记时返回 null', () async {
    expect(await ProcessRegistry.read('no-such-instance'), isNull);
  });

  test('不存在的 PID 判定为不存活', () async {
    // int32 最大值 PID 实际不存在，各平台检测渠道均应返回 false。
    final alive = await ProcessRegistry.isAlive(2147483647);
    expect(alive, isFalse);
  });
}
