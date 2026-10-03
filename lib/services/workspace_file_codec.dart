import 'dart:convert';
import 'dart:typed_data';

/// An editable view of a file. Unknown encodings remain byte accurate in hex mode.
enum WorkspaceEncoding { utf8, utf8Bom, utf16Le, utf16Be, hex }

class WorkspaceFileContent {
  const WorkspaceFileContent(this.text, this.encoding);

  final String text;
  final WorkspaceEncoding encoding;

  bool get isHex => encoding == WorkspaceEncoding.hex;

  static WorkspaceFileContent decode(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      try {
        return WorkspaceFileContent(
          _decodeUtf16(bytes, true),
          WorkspaceEncoding.utf16Le,
        );
      } on FormatException {
        return WorkspaceFileContent(_hex(bytes), WorkspaceEncoding.hex);
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      try {
        return WorkspaceFileContent(
          _decodeUtf16(bytes, false),
          WorkspaceEncoding.utf16Be,
        );
      } on FormatException {
        return WorkspaceFileContent(_hex(bytes), WorkspaceEncoding.hex);
      }
    }
    final bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    try {
      final value = utf8.decode(bytes.skip(bom ? 3 : 0).toList());
      if (value.runes.any(
        (rune) => rune < 32 && rune != 9 && rune != 10 && rune != 13,
      )) {
        throw const FormatException('Binary content');
      }
      return WorkspaceFileContent(
        value,
        bom ? WorkspaceEncoding.utf8Bom : WorkspaceEncoding.utf8,
      );
    } on FormatException {
      return WorkspaceFileContent(_hex(bytes), WorkspaceEncoding.hex);
    }
  }

  List<int> encode(String value) {
    switch (encoding) {
      case WorkspaceEncoding.utf8:
        return utf8.encode(value);
      case WorkspaceEncoding.utf8Bom:
        return [0xef, 0xbb, 0xbf, ...utf8.encode(value)];
      case WorkspaceEncoding.utf16Le:
      case WorkspaceEncoding.utf16Be:
        final little = encoding == WorkspaceEncoding.utf16Le;
        final result = <int>[
          if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff],
        ];
        for (final unit in value.codeUnits) {
          result.addAll(
            little ? [unit & 0xff, unit >> 8] : [unit >> 8, unit & 0xff],
          );
        }
        return result;
      case WorkspaceEncoding.hex:
        final compact = value.replaceAll(RegExp(r'\s'), '');
        if (compact.length.isOdd ||
            !RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
          throw const FormatException('十六进制内容只能包含 0-9、A-F，且每个字节必须有两位');
        }
        return Uint8List.fromList([
          for (var i = 0; i < compact.length; i += 2)
            int.parse(compact.substring(i, i + 2), radix: 16),
        ]);
    }
  }

  static String _decodeUtf16(List<int> bytes, bool little) {
    if (bytes.length.isOdd) {
      throw const FormatException('Invalid UTF-16 length');
    }
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static String _hex(List<int> bytes) {
    final lines = <String>[];
    for (var i = 0; i < bytes.length; i += 16) {
      lines.add(
        bytes
            .skip(i)
            .take(16)
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' '),
      );
    }
    return lines.join('\n');
  }
}
