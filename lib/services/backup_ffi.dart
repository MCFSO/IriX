// Rust FFI 备份绑定
// 通过 dart:ffi 调用 Rust 编译的动态库（xmc_backup.dll / libxmc_backup.so|.dylib）：
//
// 1. 全量备份（原备份功能）：`backup_directory` —— 整个实例目录并行 Deflate 压缩为 ZIP；
// 2. 全量 + 增量备份统一入口：`backup_request(op, argsJson, progressCb)` ——
//    返回 JSON，op 见 [BackupService.request] 的文档（status / full_create /
//    full_restore / full_delete / snapshot_create / snapshot_restore /
//    snapshot_verify / snapshot_delete / gc）。
//
// 所有耗时调用都在后台 isolate 执行，避免阻塞 UI 线程；
// 进度通过主 isolate 的 NativeCallable + SendPort 实时回传。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

/// FFI 函数签名定义
typedef BackupDirectoryC =
    Int32 Function(
      Pointer<Utf8> srcPath,
      Pointer<Utf8> dstPath,
      Pointer<Pointer<Utf8>> files,
      IntPtr filesCount,
      Uint32 compressionLevel,
      Pointer<NativeFunction<ProgressCallbackC>> progressCb,
    );
typedef BackupDirectoryDart =
    int Function(
      Pointer<Utf8> srcPath,
      Pointer<Utf8> dstPath,
      Pointer<Pointer<Utf8>> files,
      int filesCount,
      int compressionLevel,
      Pointer<NativeFunction<ProgressCallbackC>> progressCb,
    );

/// 统一备份请求：`backup_request(op, argsJson, progressCb) -> *mut c_char`
typedef BackupRequestC =
    Pointer<Utf8> Function(
      Pointer<Utf8> op,
      Pointer<Utf8> argsJson,
      Pointer<NativeFunction<ProgressCallbackC>> progressCb,
    );
typedef BackupRequestDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> op,
      Pointer<Utf8> argsJson,
      Pointer<NativeFunction<ProgressCallbackC>> progressCb,
    );

typedef CancelBackupC = Void Function();
typedef CancelBackupDart = void Function();

typedef ProgressCallbackC = Void Function(Uint64, Uint64);

/// 备份结果
class BackupResult {
  /// 0=成功, 1=路径无效, 2=IO错误, 3=已取消, 4=其他
  final int code;

  /// 失败时的错误信息 (来自 Rust get_last_error)
  final String? error;

  const BackupResult(this.code, this.error);

  bool get isSuccess => code == 0;
  bool get isCancelled => code == 3;
}

/// `backup_request` 的返回结果（JSON envelope 的 Dart 表示）。
///
/// Rust 侧返回 `{"ok":true,"data":{...}}` 或
/// `{"ok":false,"error":"...","cancelled":bool}`。
class BackupOpResult {
  /// 是否成功。
  final bool ok;

  /// 是否因为用户取消而失败。
  final bool cancelled;

  /// 失败信息。
  final String? error;

  /// 成功时的数据体（字段随 op 不同）。
  final Map<String, dynamic> data;

  const BackupOpResult({
    required this.ok,
    this.cancelled = false,
    this.error,
    this.data = const {},
  });

  factory BackupOpResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return BackupOpResult(
      ok: json['ok'] == true,
      cancelled: json['cancelled'] == true,
      error: json['error'] as String?,
      data: data is Map<String, dynamic> ? data : const {},
    );
  }

  @override
  String toString() =>
      'BackupOpResult(ok=$ok, cancelled=$cancelled, error=$error)';
}

/// 传递给后台 isolate 的压缩请求
class _BackupRequest {
  final String srcPath;
  final String dstPath;
  final List<String> files;
  final int compressionLevel;
  final SendPort sendPort;

  /// 主 isolate 创建的 NativeCallable 的 native 函数指针地址。
  /// Rust (rayon 线程) 调用它时，参数投递到主 isolate 实时处理。
  final int progressCbAddress;

  const _BackupRequest(
    this.srcPath,
    this.dstPath,
    this.files,
    this.compressionLevel,
    this.sendPort,
    this.progressCbAddress,
  );
}

/// 传递给后台 isolate 的 `backup_request` 调用参数。
class _BackupOpRequest {
  final String op;
  final String argsJson;
  final SendPort sendPort;
  final int progressCbAddress;

  const _BackupOpRequest(
    this.op,
    this.argsJson,
    this.sendPort,
    this.progressCbAddress,
  );
}

/// 备份服务 - Rust FFI 封装
///
/// 所有耗时的 FFI 调用都在后台 isolate 执行，UI 线程不会阻塞。
/// 进度通过 NativeCallable + SendPort 实时回传主 isolate。
class BackupService {
  static BackupService? _instance;
  static DynamicLibrary? _lib;

  late final CancelBackupDart _cancelBackup;
  late final GetLastErrorDart _getLastError;
  late final FreeStringDart _freeString;

  BackupService._() {
    _lib = _openLibrary();
    _cancelBackup = _lib!.lookupFunction<CancelBackupC, CancelBackupDart>(
      'cancel_backup',
    );
    _getLastError = _lib!.lookupFunction<GetLastErrorC, GetLastErrorDart>(
      'get_last_error',
    );
    _freeString = _lib!.lookupFunction<FreeStringC, FreeStringDart>(
      'free_string',
    );
  }

  /// 获取单例实例
  static BackupService get instance => _instance ??= BackupService._();

  /// 打开动态库
  static DynamicLibrary _openLibrary() => openRustLibrary('backup');

  /// 执行全量压缩备份 (在后台 isolate，不阻塞 UI)
  ///
  /// 兼容旧调用方式（只压缩 [files] 指定的条目）。实例备份页已改用
  /// [request] 的 `full_create`，该方法保留给其它调用方/测试。
  ///
  /// [srcPath] 源目录
  /// [dstPath] 目标文件路径
  /// [files] 要备份的文件/文件夹列表
  /// [compressionLevel] Deflate 压缩级别 (0-9, 0=仅存储, 6=标准, 9=最佳)
  /// [onProgress] 进度回调 (0.0 ~ 1.0)，在主 isolate 触发
  ///
  /// 返回 [BackupResult]，包含结果码和（失败时）错误信息
  Future<BackupResult> backup(
    String srcPath,
    String dstPath,
    List<String> files, {
    int compressionLevel = 6,
    void Function(double progress)? onProgress,
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<BackupResult>();

    // 在主 isolate 创建 NativeCallable.listener：native 函数被调用时，
    // 参数通过内部 SendPort 投递到主 isolate (未阻塞)，回调实时执行。
    // 可从任意线程 (含 rayon 工作线程) 并发安全调用。
    // 必须在主 isolate 创建：回调在此 isolate 执行，主 isolate 空闲才能实时处理。
    late NativeCallable<ProgressCallbackC> cb;
    cb = NativeCallable<ProgressCallbackC>.listener((int processed, int total) {
      final progress = total > 0 ? processed / total : 0.0;
      onProgress?.call(progress);
    });

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is BackupResult) {
        if (!completer.isCompleted) completer.complete(msg);
      }
    });

    await Isolate.spawn(
      _backupIsolate,
      _BackupRequest(
        srcPath,
        dstPath,
        files,
        compressionLevel,
        responsePort.sendPort,
        cb.nativeFunction.address,
      ),
    );

    final result = await completer.future;
    await sub.cancel();
    responsePort.close();
    cb.close();
    return result;
  }

  /// 调用 Rust 统一备份入口 `backup_request`（后台 isolate，不阻塞 UI）。
  ///
  /// [op] 支持：
  /// - `status`：仓库概览（策略、平台、全量/增量列表）
  /// - `full_create` / `full_restore` / `full_delete`：全量备份
  /// - `snapshot_create` / `snapshot_restore` / `snapshot_verify` /
  ///   `snapshot_delete`：增量备份
  /// - `gc`：回收未被引用的内容寻址对象
  ///
  /// [args] 原样 JSON 序列化后交给 Rust（键名 camelCase：
  /// `repoRoot` / `sourceRoot` / `name` / `parent` / `targetRoot` /
  /// `compressionLevel` / `prune` / `deep` / `label`）。
  ///
  /// [onProgress] 在主 isolate 触发，参数为 `(已处理, 总量)`；若 Rust 侧无法
  /// 预估总量则不会回调（UI 显示不确定进度）。
  Future<BackupOpResult> request(
    String op,
    Map<String, Object?> args, {
    void Function(int processed, int total)? onProgress,
    Duration timeout = const Duration(hours: 6),
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<BackupOpResult>();

    late NativeCallable<ProgressCallbackC> cb;
    cb = NativeCallable<ProgressCallbackC>.listener((int processed, int total) {
      onProgress?.call(processed, total);
    });

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (completer.isCompleted) return;
      if (msg is Map<String, dynamic>) {
        completer.complete(BackupOpResult.fromJson(msg));
      } else if (msg is String) {
        completer.complete(
          BackupOpResult(ok: false, error: msg, cancelled: false),
        );
      }
    });

    Isolate? isolate;
    var finished = false;
    try {
      isolate = await Isolate.spawn(
        _requestIsolate,
        _BackupOpRequest(
          op,
          jsonEncode(args),
          responsePort.sendPort,
          cb.nativeFunction.address,
        ),
      );
      final result = await completer.future.timeout(timeout);
      finished = true;
      return result;
    } on TimeoutException {
      // 超时后 Rust 侧仍在执行：不要关闭 NativeCallable（会被并发调用），
      // 直接杀掉后台 isolate 并返回错误，指针泄漏的代价远小于崩溃。
      isolate?.kill(priority: Isolate.immediate);
      return BackupOpResult(ok: false, error: '备份操作超时: $timeout');
    } finally {
      await sub.cancel();
      responsePort.close();
      if (finished) cb.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析 JSON 并发送回主 isolate。
  static void _requestIsolate(_BackupOpRequest req) {
    Pointer<Utf8>? opPtr;
    Pointer<Utf8>? argsPtr;

    try {
      // 后台 isolate 独立打开库 (DynamicLibrary 句柄不能跨 isolate 传递)
      final lib = _openLibrary();
      final backupRequest = lib
          .lookupFunction<BackupRequestC, BackupRequestDart>('backup_request');
      final freeString = lib.lookupFunction<FreeStringC, FreeStringDart>(
        'free_string',
      );

      opPtr = req.op.toNativeUtf8();
      argsPtr = req.argsJson.toNativeUtf8();
      final progressCb = Pointer<NativeFunction<ProgressCallbackC>>.fromAddress(
        req.progressCbAddress,
      );

      final outPtr = backupRequest(opPtr, argsPtr, progressCb);
      if (outPtr == nullptr) {
        req.sendPort.send('backup_request 返回空指针');
        return;
      }
      String text;
      try {
        text = outPtr.toDartString();
      } finally {
        freeString(outPtr);
      }

      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        req.sendPort.send(decoded);
      } else {
        req.sendPort.send('无法解析备份返回结果: $text');
      }
    } catch (e) {
      req.sendPort.send('备份 FFI 调用异常: $e');
    } finally {
      if (opPtr != null) calloc.free(opPtr);
      if (argsPtr != null) calloc.free(argsPtr);
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、发送结果
  ///
  /// FFI 调用在此 isolate 同步执行，但因为是后台 isolate，
  /// 不会阻塞主 isolate 的 UI。进度回调由主 isolate 创建的
  /// NativeCallable 处理 (地址通过请求传入)，rayon 线程调用它时
  /// 实时投递到主 isolate。
  static void _backupIsolate(_BackupRequest req) {
    Pointer<Utf8>? srcPtr;
    Pointer<Utf8>? dstPtr;
    Pointer<Pointer<Utf8>>? filesPtr;

    try {
      // 后台 isolate 独立打开库 (DynamicLibrary 句柄不能跨 isolate 传递)
      final lib = _openLibrary();
      final backupDirectory = lib
          .lookupFunction<BackupDirectoryC, BackupDirectoryDart>(
            'backup_directory',
          );
      final getLastError = lib.lookupFunction<GetLastErrorC, GetLastErrorDart>(
        'get_last_error',
      );
      final freeString = lib.lookupFunction<FreeStringC, FreeStringDart>(
        'free_string',
      );

      // 分配 native 内存
      srcPtr = req.srcPath.toNativeUtf8();
      dstPtr = req.dstPath.toNativeUtf8();
      filesPtr = calloc<Pointer<Utf8>>(req.files.length);
      for (var i = 0; i < req.files.length; i++) {
        filesPtr[i] = req.files[i].toNativeUtf8();
      }

      // 由主 isolate 创建的进度回调 native 函数指针
      final progressCb = Pointer<NativeFunction<ProgressCallbackC>>.fromAddress(
        req.progressCbAddress,
      );

      final code = backupDirectory(
        srcPtr,
        dstPtr,
        filesPtr,
        req.files.length,
        req.compressionLevel,
        progressCb,
      );

      // 在后台 isolate 获取错误信息 (thread_local 属于此 isolate 的线程)
      String? error;
      if (code != 0 && code != 3) {
        final errPtr = getLastError();
        if (errPtr != nullptr) {
          try {
            error = errPtr.toDartString();
          } finally {
            freeString(errPtr);
          }
        }
      }
      req.sendPort.send(BackupResult(code, error));
    } catch (e) {
      req.sendPort.send(BackupResult(4, '后台 isolate 异常: $e'));
    } finally {
      if (srcPtr != null) calloc.free(srcPtr);
      if (dstPtr != null) calloc.free(dstPtr);
      if (filesPtr != null) {
        // 逐个释放字符串指针，再释放指针数组本身
        for (var i = 0; i < req.files.length; i++) {
          calloc.free(filesPtr[i]);
        }
        calloc.free(filesPtr);
      }
    }
  }

  /// 取消当前备份/恢复（设置全局标志，后台 isolate 的线程会检测到）
  void cancel() {
    _cancelBackup();
  }

  /// 获取最后的错误信息 (主 isolate 调用，仅用于未进入后台 isolate 的场景)
  String? getLastError() {
    final ptr = _getLastError();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }
}
