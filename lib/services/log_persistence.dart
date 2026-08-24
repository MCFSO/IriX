// 服务器日志持久化服务
// 服务器进程的 stdout/stderr 由 Rust 侧直接重定向到日志文件
// （<应用文档目录>/logs/<instanceId>.log，见 log_tailer.dart），
// 本服务负责该文件的路径解析、读取（AI 上下文等）与删除。
//
// 保留 Rust logger 的 startWatching/stopWatching 仅为兼容旧调用方；
// 当前实例日志不再经由 Rust logger 写入（避免与进程直写重复）。

import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/logger_ffi.dart';
import '../utils/ansi_color.dart';

class LogPersistence {
  static final LogPersistence instance = LogPersistence._();
  LogPersistence._();

  static String? _docsDir;

  final Map<String, StreamSubscription<String>> _subscriptions = {};
  bool _initialized = false;

  /// Rust 日志库是否可用；库加载失败（如未构建 DLL）时降级为不写日志。
  bool _loggerAvailable = false;

  /// 日志目录路径（惰性获取并缓存）。
  static Future<String> _logDirPath() async {
    if (_docsDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      _docsDir = appDir.path;
    }
    return '$_docsDir/logs';
  }

  /// 指定实例的日志文件路径（确保目录存在）。
  static Future<String> logFilePath(String instanceId) async {
    final dir = await _logDirPath();
    await Directory(dir).create(recursive: true);
    return '$dir/$instanceId.log';
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final logDir = await _logDirPath();
      final logger = LoggerNative.init();
      final nativeLogDir = logDir.toNativeUtf8();
      logger.logInit(nativeLogDir);
      calloc.free(nativeLogDir);
      _loggerAvailable = true;
    } catch (e) {
      debugPrint('Logger unavailable, logs will not be persisted: $e');
    }
  }

  /// 兼容旧调用方：将日志流转写 Rust logger。
  void startWatching(String instanceId, Stream<String> logStream) {
    if (_subscriptions.containsKey(instanceId)) return;
    if (!_loggerAvailable) return;
    final logger = LoggerNative.init();

    _subscriptions[instanceId] = logStream.listen((line) {
      final nativeId = instanceId.toNativeUtf8();
      // 日志文件写入纯文本：去除 ANSI 转义序列（彩色只在控制台显示）。
      final nativeLine = stripAnsi(line).toNativeUtf8();
      logger.logWrite(nativeId, nativeLine);
      calloc.free(nativeId);
      calloc.free(nativeLine);
    });
  }

  void stopWatching(String instanceId) {
    _subscriptions.remove(instanceId)?.cancel();
  }

  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    if (_loggerAvailable) {
      try {
        LoggerNative.init().logShutdown();
      } catch (e) {
        debugPrint('Failed to shutdown logger: $e');
      }
    }
  }

  /// 读取实例日志（AI 上下文等）。返回去除 ANSI 转义序列的纯文本。
  ///
  /// [tail] 非空时只返回文件末尾的最近 [tail] 行。
  static Future<String?> readLogs(String instanceId, {int? tail}) async {
    final file = File(await logFilePath(instanceId));
    if (!await file.exists()) return null;

    String content;
    if (tail == null) {
      content = await file.readAsString();
    } else {
      final lines = await file.readAsLines();
      content = lines.length <= tail
          ? lines.join('\n')
          : lines.sublist(lines.length - tail).join('\n');
    }
    return stripAnsi(content);
  }

  /// 删除实例日志文件。
  static Future<void> deleteLogs(String instanceId) async {
    try {
      final file = File(await logFilePath(instanceId));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete log file: $e');
    }
    // Rust logger 兜底（旧版本遗留的日志句柄/文件）。
    try {
      final nativeId = instanceId.toNativeUtf8();
      LoggerNative.init().logDelete(nativeId);
      calloc.free(nativeId);
    } catch (e) {
      debugPrint('Failed to delete logs: $e');
    }
  }
}
