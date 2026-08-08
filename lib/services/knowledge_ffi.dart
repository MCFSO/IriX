// Rust FFI 向量知识库绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_vector_store.dll / libxmc_vector_store.so/.dylib)
// 实现基于 sqlite-vec 的本地向量数据库（RAG 知识库）：
// 建库、写入文档分块（含向量）、余弦相似度检索、文档列表与删除。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// FFI 函数签名定义
typedef VectorRequestC = Pointer<Utf8> Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);
typedef VectorRequestDart = Pointer<Utf8> Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

/// 向量库操作异常
class VectorStoreFfiException implements Exception {
  final String message;

  const VectorStoreFfiException(this.message);

  @override
  String toString() => 'VectorStoreFfiException: $message';
}

/// 传递给后台 isolate 的请求
class _VectorFfiRequest {
  final String dbPath;
  final String op;
  final String argsJson;
  final SendPort sendPort;

  const _VectorFfiRequest({
    required this.dbPath,
    required this.op,
    required this.argsJson,
    required this.sendPort,
  });
}

/// Rust 向量知识库 — FFI 封装
///
/// 单次操作 = 一次 FFI 调用：Rust 侧打开 SQLite、执行、返回 JSON。
/// 所有耗时的 FFI 调用都在后台 isolate 执行，UI 线程不会阻塞。
class VectorStoreFfi {
  static VectorStoreFfi? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static VectorStoreFfi get instance => _instance ??= VectorStoreFfi._();

  VectorStoreFfi._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_vector_store.dll'
        : Platform.isMacOS
            ? 'libxmc_vector_store.dylib'
            : 'libxmc_vector_store.so';

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
      'Rust vector_store library not found.\n'
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

  /// 执行一次向量库操作（后台 isolate，不阻塞 UI）。
  ///
  /// [dbPath] 知识库 SQLite 文件路径
  /// [op] Rust 侧操作名（init / add / search / list_documents / delete_document / stats）
  /// [args] 操作参数（值须可 JSON 序列化）
  /// [timeout] 整体超时
  Future<Map<String, dynamic>> request({
    required String dbPath,
    required String op,
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is Map<String, dynamic>) {
        completer.complete(msg);
      } else if (msg is VectorStoreFfiException) {
        completer.completeError(msg);
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _vectorRequestIsolate,
        _VectorFfiRequest(
          dbPath: dbPath,
          op: op,
          argsJson: jsonEncode(args),
          sendPort: responsePort.sendPort,
        ),
      );
      return await completer.future.timeout(timeout, onTimeout: () {
        isolate?.kill(priority: Isolate.immediate);
        throw VectorStoreFfiException('向量库操作超时: $timeout');
      });
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _vectorRequestIsolate(_VectorFfiRequest req) {
    Pointer<Utf8>? dbPtr;
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? argsPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();
      final vectorRequest =
          lib.lookupFunction<VectorRequestC, VectorRequestDart>('vector_request');

      dbPtr = req.dbPath.toNativeUtf8();
      opPtr = req.op.toNativeUtf8();
      argsPtr = req.argsJson.toNativeUtf8();

      resultPtr = vectorRequest(dbPtr, opPtr, argsPtr);

      if (resultPtr == nullptr) {
        req.sendPort
            .send(const VectorStoreFfiException('vector_request 返回空指针'));
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
        req.sendPort.send(VectorStoreFfiException(message));
      }
    } catch (e) {
      req.sendPort.send(VectorStoreFfiException('后台 isolate 异常: $e'));
    } finally {
      if (dbPtr != null) calloc.free(dbPtr);
      if (opPtr != null) calloc.free(opPtr);
      if (argsPtr != null) calloc.free(argsPtr);
      if (resultPtr != null) {
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
