// 文件下载服务 (Rust FFI 实现)
// 通过 dart:ffi 调用 Rust 编译的动态库 (xmc_downloader.dll) 实现 HTTP 流式下载
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程
//
// Rust 端实现位于 rust/downloader/src/lib.rs 的 download_file 函数，
// 使用 ureq + rustls 提供 HTTPS 支持，无需系统 OpenSSL 依赖。

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// 下载进度信息。
///
/// 由 [Downloader.downloadFile] 在下载过程中周期性回调，
/// 用于驱动 UI 进度条与速度显示等。
class DownloadProgress {
  /// 已下载的字节数。
  final int downloadedBytes;

  /// 文件总字节数，服务端未提供时为 -1。
  final int totalBytes;

  /// 当前下载速度（字节/秒）。
  final double speedBytesPerSec;

  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
  });

  /// 下载百分比（0.0 - 100.0）。
  ///
  /// 总字节数未知（<= 0）时返回 0.0。
  double get percent {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes) * 100.0;
  }
}

/// FFI 函数签名定义
typedef DownloadFileC = Int32 Function(
  Pointer<Utf8> url,
  Pointer<Utf8> targetPath,
  Pointer<Utf8> userAgent,
  Pointer<NativeFunction<DownloadProgressCallbackC>> progressCb,
);
typedef DownloadFileDart = int Function(
  Pointer<Utf8> url,
  Pointer<Utf8> targetPath,
  Pointer<Utf8> userAgent,
  Pointer<NativeFunction<DownloadProgressCallbackC>> progressCb,
);

/// 多线程分片下载 FFI 签名 (对应 Rust download_file_multipart)
typedef DownloadFileMultipartC = Int32 Function(
  Pointer<Utf8> url,
  Pointer<Utf8> targetPath,
  Pointer<Utf8> userAgent,
  Int32 threads,
  Pointer<NativeFunction<DownloadProgressCallbackC>> progressCb,
);
typedef DownloadFileMultipartDart = int Function(
  Pointer<Utf8> url,
  Pointer<Utf8> targetPath,
  Pointer<Utf8> userAgent,
  int threads,
  Pointer<NativeFunction<DownloadProgressCallbackC>> progressCb,
);

typedef CancelDownloadC = Void Function();
typedef CancelDownloadDart = void Function();

typedef GetLastErrorC = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

typedef DownloadProgressCallbackC = Void Function(Uint64, Uint64);

/// 下载结果码
enum DownloadResultCode {
  /// 成功
  success(0),
  /// URL 或路径无效
  invalidPath(1),
  /// 网络/IO 错误
  networkError(2),
  /// 用户取消
  cancelled(3),
  /// HTTP 状态码非 2xx
  httpError(4),
  /// 其他错误
  unknown(5);

  final int value;
  const DownloadResultCode(this.value);

  static DownloadResultCode fromValue(int value) {
    return DownloadResultCode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DownloadResultCode.unknown,
    );
  }
}

/// 下载请求参数 (传递给后台 isolate)
class _DownloadRequest {
  final String url;
  final String targetFilePath;
  final String userAgent;
  final SendPort sendPort;
  /// 主 isolate 创建的 NativeCallable 的 native 函数指针地址。
  final int progressCbAddress;
  /// 多线程下载的线程数；为 null 时使用单线程 download_file。
  final int? threads;

  const _DownloadRequest(
    this.url,
    this.targetFilePath,
    this.userAgent,
    this.sendPort,
    this.progressCbAddress, {
    this.threads,
  });
}

/// 后台 isolate 发送的完成消息
class _CompletionMessage {
  final int code;
  final String? error;
  const _CompletionMessage(this.code, this.error);
}

/// 文件下载服务 (Rust FFI 实现)。
///
/// 封装基于 Rust ureq 的流式下载逻辑，所有 FFI 调用在后台 isolate
/// 执行以避免阻塞 UI，进度通过 NativeCallable + SendPort 实时回传主 isolate。
///
/// 独立的下载动态库 (xmc_downloader.dll)，与备份库解耦。
class Downloader {
  static const String _defaultUserAgent =
      'xmcserverlancher/1.0.0 (https://github.com/mcfso/xmcserverlancher)';

  /// 打开动态库 (xmc_downloader)
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];
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

    final sysName = Platform.isWindows
        ? 'xmc_downloader.dll'
        : Platform.isMacOS
            ? 'libxmc_downloader.dylib'
            : 'libxmc_downloader.so';
    try {
      return DynamicLibrary.open(sysName);
    } catch (e) {
      attempts.add('系统搜索路径 "$sysName" (加载失败: $e)');
    }

    throw UnsupportedError(
      'Rust downloader library not found.\n'
      'cwd: ${Directory.current.path}\n'
      'exe: ${Platform.resolvedExecutable}\n'
      '尝试的路径:\n${attempts.map((a) => '  - $a').join('\n')}',
    );
  }

  /// 获取可能的库路径列表
  static List<String> _getPossibleLibraryPaths() {
    final paths = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_downloader.dll'
        : Platform.isMacOS
            ? 'libxmc_downloader.dylib'
            : 'libxmc_downloader.so';

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
        if (parent == dir) break;
        dir = parent;
      }
    } catch (_) {
      // 忽略
    }

    return paths;
  }

  /// 下载指定 URL 的文件到目标路径。
  ///
  /// [url] 资源地址；[targetFilePath] 本地保存路径；[onProgress] 进度回调。
  /// [threads] 多线程分片下载线程数；为 null 或 <= 1 时使用单线程流式下载，
  /// 大于 1 时调用 Rust 端 [download_file_multipart] 进行多线程断点续传下载
  /// (服务端不支持 Range 或无 Content-Length 时自动回退为单线程)。
  ///
  /// 实际下载由 Rust 的 FFI 函数执行 (基于 ureq + rustls)，
  /// 调用在后台 isolate 中进行，进度通过 NativeCallable 实时回传主 isolate。
  /// 成功时返回目标文件路径；失败时抛出 [Exception]。
  Future<String> downloadFile(
    String url,
    String targetFilePath,
    void Function(DownloadProgress) onProgress, {
    int? threads,
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<String>();

    // 主 isolate 记录速度计算所需的时间戳和已下载字节
    final stopwatch = Stopwatch()..start();
    var lastTickBytes = 0;

    // 主 isolate 创建 NativeCallable.listener：Rust 调用它时，
    // 参数通过内部 SendPort 投递到主 isolate (未阻塞)，进度回调实时执行。
    late NativeCallable<DownloadProgressCallbackC> cb;
    cb = NativeCallable<DownloadProgressCallbackC>.listener((int downloaded, int total) {
      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      final deltaBytes = downloaded - lastTickBytes;
      final speed = elapsedSeconds > 0 ? deltaBytes / elapsedSeconds : 0.0;
      lastTickBytes = downloaded;
      stopwatch.reset();

      onProgress(DownloadProgress(
        downloadedBytes: downloaded,
        totalBytes: total > 0 ? total : -1,
        speedBytesPerSec: speed,
      ));
    });

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is _CompletionMessage) {
        if (msg.code == 0) {
          completer.complete(targetFilePath);
        } else if (msg.code == 3) {
          completer.completeError(
            Exception('下载已取消'),
          );
        } else {
          completer.completeError(
            Exception('下载失败 (${DownloadResultCode.fromValue(msg.code)}): ${msg.error ?? "未知错误"}'),
          );
        }
      }
    });

    final useThreads = (threads ?? 1) > 1 ? threads : null;

    await Isolate.spawn(
      _downloadIsolate,
      _DownloadRequest(
        url,
        targetFilePath,
        _defaultUserAgent,
        responsePort.sendPort,
        cb.nativeFunction.address,
        threads: useThreads,
      ),
    );

    try {
      final result = await completer.future;
      return result;
    } finally {
      await sub.cancel();
      responsePort.close();
      cb.close();
    }
  }

  /// 后台 isolate 入口：打开库、调用 FFI、发送结果
  static void _downloadIsolate(_DownloadRequest req) {
    Pointer<Utf8>? urlPtr;
    Pointer<Utf8>? targetPtr;
    Pointer<Utf8>? uaPtr;

    try {
      // 后台 isolate 独立打开库
      final lib = _openLibrary();
      final getLastError =
          lib.lookupFunction<GetLastErrorC, GetLastErrorDart>('get_last_error');
      final freeString =
          lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

      // 由主 isolate 创建的进度回调 native 函数指针
      final progressCb =
          Pointer<NativeFunction<DownloadProgressCallbackC>>.fromAddress(
        req.progressCbAddress,
      );

      // 分配 native 内存 (非空局部指针供 FFI 调用，可空外层指针供 finally 清理)。
      final Pointer<Utf8> url = req.url.toNativeUtf8();
      final Pointer<Utf8> target = req.targetFilePath.toNativeUtf8();
      final Pointer<Utf8> ua = req.userAgent.toNativeUtf8();
      urlPtr = url;
      targetPtr = target;
      uaPtr = ua;

      // threads > 1 时使用多线程分片断点续传下载，否则使用单线程流式下载。
      final code = () {
        if (req.threads != null && req.threads! > 1) {
          final downloadMultipart = lib.lookupFunction<
              DownloadFileMultipartC, DownloadFileMultipartDart>(
              'download_file_multipart');
          return downloadMultipart(
              url, target, ua, req.threads!, progressCb);
        }
        final downloadFile =
            lib.lookupFunction<DownloadFileC, DownloadFileDart>('download_file');
        return downloadFile(url, target, ua, progressCb);
      }();

      // 在后台 isolate 获取错误信息
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
      req.sendPort.send(_CompletionMessage(5, '后台 isolate 异常: $e'));
    } finally {
      if (urlPtr != null) calloc.free(urlPtr);
      if (targetPtr != null) calloc.free(targetPtr);
      if (uaPtr != null) calloc.free(uaPtr);
    }
  }
}
