// 定位实验 2：在主 isolate 直接同步调用 FFI，验证 timeoutSecs 参数是否真正传给 Rust。
// 服务器放在独立 isolate，避免同步阻塞主 isolate 导致服务器 timer 死锁。
// Rust 侧会回显 debug_timeout_secs / debug_max_redirects 字段。

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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

void _serverIsolate(SendPort sendPort) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    Future.delayed(const Duration(seconds: 3), () {
      request.response
        ..statusCode = 200
        ..write('slow');
      request.response.close();
    });
  });
  sendPort.send(server.port);
}

void main() {
  late int serverPort;

  setUpAll(() async {
    final rp = ReceivePort();
    await Isolate.spawn(_serverIsolate, rp.sendPort);
    serverPort = await rp.first as int;
  });

  String? syncCall(int timeoutSecs) {
    final libName = Platform.isWindows
        ? 'xmc_http_client.dll'
        : 'libxmc_http_client.so';
    final cwd = Directory.current.path;
    final sep = Platform.pathSeparator;
    final candidates = [
      '$cwd$sep$libName',
      '$cwd$sep${Platform.isWindows ? 'windows${sep}runner' : 'linux'}$sep$libName',
    ];
    DynamicLibrary lib = DynamicLibrary.process();
    for (final path in candidates) {
      if (File(path).existsSync()) {
        // ignore: avoid_print
        print('LOADING: $path');
        lib = DynamicLibrary.open(path);
        break;
      }
    }

    final httpRequest =
        lib.lookupFunction<HttpRequestC, HttpRequestDart>('http_request');
    final freeString =
        lib.lookupFunction<FreeStringC, FreeStringDart>('free_string');

    final sw = Stopwatch()..start();
    final methodPtr = 'GET'.toNativeUtf8();
    final urlPtr = 'http://127.0.0.1:$serverPort/slow'.toNativeUtf8();
    final headersPtr = '{}'.toNativeUtf8();

    final resultPtr =
        httpRequest(methodPtr, urlPtr, headersPtr, nullptr, 0, timeoutSecs, 5);
    final elapsed = sw.elapsedMilliseconds;
    final raw = resultPtr == nullptr ? '<null>' : resultPtr.toDartString();
    if (resultPtr != nullptr) freeString(resultPtr);
    calloc.free(methodPtr);
    calloc.free(urlPtr);
    calloc.free(headersPtr);

    // ignore: avoid_print
    print('SYNC FFI timeout=$timeoutSecs elapsed=${elapsed}ms raw=$raw');
    return raw;
  }

  test('同步 FFI：timeout=1（期望 1 秒超时）与 timeout=0（默认 60s）对比', () {
    final raw1 = syncCall(1);
    final raw0 = syncCall(0);
    final decoded1 = jsonDecode(raw1!) as Map<String, dynamic>;
    final decoded0 = jsonDecode(raw0!) as Map<String, dynamic>;
    // ignore: avoid_print
    print('timeout=1 -> rust 收到 timeout_secs=${decoded1['debug_timeout_secs']} '
        'ok=${decoded1['ok']}');
    // ignore: avoid_print
    print('timeout=0 -> rust 收到 timeout_secs=${decoded0['debug_timeout_secs']} '
        'ok=${decoded0['ok']}');
  });
}
