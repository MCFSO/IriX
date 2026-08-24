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

typedef LogWriteNative =
    Int32 Function(Pointer<Utf8> instanceId, Pointer<Utf8> line);
typedef LogWriteDart =
    int Function(Pointer<Utf8> instanceId, Pointer<Utf8> line);

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

// 服务器进程托管（stdout/stderr 重定向到日志文件，stdin 保留管道）。
typedef SpawnWithLogNative = Int64 Function(
  Pointer<Utf8> command,
  Pointer<Utf8> cwd,
  Pointer<Utf8> logPath,
);
typedef SpawnWithLogDart = int Function(
  Pointer<Utf8> command,
  Pointer<Utf8> cwd,
  Pointer<Utf8> logPath,
);

typedef SpawnSendStdinNative = Int32 Function(Uint32 pid, Pointer<Utf8> line);
typedef SpawnSendStdinDart = int Function(int pid, Pointer<Utf8> line);

typedef SpawnTryReapNative = Int64 Function(Uint32 pid);
typedef SpawnTryReapDart = int Function(int pid);

typedef SpawnKillNative = Int32 Function(Uint32 pid);
typedef SpawnKillDart = int Function(int pid);

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

  /// 进程托管 FFI（spawn_with_log 等）是否可用。
  ///
  /// 旧版 xmc_logger.dll 不含这些导出函数时置为 false，
  /// 上层自动回退到 dart:io 管道启动。
  bool spawnAvailable = false;
  SpawnWithLogDart? _spawnWithLog;
  SpawnSendStdinDart? _spawnSendStdin;
  SpawnTryReapDart? _spawnTryReap;
  SpawnKillDart? _spawnKill;

  LoggerNative._(this._lib) {
    logInit = _lib.lookupFunction<LogInitNative, LogInitDart>('log_init');
    logWrite = _lib.lookupFunction<LogWriteNative, LogWriteDart>('log_write');
    logFlush = _lib.lookupFunction<LogFlushNative, LogFlushDart>('log_flush');
    logShutdown = _lib.lookupFunction<LogShutdownNative, LogShutdownDart>(
      'log_shutdown',
    );
    logDelete = _lib.lookupFunction<LogDeleteNative, LogDeleteDart>(
      'log_delete',
    );
    getLastError = _lib.lookupFunction<GetLastErrorNative, GetLastErrorDart>(
      'get_last_error',
    );
    freeString = _lib.lookupFunction<FreeStringNative, FreeStringDart>(
      'free_string',
    );

    // 进程托管导出函数为后续新增能力，旧 DLL 缺失时保持兼容（回退管道启动）。
    try {
      _spawnWithLog = _lib.lookupFunction<SpawnWithLogNative, SpawnWithLogDart>(
        'spawn_with_log',
      );
      _spawnSendStdin = _lib.lookupFunction<
        SpawnSendStdinNative,
        SpawnSendStdinDart
      >('spawn_send_stdin');
      _spawnTryReap = _lib.lookupFunction<SpawnTryReapNative, SpawnTryReapDart>(
        'spawn_try_reap',
      );
      _spawnKill = _lib.lookupFunction<SpawnKillNative, SpawnKillDart>(
        'spawn_kill',
      );
      spawnAvailable = true;
    } catch (_) {
      spawnAvailable = false;
    }
  }

  /// 进程托管 FFI 单例（首次访问时加载动态库）。
  static LoggerNative get instance => init();

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
      lib ??= DynamicLibrary.open(libName);
    }
    _instance = LoggerNative._(lib);
    return _instance!;
  }

  String? getLastErrorMessage() {
    final ptr = getLastError();
    if (ptr == Pointer<Utf8>.fromAddress(0)) return null;
    final msg = ptr.toDartString();
    freeString(ptr);
    return msg;
  }

  /// 启动服务器进程：stdout/stderr 追加写入 [logPath]，stdin 保留管道。
  ///
  /// 返回子进程 PID（>0）；失败返回 -1（通过 [getLastErrorMessage] 取原因）。
  int spawnProcess(String command, String cwd, String logPath) {
    final f = _spawnWithLog;
    if (f == null) return -1;
    final cmdPtr = command.toNativeUtf8();
    final cwdPtr = cwd.toNativeUtf8();
    final logPtr = logPath.toNativeUtf8();
    try {
      return f(cmdPtr, cwdPtr, logPtr);
    } finally {
      calloc.free(cmdPtr);
      calloc.free(cwdPtr);
      calloc.free(logPtr);
    }
  }

  /// 向托管进程的 stdin 写入一行。0 成功，1 进程未知或写入失败。
  int spawnSendStdin(int pid, String line) {
    final f = _spawnSendStdin;
    if (f == null) return 1;
    final linePtr = line.toNativeUtf8();
    try {
      return f(pid, linePtr);
    } finally {
      calloc.free(linePtr);
    }
  }

  /// 回收托管进程的退出状态：-1 未知 PID，-2 仍在运行，其余为退出码。
  int spawnTryReap(int pid) => _spawnTryReap?.call(pid) ?? -1;

  /// 强制终止托管进程。0 成功，1 进程未知。
  int spawnKill(int pid) => _spawnKill?.call(pid) ?? 1;
}
