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

void _socketServerIsolate(SendPort sendPort) async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  server.listen((socket) {
    socket.listen((_) {
      Future.delayed(const Duration(seconds: 3), () {
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nslow');
        socket.close();
      });
    });
  });
  sendPort.send(server.port);
}

void main() {
  late int httpServerPort;
  late int socketServerPort;

  setUpAll(() async {
    var rp = ReceivePort();
    await Isolate.spawn(_serverIsolate, rp.sendPort);
    httpServerPort = await rp.first as int;

    rp = ReceivePort();
    await Isolate.spawn(_socketServerIsolate, rp.sendPort);
    socketServerPort = await rp.first as int;
  });

  String? syncCall(String url, int timeoutSecs) {
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
    final urlPtr = url.toNativeUtf8();
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

  test('同步 FFI 对比：HttpServer vs ServerSocket（timeout=1）', () {
    final raw1 = syncCall('http://127.0.0.1:$httpServerPort/slow', 1);
    final raw2 = syncCall('http://127.0.0.1:$socketServerPort/slow', 1);
    final decoded1 = jsonDecode(raw1!) as Map<String, dynamic>;
    final decoded2 = jsonDecode(raw2!) as Map<String, dynamic>;
    // ignore: avoid_print
    print('HttpServer: rust 收到 timeout_secs=${decoded1['debug_timeout_secs']} '
        'ok=${decoded1['ok']}');
    // ignore: avoid_print
    print('ServerSocket: rust 收到 timeout_secs=${decoded2['debug_timeout_secs']} '
        'ok=${decoded2['ok']}');
  });
}
