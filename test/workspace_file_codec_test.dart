import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/workspace_file_codec.dart';

void main() {
  test('text encodings and original line endings round trip', () {
    final samples = <List<int>>[
      utf8.encode('server-port=25565\r\n欢迎'),
      [0xef, 0xbb, 0xbf, ...utf8.encode('hello\nworld')],
      [0xff, 0xfe, 0x41, 0x00, 0x0d, 0x00, 0x0a, 0x00],
      [0xfe, 0xff, 0x00, 0x41, 0x00, 0x0a],
    ];
    for (final bytes in samples) {
      final content = WorkspaceFileContent.decode(bytes);
      expect(content.isHex, isFalse);
      expect(content.encode(content.text), bytes);
    }
  });

  test('binary content and invalid UTF-16 stay editable as exact bytes', () {
    final samples = <List<int>>[
      [0x00, 0xff, 0x7f, 0x0a],
      [0xff, 0xfe, 0x01],
      [0x01, 0x02, 0x03],
    ];
    for (final bytes in samples) {
      final content = WorkspaceFileContent.decode(bytes);
      expect(content.isHex, isTrue);
      expect(content.encode(content.text), bytes);
    }
  });

  test('hex editor accepts whitespace and rejects malformed bytes', () {
    final content = WorkspaceFileContent.decode([0x00, 0xff]);
    expect(content.encode('DE AD\nBE EF'), [0xde, 0xad, 0xbe, 0xef]);
    expect(() => content.encode('ABC'), throwsFormatException);
    expect(() => content.encode('GG'), throwsFormatException);
  });
}
