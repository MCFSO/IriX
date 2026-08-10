// 日志文件解析服务
// 读取 .log / .log.gz 文件（gzip 自动解压），统计元信息，
// 并生成带格式信息的、可直接发送给 AI 的消息文本。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析后的日志元信息与内容。
class ParsedLog {
  final String path;
  final String fileName;

  /// 是否为 .log.gz 压缩文件。
  final bool compressed;

  /// 磁盘上的文件大小（字节）。
  final int fileSizeBytes;

  /// 解压后的总行数。
  final int lineCount;

  /// 内容是否因超过长度限制而被截断（保留末尾）。
  final bool truncated;

  /// 实际发送的日志内容。
  final String content;

  const ParsedLog({
    required this.path,
    required this.fileName,
    required this.compressed,
    required this.fileSizeBytes,
    required this.lineCount,
    required this.truncated,
    required this.content,
  });

  /// 人类可读的文件大小。
  String get sizeLabel {
    const kb = 1024.0;
    const mb = 1024 * 1024.0;
    if (fileSizeBytes >= mb) {
      return '${(fileSizeBytes / mb).toStringAsFixed(2)} MB';
    }
    if (fileSizeBytes >= kb) {
      return '${(fileSizeBytes / kb).toStringAsFixed(1)} KB';
    }
    return '$fileSizeBytes B';
  }
}

/// 读取并解析日志文件（.log 或 .log.gz，后者自动解压）。
///
/// 流式读取，内存占用有界（仅保留末尾 [maxChars] 字符），
/// 超长文件只保留末尾部分（崩溃与严重错误通常出现在日志末尾）。
Future<ParsedLog> parseServerLog(String path, {int maxChars = 20000}) async {
  final file = File(path);
  if (!await file.exists()) {
    throw FileSystemException('文件不存在', path);
  }
  final fileSize = await file.length();
  final fileName = p.basename(path);
  final compressed = fileName.toLowerCase().endsWith('.gz');

  // 尾部滑动窗口：每次累加后若超限则裁剪开头，保证只保留末尾内容。
  final tail = StringBuffer();
  var totalChars = 0;
  var newlineCount = 0;
  var lastChar = '';

  final raw = file.openRead();
  final decoded = compressed
      ? raw.transform(gzip.decoder).transform(utf8.decoder)
      : raw.transform(utf8.decoder);
  await for (final chunk in decoded) {
    totalChars += chunk.length;
    newlineCount += '\n'.allMatches(chunk).length;
    lastChar = chunk.isEmpty ? lastChar : chunk[chunk.length - 1];
    tail.write(chunk);
    if (tail.length > maxChars) {
      final kept = tail.toString().substring(tail.length - maxChars);
      tail
        ..clear()
        ..write(kept);
    }
  }

  final content = tail.toString();
  final truncated = totalChars > maxChars;
  final lineCount = totalChars == 0
      ? 0
      : newlineCount + (lastChar == '\n' ? 0 : 1);

  return ParsedLog(
    path: path,
    fileName: fileName,
    compressed: compressed,
    fileSizeBytes: fileSize,
    lineCount: lineCount,
    truncated: truncated,
    content: content,
  );
}

/// 生成发送给 AI 的消息文本（含格式元信息与日志内容）。
String buildLogAiMessage(
  ParsedLog log, {
  String? instanceName,
  String? source,
}) {
  final buffer = StringBuffer()
    ..writeln('【日志分析请求】')
    ..writeln('文件名: ${log.fileName}')
    ..writeln('来源: ${source ?? log.path}');
  if (instanceName != null && instanceName.isNotEmpty) {
    buffer.writeln('实例: $instanceName');
  }
  buffer.writeln(
    '格式: ${log.compressed ? '.log.gz（gzip 压缩，已自动解压为纯文本）' : '.log（纯文本）'}',
  );
  buffer.writeln('文件大小: ${log.sizeLabel}');
  buffer.writeln('总行数: ${log.lineCount}');
  if (log.truncated) {
    buffer.writeln(
      '提示: 内容较长，已截断，仅保留末尾 ${log.content.length} 字符（崩溃与错误通常出现在日志末尾）。'
      '如需更多信息可调用工具继续查看。',
    );
  }
  buffer
    ..writeln()
    ..writeln('请分析以上服务器日志，找出崩溃或错误原因，并给出修复建议。')
    ..writeln()
    ..writeln('--- 日志内容开始 ---')
    ..write(log.content);
  if (!log.content.endsWith('\n')) {
    buffer.writeln();
  }
  buffer.writeln('--- 日志内容结束 ---');
  return buffer.toString();
}
