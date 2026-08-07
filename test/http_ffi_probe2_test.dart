// 定位实验 2：绕过 HttpFfiService 的 Isolate 包装，在主 isolate 直接同步调用 FFI。
// 区分：FFI 参数传递问题 vs Isolate.spawn 包装问题。

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef HttpRequestC = Pointer<Utf8> Function(
  Pointer<Utf8> method,
  Pointer<Utf8> url,
  Pointer<Utf8> headersJson,
  Pointer<Uint8> body,
  IntPtr bodyLen,
  Uint64 timeoutSecs,
  Uint32 maxRedirects,
);
typedef HttpRequestDart = Pointer<Utf8> Function(
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

void main() {
  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/slow') {
        Future.delayed(const Duration(seconds: 3), () {
          request.response
            ..statusCode = 200
            ..write('slow');
          request.response.close();
        });
        return;
      } else {
        request.response
          ..statusCode = 200
          ..write('ok');
      }
      request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('同步 FFI 调用（timeout=1s）：期望 1 秒超时', () async {
    final libName = Platform.isWindows
        ? 'xmc_http_client.dll'
        : 'libxmc_http_client.so';
    final cwd = Directory.current.path;
    final sep = Platform.pathSeparator;
    final candidates = [
      '$cwd$sep$libName',
      '$cwd$sep${Platform.isWindows ? 'windows${sep}runner' : 'linux'}$sep$libName',
    ];
    DynamicLibrary? lib;
    for (final path in candidates) {
      if (File(path).existsSync()) {
        // ignore: avoid_print
        print('LOADING: $path');
        lib = DynamicLibrary.open(path);
        break;
      }
    }
    lib ??= DynamicLibrary.open(libName);

    final httpRequest =
        lib.lookupFunction<HttpRequestC, HttpRequestDart>('http_request');
    final freeString =
        lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

    final sw = Stopwatch()..start();
    final methodPtr = 'GET'.toNativeUtf8();
    final urlPtr = 'http://127.0.0.1:${server.port}/slow'.toNativeUtf8();
    final headersPtr = '{}'.toNativeUtf8();

    final resultPtr = httpRequest(methodPtr, urlPtr, headersPtr, nullptr, 0, 1, 5);
    final elapsed = sw.elapsedMilliseconds;
    final raw = resultPtr == nullptr ? '<null>' : resultPtr.toDartString();
    if (resultPtr != nullptr) freeString(resultPtr);
    calloc.free(methodPtr);
    calloc.free(urlPtr);
    calloc.free(headersPtr);

    // ignore: avoid_print
    print('SYNC FFI elapsed=${elapsed}ms raw=$raw');
    expect(elapsed, lessThan(2000), reason: '1 秒读超时未生效');
  });
}
