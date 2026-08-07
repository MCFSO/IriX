// IriX 集成测试
// 在真实设备（Windows 桌面）上启动完整应用，验证：
// - 应用可正常启动并渲染主界面
// - 左侧导航栏 6 个页面均可切换并渲染
// - 空列表时的引导流程（新建 / 导入实例）
// - 设置对话框可打开关闭

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:irix/main.dart' as app;
import 'package:irix/screens/ai_screen.dart';
import 'package:irix/screens/database_screen.dart';
import 'package:irix/screens/frp_screen.dart';
import 'package:irix/screens/marketplace_screen.dart';
import 'package:irix/screens/new_instance_screen.dart';
import 'package:irix/screens/nodes_screen.dart';
import 'package:irix/screens/onboarding_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railDestination(String label) => find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(label),
      );

  /// 切换左侧导航并确认目标页面已渲染（等待异步加载期间不断帧）。
  Future<void> switchTo(WidgetTester tester, String label) async {
    await tester.tap(railDestination(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('应用启动并渲染主界面（导航栏 6 个页面）', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // 主界面与导航栏
    expect(find.byType(NavigationRail), findsOneWidget);
    for (final label in ['实例', '节点', '市场', '数据库', 'AI', 'FRP']) {
      expect(railDestination(label), findsOneWidget, reason: '导航项 $label');
    }

    // 实例页：空列表显示引导卡片，否则显示实例列表（AppBar 标题 IriX）
    final onboardingVisible = find.byType(OnboardingScreen).evaluate().isNotEmpty;
    if (onboardingVisible) {
      expect(find.text('新建'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
    } else {
      expect(find.text('IriX'), findsWidgets);
    }
  });

  testWidgets('左侧导航可切换全部页面', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    await switchTo(tester, '节点');
    expect(find.byType(NodesScreen), findsOneWidget);

    await switchTo(tester, '市场');
    expect(find.byType(MarketplaceScreen), findsOneWidget);

    await switchTo(tester, '数据库');
    expect(find.byType(DatabaseScreen), findsOneWidget);

    await switchTo(tester, 'AI');
    expect(find.byType(AiScreen), findsOneWidget);

    await switchTo(tester, 'FRP');
    expect(find.byType(FrpScreen), findsOneWidget);

    // 回到实例页
    await switchTo(tester, '实例');
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('设置对话框可打开并关闭', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    final settingsButton = find.byTooltip('设置');
    if (settingsButton.evaluate().isEmpty) {
      // 空列表态没有设置入口，跳过
      return;
    }
    await tester.tap(settingsButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('设置'), findsWidgets);
    expect(find.textContaining('下载线程数'), findsOneWidget);
    expect(find.textContaining('数据库每页行数'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('关闭'), findsNothing);
  });

  testWidgets('空列表引导流程：新建 → 下载/导入核心', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // 无实例时才走引导流程
    if (find.byType(OnboardingScreen).evaluate().isEmpty) {
      return;
    }

    // 新建实例 → 二级选择页
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.byType(NewInstanceScreen), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);

    // 返回引导页
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('新建'), findsOneWidget);
  });
}
