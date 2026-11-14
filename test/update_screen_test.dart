// 设置页「软件更新」分区渲染测试
//
// 该分区在 initState 里读 SQLite，而 widget 测试跑在假时钟下：
// 所以必须把 pumpWidget 放进 [WidgetTester.runAsync] 里，让 DB Future 在真实
// 事件循环里完成，之后再用普通 pump 取帧；断言里若还要读库，也要包 runAsync。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:irix/l10n/app_localizations.dart';
import 'package:irix/screens/settings_screen.dart';
import 'package:irix/services/app_version.dart';
import 'package:irix/services/database_manager.dart';
import 'package:irix/services/font_settings.dart';
import 'package:irix/services/locale_settings.dart';
import 'package:irix/services/update_service.dart';
import 'package:irix/services/update_settings.dart';
import 'package:irix/state/app_state.dart';
import 'package:irix/state/cluster_state.dart';
import 'package:irix/state/node_state.dart';
import 'package:irix/utils/apple_widgets.dart';
import 'package:irix/widgets/java_management_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_update_screen');
    await DatabaseManager.instance.init(
      dbPath: p.join(tempDir.path, 'test.db'),
      dataDir: tempDir.path,
    );
  });

  setUp(() async {
    // 每个用例都从「从未检查过、没跳过版本、没有自定义更新源」的干净状态开始。
    await UpdateSettings.setAutoCheck(true);
    await UpdateSettings.setIncludePrerelease(false);
    await UpdateSettings.setSkippedVersion('');
    await UpdateSettings.setLastCheckAtMs(0);
    await UpdateSettings.setLastKnownLatest('');
    await UpdateSettings.setFeedUrl('');
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider(create: (_) => NodeState()),
            ChangeNotifierProvider(create: (_) => ClusterState()),
            ChangeNotifierProvider(create: (_) => FontSettings.instance),
            ChangeNotifierProvider(create: (_) => LocaleSettings.instance),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(initialSection: SettingsSection.update),
          ),
        ),
      );
      // 等 initState 里的 SQLite 读取完成（真实事件循环里推进）。
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
  }

  testWidgets('展示当前版本、开关与检查入口', (tester) async {
    await pumpSection(tester);

    // 加载完成后不应再有进度圈
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.textContaining('当前版本 $kIrixAppVersionLabel'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${UpdateService.platformTag}/${UpdateService.archTag}',
      ),
      findsOneWidget,
    );
    expect(find.text('尚未检查过更新'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('打开发布页'), findsOneWidget);
    expect(find.text('启动时自动检查更新'), findsOneWidget);
    expect(find.text('包含预发布版本'), findsOneWidget);
    // 更新源区块
    expect(find.text('更新源'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('用回默认'), findsOneWidget);
    expect(
      find.textContaining(
        '当前生效：${UpdateService.feedCandidates(configured: '').first}',
      ),
      findsOneWidget,
      reason: '未配置自定义源时应显示内置源（项目自建 Cloudflare Worker）',
    );
    expect(find.byType(AppleSwitch), findsNWidgets(2));
    // 只展示了「软件更新」分区，没有顺带渲染 Java 管理
    expect(find.byType(JavaManagementSection), findsNothing);
  });

  testWidgets('保存更新源并规范化（自动补 /api/releases）', (tester) async {
    await pumpSection(tester);

    await tester.enterText(find.byType(TextField).first, 'irix.example.workers.dev');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();

    expect(
      await tester.runAsync(() => UpdateSettings.getFeedUrl()),
      'https://irix.example.workers.dev/api/releases',
    );
    // 「当前生效」随之更新到 Worker
    expect(
      find.textContaining('当前生效：https://irix.example.workers.dev/api/releases'),
      findsOneWidget,
    );

    // 「用回默认」清空自定义源
    await tester.tap(find.text('用回默认'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    expect(
      await tester.runAsync(() => UpdateSettings.getFeedUrl()),
      '',
    );
  });

  testWidgets('切换「启动时自动检查更新」写入设置', (tester) async {
    await pumpSection(tester);
    expect(
      await tester.runAsync(() => UpdateSettings.getAutoCheck()),
      isTrue,
    );

    // 分区内第一个开关是「启动时自动检查更新」。
    await tester.tap(find.byType(AppleSwitch).first);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();

    expect(
      await tester.runAsync(() => UpdateSettings.getAutoCheck()),
      isFalse,
    );
  });
}
