// 日志服务 (Rust FFI 实现)
// 通过 dart:ffi 调用 Rust 编译的动态库 (xmc_logger.dll) 实现高性能异步日志写入
//
// Rust 端实现位于 rust/logger/src/lib.rs

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef LogInitNative = Int32 Function(Pointer<Utf8> logDir);
typedef LogInitDart = int Function(Pointer<Utf8> logDir);

typedef LogWriteNative = Int32 Function(Pointer<Utf8> instanceId, Pointer<Utf8> line);
typedef LogWriteDart = int Function(Pointer<Utf8> instanceId, Pointer<Utf8> line);

typedef LogFlushNative = Int32 Function();
typedef LogFlushDart = int Function();

typedef LogShutdownNative = Int32 Function();
typedef LogShutdownDart = int Function();

typedef LogDeleteNative = Int32 Function(Pointer<Utf8> instanceId);
typedef LogDeleteDart = int Function(Pointer<Utf8> instanceId);

typedef GetLastErrorNative = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

typedef FreeStringNative = Void Function(Pointer<Utf8> s);
typedef FreeStringDart = void Function(Pointer<Utf8> s);

class LoggerNative {
  static LoggerNative? _instance;
  late final DynamicLibrary _lib;
  late final LogInitDart logInit;
  late final LogWriteDart logWrite;
  late final LogFlushDart logFlush;
  late final LogShutdownDart logShutdown;
  late final LogDeleteDart logDelete;
  late final GetLastErrorDart getLastError;
  late final FreeStringDart freeString;

  LoggerNative._(this._lib) {
    logInit = _lib.lookupFunction<LogInitNative, LogInitDart>('log_init');
    logWrite = _lib.lookupFunction<LogWriteNative, LogWriteDart>('log_write');
    logFlush = _lib.lookupFunction<LogFlushNative, LogFlushDart>('log_flush');
    logShutdown = _lib.lookupFunction<LogShutdownNative, LogShutdownDart>('log_shutdown');
    logDelete = _lib.lookupFunction<LogDeleteNative, LogDeleteDart>('log_delete');
    getLastError = _lib.lookupFunction<GetLastErrorNative, GetLastErrorDart>('get_last_error');
    freeString = _lib.lookupFunction<FreeStringNative, FreeStringDart>('free_string');
  }

  static LoggerNative init() {
    if (_instance != null) return _instance!;
    final libName = Platform.isWindows
        ? 'xmc_logger.dll'
        : Platform.isMacOS
            ? 'libxmc_logger.dylib'
            : 'libxmc_logger.so';

    DynamicLibrary? lib;
    try {
      lib = DynamicLibrary.open(libName);
    } catch (_) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final attempts = <String>[
        p.join(exeDir, libName),
        p.join(exeDir, 'lib', libName),
        p.join(Directory.current.path, libName),
      ];
      for (final path in attempts) {
        if (File(path).existsSync()) {
          lib = DynamicLibrary.open(path);
          break;
        }
      }

      if (lib == null) {
        var dir = Directory.current;
        for (int i = 0; i < 10; i++) {
          final path = p.join(dir.path, libName);
          if (File(path).existsSync()) {
            lib = DynamicLibrary.open(path);
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
      }
      if (lib == null) {
        lib = DynamicLibrary.open(libName);
      }
    }
    _instance = LoggerNative._(lib!);
    return _instance!;
  }

  String? getLastErrorMessage() {
    final ptr = getLastError();
    if (ptr == Pointer<Utf8>.fromAddress(0)) return null;
    final msg = ptr.toDartString();
    freeString(ptr);
    return msg;
  }
}
