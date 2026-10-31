// 流式装箱（FlowPacker）单元测试
//
// 覆盖：空列表、单行装满、跨行换行、间距计算、超宽条目独占一行、顺序保持。

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/utils/flow_packer.dart';

void main() {
  group('FlowPacker.pack', () {
    test('空列表返回空行集', () {
      expect(
        FlowPacker.pack(const [], maxWidth: 100, spacing: 8),
        isEmpty,
      );
    });

    test('全部放得下时只有一行', () {
      // 30*3 + 8*2 = 106 ≤ 110
      final rows = FlowPacker.pack(
        [30, 30, 30],
        maxWidth: 110,
        spacing: 8,
      );
      expect(rows.length, 1);
      expect(rows.first, [0, 1, 2]);
    });

    test('放不下时换行且保持顺序', () {
      // 40 + 8 + 40 = 88 ≤ 100；再加 40 需要 136 > 100
      final rows = FlowPacker.pack(
        [40, 40, 40],
        maxWidth: 100,
        spacing: 8,
      );
      expect(rows, [
        [0, 1],
        [2],
      ]);
    });

    test('刚好等于容器宽度时不分行', () {
      // 46 + 8 + 46 = 100
      final rows = FlowPacker.pack(
        [46, 46],
        maxWidth: 100,
        spacing: 8,
      );
      expect(rows.length, 1);
    });

    test('超出 1px 即换行', () {
      final rows = FlowPacker.pack(
        [46, 47],
        maxWidth: 100,
        spacing: 8,
      );
      expect(rows, [
        [0],
        [1],
      ]);
    });

    test('超宽条目独占一行且不丢项', () {
      final rows = FlowPacker.pack(
        [200, 30],
        maxWidth: 100,
        spacing: 8,
      );
      expect(rows, [
        [0],
        [1],
      ]);
      expect(rows.expand((r) => r).toList(), [0, 1]);
    });

    test('间距为 0 时按纯宽度装箱', () {
      final rows = FlowPacker.pack(
        [50, 50, 50],
        maxWidth: 100,
        spacing: 0,
      );
      expect(rows, [
        [0, 1],
        [2],
      ]);
    });
  });
}
