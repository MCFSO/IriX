// 更新提醒窗布局与交互测试
//
// 只验证渲染与「稍后提醒」这类不触网的路径；下载/安装依赖 Rust FFI 与真实
// 网络，由手工端到端验证（见 docs/ota-update.md §8）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/l10n/app_localizations.dart';
import 'package:irix/models/update_info.dart';
import 'package:irix/widgets/update_dialog.dart';

UpdateInfo _info({bool withAsset = true}) {
  final release = UpdateRelease.fromJson({
    'tag_name': 'Stable-v1.3.0',
    'name': 'v1.3.0',
    'draft': false,
    'prerelease': false,
    'published_at': '2026-11-01T00:08:42Z',
    'html_url': 'https://github.com/MCFSO/IriX/releases/tag/Stable-v1.3.0',
    'body': '# IriX 1.3.0\n\n## 重点\n\n- 设备绑定\n- 备份重做\n',
    'assets': [
      {
        'name': 'irix-1.3.0-windows-x64.exe',
        'browser_download_url':
            'https://github.com/MCFSO/IriX/releases/download/Stable-v1.3.0/irix-1.3.0-windows-x64.exe',
        'size': 26032108,
        'digest':
            'sha256:f190066c49a1bd6826d00c6a76369c1dc3e951ff5245fe1101d020eb3d6933f9',
      },
    ],
  })!;
  return UpdateInfo(
    release: release,
    currentVersion: release.version,
    asset: withAsset ? release.assets.first : null,
  );
}

void main() {
  /// 打开更新提醒窗；对话框返回时通过 [onResult] 回传用户选择。
  Future<void> pumpDialog(
    WidgetTester tester, {
    bool withAsset = true,
    int runningInstances = 0,
    void Function(UpdateDialogResult)? onResult,
  }) async {
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
                onPressed: () async {
                  final result = await showUpdateDialog(
                    context,
                    info: _info(withAsset: withAsset),
                    runningInstances: runningInstances,
                  );
                  onResult?.call(result);
                },
                child: const Text('open-update'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-update'));
    await tester.pumpAndSettle();
  }

  testWidgets('显示版本、安装包信息与更新说明', (tester) async {
    await pumpDialog(tester);

    expect(find.text('发现新版本 v1.3.0'), findsOneWidget);
    // 当前版本 → 新版本 · 发布时间 · 安装包名称与大小
    expect(find.textContaining('v1.3.0 → v1.3.0'), findsOneWidget);
    expect(find.textContaining('irix-1.3.0-windows-x64.exe'), findsOneWidget);
    expect(find.text('更新内容'), findsOneWidget);
    // Markdown 正文渲染为文本
    expect(find.textContaining('设备绑定'), findsOneWidget);

    // 三个可用动作 + 发布页入口
    expect(find.text('稍后提醒'), findsOneWidget);
    expect(find.text('跳过此版本'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
    expect(find.text('前往发布页'), findsOneWidget);
  });

  testWidgets('「稍后提醒」关闭对话框并返回 later', (tester) async {
    UpdateDialogResult? captured;
    await pumpDialog(tester, onResult: (result) => captured = result);
    await tester.tap(find.text('稍后提醒'));
    await tester.pumpAndSettle();
    expect(captured, UpdateDialogResult.later);
    expect(find.text('发现新版本 v1.3.0'), findsNothing);
  });

  testWidgets('无匹配安装包时改为引导去发布页', (tester) async {
    await pumpDialog(tester, withAsset: false);
    // 主按钮文案变为「前往发布页」，不再提供「下载并安装」
    expect(find.text('下载并安装'), findsNothing);
    expect(find.text('前往发布页'), findsNWidgets(2));
  });

  testWidgets('有实例运行时给出提醒', (tester) async {
    await pumpDialog(tester, runningInstances: 2);
    expect(find.textContaining('检测到 2 个实例正在运行'), findsOneWidget);
  });
}
