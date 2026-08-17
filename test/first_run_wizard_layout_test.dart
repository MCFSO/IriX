// 首次引导向导布局测试：窄窗口不溢出（RenderFlex overflow 会以异常形式导致测试失败）、
// 遮罩阻断点击、左上角「跳过」按钮 50% 不透明度且可点击。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/database_manager.dart';
import 'package:irix/widgets/first_run_wizard.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_wizard_test');
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

  Future<void> pumpWizard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstRunWizardOverlay(
            onSkip: () {},
            onFinish: (_) {},
          ),
        ),
      ),
    );
    // 等 initState 的 JDK 已装检测完成
    await tester.pumpAndSettle();
  }

  testWidgets('窄窗口（640x400）渲染不溢出', (tester) async {
    await pumpWizard(tester, const Size(640, 400));
    expect(find.text('首次配置引导'), findsOneWidget);
    expect(find.textContaining('安装 JDK 8'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('极小窗口（480x320）仍不溢出', (tester) async {
    await pumpWizard(tester, const Size(480, 320));
    expect(tester.takeException(), isNull);
    // 引导卡片仍可见
    expect(find.text('首次配置引导'), findsOneWidget);
  });

  testWidgets('遮罩阻断背景点击 + 跳过按钮 50% 不透明度', (tester) async {
    await pumpWizard(tester, const Size(800, 600));
    // 阻断层存在
    expect(
      find.byWidgetPredicate(
        (w) => w is AbsorbPointer && w.absorbing == true,
      ),
      findsWidgets,
    );
    // 左上角跳过按钮：Opacity 0.5 包裹的 TextButton
    final opacityFinder = find.byWidgetPredicate(
      (w) =>
          w is Opacity &&
          w.opacity == 0.5 &&
          w.child is TextButton,
    );
    expect(opacityFinder, findsOneWidget);
    var skipped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirstRunWizardOverlay(
            onSkip: () => skipped = true,
            onFinish: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    expect(skipped, isTrue);
  });
}
