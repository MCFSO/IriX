// Rust FFI 通用 HTTP 请求绑定
// 通过 dart:ffi 调用 Rust 动态库 (xmc_http_client.dll / libxmc_http_client.so/.dylib)
// 实现完整的 HTTP 请求（GET/POST/PUT/PATCH/DELETE/HEAD），
// Rust 侧使用 ureq + rustls，无 OpenSSL 依赖。
// 所有 FFI 调用在后台 isolate 执行，避免阻塞 UI 线程。

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'simd_ffi.dart';

/// FFI 函数签名定义
typedef HttpRequestC =
    Pointer<Utf8> Function(
      Pointer<Utf8> method,
      Pointer<Utf8> url,
      Pointer<Utf8> headersJson,
      Pointer<Uint8> body,
      IntPtr bodyLen,
      Uint64 timeoutSecs,
      Uint32 maxRedirects,
    );
typedef HttpRequestDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> method,
      Pointer<Utf8> url,
      Pointer<Utf8> headersJson,
      Pointer<Uint8> body,
      int bodyLen,
      int timeoutSecs,
      int maxRedirects,
    );

typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

typedef GetLastErrorC = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

/// HTTP 响应（Rust 侧解析后返回）
class HttpFfiResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  const HttpFfiResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  bool get isOk => statusCode >= 200 && statusCode < 300;

  /// 响应体按 UTF-8 解码（非文本内容请用 [bodyBytes]）。
  String get body => utf8.decode(bodyBytes, allowMalformed: true);

  @override
  String toString() =>
      'HttpFfiResponse($statusCode, headers: ${headers.length}, body: ${bodyBytes.length} bytes)';
}

/// HTTP 请求异常
class HttpFfiException implements Exception {
  final String message;

  /// HTTP 状态码（网络错误时为 null）
  final int? statusCode;

  const HttpFfiException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? 'HttpFfiException: $message'
      : 'HttpFfiException($statusCode): $message';
}

/// 传递给后台 isolate 的请求
class _HttpFfiRequest {
  final String method;
  final String url;
  final String headersJson;
  final Uint8List body;
  final int timeoutSecs;
  final int maxRedirects;
  final SendPort sendPort;

  const _HttpFfiRequest({
    required this.method,
    required this.url,
    required this.headersJson,
    required this.body,
    required this.timeoutSecs,
    required this.maxRedirects,
    required this.sendPort,
  });
}

/// Rust 通用 HTTP 客户端 — FFI 封装
///
/// 所有耗时的 FFI 调用都在后台 isolate 执行，UI 线程不会阻塞。
/// 全项目 HTTP 请求均经由本服务（以及 [Downloader] 负责大文件流式下载），
/// 接口设计对齐 http.Response 常用字段。
class HttpFfiService {
  static HttpFfiService? _instance;

  /// 单例实例（懒加载，首次调用时打开动态库）。
  static HttpFfiService get instance => _instance ??= HttpFfiService._();

  HttpFfiService._();

  /// 打开动态库（尝试多个可能的路径）。
  static DynamicLibrary _openLibrary() {
    final attempts = <String>[];
    final libName = Platform.isWindows
        ? 'xmc_http_client.dll'
        : Platform.isMacOS
        ? 'libxmc_http_client.dylib'
        : 'libxmc_http_client.so';

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
      'Rust http_client library not found.\n'
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
    // (flutter run 时 exe 位于 build/.../runner/Debug 等子目录，需向上找项目根)
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

  /// 发送 HTTP 请求（后台 isolate 执行，不阻塞 UI）。
  ///
  /// [method] GET/POST/PUT/PATCH/DELETE/HEAD
  /// [url] 完整 URL
  /// [headers] 请求头
  /// [body] 请求体（可空，配合 POST/PUT/PATCH 使用）
  /// [timeout] 读取超时
  /// [maxRedirects] 最大重定向次数
  Future<HttpFfiResponse> request({
    required String method,
    required String url,
    Map<String, String>? headers,
    List<int>? body,
    Duration timeout = const Duration(seconds: 30),
    int maxRedirects = 5,
  }) async {
    final responsePort = ReceivePort();
    final completer = Completer<HttpFfiResponse>();

    late StreamSubscription sub;
    sub = responsePort.listen((msg) {
      if (msg is HttpFfiResponse) {
        completer.complete(msg);
      } else if (msg is HttpFfiException) {
        completer.completeError(msg);
      }
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _httpRequestIsolate,
        _HttpFfiRequest(
          method: method,
          url: url,
          headersJson: jsonEncode(headers ?? const <String, String>{}),
          body: body == null ? Uint8List(0) : Uint8List.fromList(body),
          timeoutSecs: timeout.inSeconds.clamp(1, 3600),
          maxRedirects: maxRedirects.clamp(0, 50),
          sendPort: responsePort.sendPort,
        ),
      );
      // Dart 层硬超时兜底：Rust 侧 SO_RCVTIMEO 在个别平台/环境下可能失效，
      // 这里保证调用方总能按预期超时返回，并尽力终止后台 isolate。
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          isolate?.kill(priority: Isolate.immediate);
          throw HttpFfiException('请求超时: $timeout');
        },
      );
    } finally {
      await sub.cancel();
      responsePort.close();
    }
  }

  /// GET 请求。
  Future<HttpFfiResponse> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) => request(method: 'GET', url: url, headers: headers, timeout: timeout);

  /// POST 请求（[body] 为字节数组或 UTF-8 字符串）。
  Future<HttpFfiResponse> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) => request(
    method: 'POST',
    url: url,
    headers: headers,
    body: _encodeBody(body),
    timeout: timeout,
  );

  /// PUT 请求。
  Future<HttpFfiResponse> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) => request(
    method: 'PUT',
    url: url,
    headers: headers,
    body: _encodeBody(body),
    timeout: timeout,
  );

  /// PATCH 请求。
  Future<HttpFfiResponse> patch(
    String url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) => request(
    method: 'PATCH',
    url: url,
    headers: headers,
    body: _encodeBody(body),
    timeout: timeout,
  );

  /// DELETE 请求。
  Future<HttpFfiResponse> delete(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) => request(method: 'DELETE', url: url, headers: headers, timeout: timeout);

  /// HEAD 请求。
  Future<HttpFfiResponse> head(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) => request(method: 'HEAD', url: url, headers: headers, timeout: timeout);

  static List<int>? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is List<int>) return body;
    if (body is String) return utf8.encode(body);
    if (body is Map || body is List) return utf8.encode(jsonEncode(body));
    return utf8.encode(body.toString());
  }

  /// 解码 Rust 侧返回的 base64 响应体。
  /// 优先使用 SIMD 原生库（AVX2/SSSE3 加速，速度约 2.3 倍），
  /// 库缺失或输入非法时回退 dart:convert。
  static Uint8List _decodeBodyB64(String bodyB64) {
    if (bodyB64.isEmpty) return Uint8List(0);
    final simd = SimdNative.tryInit();
    if (simd != null) {
      final decoded = simdBase64Decode(bodyB64);
      if (decoded != null) return decoded;
    }
    return base64Decode(bodyB64);
  }

  /// 后台 isolate 入口：打开库、调用 FFI、解析结果并发送回主 isolate。
  static void _httpRequestIsolate(_HttpFfiRequest req) {
    Pointer<Utf8>? methodPtr;
    Pointer<Utf8>? urlPtr;
    Pointer<Utf8>? headersPtr;
    Pointer<Uint8>? bodyPtr;
    Pointer<Utf8>? resultPtr;

    try {
      final lib = _openLibrary();      final httpRequest = lib.lookupFunction<HttpRequestC, HttpRequestDart>(
        'http_request',
      );

      methodPtr = req.method.toNativeUtf8();
      urlPtr = req.url.toNativeUtf8();
      headersPtr = req.headersJson.toNativeUtf8();
      if (req.body.isNotEmpty) {
        bodyPtr = calloc<Uint8>(req.body.length);
        bodyPtr.asTypedList(req.body.length).setAll(0, req.body);
      }

      resultPtr = httpRequest(
        methodPtr,
        urlPtr,
        headersPtr,
        bodyPtr ?? nullptr,
        req.body.length,
        req.timeoutSecs,
        req.maxRedirects,
      );

      if (resultPtr == nullptr) {
        req.sendPort.send(const HttpFfiException('http_request 返回空指针'));
        return;
      }

      final resultJson = resultPtr.toDartString();
      final decoded = jsonDecode(resultJson) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        final status = (decoded['status'] as num).toInt();
        final headers = <String, String>{};
        final rawHeaders = decoded['headers'] as Map<String, dynamic>? ?? {};
        rawHeaders.forEach((name, values) {
          final list = (values as List<dynamic>).cast<String>();
          headers[name] = list.join(', ');
        });
        final bodyB64 = decoded['body_b64'] as String? ?? '';
        final bodyBytes = _decodeBodyB64(bodyB64);
        req.sendPort.send(
          HttpFfiResponse(
            statusCode: status,
            headers: headers,
            bodyBytes: bodyBytes,
          ),
        );
      } else {
        final message = decoded['error'] as String? ?? '未知错误';
        final status = (decoded['status'] as num?)?.toInt();
        req.sendPort.send(HttpFfiException(message, statusCode: status));
      }
    } catch (e) {
      req.sendPort.send(HttpFfiException('后台 isolate 异常: $e'));
    } finally {
      if (methodPtr != null) calloc.free(methodPtr);
      if (urlPtr != null) calloc.free(urlPtr);
      if (headersPtr != null) calloc.free(headersPtr);
      if (bodyPtr != null) calloc.free(bodyPtr);
      if (resultPtr != null) {
        // resultPtr 由 Rust 分配，需用 Rust 侧 free_string 释放
        try {
          final lib = _openLibrary();
          final freeString = lib.lookupFunction<FreeStringC, FreeStringDart>(
            'free_string',
          );
          freeString(resultPtr);
        } catch (_) {
          // 库句柄无法再次打开时忽略（指针泄漏可接受，仅调试场景）
        }
      }
    }
  }
}
