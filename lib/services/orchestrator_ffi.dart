// Rust FFI 编排引擎绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_orchestrator.dll / libxmc_orchestrator.so/.dylib)
// 实现 K8s 风格 MC 服务器编排控制平面：
// 期望状态对账 / 崩溃自愈 / 按在线人数弹性扩缩容 / 跨物理机迁移状态机。
// Rust 侧为纯计算引擎（无网络），观测采集与动作执行由 Dart 层完成。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// FFI 函数签名定义
typedef OrchestratorRequestC =
    Pointer<Utf8> Function(Pointer<Utf8> argsJson, Pointer<Utf8> op);
typedef OrchestratorRequestDart =
    Pointer<Utf8> Function(Pointer<Utf8> argsJson, Pointer<Utf8> op);

typedef OrchestratorFreeStringC = Void Function(Pointer<Utf8> ptr);
typedef OrchestratorFreeStringDart = void Function(Pointer<Utf8> ptr);

/// 编排操作异常
class OrchestratorFfiException implements Exception {
  final String message;

  const OrchestratorFfiException(this.message);

  @override
  String toString() => 'OrchestratorFfiException: $message';
}

/// 传递给后台 isolate 的请求
class _OrchestratorFfiRequest {
  final String argsJson;
  final String op;
  final SendPort sendPort;

  const _OrchestratorFfiRequest({
    required this.argsJson,
    required this.op,
    required this.sendPort,
  });
}

/// Rust 编排引擎 — FFI 封装
///
/// 单次操作 = 一次 FFI 调用：Rust 侧按需打开 SQLite（dbPath 参数）、
/// 执行引擎逻辑、返回 JSON。所有耗时调用都在后台 isolate 执行。
class OrchestratorFfi {
  static OrchestratorFfi? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static OrchestratorFfi get instance => _instance ??= OrchestratorFfi._();

  OrchestratorFfi._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_orchestrator.dll'
        : Platform.isMacOS
        ? 'libxmc_orchestrator.dylib'
        : 'libxmc_orchestrator.so';

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
      'Rust orchestrator library not found.\n'
      '请先运行 build_rust.bat / build_rust.sh 编译并复制动态库。\n'
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

  /// 执行一次编排操作（后台 isolate，不阻塞 UI）。
  ///
  /// [op] Rust 侧操作名（init / upsert_service / delete_service /
  ///   list_services / get_service / list_replicas / reconcile / observe /
  ///   status / migrate_start / report_migration / migrate_cancel /
  ///   list_migrations / mc_ping / reset）
  /// [args] 操作参数（值须可 JSON 序列化，含 dbPath）
  Future<dynamic> request({
    required String op,
    Map<String, dynamic> args = const {},
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<dynamic>();

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is OrchestratorFfiException) {
        completer.completeError(msg);
      } else {
        completer.complete(msg);
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _orchestratorRequestIsolate,
        _OrchestratorFfiRequest(
          argsJson: jsonEncode(args),
          op: op,
          sendPort: responsePort.sendPort,
        ),
      );
      // Dart 层硬超时兜底：超时后尽力终止后台 isolate。
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate?.kill(priority: Isolate.immediate);
          throw OrchestratorFfiException('编排操作超时: $timeout');
        },
      );
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _orchestratorRequestIsolate(_OrchestratorFfiRequest req) {
    Pointer<Utf8>? argsPtr;
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();
      final orchestratorRequest = lib
          .lookupFunction<OrchestratorRequestC, OrchestratorRequestDart>(
            'orchestrator_request',
          );

      argsPtr = req.argsJson.toNativeUtf8();
      opPtr = req.op.toNativeUtf8();

      resultPtr = orchestratorRequest(argsPtr, opPtr);

      if (resultPtr == nullptr) {
        req.sendPort.send(
          const OrchestratorFfiException('orchestrator_request 返回空指针'),
        );
        return;
      }

      final resultJson = resultPtr.toDartString();
      final decoded = jsonDecode(resultJson) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        req.sendPort.send(decoded['result']);
      } else {
        final message = decoded['error'] as String? ?? '未知错误';
        req.sendPort.send(OrchestratorFfiException(message));
      }
    } catch (e) {
      req.sendPort.send(OrchestratorFfiException('后台 isolate 异常: $e'));
    } finally {
      if (argsPtr != null) calloc.free(argsPtr);
      if (opPtr != null) calloc.free(opPtr);
      if (resultPtr != null) {
        // resultPtr 由 Rust 分配，需用 Rust 侧 free 函数释放
        try {
          final lib = _openLibrary();
          final freeString = lib
              .lookupFunction<
                OrchestratorFreeStringC,
                OrchestratorFreeStringDart
              >('orchestrator_free_string');
          freeString(resultPtr);
        } catch (_) {
          // 库句柄无法再次打开时忽略
        }
      }
    }
  }
}
