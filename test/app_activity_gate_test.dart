// 最小化门闸（AppActivityGate）测试
//
// 覆盖：最小化时 Offstage + TickerMode 关闭、恢复时补回；
// 全局标记 AppActivity.minimized 与生命周期同步。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/state/app_activity.dart';
import 'package:irix/widgets/app_activity_gate.dart';

void main() {
  tearDown(() => AppActivity.instance.setMinimized(false));

  testWidgets('最小化时离屏并停止动画，恢复后补回', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppActivityGate(child: Scaffold(body: Text('content'))),
      ),
    );

    final gateOffstage = find.byKey(const ValueKey('app-activity-offstage'));

    // 初始可见
    var offstage = tester.widget<Offstage>(gateOffstage);
    expect(offstage.offstage, isFalse);
    expect(find.text('content'), findsOneWidget);
    expect(AppActivity.instance.isMinimized, isFalse);

    // 最小化（桌面端上报 hidden）
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    offstage = tester.widget<Offstage>(gateOffstage);
    expect(offstage.offstage, isTrue);
    expect(AppActivity.instance.isMinimized, isTrue);

    final tickerMode = tester.widget<TickerMode>(
      find.ancestor(of: gateOffstage, matching: find.byType(TickerMode)).first,
    );
    expect(tickerMode.enabled, isFalse);

    // 恢复
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    offstage = tester.widget<Offstage>(gateOffstage);
    expect(offstage.offstage, isFalse);
    expect(AppActivity.instance.isMinimized, isFalse);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('paused 也视为不可见', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppActivityGate(child: Scaffold(body: Text('content'))),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(AppActivity.instance.isMinimized, isTrue);
  });
}
