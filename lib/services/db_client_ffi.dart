// Rust FFI 远程数据库客户端绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_db_client.dll / libxmc_db_client.so/.dylib)
// 实现 MySQL / MariaDB / PostgreSQL / Redis 的连接与操作。
// Rust 侧使用 mysql / postgres / redis 纯 Rust crate，无 OpenSSL 依赖。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// FFI 函数签名定义
typedef DbRequestC = Pointer<Utf8> Function(
  Pointer<Utf8> connJson,
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);
typedef DbRequestDart = Pointer<Utf8> Function(
  Pointer<Utf8> connJson,
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

/// 数据库操作异常
class DbClientFfiException implements Exception {
  final String message;

  const DbClientFfiException(this.message);

  @override
  String toString() => 'DbClientFfiException: $message';
}

/// 传递给后台 isolate 的请求
class _DbFfiRequest {
  final String connJson;
  final String op;
  final String argsJson;
  final SendPort sendPort;

  const _DbFfiRequest({
    required this.connJson,
    required this.op,
    required this.argsJson,
    required this.sendPort,
  });
}

/// Rust 远程数据库客户端 — FFI 封装
///
/// 单次数据库操作 = 一次 FFI 调用：Rust 侧建立连接、执行、关闭连接，返回 JSON。
/// 所有耗时的 FFI 调用都在后台 isolate 执行，UI 线程不会阻塞。
class DbClientFfi {
  static DbClientFfi? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static DbClientFfi get instance => _instance ??= DbClientFfi._();

  DbClientFfi._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_db_client.dll'
        : Platform.isMacOS
            ? 'libxmc_db_client.dylib'
            : 'libxmc_db_client.so';

    for (final libPath in _getPossibleLibraryPaths(libName)) {
      try {
        final file = File(libPath);
        if (file.existsSync()) {
          return DynamicLibrary.open(libPath);
        }
        attempts.add('$libPath (文件不存在)');
      } catch (e) {
        attempts.add('$libPath (加载失败: $e)');
      }
    }

    try {
      return DynamicLibrary.open(libName);
    } catch (e) {
      attempts.add('系统搜索路径 "$libName" (加载失败: $e)');
    }

    throw UnsupportedError(
      'Rust db_client library not found.\n'
      'cwd: ${Directory.current.path}\n'
      'exe: ${Platform.resolvedExecutable}\n'
      '尝试的路径:\n${attempts.map((a) => '  - $a').join('\n')}',
    );
  }

  /// 获取可能的库路径列表
  static List<String> _getPossibleLibraryPaths(String libName) {
    final paths = <String>[];

    // 当前工作目录
    final cwd = Directory.current.path;
    paths.add(p.join(cwd, libName));
    paths.add(p.join(cwd, 'lib', libName));
    if (Platform.isWindows) {
      paths.add(p.join(cwd, 'windows', 'runner', libName));
    } else if (Platform.isMacOS) {
      paths.add(p.join(cwd, 'macos', libName));
    } else {
      paths.add(p.join(cwd, 'linux', libName));
    }

    // 从 exe 目录开始向上逐级查找
    try {
      final exePath = Platform.resolvedExecutable;
      var dir = p.dirname(exePath);
      for (var i = 0; i < 10; i++) {
        paths.add(p.join(dir, libName));
        paths.add(p.join(dir, 'lib', libName));
        if (Platform.isWindows) {
          paths.add(p.join(dir, 'windows', 'runner', libName));
        } else if (Platform.isMacOS) {
          paths.add(p.join(dir, 'macos', libName));
          paths.add(p.join(dir, '..', 'Frameworks', libName));
        } else {
          paths.add(p.join(dir, 'linux', libName));
        }
        final parent = p.dirname(dir);
        if (parent == dir) break; // 到达文件系统根
        dir = parent;
      }
    } catch (_) {
      // 忽略
    }

    return paths;
  }

  /// 执行一次数据库操作（后台 isolate，不阻塞 UI）。
  ///
  /// [dbType] mysql / mariadb / postgres / redis
  /// [op] Rust 侧操作名（test_connection / get_databases / ...）
  /// [args] 操作参数（值须可 JSON 序列化）
  /// [timeout] 整体超时（Rust 内部另有连接/读写超时兜底）
  Future<Map<String, dynamic>> request({
    required String dbType,
    required String host,
    required int port,
    String? username,
    String? password,
    String? database,
    bool useSsl = false,
    required String op,
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is Map<String, dynamic>) {
        completer.complete(msg);
      } else if (msg is DbClientFfiException) {
        completer.completeError(msg);
      }
    });

    final connJson = jsonEncode({
      'type': dbType,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'database': database,
      'ssl': useSsl,
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _dbRequestIsolate,
        _DbFfiRequest(
          connJson: connJson,
          op: op,
          argsJson: jsonEncode(args),
          sendPort: responsePort.sendPort,
        ),
      );
      // Dart 层硬超时兜底：超时后尽力终止后台 isolate。
      return await completer.future.timeout(timeout, onTimeout: () {
        isolate?.kill(priority: Isolate.immediate);
        throw DbClientFfiException('数据库操作超时: $timeout');
      });
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _dbRequestIsolate(_DbFfiRequest req) {
    Pointer<Utf8>? connPtr;
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? argsPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();
      final dbRequest =
          lib.lookupFunction<DbRequestC, DbRequestDart>('db_request');

      connPtr = req.connJson.toNativeUtf8();
      opPtr = req.op.toNativeUtf8();
      argsPtr = req.argsJson.toNativeUtf8();

      resultPtr = dbRequest(connPtr, opPtr, argsPtr);

      if (resultPtr == nullptr) {
        req.sendPort
            .send(const DbClientFfiException('db_request 返回空指针'));
        return;
      }

      final resultJson = resultPtr.toDartString();
      final decoded = jsonDecode(resultJson) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        req.sendPort.send(
          (decoded['result'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
      } else {
        final message = decoded['error'] as String? ?? '未知错误';
        req.sendPort.send(DbClientFfiException(message));
      }
    } catch (e) {
      req.sendPort.send(DbClientFfiException('后台 isolate 异常: $e'));
    } finally {
      if (connPtr != null) calloc.free(connPtr);
      if (opPtr != null) calloc.free(opPtr);
      if (argsPtr != null) calloc.free(argsPtr);
      if (resultPtr != null) {
        // resultPtr 由 Rust 分配，需用 Rust 侧 free_string 释放
        try {
          final lib = _openLibrary();
          final freeString =
              lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');
          freeString(resultPtr);
        } catch (_) {
          // 库句柄无法再次打开时忽略（指针泄漏可接受，仅调试场景）
        }
      }
    }
  }
}