// 添加节点三步向导按钮布局测试：
// 「取消」在每一步都保留且固定在最左侧，与右侧的「上一步 / 下一步 / 测试连接 / 完成」
// 拉开足够距离，避免想点「下一步」时误触取消整个向导。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/l10n/app_localizations.dart';
import 'package:irix/widgets/add_node_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAddNodeDialog(context),
                child: const Text('open-wizard'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-wizard'));
    await tester.pumpAndSettle();
  }

  /// 「取消」必须靠左，且与右侧任何「向前推进」的按钮保持较大间距、位于同一行。
  void expectCancelFarLeft(WidgetTester tester) {
    final dialog = tester.getRect(find.byType(AlertDialog));
    final cancelRect = tester.getRect(find.text('取消'));
    expect(
      cancelRect.center.dx - dialog.left,
      lessThan(dialog.width / 2),
      reason: '「取消」应在对话框左半边',
    );

    for (final label in ['上一步', '下一步', '测试连接', '完成']) {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) continue;
      final forwardRect = tester.getRect(finder);
      expect(
        forwardRect.center.dx,
        greaterThan(cancelRect.center.dx),
        reason: '「$label」应在「取消」右侧',
      );
      expect(
        forwardRect.center.dx - cancelRect.center.dx,
        greaterThan(200),
        reason: '「$label」与「取消」应拉开距离，避免误触',
      );
      expect(
        (forwardRect.center.dy - cancelRect.center.dy).abs(),
        lessThan(8),
        reason: '「$label」与「取消」应在同一行',
      );
    }
  }

  testWidgets('三步向导每一步都保留「取消」并固定在最左', (tester) async {
    await pumpDialog(tester);

    // 步骤 1：类型
    expect(find.text('选择节点类型'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('上一步'), findsNothing);
    expectCancelFarLeft(tester);

    // 步骤 2：名称 / 地址（此前这一步没有取消入口，只有「上一步」）
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('节点地址'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('上一步'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expectCancelFarLeft(tester);

    // 步骤 3：Key
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('节点 Key / API Key'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('上一步'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expectCancelFarLeft(tester);

    // 最后一步的「取消」依然能关闭整个向导
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('「上一步」逐级回退且不关闭向导', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    expect(find.text('选择节点类型'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
