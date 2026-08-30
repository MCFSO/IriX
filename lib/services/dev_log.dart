// 开发者日志服务
//
// 仅在开发者模式开启时记录。日志写入「可执行文件所在目录 / logs」下的
// 会话日志文件：每次应用启动且开发者模式开启（或运行期开启开发者模式）
// 时新建一个带精确时间戳的文件 dev-YYYYMMDD-HHMMSS.log，无限增长，
// 每个开启时段一个独立文件，便于按次排查。
//
// 落盘由 Rust 侧 xmc_devlog 动态库的后台线程负责（不阻塞 Dart/UI），
// 本服务只负责开关判断与调用 FFI。Rust 端为每行加时间戳并写盘。
//
// 记录内容：应用操作轨迹、网络请求明细、启动流程与崩溃堆栈
// （运行日志流由 Rust logger 写入文档目录 logs/<id>.log，与此并存）。

import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'devlog_ffi.dart';
import 'developer_settings.dart';

/// 日志级别。
enum DevLogLevel {
  info,
  warn,
  error;

  String get tag => switch (this) {
        DevLogLevel.info => 'INFO',
        DevLogLevel.warn => 'WARN',
        DevLogLevel.error => 'ERROR',
      };
}

/// 开发者日志单例。
class DevLog {
  DevLog._();
  static final DevLog instance = DevLog._();

  /// 开发者模式是否开启（启动时缓存，开关变化时刷新）。
  bool _enabled = false;

  /// Rust 侧是否已初始化（已 app_log_init 且未 shutdown）。
  bool _rustReady = false;

  /// FFI 是否可用（动态库加载成功）。
  bool _ffiOk = false;

  /// 初始化：读取开关缓存，开启时调用 Rust app_log_init 新建会话日志。
  Future<void> init() async {
    _ensureFfi();
    _enabled = await DeveloperSettings.isEnabled();
    if (_enabled) {
      _startSession();
    }
  }

  /// 尝试加载 Rust 动态库；失败则降级为不记录。
  void _ensureFfi() {
    if (_ffiOk) return;
    try {
      DevLogNative.init();
      _ffiOk = true;
    } catch (e) {
      _ffiOk = false;
    }
  }

  /// 刷新开关状态（设置开关变化时调用）。
  ///
  /// 从未开启→开启时新建会话日志；从开启→关闭时关闭 Rust 会话。
  Future<void> refreshEnabled() async {
    final next = await DeveloperSettings.isEnabled();
    if (next == _enabled) return;
    _enabled = next;
    if (_enabled) {
      _startSession();
      devAction('developer_mode', '开发者模式已开启');
    } else {
      _stopSession();
    }
  }

  /// 开发者模式当前是否启用。
  bool get enabled => _enabled;

  /// 调用 Rust app_log_init：在 exe 目录下的 logs 子目录新建会话文件并启动写线程。
  void _startSession() {
    if (!_ffiOk) return;
    if (_rustReady) return;
    try {
      final dir = p.dirname(Platform.resolvedExecutable);
      final nativeDir = dir.toNativeUtf8();
      try {
        final rc = DevLogNative.instance.appLogInit(nativeDir);
        if (rc == 0) {
          _rustReady = true;
        }
      } finally {
        calloc.free(nativeDir);
      }
    } catch (_) {
      _rustReady = false;
    }
  }

  /// 调用 Rust app_log_shutdown：flush 并回收写线程。
  void _stopSession() {
    if (!_ffiOk || !_rustReady) return;
    try {
      DevLogNative.instance.appLogShutdown();
    } catch (_) {
      // 忽略
    }
    _rustReady = false;
  }

  /// 核心写入入口：先判开关与 Rust 就绪，再调 FFI 落盘。
  void log(DevLogLevel level, String tag, String message) {
    if (!_enabled || !_rustReady) return;
    try {
      final nativeLevel = level.tag.toNativeUtf8();
      final nativeTag = tag.toNativeUtf8();
      final nativeMsg = message.toNativeUtf8();
      try {
        DevLogNative.instance.appLogWrite(nativeLevel, nativeTag, nativeMsg);
      } finally {
        calloc.free(nativeLevel);
        calloc.free(nativeTag);
        calloc.free(nativeMsg);
      }
    } catch (_) {
      // 写入失败静默忽略
    }
  }

  /// flush 后台缓冲（应用退出前调用，确保崩溃前的日志落盘）。
  void flush() {
    if (!_ffiOk || !_rustReady) return;
    try {
      DevLogNative.instance.appLogFlush();
    } catch (_) {
      // 忽略
    }
  }

  // === 便捷方法 ===

  /// 一般信息（操作轨迹 / 启动流程）。
  void devInfo(String tag, String message) => log(DevLogLevel.info, tag, message);

  /// 警告（非致命异常 / 降级）。
  void devWarn(String tag, String message) =>
      log(DevLogLevel.warn, tag, message);

  /// 错误（异常 / 失败）。
  void devError(String tag, String message) =>
      log(DevLogLevel.error, tag, message);

  /// HTTP 请求明细。
  void devHttp(String message) => log(DevLogLevel.info, 'http', message);

  /// 数据库操作明细。
  void devDb(String message) => log(DevLogLevel.info, 'db', message);

  /// 应用操作轨迹。
  void devAction(String tag, String message) =>
      log(DevLogLevel.info, tag, message);
}
