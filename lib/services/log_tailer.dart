// 日志文件增量尾随器
// 以轮询方式跟踪日志文件的增长，按行解码（UTF-8，容忍坏字节）并推入广播流。
//
// 服务器进程的 stdout/stderr 由 Rust 侧直接重定向到日志文件
// （xmc_logger::spawn_with_log），因此本尾随器是控制台终端的统一数据源：
// 启动器存活期间与接管外部进程（启动器重启后按 PID 恢复）时行为一致，
// 即使启动器崩溃，服务器仍持续写日志，重启后即可接着看到后续输出。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LogFileTailer {
  /// 创建一个尾随 [filePath] 的日志流。
  LogFileTailer(this.filePath);

  /// 被尾随的日志文件路径。
  final String filePath;

  /// 历史回放读取的字节上限（文件尾部）。
  static const int _maxHistoryBytes = 256 * 1024;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  RandomAccessFile? _raf;
  Timer? _timer;
  int _position = 0;
  bool _started = false;
  bool _disposed = false;

  /// 跨轮询残留的字节（可能含不完整的多字节序列）与文本。
  List<int> _pendingBytes = <int>[];
  String _pendingText = '';

  /// 日志行流（原始输出，保留 ANSI 转义序列）。
  Stream<String> get stream => _controller.stream;

  /// 开始尾随：从文件当前末尾开始推流（历史通过 [readRecentLines] 单独回放）。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await file.parent.create(recursive: true);
        await file.create();
      }
      _raf = await file.open(mode: FileMode.read);
      _position = await _raf!.length();
      _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        unawaited(_poll());
      });
      // 立即补一轮，缩短首屏等待。
      unawaited(_poll());
    } catch (_) {
      // 文件暂不可读时静默；轮询不会建立，上层仍可正常使用空流。
    }
  }

  Future<void> _poll() async {
    final raf = _raf;
    if (raf == null || _disposed) return;
    try {
      final length = await raf.length();
      if (length < _position) {
        // 日志文件被截断/重建（如手动删除），从头继续。
        _position = 0;
        _pendingBytes = <int>[];
        _pendingText = '';
      }
      if (length > _position) {
        await raf.setPosition(_position);
        final bytes = await raf.read(length - _position);
        _position = length;
        _consumeBytes(bytes);
      }
    } catch (_) {
      // 读取失败（文件被占用等）忽略，下一轮重试。
    }
  }

  /// 读取文件尾部最近 [maxLines] 行（用于终端打开时的历史回放）。
  Future<List<String>> readRecentLines(int maxLines) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const <String>[];
      final raf = await file.open(mode: FileMode.read);
      try {
        final length = await raf.length();
        final start =
            length > _maxHistoryBytes ? length - _maxHistoryBytes : 0;
        await raf.setPosition(start);
        final bytes = await raf.read(length - start);
        var text = utf8.decode(bytes, allowMalformed: true);
        // 丢弃首行可能被截断的部分。
        if (start > 0) {
          final firstBreak = text.indexOf('\n');
          if (firstBreak >= 0) {
            text = text.substring(firstBreak + 1);
          }
        }
        final lines = text
            .split('\n')
            .map((line) => line.endsWith('\r') ? line.substring(0, line.length - 1) : line)
            .toList();
        // 去除文件末尾换行符产生的空行。
        if (lines.isNotEmpty && lines.last.isEmpty) {
          lines.removeLast();
        }
        if (lines.length <= maxLines) return lines;
        return lines.sublist(lines.length - maxLines);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return const <String>[];
    }
  }

  void _consumeBytes(List<int> bytes) {
    _pendingBytes.addAll(bytes);
    final hold = _incompleteTailLength(_pendingBytes);
    final decodeEnd = _pendingBytes.length - hold;
    if (decodeEnd > 0) {
      final chunk = _pendingBytes.sublist(0, decodeEnd);
      _pendingBytes = _pendingBytes.sublist(decodeEnd);
      _pendingText += utf8.decode(chunk, allowMalformed: true);
      _emitLines();
    }
    // 防残留无限增长（极端场景：文件尾一直是无法解码的字节）。
    if (_pendingBytes.length > 1 << 16) {
      _pendingBytes = <int>[];
    }
  }

  /// 计算字节数组末尾可能不完整的多字节 UTF-8 序列长度，留待下轮补齐。
  static int _incompleteTailLength(List<int> bytes) {
    final n = bytes.length;
    if (n == 0) return 0;
    final last = bytes[n - 1];
    if (last < 0x80) return 0;
    if ((last & 0xC0) == 0x80) {
      // 末尾是续字节：向前找序列起始字节。
      var i = n - 2;
      var continuationCount = 1;
      while (i >= 0 && continuationCount < 3 && (bytes[i] & 0xC0) == 0x80) {
        i--;
        continuationCount++;
      }
      if (i < 0) return 0;
      final need = _utf8SequenceLength(bytes[i]);
      if (need == 0) return 0;
      return n - i < need ? n - i : 0;
    }
    // 末尾字节本身是序列起始字节（0xC0-0xF7）→ 序列必然未完成。
    return _utf8SequenceLength(last) > 1 ? 1 : 0;
  }

  /// 起始字节对应的完整 UTF-8 序列长度；非起始字节返回 0。
  static int _utf8SequenceLength(int lead) {
    if ((lead & 0xE0) == 0xC0) return 2;
    if ((lead & 0xF0) == 0xE0) return 3;
    if ((lead & 0xF8) == 0xF0) return 4;
    return 0;
  }

  void _emitLines() {
    // 单行超长保护：避免无换行的巨量输出撑爆内存。
    if (_pendingText.length > 1 << 20 && !_pendingText.contains('\n')) {
      final line = _pendingText;
      _pendingText = '';
      if (!_controller.isClosed) {
        _controller.add(line);
      }
      return;
    }
    while (true) {
      final idx = _pendingText.indexOf('\n');
      if (idx < 0) break;
      var line = _pendingText.substring(0, idx);
      _pendingText = _pendingText.substring(idx + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (!_controller.isClosed) {
        _controller.add(line);
      }
    }
  }

  /// 释放轮询定时器与文件句柄（不删除文件）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_raf?.close().catchError((_) {}));
    _raf = null;
    _controller.close();
  }
}
