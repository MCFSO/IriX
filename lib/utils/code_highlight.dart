import 'package:flutter/material.dart';

const _cyan = Color(0xFF79C0FF);
const _green = Color(0xFFA5D6A7);
const _orange = Color(0xFFFFAB70);
const _grey = Color(0xFF8B949E);
const _yellow = Color(0xFFFFD700);

final _commentStyle = TextStyle(color: _grey, fontStyle: FontStyle.italic);
final _keyStyle = TextStyle(color: _cyan);
final _stringStyle = TextStyle(color: _green);
final _numberStyle = TextStyle(color: _orange);
final _sectionStyle = TextStyle(color: _yellow);

class _Token {
  final int start;
  final int end;
  final TextStyle style;
  _Token(this.start, this.end, this.style);
}

TextSpan highlightCode(
  String content,
  String? fileName, {
  TextStyle? baseStyle,
}) {
  if (content.isEmpty) {
    return TextSpan(text: content, style: baseStyle);
  }
  final language = _detectLanguage(fileName);
  switch (language) {
    case 'yaml':
      return _highlightYaml(content, baseStyle);
    case 'properties':
      return _highlightProperties(content, baseStyle);
    case 'json':
      return _highlightJson(content, baseStyle);
    case 'toml':
      return _highlightToml(content, baseStyle);
    default:
      return TextSpan(text: content, style: baseStyle);
  }
}

String? _detectLanguage(String? fileName) {
  if (fileName == null) return null;
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.yml') || lower.endsWith('.yaml')) return 'yaml';
  if (lower.endsWith('.properties')) return 'properties';
  if (lower.endsWith('.json')) return 'json';
  if (lower.endsWith('.toml')) return 'toml';
  return null;
}

TextSpan _highlightYaml(String content, TextStyle? baseStyle) {
  final tokens = <_Token>[];

  for (final m in RegExp(
    r"'[^']*'"
    r'|"'
    r'[^"]*"',
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _stringStyle));
  }

  for (final m in RegExp(r'#.*$', multiLine: true).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _commentStyle));
  }

  for (final m in RegExp(
    r'^([ \t]*)([\w][\w.\-]*)\s*(:)',
    multiLine: true,
  ).allMatches(content)) {
    final indentLen = m.group(1)!.length;
    final keyLen = m.group(2)!.length;
    final keyStart = m.start + indentLen;
    tokens.add(_Token(keyStart, keyStart + keyLen, _keyStyle));
  }

  for (final m in RegExp(r'\b\d+\.?\d*\b').allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  for (final m in RegExp(
    r'\b(?:true|false|yes|no|on|off|null|~)\b',
    caseSensitive: false,
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  return _buildSpan(content, tokens, baseStyle);
}

TextSpan _highlightProperties(String content, TextStyle? baseStyle) {
  final tokens = <_Token>[];

  for (final m in RegExp(
    r'^[ \t]*[#!].*$',
    multiLine: true,
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _commentStyle));
  }

  for (final m in RegExp(
    r'^([ \t]*)([^=:\s]+)\s*[=:]\s*(.*)$',
    multiLine: true,
  ).allMatches(content)) {
    final indentLen = m.group(1)!.length;
    final keyLen = m.group(2)!.length;
    final keyStart = m.start + indentLen;
    tokens.add(_Token(keyStart, keyStart + keyLen, _keyStyle));

    final valueStart = m.start + m.group(0)!.length - m.group(3)!.length;
    if (m.group(3)!.isNotEmpty) {
      tokens.add(_Token(valueStart, m.end, _stringStyle));
    }
  }

  return _buildSpan(content, tokens, baseStyle);
}

TextSpan _highlightJson(String content, TextStyle? baseStyle) {
  final tokens = <_Token>[];

  for (final m in RegExp(
    r'"(?:[^"\\]'
    r'|\\.)*"\s*:',
  ).allMatches(content)) {
    final colonIdx = m.group(0)!.indexOf(':');
    tokens.add(_Token(m.start, m.start + colonIdx, _keyStyle));
  }

  for (final m in RegExp(
    r'"(?:[^"\\]'
    r'|\\.)*"',
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _stringStyle));
  }

  for (final m in RegExp(r'\b\d+\.?\d*\b').allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  for (final m in RegExp(
    r'\b(?:true|false|null)\b',
    caseSensitive: false,
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  return _buildSpan(content, tokens, baseStyle);
}

TextSpan _highlightToml(String content, TextStyle? baseStyle) {
  final tokens = <_Token>[];

  for (final m in RegExp(
    r'^[ \t]*\[[^\]]+\]',
    multiLine: true,
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _sectionStyle));
  }

  for (final m in RegExp(r'#.*$', multiLine: true).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _commentStyle));
  }

  for (final m in RegExp(
    r'"(?:[^"\\]'
    r'|\\.)*"',
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _stringStyle));
  }

  for (final m in RegExp(
    r'^([ \t]*)([\w][\w.\-]*)\s*=\s*',
    multiLine: true,
  ).allMatches(content)) {
    final indentLen = m.group(1)!.length;
    final keyLen = m.group(2)!.length;
    final keyStart = m.start + indentLen;
    tokens.add(_Token(keyStart, keyStart + keyLen, _keyStyle));
  }

  for (final m in RegExp(r'\b\d+\.?\d*\b').allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  for (final m in RegExp(
    r'\b(?:true|false)\b',
    caseSensitive: false,
  ).allMatches(content)) {
    tokens.add(_Token(m.start, m.end, _numberStyle));
  }

  return _buildSpan(content, tokens, baseStyle);
}

TextSpan _buildSpan(String content, List<_Token> tokens, TextStyle? baseStyle) {
  tokens.sort((a, b) => a.start.compareTo(b.start));

  final clean = <_Token>[];
  var lastEnd = 0;
  for (final token in tokens) {
    if (token.start >= lastEnd) {
      clean.add(token);
      lastEnd = token.end;
    }
  }

  final children = <TextSpan>[];
  var pos = 0;
  for (final token in clean) {
    if (token.start > pos) {
      children.add(TextSpan(text: content.substring(pos, token.start)));
    }
    children.add(
      TextSpan(
        text: content.substring(token.start, token.end),
        style: baseStyle?.merge(token.style) ?? token.style,
      ),
    );
    pos = token.end;
  }
  if (pos < content.length) {
    children.add(TextSpan(text: content.substring(pos)));
  }

  return TextSpan(style: baseStyle, children: children);
}

class HighlightTextEditingController extends TextEditingController {
  HighlightTextEditingController({super.text, this.fileName});

  String? fileName;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final textValue = text;
    if (textValue.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return highlightCode(textValue, fileName, baseStyle: style);
  }
}
