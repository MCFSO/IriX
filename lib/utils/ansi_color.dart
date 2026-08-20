// ANSI 转义序列解析与渲染
// 将 Minecraft 服务端（Paper / Spigot 等启用 ANSI 输出时）日志中的
// SGR 转义序列解析为 Flutter TextSpan，实现彩色控制台显示；
// stripAnsi 用于写日志文件等纯文本场景时去除控制字符。

import 'package:flutter/painting.dart';

/// ANSI CSI 序列正则（用于从纯文本中剔除控制字符）。
final RegExp _ansiRegex = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

/// SGR 颜色序列正则（`ESC [ params m`）。
final RegExp _sgrRegex = RegExp(r'\x1B\[([0-9;]*)m');

/// 去除字符串中的全部 ANSI 转义序列。
String stripAnsi(String input) => input.replaceAll(_ansiRegex, '');

/// 标准 16 色调色板（0-7 暗色，8-15 亮色，与常见终端一致）。
const List<Color> _ansiPalette = [
  Color(0xFF1E1E1E), // 30 black
  Color(0xFFCD3131), // 31 red
  Color(0xFF0DBC79), // 32 green
  Color(0xFFE5E510), // 33 yellow
  Color(0xFF2472C8), // 34 blue
  Color(0xFFBC3FBC), // 35 magenta
  Color(0xFF11A8CD), // 36 cyan
  Color(0xFFE5E5E5), // 37 white
  Color(0xFF666666), // 90 bright black
  Color(0xFFF14C4C), // 91 bright red
  Color(0xFF23D18B), // 92 bright green
  Color(0xFFF5F543), // 93 bright yellow
  Color(0xFF3B8EEA), // 94 bright blue
  Color(0xFFD670D6), // 95 bright magenta
  Color(0xFF29B8DB), // 96 bright cyan
  Color(0xFFFFFFFF), // 97 bright white
];

/// 将 256 色索引映射为颜色：
/// 0-15 基本色；16-231 为 6x6x6 立方体；232-255 灰度。
Color _color256(int index) {
  if (index < 16) return _ansiPalette[index];
  if (index < 232) {
    index -= 16;
    int level(int v) => v == 0 ? 0 : 55 + v * 40;
    return Color.fromARGB(
      255,
      level(index ~/ 36),
      level((index % 36) ~/ 6),
      level(index % 6),
    );
  }
  final gray = 8 + (index - 232) * 10;
  return Color.fromARGB(255, gray, gray, gray);
}

/// 当前 SGR 状态（随序列逐步累积）。
class _SgrState {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  Color? fg;
  Color? bg;

  /// 应用一个 SGR 参数序列（`38;5;n` 等多参数指令按段消费）。
  void apply(List<int> params) {
    var i = 0;
    while (i < params.length) {
      final code = params[i];
      if (code == 0) {
        bold = false;
        italic = false;
        underline = false;
        fg = null;
        bg = null;
      } else if (code == 1) {
        bold = true;
      } else if (code == 3) {
        italic = true;
      } else if (code == 4) {
        underline = true;
      } else if (code == 22) {
        bold = false;
      } else if (code == 23) {
        italic = false;
      } else if (code == 24) {
        underline = false;
      } else if (code >= 30 && code <= 37) {
        fg = _ansiPalette[code - 30];
      } else if (code >= 90 && code <= 97) {
        fg = _ansiPalette[code - 90 + 8];
      } else if (code >= 40 && code <= 47) {
        bg = _ansiPalette[code - 40];
      } else if (code >= 100 && code <= 107) {
        bg = _ansiPalette[code - 100 + 8];
      } else if (code == 39) {
        fg = null;
      } else if (code == 49) {
        bg = null;
      } else if (code == 38 && i + 1 < params.length) {
        // 前景：38;5;n 或 38;2;r;g;b
        final mode = params[i + 1];
        if (mode == 5 && i + 2 < params.length) {
          fg = _color256(params[i + 2]);
          i += 2;
        } else if (mode == 2 && i + 4 < params.length) {
          fg = Color.fromARGB(
            255,
            params[i + 2].clamp(0, 255),
            params[i + 3].clamp(0, 255),
            params[i + 4].clamp(0, 255),
          );
          i += 4;
        }
      } else if (code == 48 && i + 1 < params.length) {
        // 背景：48;5;n 或 48;2;r;g;b
        final mode = params[i + 1];
        if (mode == 5 && i + 2 < params.length) {
          bg = _color256(params[i + 2]);
          i += 2;
        } else if (mode == 2 && i + 4 < params.length) {
          bg = Color.fromARGB(
            255,
            params[i + 2].clamp(0, 255),
            params[i + 3].clamp(0, 255),
            params[i + 4].clamp(0, 255),
          );
          i += 4;
        }
      }
      i++;
    }
  }
}

/// 将一行日志（可能含 ANSI SGR 序列）解析为 [TextSpan] 列表。
///
/// [baseStyle] 为默认文本样式；序列中的颜色 / 加粗 / 斜体 / 下划线会覆盖之。
/// 无 ANSI 序列时返回单个 span，行为与原样文本一致。
List<TextSpan> ansiSpans(String line, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  if (!line.contains('\x1B[')) {
    return [TextSpan(text: line, style: baseStyle)];
  }
  final state = _SgrState();
  var pos = 0;
  for (final match in _sgrRegex.allMatches(line)) {
    if (match.start > pos) {
      spans.add(_span(line.substring(pos, match.start), baseStyle, state));
    }
    final params = match
        .group(1)!
        .split(';')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    if (params.isEmpty) params.add(0);
    state.apply(params);
    pos = match.end;
  }
  if (pos < line.length) {
    spans.add(_span(line.substring(pos), baseStyle, state));
  }
  if (spans.isEmpty) {
    return [TextSpan(text: line, style: baseStyle)];
  }
  return spans;
}

TextSpan _span(String text, TextStyle baseStyle, _SgrState state) {
  return TextSpan(
    text: text,
    style: baseStyle.copyWith(
      color: state.fg ?? baseStyle.color,
      backgroundColor: state.bg,
      fontWeight: state.bold
          ? FontWeight.bold
          : (baseStyle.fontWeight ?? FontWeight.normal),
      fontStyle: state.italic
          ? FontStyle.italic
          : (baseStyle.fontStyle ?? FontStyle.normal),
      decoration: state.underline
          ? TextDecoration.underline
          : baseStyle.decoration,
    ),
  );
}
