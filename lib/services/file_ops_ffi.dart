// 文件操作服务 (Rust FFI 实现)
// 通过 dart:ffi 调用 Rust 编译的动态库 (xmc_file_ops.dll) 实现高性能文件操作
// 大文件复制/移动在后台 isolate 执行，避免阻塞 UI 线程
//
// Rust 端实现位于 rust/file_ops/src/lib.rs

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// 文件/目录条目信息
class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String,
      path: json['path'] as String,
      isDirectory: json['is_directory'] as bool,
      size: json['size'] as int,
      modified: DateTime.fromMillisecondsSinceEpoch(
          (json['modified'] as int) * 1000,
        ),
    );
  }
}

/// FFI 函数签名定义
typedef ScanDirC = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef ScanDirDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef GetFileInfoC = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef GetFileInfoDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef ClipboardSetC = Void Function(Pointer<Utf8> path, Int32 isCut);
typedef ClipboardSetDart = void Function(Pointer<Utf8> path, int isCut);

typedef ClipboardGetC = Pointer<Utf8> Function();
typedef ClipboardGetDart = Pointer<Utf8> Function();

typedef ClipboardClearC = Void Function();
typedef ClipboardClearDart = void Function();

typedef CopyFileC = Int32 Function(
  Pointer<Utf8> src,
  Pointer<Utf8> dst,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);
typedef CopyFileDart = int Function(
  Pointer<Utf8> src,
  Pointer<Utf8> dst,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);

typedef MoveFileC = Int32 Function(
  Pointer<Utf8> src,
  Pointer<Utf8> dst,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);
typedef MoveFileDart = int Function(
  Pointer<Utf8> src,
  Pointer<Utf8> dst,
  Pointer<NativeFunction<ProgressCallbackC>> progressCb,
);

typedef DeleteToTrashC = Int32 Function(
  Pointer<Utf8> rootPath,
  Pointer<Utf8> filePath,
);
typedef DeleteToTrashDart = int Function(
  Pointer<Utf8> rootPath,
  Pointer<Utf8> filePath,
);

typedef DeletePermanentlyC = Int32 Function(Pointer<Utf8> path);
typedef DeletePermanentlyDart = int Function(Pointer<Utf8> path);

typedef CreateDirectoryC = Int32 Function(Pointer<Utf8> path);
typedef CreateDirectoryDart = int Function(Pointer<Utf8> path);

typedef RenameEntryC = Int32 Function(
  Pointer<Utf8> oldPath,
  Pointer<Utf8> newPath,
);
typedef RenameEntryDart = int Function(
  Pointer<Utf8> oldPath,
  Pointer<Utf8> newPath,
);

typedef CancelOperationC = Void Function();
typedef CancelOperationDart = void Function();

typedef GetLastErrorC = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

typedef ProgressCallbackC = Void Function(Uint64 current, Uint64 total);

/// 文件操作结果码
enum FileOpResultCode {
  success(0),
  invalidPath(1),
  ioError(2),
  cancelled(3),
  unknown(9);

  final int value;
  const FileOpResultCode(this.value);

  static FileOpResultCode fromValue(int value) {
    return FileOpResultCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => FileOpResultCode.unknown,
    );
  }
}

/// 传递给后台 isolate 的文件操作请求
class _FileOpRequest {
  final String src;
  final String dst;
  final bool isMove;
  final SendPort sendPort;
  final int? progressCbAddress;

  const _FileOpRequest(
    this.src,
    this.dst,
    this.isMove,
    this.sendPort,
    this.progressCbAddress,
  );
}

/// 后台 isolate 发送的完成消息
class _CompletionMessage {
  final int code;
  final String? error;
  const _CompletionMessage(this.code, this.error);
}

/// 动态库访问抽象
abstract class _FileOpsLib {
  static DynamicLibrary? _lib;
  static final List<String> _attempts = [];

  static DynamicLibrary get lib {
    if (_lib != null) return _lib!;
    final libName = Platform.isWindows
        ? 'xmc_file_ops.dll'
        : Platform.isMacOS
            ? 'libxmc_file_ops.dylib'
            : 'libxmc_file_ops.so';

    for (final libPath in _getPossibleLibraryPaths(libName)) {
      try {
        final file = File(libPath);
        if (file.existsSync()) {
          _lib = DynamicLibrary.open(libPath);
          return _lib!;
        } else {
          _attempts.add('$libPath (文件不存在)');
        }
      } catch (e) {
        _attempts.add('$libPath (加载失败: $e)');
      }
    }

    try {
      _lib = DynamicLibrary.open(libName);
      return _lib!;
    } catch (e) {
      _attempts.add('系统搜索路径 "$libName" (加载失败: $e)');
    }

    throw UnsupportedError(
      'Rust file_ops library not found.\n'
      'cwd: ${Directory.current.path}\n'
      'exe: ${Platform.resolvedExecutable}\n'
      '尝试的路径:\n${_attempts.map((a) => '  - $a').join('\n')}',
    );
  }

  static List<String> _getPossibleLibraryPaths(String libName) {
    final paths = <String>[];
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
        if (parent == dir) break;
        dir = parent;
      }
    } catch (_) {}

    return paths;
  }
}

/// 文件操作服务 (Rust FFI 实现)。
///
/// 封装基于 Rust 的高性能文件操作逻辑。
/// 大文件 (>1MB) 的复制/移动在后台 isolate 执行以避免阻塞 UI，
/// 进度通过 NativeCallable + SendPort 实时回传主 isolate。
class FileOps {
  /// 扫描目录，返回文件/目录条目列表
  static List<FileEntry> scanDir(String path) {
    final lib = _FileOpsLib.lib;
    final scanDir =
        lib.lookupFunction<ScanDirC, ScanDirDart>('scan_dir');
    final freeString =
        lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

    final pathPtr = path.toNativeUtf8();
    try {
      final jsonPtr = scanDir(pathPtr);
      if (jsonPtr == nullptr) return [];
      try {
        final json = jsonPtr.toDartString();
        final list = jsonDecode(json) as List<dynamic>;
        return list
            .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } finally {
        freeString(jsonPtr);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 获取单个文件/目录信息，不存在时返回 null
  static FileEntry? getFileInfo(String path) {
    final lib = _FileOpsLib.lib;
    final getFileInfo =
        lib.lookupFunction<GetFileInfoC, GetFileInfoDart>('get_file_info');
    final freeString =
        lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

    final pathPtr = path.toNativeUtf8();
    try {
      final jsonPtr = getFileInfo(pathPtr);
      if (jsonPtr == nullptr) return null;
      try {
        final json = jsonPtr.toDartString();
        if (json.isEmpty) return null;
        final map = jsonDecode(json) as Map<String, dynamic>;
        return FileEntry.fromJson(map);
      } finally {
        freeString(jsonPtr);
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 设置剪贴板内容
  static void clipboardSet(String path, bool isCut) {
    final lib = _FileOpsLib.lib;
    final clipboardSet =
        lib.lookupFunction<ClipboardSetC, ClipboardSetDart>('clipboard_set');

    final pathPtr = path.toNativeUtf8();
    try {
      clipboardSet(pathPtr, isCut ? 1 : 0);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 获取剪贴板内容，无内容时返回 null
  static ({String path, bool isCut})? clipboardGet() {
    final lib = _FileOpsLib.lib;
    final clipboardGet =
        lib.lookupFunction<ClipboardGetC, ClipboardGetDart>('clipboard_get');
    final freeString =
        lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

    final jsonPtr = clipboardGet();
    if (jsonPtr == nullptr) return null;
    try {
      final json = jsonPtr.toDartString();
      if (json.isEmpty) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      return (
        path: map['path'] as String,
        isCut: map['is_cut'] as bool,
      );
    } finally {
      freeString(jsonPtr);
    }
  }

  /// 清空剪贴板
  static void clipboardClear() {
    final lib = _FileOpsLib.lib;
    final clipboardClear =
        lib.lookupFunction<ClipboardClearC, ClipboardClearDart>(
            'clipboard_clear');
    clipboardClear();
  }

  /// 复制文件
  ///
  /// [src] 源文件路径，[dst] 目标路径，[onProgress] 进度回调 (current/total 单位: bytes)。
  /// 小文件 (<1MB) 在主 isolate 直接执行，大文件在后台 isolate 执行。
  static Future<bool> copyFile(
    String src,
    String dst, {
    void Function(int current, int total)? onProgress,
  }) async {
    return _copyOrMove(src, dst, false, onProgress: onProgress);
  }

  /// 移动文件
  ///
  /// [src] 源文件路径，[dst] 目标路径，[onProgress] 进度回调 (current/total 单位: bytes)。
  /// 小文件 (<1MB) 在主 isolate 直接执行，大文件在后台 isolate 执行。
  static Future<bool> moveFile(
    String src,
    String dst, {
    void Function(int current, int total)? onProgress,
  }) async {
    return _copyOrMove(src, dst, true, onProgress: onProgress);
  }

  /// 复制或移动文件的内部实现
  static Future<bool> _copyOrMove(
    String src,
    String dst,
    bool isMove, {
    void Function(int current, int total)? onProgress,
  }) async {
    final srcFile = File(src);
    final size = await srcFile.exists()
        ? await srcFile.length()
        : -1;

    final isSmall = size >= 0 && size < 1024 * 1024;

    if (isSmall) {
      return _copyOrMoveSync(src, dst, isMove, nullptr);
    }

    if (onProgress == null) {
      return await Isolate.run(() => _fileOpIsolateNoProgress(src, dst, isMove));
    }

    final responsePort = ReceivePort();
    final completer = Completer<bool>();

    late NativeCallable<ProgressCallbackC> cb;
    cb = NativeCallable<ProgressCallbackC>.listener(
        (int current, int total) {
      onProgress(current, total);
    });

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is _CompletionMessage) {
        completer.complete(msg.code == 0);
      }
    });

    await Isolate.spawn(
      _fileOpIsolateWithProgress,
      _FileOpRequest(
        src,
        dst,
        isMove,
        responsePort.sendPort,
        cb.nativeFunction.address,
      ),
    );

    try {
      return await completer.future;
    } finally {
      await sub.cancel();
      responsePort.close();
      cb.close();
    }
  }

  static bool _copyOrMoveSync(
    String src,
    String dst,
    bool isMove,
    Pointer<NativeFunction<ProgressCallbackC>> progressCb,
  ) {
    final lib = _FileOpsLib.lib;
    final fnName = isMove ? 'move_file' : 'copy_file';
    final fn = isMove
        ? lib.lookupFunction<MoveFileC, MoveFileDart>(fnName)
        : lib.lookupFunction<CopyFileC, CopyFileDart>(fnName);

    final srcPtr = src.toNativeUtf8();
    final dstPtr = dst.toNativeUtf8();
    try {
      final code = fn(srcPtr, dstPtr, progressCb);
      return code == 0;
    } finally {
      calloc.free(srcPtr);
      calloc.free(dstPtr);
    }
  }

  /// 无进度的后台 isolate 入口
  static bool _fileOpIsolateNoProgress(String src, String dst, bool isMove) {
    return _copyOrMoveSync(src, dst, isMove, nullptr);
  }

  /// 带进度的后台 isolate 入口
  static void _fileOpIsolateWithProgress(_FileOpRequest req) {
    Pointer<Utf8>? srcPtr;
    Pointer<Utf8>? dstPtr;

    try {
      final lib = _FileOpsLib.lib;
      final getLastError =
          lib.lookupFunction<GetLastErrorC, GetLastErrorDart>('get_last_error');
      final freeString =
          lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

      final progressCb =
          Pointer<NativeFunction<ProgressCallbackC>>.fromAddress(
        req.progressCbAddress!,
      );

      final fn = req.isMove
          ? lib.lookupFunction<MoveFileC, MoveFileDart>('move_file')
          : lib.lookupFunction<CopyFileC, CopyFileDart>('copy_file');

      srcPtr = req.src.toNativeUtf8();
      dstPtr = req.dst.toNativeUtf8();

      final code = fn(srcPtr, dstPtr, progressCb);

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
      req.sendPort.send(_CompletionMessage(code, error));
    } catch (e) {
      req.sendPort.send(_CompletionMessage(9, '后台 isolate 异常: $e'));
    } finally {
      if (srcPtr != null) calloc.free(srcPtr);
      if (dstPtr != null) calloc.free(dstPtr);
    }
  }

  /// 删除到回收站
  ///
  /// 异步操作，返回 true 表示成功。
  static Future<bool> deleteToTrash(String rootPath, String filePath) async {
    return await Isolate.run(() => _deleteToTrashSync(rootPath, filePath));
  }

  static bool _deleteToTrashSync(String rootPath, String filePath) {
    final lib = _FileOpsLib.lib;
    final deleteToTrash =
        lib.lookupFunction<DeleteToTrashC, DeleteToTrashDart>(
            'delete_to_trash');

    final rootPtr = rootPath.toNativeUtf8();
    final filePtr = filePath.toNativeUtf8();
    try {
      final code = deleteToTrash(rootPtr, filePtr);
      return code == 0;
    } finally {
      calloc.free(rootPtr);
      calloc.free(filePtr);
    }
  }

  /// 永久删除文件/目录
  ///
  /// 异步操作，返回 true 表示成功。
  static Future<bool> deletePermanently(String path) async {
    return await Isolate.run(() => _deletePermanentlySync(path));
  }

  static bool _deletePermanentlySync(String path) {
    final lib = _FileOpsLib.lib;
    final deletePermanently =
        lib.lookupFunction<DeletePermanentlyC, DeletePermanentlyDart>(
            'delete_permanently');

    final pathPtr = path.toNativeUtf8();
    try {
      final code = deletePermanently(pathPtr);
      return code == 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 创建目录
  ///
  /// 异步操作，返回 true 表示成功。
  static Future<bool> createDirectory(String path) async {
    return await Isolate.run(() => _createDirectorySync(path));
  }

  static bool _createDirectorySync(String path) {
    final lib = _FileOpsLib.lib;
    final createDirectory =
        lib.lookupFunction<CreateDirectoryC, CreateDirectoryDart>(
            'create_directory');

    final pathPtr = path.toNativeUtf8();
    try {
      final code = createDirectory(pathPtr);
      return code == 0;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 重命名文件/目录
  ///
  /// 异步操作，返回 true 表示成功。
  static Future<bool> renameEntry(String oldPath, String newPath) async {
    return await Isolate.run(() => _renameEntrySync(oldPath, newPath));
  }

  static bool _renameEntrySync(String oldPath, String newPath) {
    final lib = _FileOpsLib.lib;
    final renameEntry =
        lib.lookupFunction<RenameEntryC, RenameEntryDart>('rename_entry');

    final oldPtr = oldPath.toNativeUtf8();
    final newPtr = newPath.toNativeUtf8();
    try {
      final code = renameEntry(oldPtr, newPtr);
      return code == 0;
    } finally {
      calloc.free(oldPtr);
      calloc.free(newPtr);
    }
  }

  /// 取消当前正在执行的文件操作
  static void cancelOperation() {
    try {
      final lib = _FileOpsLib.lib;
      final cancelOperation =
          lib.lookupFunction<CancelOperationC, CancelOperationDart>(
              'cancel_operation');
      cancelOperation();
    } catch (_) {}
  }

  /// 获取最后的错误信息
  static String? getLastError() {
    try {
      final lib = _FileOpsLib.lib;
      final getLastError =
          lib.lookupFunction<GetLastErrorC, GetLastErrorDart>('get_last_error');
      final freeString =
          lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

      final ptr = getLastError();
      if (ptr == nullptr) return null;
      try {
        return ptr.toDartString();
      } finally {
        freeString(ptr);
      }
    } catch (_) {
      return null;
    }
  }
}
