// Rust FFI 备份压缩绑定
// 通过 dart:ffi 调用 Rust 编译的动态库实现 LZMA2 压缩

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

typedef ProgressCallbackC = Void Function(Uint64, Uint64);
typedef ProgressCallbackDart = void Function(int, int);

/// 备份服务 - Rust FFI 封装
class BackupService {
  static BackupService? _instance;
  static DynamicLibrary? _lib;

  late final BackupDirectoryDart _backupDirectory;
  late final CancelBackupDart _cancelBackup;

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
  }

  /// 获取单例实例
  static BackupService get instance => _instance ??= BackupService._();

  /// 打开动态库
  static DynamicLibrary _openLibrary() {
    // 尝试多个可能的路径
    final possiblePaths = _getPossibleLibraryPaths();

    for (final libPath in possiblePaths) {
      try {
        final file = File(libPath);
        if (file.existsSync()) {
          return DynamicLibrary.open(libPath);
        }
      } catch (_) {
        // 继续尝试下一个路径
      }
    }

    // 如果都找不到，尝试使用系统默认搜索路径
    try {
      if (Platform.isWindows) {
        return DynamicLibrary.open('xmc_backup.dll');
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libxmc_backup.dylib');
      } else {
        return DynamicLibrary.open('libxmc_backup.so');
      }
    } catch (_) {
      throw UnsupportedError(
        'Rust backup library not found. '
        'Please ensure xmc_backup.dll/.so/.dylib is in the application directory.',
      );
    }
  }

  /// 获取可能的库路径列表
  static List<String> _getPossibleLibraryPaths() {
    final paths = <String>[];

    // 当前工作目录
    final cwd = Directory.current.path;
    if (Platform.isWindows) {
      paths.add(p.join(cwd, 'xmc_backup.dll'));
      paths.add(p.join(cwd, 'windows', 'runner', 'xmc_backup.dll'));
    } else if (Platform.isMacOS) {
      paths.add(p.join(cwd, 'libxmc_backup.dylib'));
      paths.add(p.join(cwd, 'macos', 'libxmc_backup.dylib'));
    } else {
      paths.add(p.join(cwd, 'libxmc_backup.so'));
      paths.add(p.join(cwd, 'linux', 'libxmc_backup.so'));
    }

    // 可执行文件目录
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      if (Platform.isWindows) {
        paths.add(p.join(exeDir, 'xmc_backup.dll'));
      } else if (Platform.isMacOS) {
        // macOS 应用包内部
        paths.add(p.join(exeDir, '..', 'Frameworks', 'libxmc_backup.dylib'));
        paths.add(p.join(exeDir, 'libxmc_backup.dylib'));
      } else {
        paths.add(p.join(exeDir, 'libxmc_backup.so'));
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

  /// 进度回调 (native 调用)
  static void _progressCallback(int processed, int total) {
    final progress = total > 0 ? processed / total : 0.0;
    instance.onProgress?.call(progress);
  }
}