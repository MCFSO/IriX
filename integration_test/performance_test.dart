// IriX 市场项目列表滚动性能测试
// 在真实设备上启动应用，切换到「市场」页，连续滚动项目列表（含触底加载更多），
// 通过 TimelineSummary 记录帧构建 / 光栅化耗时，并输出到控制台与 build/perf/ 目录。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/main.dart' as app;

/// 轮询等待 [finder] 出现，超时抛出 [TimeoutException]。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TimeoutException('等待 $finder 超时');
}

/// 从进程工作目录向上查找项目根（包含 pubspec.yaml 的目录）。
Directory _findProjectRoot() {
  const maxDepth = 8;
  var dir = Directory.current;
  for (var i = 0; i < maxDepth; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('市场项目列表滚动性能', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    // 切换到「市场」页
    await tester.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('市场'),
    ));
    await tester.pump();

    // 等待首屏项目列表加载（依赖网络；失败则记录并跳过）
    try {
      await _waitFor(tester, find.byType(ListView));
    } on TimeoutException {
      debugPrint('PERF_MARKET_SCROLL: SKIPPED (市场列表未加载，可能网络不可用)');
      return;
    }

    final listFinder = find.byType(ListView);
    expect(listFinder, findsOneWidget);

    // 记录：连续 fling 滚动，期间会触发触底加载更多（网络请求 + 图片加载）。
    // watchPerformance 采集 FrameTiming 汇总到 binding.reportData['performance']。
    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        await tester.fling(listFinder, const Offset(0, -1200), 4000);
        await tester.pump(const Duration(milliseconds: 400));
      }
    });

    final performance =
        (binding.reportData?['performance'] as Map<String, dynamic>?) ??
            <String, dynamic>{};
    final data = <String, dynamic>{
      'test': 'market_scroll',
      ...performance,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // 控制台记录（flutter test 输出中可见）
    debugPrint('PERF_MARKET_SCROLL: ${jsonEncode(data)}');

    // 写入 build/perf/ 持久化记录
    try {
      final root = _findProjectRoot();
      final outDir = Directory(p.join(root.path, 'build', 'perf'));
      await outDir.create(recursive: true);
      final outFile = File(p.join(outDir.path, 'market_scroll_perf.json'));
      await outFile.writeAsString(jsonEncode(data));
      debugPrint('PERF_MARKET_SCROLL: 已保存到 ${outFile.path}');
    } catch (e) {
      debugPrint('PERF_MARKET_SCROLL: 保存文件失败: $e');
    }

    // 基本断言：确实采集到帧，且构建耗时在合理范围（debug 桌面端，阈值宽松）
    final frameCount = (data['frame_count'] as num?) ?? 0;
    final avgBuild =
        (data['average_frame_build_time_millis'] as num?) ?? 0;
    final avgRaster =
        (data['average_frame_rasterizer_time_millis'] as num?) ?? 0;
    expect(frameCount, greaterThan(0), reason: '未采集到帧时间数据');
    expect(avgBuild, lessThan(100), reason: '平均帧构建耗时过高');
    expect(avgRaster, lessThan(200), reason: '平均帧光栅化耗时过高');
  });
}
