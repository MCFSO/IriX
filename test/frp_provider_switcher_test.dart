// FRP 提供商切换胶囊布局测试：
// 1. 鼠标悬浮高亮必须铺满整块圆角背景（InkWell 的区域 == Material 胶囊区域）；
// 2. 左右内边距区域也能点亮高亮、也能点击展开菜单；
// 3. 高亮不会溢出胶囊之外。

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/frp_provider.dart';
import 'package:irix/widgets/frp_provider_switcher.dart';

void main() {
  final boundaryKey = GlobalKey();

  /// 读取整屏渲染结果中某个全局坐标处的像素颜色。
  ///
  /// `toImage` 要走引擎的光栅线程，必须放在 [WidgetTester.runAsync] 里，
  /// 否则在 widget test 的伪异步时钟下永远不会完成。
  Future<Color> pixelAt(WidgetTester tester, Offset position) async {
    Color? color;
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final i = (position.dy.round() * image.width + position.dx.round()) * 4;
        color = Color.fromARGB(
          bytes[i + 3],
          bytes[i],
          bytes[i + 1],
          bytes[i + 2],
        );
      } finally {
        image.dispose();
      }
    });
    return color!;
  }

  /// 渲染仅含提供商切换栏的 AppBar，返回胶囊矩形。
  Future<Rect> pumpSwitcher(
    WidgetTester tester, {
    ValueChanged<String>? onChanged,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(
              title: FrpProviderSwitcher(
                providerId: FrpProviderKind.openfrp.id,
                onChanged: onChanged ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(FrpProviderSwitcher));
  }

  /// 悬浮/点击区域（InkWell）与背景（Material 胶囊）必须完全重合。
  testWidgets('悬浮高亮区域与圆角背景完全重合', (tester) async {
    await pumpSwitcher(tester);

    final pillFinder = find.descendant(
      of: find.byType(FrpProviderSwitcher),
      matching: find.byType(Material),
    );
    expect(pillFinder, findsOneWidget);
    final inkWellFinder = find.descendant(
      of: pillFinder,
      matching: find.byType(InkWell),
    );
    expect(inkWellFinder, findsOneWidget);

    final pillSize = tester.getSize(pillFinder);
    final inkSize = tester.getSize(inkWellFinder);
    // 修复前内边距套在 DropdownButton 外层，高亮区域比胶囊左右各窄 10。
    expect(inkSize.width, pillSize.width);
    expect(inkSize.height, pillSize.height);
    expect(tester.getTopLeft(inkWellFinder), tester.getTopLeft(pillFinder));

    const radius = Radius.circular(FrpProviderSwitcher.radius);
    expect(tester.widget<Material>(pillFinder).borderRadius, const BorderRadius.all(radius));
    expect(tester.widget<InkWell>(inkWellFinder).borderRadius, const BorderRadius.all(radius));
  });

  testWidgets('鼠标悬浮时高亮铺满整块胶囊（含左右内边距）', (tester) async {
    final pill = await pumpSwitcher(tester);

    // 采样点：左右内边距内各一点（距边缘 3px、垂直居中），以及胶囊外一点。
    final leftProbe = Offset(pill.left + 3, pill.center.dy);
    final rightProbe = Offset(pill.right - 3, pill.center.dy);
    final outsideProbe = Offset(pill.left - 4, pill.center.dy);

    final leftBefore = await pixelAt(tester, leftProbe);
    final rightBefore = await pixelAt(tester, rightProbe);
    final outsideBefore = await pixelAt(tester, outsideProbe);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(pill.center);
    await tester.pumpAndSettle();

    final leftAfter = await pixelAt(tester, leftProbe);
    final rightAfter = await pixelAt(tester, rightProbe);
    final outsideAfter = await pixelAt(tester, outsideProbe);

    // 左右内边距区域被悬浮高亮点亮（修复前这两处保持背景色不变）。
    expect(
      leftAfter.computeLuminance(),
      greaterThan(leftBefore.computeLuminance()),
      reason: '左内边距区域应被悬浮高亮覆盖',
    );
    expect(
      rightAfter.computeLuminance(),
      greaterThan(rightBefore.computeLuminance()),
      reason: '右内边距区域应被悬浮高亮覆盖',
    );
    // 高亮被圆角裁剪，不会溢到胶囊外。
    expect(outsideAfter, outsideBefore);
  });

  testWidgets('点击胶囊内边距区域也能展开菜单并回调', (tester) async {
    String? picked;
    final pill = await pumpSwitcher(tester, onChanged: (v) => picked = v);

    await tester.tapAt(Offset(pill.left + 3, pill.center.dy));
    await tester.pumpAndSettle();

    final item = find.text(FrpProviderKind.custom.label);
    expect(item, findsOneWidget, reason: '菜单应已展开');

    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(picked, FrpProviderKind.custom.id);
  });
}
