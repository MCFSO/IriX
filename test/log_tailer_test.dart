// LogFileTailer 单元测试
// 覆盖：实时尾随、CRLF 行处理、UTF-8 解码、启动位置（不重复推送旧内容）、
// 历史回放（readRecentLines）与文件截断恢复。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/log_tailer.dart';

void main() {
  late Directory tempDir;
  late String logPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_tailer_test');
    logPath = '${tempDir.path}/test.log';
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 收集流中未来 [count] 行（带超时保护）。
  Future<List<String>> collectLines(Stream<String> stream, int count) async {
    final lines = <String>[];
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = stream.listen((line) {
      lines.add(line);
      if (lines.length >= count && !completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await sub.cancel();
    return lines;
  }

  test('实时尾随：启动后新增的行按行推送', () async {
    final tailer = LogFileTailer(logPath);
    await tailer.start();
    final future = collectLines(tailer.stream, 2);
    await File(logPath).writeAsString('hello\nworld\n', mode: FileMode.append);
    final lines = await future;
    expect(lines, equals(['hello', 'world']));
    tailer.dispose();
  });

  test('CRLF 行尾的 \\r 被去除', () async {
    final tailer = LogFileTailer(logPath);
    await tailer.start();
    final future = collectLines(tailer.stream, 2);
    await File(logPath).writeAsString('a\r\nb\r\n', mode: FileMode.append);
    final lines = await future;
    expect(lines, equals(['a', 'b']));
    tailer.dispose();
  });

  test('UTF-8 多字节内容正确解码', () async {
    final tailer = LogFileTailer(logPath);
    await tailer.start();
    final future = collectLines(tailer.stream, 1);
    await File(
      logPath,
    ).writeAsString('服务器输出 ✦ 你好\n', mode: FileMode.append);
    final lines = await future;
    expect(lines, equals(['服务器输出 ✦ 你好']));
    tailer.dispose();
  });

  test('启动位置为文件末尾：既有内容不重复推送', () async {
    await File(logPath).writeAsString('old\n');
    final tailer = LogFileTailer(logPath);
    await tailer.start();
    final future = collectLines(tailer.stream, 1);
    await File(logPath).writeAsString('new\n', mode: FileMode.append);
    final lines = await future;
    expect(lines, equals(['new']));
    tailer.dispose();
  });

  test('readRecentLines 返回尾部指定行数', () async {
    await File(logPath).writeAsString('l1\nl2\nl3\nl4\n');
    final tailer = LogFileTailer(logPath);
    final lines = await tailer.readRecentLines(2);
    expect(lines, equals(['l3', 'l4']));
    tailer.dispose();
  });

  test('readRecentLines 行数不足时返回全部', () async {
    await File(logPath).writeAsString('l1\nl2\n');
    final tailer = LogFileTailer(logPath);
    final lines = await tailer.readRecentLines(10);
    expect(lines, equals(['l1', 'l2']));
    tailer.dispose();
  });

  test('文件被截断后从新内容继续推送', () async {
    final tailer = LogFileTailer(logPath);
    await tailer.start();
    await File(logPath).writeAsString('aaaa\nbbbb\n', mode: FileMode.append);
    // 等待轮询读掉旧内容。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final future = collectLines(tailer.stream, 1);
    // 覆盖写入（截断）后仅剩新内容。
    await File(logPath).writeAsString('cccc\n');
    final lines = await future;
    expect(lines, equals(['cccc']));
    tailer.dispose();
  });
}
