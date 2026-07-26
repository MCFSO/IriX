// Rust FFI 备份压缩绑定
// 通过 dart:ffi 调用 Rust 编译的动态库实现 ZIP (Deflate) 压缩

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// FFI 函数签名定义
typedef BackupDirectoryC = Int32 Function(
  Pointer<Utf8> srcPath,
  Pointer<Utf8> dstPath,
  Pointer<Pointer<Utf8>> files,
  IntPtr filesCount,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);
typedef BackupDirectoryDart = int Function(
  Pointer<Utf8> srcPath,
  Pointer<Utf8> dstPath,
  Pointer<Pointer<Utf8>> files,
  int filesCount,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);

typedef CancelBackupC = Void Function();
typedef CancelBackupDart = void Function();

typedef GetLastErrorC = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

typedef ProgressCallbackC = Void Function(Uint64, Uint64);
typedef ProgressCallbackDart = void Function(int, int);

/// 备份服务 - Rust FFI 封装
class BackupService {
  static BackupService? _instance;
  static DynamicLibrary? _lib;

  late final BackupDirectoryDart _backupDirectory;
  late final CancelBackupDart _cancelBackup;
  late final GetLastErrorDart _getLastError;
  late final FreeStringDart _freeString;

  /// 进度回调
  void Function(double progress)? onProgress;

  BackupService._() {
    _lib = _openLibrary();
    _backupDirectory = _lib!.lookupFunction<BackupDirectoryC, BackupDirectoryDart>(
      'backup_directory',
    );
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
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];

    // 尝试多个可能的路径
    for (final libPath in _getPossibleLibraryPaths()) {
      try {
        final file = File(libPath);
        if (file.existsSync()) {
          return DynamicLibrary.open(libPath);
        } else {
          attempts.add('$libPath (文件不存在)');
        }
      } catch (e) {
        attempts.add('$libPath (加载失败: $e)');
      }
    }

    // 如果都找不到，尝试使用系统默认搜索路径
    final sysName = Platform.isWindows
        ? 'xmc_backup.dll'
        : Platform.isMacOS
            ? 'libxmc_backup.dylib'
            : 'libxmc_backup.so';
    try {
      return DynamicLibrary.open(sysName);
    } catch (e) {
      attempts.add('系统搜索路径 "$sysName" (加载失败: $e)');
    }

    throw UnsupportedError(
      'Rust backup library not found.\n'
      'cwd: ${Directory.current.path}\n'
      'exe: ${Platform.resolvedExecutable}\n'
      '尝试的路径:\n${attempts.map((a) => '  - $a').join('\n')}',
    );
  }

  /// 获取可能的库路径列表
  static List<String> _getPossibleLibraryPaths() {
    final paths = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_backup.dll'
        : Platform.isMacOS
            ? 'libxmc_backup.dylib'
            : 'libxmc_backup.so';

    // 当前工作目录
    final cwd = Directory.current.path;
    paths.add(p.join(cwd, libName));
    if (Platform.isWindows) {
      paths.add(p.join(cwd, 'windows', 'runner', libName));
    } else if (Platform.isMacOS) {
      paths.add(p.join(cwd, 'macos', libName));
    } else {
      paths.add(p.join(cwd, 'linux', libName));
    }

    // 从 exe 目录开始向上逐级查找
    // (flutter run 时 exe 位于 build/windows/runner/Debug 等子目录，需向上找项目根)
    try {
      final exePath = Platform.resolvedExecutable;
      var dir = p.dirname(exePath);
      for (var i = 0; i < 10; i++) {
        paths.add(p.join(dir, libName));
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

  /// 执行备份
  ///
  /// [srcPath] 源目录
  /// [dstPath] 目标文件路径
  /// [files] 要备份的文件/文件夹列表
  /// [onProgress] 进度回调 (0.0 ~ 1.0)
  ///
  /// 返回值:
  /// - 0: 成功
  /// - 1: 路径无效
  /// - 2: IO 错误
  /// - 3: 用户取消
  /// - 4: 其他错误
  Future<int> backup(
    String srcPath,
    String dstPath,
    List<String> files, {
    void Function(double progress)? onProgress,
  }) async {
    this.onProgress = onProgress;

    // 分配 native 内存
    final srcPtr = srcPath.toNativeUtf8();
    final dstPtr = dstPath.toNativeUtf8();

    // 创建文件列表指针数组
    final filesPtr = calloc<Pointer<Utf8>>(files.length);
    for (var i = 0; i < files.length; i++) {
      filesPtr[i] = files[i].toNativeUtf8();
    }

    // 创建进度回调
    final progressCb = Pointer.fromFunction<ProgressCallbackC>(_progressCallback);

    try {
      final result = _backupDirectory(
        srcPtr,
        dstPtr,
        filesPtr,
        files.length,
        progressCb,
      );
      return result;
    } finally {
      // 释放内存
      calloc.free(srcPtr);
      calloc.free(dstPtr);
      for (var i = 0; i < files.length; i++) {
        calloc.free(filesPtr[i]);
      }
      calloc.free(filesPtr);
    }
  }

  /// 取消备份
  void cancel() {
    _cancelBackup();
  }

  /// 获取最后的错误信息
  String? getLastError() {
    final ptr = _getLastError();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  /// 进度回调 (native 调用)
  static void _progressCallback(int processed, int total) {
    final progress = total > 0 ? processed / total : 0.0;
    instance.onProgress?.call(progress);
  }
}