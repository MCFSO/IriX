// 日志解析服务测试：覆盖 .log 读取与 .log.gz 解压、行数与截断逻辑。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/log_parser.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_log_parser_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('解析普通 .log 文件', () async {
    final file = File('${tempDir.path}/latest.log');
    await file.writeAsString('2024-01-01 10:00:00 [INFO] Server started\n'
        '2024-01-01 10:00:01 [WARN] low memory\n'
        '2024-01-01 10:00:02 [ERROR] crash detected');

    final parsed = await parseServerLog(file.path);
    expect(parsed.fileName, 'latest.log');
    expect(parsed.compressed, isFalse);
    expect(parsed.lineCount, 3);
    expect(parsed.truncated, isFalse);
    expect(parsed.content, contains('[ERROR] crash detected'));
    expect(parsed.sizeLabel, contains('B'));
  });

  test('解析 .log.gz 并自动解压', () async {
    final plain = 'line one\nline two\nline three\n';
    final gzPath = '${tempDir.path}/debug.log.gz';
    final gzFile = File(gzPath);
    await gzFile.writeAsBytes(gzip.encode(plain.codeUnits));

    final parsed = await parseServerLog(gzPath);
    expect(parsed.fileName, 'debug.log.gz');
    expect(parsed.compressed, isTrue);
    expect(parsed.lineCount, 3);
    expect(parsed.content, 'line one\nline two\nline three\n');
  });

  test('超长日志截断并保留末尾', () async {
    final lines = [for (var i = 0; i < 1000; i++) 'log line $i ... 填充内容'];
    final file = File('${tempDir.path}/big.log');
    await file.writeAsString(lines.join('\n'));

    final parsed = await parseServerLog(file.path, maxChars: 200);
    expect(parsed.truncated, isTrue);
    expect(parsed.lineCount, 1000);
    expect(parsed.content.length, lessThanOrEqualTo(200));
    expect(parsed.content, contains('log line 999'));
    // 解压后的 AI 消息应包含格式信息。
    final message = buildLogAiMessage(parsed, instanceName: '我的服务器');
    expect(message, contains('big.log'));
    expect(message, contains('我的服务器'));
    expect(message, contains('1000'));
    expect(message, contains('--- 日志内容开始 ---'));
    expect(message, contains('--- 日志内容结束 ---'));
  });

  test('不存在的文件抛出异常', () async {
    expect(
      () => parseServerLog('${tempDir.path}/missing.log'),
      throwsA(isA<FileSystemException>()),
    );
  });
}