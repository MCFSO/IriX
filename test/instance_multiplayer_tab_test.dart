// 实例「联机」Tab 组件测试。
//
// 只验证「状态 → 界面」的映射与房客加入流程（不需要 AppState/Provider）。
// 房主扫描会读取 AppState 并联动启动实例，属于集成测试范畴，这里不覆盖。
//
// 为避免 testWidgets 的 pending-timer 断言，这里用 `debugForceState` 直接把
// 管理器推进到目标状态（不启动联机核心、不创建轮询定时器），用例末尾先卸载
// 组件树再 dispose 管理器（ChangeNotifier 释放后不能再被 removeListener）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irix/l10n/app_localizations.dart';
import 'package:irix/screens/instance_multiplayer_tab.dart';
import 'package:irix/services/terracotta/terracotta_manager.dart';
import 'package:irix/services/terracotta/terracotta_state.dart';

import 'support/terracotta_fakes.dart';

void main() {
  late Directory tempDir;
  late FakeControlApi api;
  late FakeLauncher launcher;
  late TerracottaManager manager;
  late bool disposed;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('irix-terracotta-tab-');
    api = FakeControlApi();
    launcher = FakeLauncher(25566);
    manager = TerracottaManager(
      api: api,
      launcher: launcher,
      terracottaRootProvider: () async => tempDir.path,
      bundleBuilder: buildTestBundle,
      // 组件测试不依赖轮询：给一个足够长的间隔，避免假时钟里反复回调。
      pollActive: const Duration(hours: 1),
      pollIdle: const Duration(hours: 1),
    );
    disposed = false;
  });

  void safeDispose() {
    if (disposed) return;
    disposed = true;
    manager.dispose();
  }

  tearDown(() {
    safeDispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 卸载组件树并释放管理器。
  Future<void> teardownTab(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    safeDispose();
  }

  Future<void> pumpTab(WidgetTester tester) async {
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
        home: Scaffold(
          body: InstanceMultiplayerTab(
            instanceId: 'inst-1',
            instanceName: '生存服',
            manager: manager,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('空闲态展示房主/房客入口与署名牌', (tester) async {
    manager.debugForceState(
      TerracottaWaiting(port: 25566, index: 1),
      port: 25566,
    );
    await pumpTab(tester);

    expect(find.text('联机核心已就绪'), findsOneWidget);
    expect(find.text('我想当房主'), findsOneWidget);
    expect(find.text('我想当房客'), findsOneWidget);
    expect(find.text('关于多人联机'), findsOneWidget);
    // 玩家名默认取实例名（会出现在联机核心的玩家列表里）。
    expect(manager.playerName, '生存服');
    await teardownTab(tester);
  });

  testWidgets('房客流程：输入邀请码后进入「正在加入房间」', (tester) async {
    manager.debugForceState(
      TerracottaWaiting(port: 25566, index: 1),
      port: 25566,
    );
    await pumpTab(tester);

    await tester.tap(find.text('我想当房客'));
    await tester.pumpAndSettle();
    expect(find.text('请输入房主提供的邀请码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '246813579');
    await tester.tap(find.widgetWithText(FilledButton, '我想当房客'));
    // 「正在加入房间」是 indeterminate 进度条，pumpAndSettle 永远不会收敛，
    // 这里只推进固定帧数等弹窗关闭与状态刷新。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.lastGuestingRoom, '246813579');
    expect(manager.state, isA<TerracottaGuestConnecting>());
    expect(find.text('正在加入房间'), findsOneWidget);
    await teardownTab(tester);
  });

  testWidgets('邀请码为空时不发起请求', (tester) async {
    manager.debugForceState(
      TerracottaWaiting(port: 25566, index: 1),
      port: 25566,
    );
    await pumpTab(tester);

    await tester.tap(find.text('我想当房客'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '我想当房客'));
    await tester.pumpAndSettle();

    expect(api.guestingCalls, 0);
    expect(manager.state, isA<TerracottaWaiting>());
    await teardownTab(tester);
  });

  testWidgets('房间已创建时展示邀请码与玩家列表', (tester) async {
    manager.debugForceState(
      const TerracottaHostOk(
        port: 25566,
        index: 5,
        room: '135792468',
        profiles: [
          TerracottaProfile(
            machineId: 'a',
            name: 'Alice',
            vendor: 'HMCL',
            kind: TerracottaPlayerKind.host,
          ),
          TerracottaProfile(
            machineId: 'b',
            name: 'Bob',
            vendor: 'PCL CE',
            kind: TerracottaPlayerKind.guest,
          ),
        ],
        profileIndex: 1,
      ),
      port: 25566,
    );
    await pumpTab(tester);

    expect(find.text('已启动房间'), findsOneWidget);
    expect(find.text('135792468'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('房主'), findsOneWidget);
    expect(find.text('房客'), findsOneWidget);
    await teardownTab(tester);
  });

  testWidgets('平台不支持时只提示，不给「重试」', (tester) async {
    manager.debugForceState(const TerracottaFatal(TerracottaFatalType.os));
    await pumpTab(tester);

    expect(find.textContaining('暂不支持多人联机'), findsWidgets);
    expect(find.text('重试'), findsNothing);
    await teardownTab(tester);
  });
}
