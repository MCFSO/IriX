// 观察实验：Dart HttpServer 延迟响应期间，裸 Socket 客户端收到什么字节？
// 排除 FFI 层，纯 dart:io。用于定位 Linux CI 上读超时不触发的问题。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
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

  test('裸 Socket 观察：延迟期间收到什么', () async {
    final socket = await Socket.connect('127.0.0.1', server.port);
    final events = <String>[];
    socket.listen(
      (data) {
        events.add(
            'T+${DateTime.now().difference(_start).inMilliseconds}ms 收到 ${data.length} 字节: "${utf8.decode(data, allowMalformed: true)}"');
      },
      onDone: () => events.add('T+${DateTime.now().difference(_start).inMilliseconds}ms 连接关闭'),
      onError: (e) => events.add('T+${DateTime.now().difference(_start).inMilliseconds}ms 错误: $e'),
      cancelOnError: true,
    );
    _start = DateTime.now();
    socket.write('GET /slow HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n');
    await socket.flush();

    await Future.delayed(const Duration(seconds: 5));
    await socket.close();

    // ignore: avoid_print
    print('=== 5 秒观察结果 ===');
    for (final e in events) {
      // ignore: avoid_print
      print(e);
    }
  });
}

DateTime _start = DateTime.now();
