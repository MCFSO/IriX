// 服务器日志持久化服务
// 通过 Rust logger crate 异步写入日志文件

import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/logger_ffi.dart';

class LogPersistence {
  static final LogPersistence instance = LogPersistence._();
  LogPersistence._();

  final Map<String, StreamSubscription<String>> _subscriptions = {};
  bool _initialized = false;

  /// Rust 日志库是否可用；库加载失败（如未构建 DLL）时降级为不写日志。
  bool _loggerAvailable = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = '${appDir.path}/logs';
      final logger = LoggerNative.init();
      final nativeLogDir = logDir.toNativeUtf8();
      logger.logInit(nativeLogDir);
      calloc.free(nativeLogDir);
      _loggerAvailable = true;
    } catch (e) {
      debugPrint('Logger unavailable, logs will not be persisted: $e');
    }
  }

  void startWatching(String instanceId, Stream<String> logStream) {
    if (_subscriptions.containsKey(instanceId)) return;
    if (!_loggerAvailable) return;
    final logger = LoggerNative.init();

    _subscriptions[instanceId] = logStream.listen((line) {
      final nativeId = instanceId.toNativeUtf8();
      final nativeLine = line.toNativeUtf8();
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

  static Future<String?> readLogs(String instanceId, {int? tail}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/logs/$instanceId.log');
    if (!await file.exists()) return null;

    if (tail == null) return file.readAsString();

    final lines = await file.readAsLines();
    if (lines.length <= tail) return lines.join('\n');
    return lines.sublist(lines.length - tail).join('\n');
  }

  static Future<void> deleteLogs(String instanceId) async {
    try {
      final nativeId = instanceId.toNativeUtf8();
      LoggerNative.init().logDelete(nativeId);
      calloc.free(nativeId);
    } catch (e) {
      debugPrint('Failed to delete logs: $e');
    }
  }
}
