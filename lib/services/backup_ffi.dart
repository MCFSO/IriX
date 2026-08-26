// Rust FFI 备份压缩绑定
// 通过 dart:ffi 调用 Rust 编译的动态库实现 ZIP (Deflate) 压缩
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程

import 'dart:async';
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

/// 传递给后台 isolate 的请求
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

  /// 执行备份 (在后台 isolate，不阻塞 UI)
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
        completer.complete(msg);
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

  /// 取消备份 (设置全局标志，后台 isolate 的压缩线程会检测到)
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
