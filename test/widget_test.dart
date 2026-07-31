// IriX 冒烟测试
// 验证应用根组件 MyApp 能够正常构建，不引用尚未创建的界面/状态。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/main.dart';

void main() {
  testWidgets('MyApp 能够正常构建', (WidgetTester tester) async {
    // 构建应用并触发一帧，期望不抛出异常。
    expect(() => tester.pumpWidget(const MyApp()), returnsNormally);
  });
}
