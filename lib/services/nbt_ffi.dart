// Rust FFI NBT 绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_nbt.dll / libxmc_nbt.so/.dylib)
// 实现 Minecraft NBT 的解析/序列化与树编辑（复刻 AnkiNBT 的编辑能力）：
// 二进制(.nbt gzip) <-> SNBT 文本双向转换、树路径增删改查与搜索。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

/// FFI 函数签名定义（nbt_request 为 2 参：op + argsJson，无连接参数）。
typedef NbtRequestC = Pointer<Utf8> Function(
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);
typedef NbtRequestDart = Pointer<Utf8> Function(
  Pointer<Utf8> op,
  Pointer<Utf8> argsJson,
);

/// NBT 操作异常
class NbtFfiException implements Exception {
  final String message;

  const NbtFfiException(this.message);

  @override
  String toString() => 'NbtFfiException: $message';
}

/// 传递给后台 isolate 的请求
class _NbtFfiRequest {
  final String op;
  final String argsJson;
  final SendPort sendPort;

  const _NbtFfiRequest({
    required this.op,
    required this.argsJson,
    required this.sendPort,
  });
}

/// Rust NBT 编解码与树编辑 —— FFI 封装
///
/// 单次操作 = 一次 FFI 调用（op + argsJson）。所有耗时 FFI 调用在后台 isolate
/// 执行，UI 线程不会阻塞。返回 JSON：`{"ok":true,"result":...}` / `{"ok":false,"error":...}`。
class NbtFfi {
  static NbtFfi? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static NbtFfi get instance => _instance ??= NbtFfi._();

  NbtFfi._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() => openRustLibrary('nbt');

  /// 执行一次 NBT 操作（后台 isolate，不阻塞 UI）。
  ///
  /// [op] Rust 侧操作名：parse_binary / to_binary / parse_snbt / to_snbt /
  /// get / set / delete / search
  /// [args] 操作参数（值须可 JSON 序列化），Rust 侧统一解码为 argsJson
  /// [timeout] 整体超时
  Future<Map<String, dynamic>> request({
    required String op,
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<Map<String, dynamic>>();

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is Map<String, dynamic>) {
        completer.complete(msg);
      } else if (msg is NbtFfiException) {
        completer.completeError(msg);
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _nbtRequestIsolate,
        _NbtFfiRequest(
          op: op,
          argsJson: jsonEncode(args),
          sendPort: responsePort.sendPort,
        ),
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate?.kill(priority: Isolate.immediate);
          throw NbtFfiException('NBT 操作超时: $timeout');
        },
      );
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _nbtRequestIsolate(_NbtFfiRequest req) {
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? argsPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();
      final nbtRequest =
          lib.lookupFunction<NbtRequestC, NbtRequestDart>('nbt_request');

      opPtr = req.op.toNativeUtf8();
      argsPtr = req.argsJson.toNativeUtf8();

      resultPtr = nbtRequest(opPtr, argsPtr);

      if (resultPtr == nullptr) {
        req.sendPort.send(const NbtFfiException('nbt_request 返回空指针'));
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
        req.sendPort.send(NbtFfiException(message));
      }
    } catch (e) {
      req.sendPort.send(NbtFfiException('后台 isolate 异常: $e'));
    } finally {
      if (opPtr != null) calloc.free(opPtr);
      if (argsPtr != null) calloc.free(argsPtr);
      if (resultPtr != null) {
        freeRustString(_openLibrary(), resultPtr);
      }
    }
  }
}
