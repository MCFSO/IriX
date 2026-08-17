// 本地 MCP 服务器协议测试
// 验证 JSON-RPC 2.0 握手、工具列表、只读工具直接执行、
// 敏感工具必须授权（拒绝返回 isError）等行为。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/mcp_server.dart';
import 'package:irix/state/app_state.dart';

void main() {
  late McpServer server;
  late HttpClient client;

  setUp(() async {
    client = HttpClient();
    server = McpServer(AppState());
    await server.start(0);
  });

  tearDown(() async {
    await server.stop();
    client.close(force: true);
  });

  Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  /// 携带 H-3 鉴权头的 POST。
  Future<TestHttpResponse> post(Map<String, dynamic> body) async {
    final request = await client.postUrl(uri('/mcp'))
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Authorization', 'Bearer ${server.token}')
      ..add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    return TestHttpResponse.read(response);
  }

  Future<TestHttpResponse> get(Uri u, {bool withAuth = true}) async {
    final request = await client.getUrl(u);
    if (withAuth) {
      request.headers.set('Authorization', 'Bearer ${server.token}');
    }
    final response = await request.close();
    return TestHttpResponse.read(response);
  }

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final res = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params ?? {},
    });
    expect(res.statusCode, 200, reason: res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  test('initialize 握手返回服务器信息与工具能力', () async {
    final res = await rpc('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0'},
    });
    expect(res['id'], 1);
    final result = res['result'] as Map<String, dynamic>;
    expect(result['protocolVersion'], '2025-03-26');
    expect((result['serverInfo'] as Map)['name'], 'IriX');
    expect((result['capabilities'] as Map)['tools'], isNotNull);
  });

  test('tools/list 暴露 IriX 工具集', () async {
    final res = await rpc('tools/list');
    final tools = ((res['result'] as Map<String, dynamic>)['tools'] as List);
    final names = tools.map((t) => (t as Map)['name']).toList();
    expect(
      names,
      containsAll([
        'list_instances',
        'read_logs',
        'search_logs',
        'list_files',
        'read_file',
        'send_server_command',
        'start_instance',
        'stop_instance',
      ]),
    );
    for (final tool in tools) {
      expect((tool as Map)['inputSchema'], isNotNull);
    }
  });

  test('只读工具直接执行，无需授权', () async {
    final res = await rpc('tools/call', {
      'name': 'list_instances',
      'arguments': {},
    });
    final result = res['result'] as Map<String, dynamic>;
    expect(result['isError'], false);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    expect(text, contains('没有已创建的实例'));
  });

  test('敏感工具必须授权，拒绝时返回 isError', () async {
    final notifier = server.currentRequest;
    notifier.addListener(() {
      final request = notifier.value;
      if (request != null) {
        // 模拟用户在 UI 中点击「拒绝」。
        request.resolve(false);
      }
    });

    final res = await rpc('tools/call', {
      'name': 'stop_instance',
      'arguments': {'instance_id': 'unknown'},
    });
    final result = res['result'] as Map<String, dynamic>;
    expect(result['isError'], true);
    final text = ((result['content'] as List).first as Map)['text'] as String;
    expect(text, contains('拒绝了'));
    expect(notifier.value, isNull);
  });

  test('敏感工具授权后执行', () async {
    final notifier = server.currentRequest;
    notifier.addListener(() {
      final request = notifier.value;
      if (request != null) {
        // 模拟用户在 UI 中点击「允许」。
        request.resolve(true);
      }
    });

    final res = await rpc('tools/call', {
      'name': 'stop_instance',
      'arguments': {'instance_id': 'nonexistent'},
    });
    final result = res['result'] as Map<String, dynamic>;
    // 实例不存在 → 工具返回错误文本（说明授权通过后确实执行了处理逻辑）。
    final text = ((result['content'] as List).first as Map)['text'] as String;
    expect(text, contains('实例不存在'));
  });

  test('无 id 的通知返回 202 空响应', () async {
    final res = await post({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': {},
    });
    expect(res.statusCode, HttpStatus.accepted);
    expect(res.body.isEmpty, true);
  });

  test('未知方法返回 JSON-RPC 错误', () async {
    final res = await rpc('unknown/method');
    final error = res['error'] as Map<String, dynamic>;
    expect(error['code'], -32601);
  });

  test('未知工具返回参数错误', () async {
    final res = await rpc('tools/call', {
      'name': 'not_a_tool',
      'arguments': {},
    });
    final error = res['error'] as Map<String, dynamic>;
    expect(error['code'], -32602);
  });

  test('无鉴权请求被拒绝（H-3）', () async {
    final request = await client.postUrl(uri('/mcp'))
      ..headers.set('Content-Type', 'application/json')
      ..add(utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    expect(response.statusCode, HttpStatus.unauthorized);
    expect(body, contains('未授权'));
  });

  test('错误 token 被拒绝（H-3）', () async {
    final request = await client.postUrl(uri('/mcp'))
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Authorization', 'Bearer wrong-token')
      ..add(utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('跨源浏览器请求被拒绝（H-3）', () async {
    final request = await client.postUrl(uri('/mcp'))
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Authorization', 'Bearer ${server.token}')
      ..headers.set('Origin', 'https://evil.example.com')
      ..add(utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('本机 Origin 请求放行（H-3）', () async {
    final request = await client.postUrl(uri('/mcp'))
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Authorization', 'Bearer ${server.token}')
      ..headers.set('Origin', 'http://127.0.0.1:8080')
      ..add(utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'})));
    final response = await request.close();
    expect(response.statusCode, 200);
  });

  test('每次启动生成不同 token（H-3）', () async {
    final first = server.token;
    expect(first.length, 64);
    await server.start(0);
    expect(server.token, isNot(first));
  });

  test('GET / 返回信息页（需鉴权，不含工具枚举）', () async {
    final res = await get(uri('/'));
    expect(res.statusCode, 200);
    expect(res.body, contains('IriX MCP Server'));
    expect(res.body, contains('/mcp'));
    // H-3：信息页不再枚举工具清单。
    expect(res.body, isNot(contains('list_instances')));
  });
}

/// dart:io HttpClient 响应简化封装，替代 package:http Response。
class TestHttpResponse {
  TestHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;

  static Future<TestHttpResponse> read(HttpClientResponse response) async {
    final status = response.statusCode;
    final body = await utf8.decodeStream(response);
    return TestHttpResponse(status, body);
  }
}
