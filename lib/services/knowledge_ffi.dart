// Rust FFI 向量知识库绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_vector_store.dll / libxmc_vector_store.so/.dylib)
// 实现基于 Milvus 的远程向量数据库（RAG 知识库）：
// 建库、写入文档分块（含向量）、余弦相似度检索、文档列表与删除。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

/// FFI 函数签名定义
typedef VectorRequestC =
    Pointer<Utf8> Function(
      Pointer<Utf8> connJson,
      Pointer<Utf8> op,
      Pointer<Utf8> argsJson,
    );
typedef VectorRequestDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> connJson,
      Pointer<Utf8> op,
      Pointer<Utf8> argsJson,
    );

/// 向量库操作异常
class VectorStoreFfiException implements Exception {
  final String message;

  const VectorStoreFfiException(this.message);

  @override
  String toString() => 'VectorStoreFfiException: $message';
}

/// 传递给后台 isolate 的请求
class _VectorFfiRequest {
  final String connJson;
  final String op;
  final String argsJson;
  final SendPort sendPort;

  const _VectorFfiRequest({
    required this.connJson,
    required this.op,
    required this.argsJson,
    required this.sendPort,
  });
}

/// Rust 向量知识库 — FFI 封装
///
/// 单次操作 = 一次 FFI 调用：Rust 侧连接 Milvus、执行、返回 JSON。
/// 所有耗时的 FFI 调用都在后台 isolate 执行，UI 线程不会阻塞。
class VectorStoreFfi {
  static VectorStoreFfi? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static VectorStoreFfi get instance => _instance ??= VectorStoreFfi._();

  VectorStoreFfi._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() =>
      openRustLibrary('vector_store');

  /// 执行一次向量库操作（后台 isolate，不阻塞 UI）。
  ///
  /// [connJson] Milvus 连接配置 JSON（uri / token / collection）
  /// [op] Rust 侧操作名（init / add / search / list_documents / delete_document / stats）
  /// [args] 操作参数（值须可 JSON 序列化）
  /// [timeout] 整体超时
  Future<Map<String, dynamic>> request({
    required String connJson,
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
          connJson: connJson,
          op: op,
          argsJson: jsonEncode(args),
          sendPort: responsePort.sendPort,
        ),
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate?.kill(priority: Isolate.immediate);
          throw VectorStoreFfiException('向量库操作超时: $timeout');
        },
      );
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _vectorRequestIsolate(_VectorFfiRequest req) {
    Pointer<Utf8>? connPtr;
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? argsPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();
      final vectorRequest = lib
          .lookupFunction<VectorRequestC, VectorRequestDart>('vector_request');

      connPtr = req.connJson.toNativeUtf8();
      opPtr = req.op.toNativeUtf8();
      argsPtr = req.argsJson.toNativeUtf8();

      resultPtr = vectorRequest(connPtr, opPtr, argsPtr);

      if (resultPtr == nullptr) {
        req.sendPort.send(
          const VectorStoreFfiException('vector_request 返回空指针'),
        );
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
      if (connPtr != null) calloc.free(connPtr);
      if (opPtr != null) calloc.free(opPtr);
      if (argsPtr != null) calloc.free(argsPtr);
      if (resultPtr != null) {
        freeRustString(_openLibrary(), resultPtr);
      }
    }
  }
}
