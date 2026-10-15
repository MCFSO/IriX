// 侧边栏索引映射的单元测试
//
// 背景：单机 7 项（0..6，插件在 6）与多机 9 项（0..8，插件在 8）项数不同、
// 前段顺序也不同（多机多出「容器」「编排」）。切换模式时必须保证：
//   1. 索引不越界（否则内容区取到错误页面）
//   2. 「插件」在切换后仍指向插件（不能被 clamp 到别的页面）
//
// 这里复刻 HomeScreen._resolveIndex 的逻辑做纯函数验证，
// 避免依赖 widget 树。

import 'package:flutter_test/flutter_test.dart';

/// 复刻 _HomeScreenState._resolveIndex。
int resolveIndex({
  required bool multi,
  required int length,
  required int selectedIndex,
  required bool lastModeWasMulti,
}) {
  final maxIndex = length - 1;
  final lastIndexWasPlugin = lastModeWasMulti
      ? selectedIndex == 8
      : selectedIndex == 6;

  if (multi) {
    if (lastIndexWasPlugin) return maxIndex;
    return selectedIndex.clamp(0, maxIndex);
  }
  if (selectedIndex == 8) return maxIndex;
  return selectedIndex.clamp(0, maxIndex);
}

void main() {
  const singleLen = 7; // 0..6，插件 = 6
  const multiLen = 9; // 0..8，插件 = 8

  group('单机模式', () {
    test('普通索引原样保留', () {
      for (var i = 0; i < singleLen; i++) {
        expect(
          resolveIndex(
            multi: false,
            length: singleLen,
            selectedIndex: i,
            lastModeWasMulti: false,
          ),
          i,
        );
      }
    });

    test('从多机(8=插件)切回单机仍指向插件', () {
      expect(
        resolveIndex(
          multi: false,
          length: singleLen,
          selectedIndex: 8,
          lastModeWasMulti: true,
        ),
        singleLen - 1,
      );
    });

    test('越界索引被收敛到末项', () {
      expect(
        resolveIndex(
          multi: false,
          length: singleLen,
          selectedIndex: 99,
          lastModeWasMulti: false,
        ),
        singleLen - 1,
      );
    });
  });

  group('多机模式', () {
    test('从未越界的多机索引原样保留', () {
      for (var i = 0; i < multiLen; i++) {
        expect(
          resolveIndex(
            multi: true,
            length: multiLen,
            selectedIndex: i,
            lastModeWasMulti: true,
          ),
          i,
          reason: 'index $i 在多机模式下应保持不变',
        );
      }
    });

    test('从单机(6=插件)切到多机仍指向插件', () {
      expect(
        resolveIndex(
          multi: true,
          length: multiLen,
          selectedIndex: 6,
          lastModeWasMulti: false,
        ),
        multiLen - 1,
      );
    });

    test('单机普通索引切到多机后不越界', () {
      for (var i = 0; i < singleLen - 1; i++) {
        final r = resolveIndex(
          multi: true,
          length: multiLen,
          selectedIndex: i,
          lastModeWasMulti: false,
        );
        expect(r, inInclusiveRange(0, multiLen - 1));
      }
    });
  });

  group('回归：插件页在切换后始终可达', () {
    test('单机 → 多机 → 单机 往返后仍是插件', () {
      // 单机下选中插件（6）
      final toMulti = resolveIndex(
        multi: true,
        length: multiLen,
        selectedIndex: 6,
        lastModeWasMulti: false,
      );
      expect(toMulti, multiLen - 1, reason: '切到多机应停在插件');

      // 再切回单机（上次是多机、索引 8 = 插件）
      final backToSingle = resolveIndex(
        multi: false,
        length: singleLen,
        selectedIndex: toMulti,
        lastModeWasMulti: true,
      );
      expect(backToSingle, singleLen - 1, reason: '切回单机仍是插件');
    });
  });
}
