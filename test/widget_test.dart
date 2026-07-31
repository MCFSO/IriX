// IriX 冒烟测试
// 验证应用根组件 MyApp 能够正常构建，不引用尚未创建的界面/状态。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/main.dart';
import 'package:irix/services/database_manager.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // 使用临时目录初始化 SQLite，避免依赖 path_provider 平台通道。
    tempDir = await Directory.systemTemp.createTemp('irix_test');
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

  testWidgets('MyApp 能够正常构建', (WidgetTester tester) async {
    // 构建应用并触发一帧，期望不抛出异常。
    expect(() => tester.pumpWidget(const MyApp()), returnsNormally);
  });
}
