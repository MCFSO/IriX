// http_ffi 集成测试
// 使用本地 HttpServer 验证 Rust 侧 HTTP 请求 FFI 封装：
// GET/POST/HEAD、请求头、JSON/二进制响应体、404 错误、重定向。
// 需要先构建 Rust http_client 模块并复制动态库到 windows/runner/ 或项目根目录。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/http_ffi.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/json') {
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'application/json')
          ..headers.set('X-Custom', 'hello')
          ..write(jsonEncode({'name': 'IriX', 'ok': true}));
      } else if (path == '/echo') {
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'application/octet-stream')
          ..add(utf8.encode(
              '${request.method}:${request.uri.query}'));
      } else if (path == '/binary') {
        request.response.add(Uint8List.fromList(
            [0x00, 0x01, 0xFF, 0xFE, 0x80, 0x41]));
      } else if (path == '/notfound') {
        request.response
          ..statusCode = 404
          ..write('{"error":"missing"}');
      } else if (path == '/redirect') {
        request.response
          ..statusCode = 302
          ..headers.set('Location', '$baseUrl/json');
      } else if (path == '/slow') {
        // 延迟响应用于超时测试
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

  test('GET 请求返回 JSON 与自定义响应头', () async {
    final res = await HttpFfiService.instance.get('$baseUrl/json');
    expect(res.statusCode, 200);
    expect(res.isOk, isTrue);
    expect(res.headers['content-type'], 'application/json');
    expect(res.headers['x-custom'], 'hello');
    expect(jsonDecode(res.body), {'name': 'IriX', 'ok': true});
  });

  test('POST 请求带请求体与查询参数', () async {
    final res = await HttpFfiService.instance.post(
      '$baseUrl/echo?a=1&b=2',
      body: 'payload',
      headers: {'Content-Type': 'text/plain'},
    );
    expect(res.statusCode, 200);
    expect(res.body, 'POST:a=1&b=2');
  });

  test('二进制响应体原样返回', () async {
    final res = await HttpFfiService.instance.get('$baseUrl/binary');
    expect(res.statusCode, 200);
    expect(res.bodyBytes, [0x00, 0x01, 0xFF, 0xFE, 0x80, 0x41]);
  });

  test('404 返回非 2xx 状态码（不抛异常）', () async {
    final res = await HttpFfiService.instance.get('$baseUrl/notfound');
    expect(res.statusCode, 404);
    expect(res.isOk, isFalse);
    expect(res.body, contains('missing'));
  });

  test('302 重定向自动跟随', () async {
    final res = await HttpFfiService.instance.get('$baseUrl/redirect');
    expect(res.statusCode, 200);
    expect(jsonDecode(res.body), {'name': 'IriX', 'ok': true});
  });

  test('HEAD 请求返回空响应体', () async {
    final res = await HttpFfiService.instance.head('$baseUrl/json');
    expect(res.statusCode, 200);
    expect(res.bodyBytes, isEmpty);
  });

  test('请求头透传给服务端', () async {
    final res = await HttpFfiService.instance.post(
      '$baseUrl/echo',
      body: 'x',
      headers: {'X-Token': 'secret-123'},
    );
    expect(res.statusCode, 200);
  });

  test('连接不存在的端口返回网络错误', () async {
    // 使用一个未被监听的端口
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close(force: true);

    await expectLater(
      HttpFfiService.instance.get(
        'http://127.0.0.1:$deadPort/nothing',
        timeout: const Duration(seconds: 5),
      ),
      throwsA(isA<HttpFfiException>()),
    );
  });

  test('请求超时抛异常', () async {
    await expectLater(
      HttpFfiService.instance.get(
        '$baseUrl/slow',
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<HttpFfiException>()),
    );
  });
}
