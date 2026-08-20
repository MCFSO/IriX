// ANSI 转义序列解析单元测试
// 覆盖：纯文本、前景色、加粗/下划线、256 色、状态累积、stripAnsi。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/utils/ansi_color.dart';

void main() {
  const base = TextStyle(fontSize: 12, color: Colors.white);

  group('ansiSpans', () {
    test('无 ANSI 序列时返回单个 span', () {
      final spans = ansiSpans('Hello world', base);
      expect(spans.length, 1);
      expect(spans.single.text, 'Hello world');
      expect(spans.single.style?.color, Colors.white);
    });

    test('31m 红色前景', () {
      final spans = ansiSpans('\x1B[31mred\x1B[0m', base);
      expect(spans.length, 1);
      expect(spans[0].text, 'red');
      expect(spans[0].style?.color, isNot(Colors.white));
    });

    test('红色 + 加粗状态累积（\x1B[31m 后接 \x1B[1m）', () {
      final spans = ansiSpans(
        '\x1B[31mred \x1B[1mbold red\x1B[0m plain',
        base,
      );
      expect(spans.length, 3);
      expect(spans[0].text, 'red ');
      expect(spans[0].style?.color, isNot(Colors.white));
      expect(spans[0].style?.fontWeight, isNot(FontWeight.bold));
      expect(spans[1].text, 'bold red');
      expect(spans[1].style?.fontWeight, FontWeight.bold);
      expect(spans[1].style?.color, isNot(Colors.white));
      expect(spans[2].text, ' plain');
      expect(spans[2].style?.color, Colors.white);
      expect(spans[2].style?.fontWeight, isNot(FontWeight.bold));
    });

    test('4m 下划线 + 39m 恢复默认前景', () {
      final spans = ansiSpans('\x1B[4munderline\x1B[39m', base);
      expect(spans.length, 1);
      expect(spans[0].style?.decoration, TextDecoration.underline);
      expect(spans[0].style?.color, Colors.white);
    });

    test('256 色 38;5;196m', () {
      final spans = ansiSpans('\x1B[38;5;196mred\x1B[0m', base);
      expect(spans.first.style?.color, const Color(0xFFFF0000));
    });

    test('亮色 91m', () {
      final spans = ansiSpans('\x1B[91mbright\x1B[0m', base);
      expect(spans.first.style?.color, isNot(Colors.white));
    });

    test('空行', () {
      expect(ansiSpans('', base).length, 1);
    });
  });

  group('stripAnsi', () {
    test('去除颜色与样式序列', () {
      expect(
        stripAnsi('\x1B[31mred\x1B[0m \x1B[1mbold\x1B[0m'),
        'red bold',
      );
    });

    test('去除 256 色序列', () {
      expect(stripAnsi('\x1B[38;5;196mX\x1B[0m'), 'X');
    });

    test('无 ANSI 文本保持不变', () {
      expect(stripAnsi('plain text'), 'plain text');
    });
  });
}
