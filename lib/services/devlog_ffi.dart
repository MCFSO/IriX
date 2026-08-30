// 开发者日志 FFI 封装（Rust xmc_devlog 动态库）
// 调用 Rust 侧 app_log_init / app_log_write / app_log_flush / app_log_shutdown，
// 由 Rust 后台线程负责格式化与落盘（<exe 目录>/logs/dev-<时间戳>.log）。

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

typedef AppLogInitNative = Int32 Function(Pointer<Utf8> dir);
typedef AppLogInitDart = int Function(Pointer<Utf8> dir);

typedef AppLogWriteNative =
    Int32 Function(Pointer<Utf8> level, Pointer<Utf8> tag, Pointer<Utf8> msg);
typedef AppLogWriteDart =
    int Function(Pointer<Utf8> level, Pointer<Utf8> tag, Pointer<Utf8> msg);

typedef AppLogFlushNative = Int32 Function();
typedef AppLogFlushDart = int Function();

typedef AppLogShutdownNative = Int32 Function();
typedef AppLogShutdownDart = int Function();

typedef GetLastErrorNative = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

typedef FreeStringNative = Void Function(Pointer<Utf8> s);
typedef FreeStringDart = void Function(Pointer<Utf8> s);

/// 开发者日志 FFI 单例。
class DevLogNative {
  static DevLogNative? _instance;
  late final DynamicLibrary _lib;
  late final AppLogInitDart appLogInit;
  late final AppLogWriteDart appLogWrite;
  late final AppLogFlushDart appLogFlush;
  late final AppLogShutdownDart appLogShutdown;
  late final GetLastErrorDart getLastError;
  late final FreeStringDart freeString;

  DevLogNative._(this._lib) {
    appLogInit = _lib.lookupFunction<AppLogInitNative, AppLogInitDart>(
      'app_log_init',
    );
    appLogWrite = _lib.lookupFunction<AppLogWriteNative, AppLogWriteDart>(
      'app_log_write',
    );
    appLogFlush = _lib.lookupFunction<AppLogFlushNative, AppLogFlushDart>(
      'app_log_flush',
    );
    appLogShutdown = _lib.lookupFunction<AppLogShutdownNative, AppLogShutdownDart>(
      'app_log_shutdown',
    );
    getLastError = _lib.lookupFunction<GetLastErrorNative, GetLastErrorDart>(
      'get_last_error',
    );
    freeString = _lib.lookupFunction<FreeStringNative, FreeStringDart>(
      'free_string',
    );
  }

  /// 单例（首次访问时加载动态库）。
  static DevLogNative get instance => init();

  static DevLogNative init() {
    if (_instance != null) return _instance!;
    final lib = openRustLibrary('devlog');
    _instance = DevLogNative._(lib);
    return _instance!;
  }

  String? getLastErrorMessage() {
    final ptr = getLastError();
    if (ptr == nullptr) return null;
    final msg = ptr.toDartString();
    freeString(ptr);
    return msg;
  }
}
