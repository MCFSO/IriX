// irix-node v1.2.0 账户会话认证兼容性测试
//
// 背景：irix-node v1.2.0 移除了固定 apikey 通道，全部 API 请求必须携带
// 账户会话 token（见 NODE_API.md §1）。本地 HttpServer 模拟节点契约：
//   POST /api/auth/login  → {status:200,data:{token,username,isAdmin,expiresAt}}
//   GET  /api/overview    → 校验 X-Auth-Token，缺失/过期返回
//                           403「未认证或会话已过期（请先登录 …）」
// 验证客户端能自动登录、会话失效后自动重登，且不再向 irix-node 发送 X-Api-Key。
//
// 需要先构建 Rust http_client 模块并复制动态库到 windows/runner/ 或项目根目录。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/node.dart';
import 'package:irix/services/node_api_client.dart';

void main() {
  const username = 'bootstrapAdmin';
  const password = 'super-secret-password';
  const initialToken = 'token-1';

  late HttpServer server;
  late String baseUrl;

  /// 当前有效的会话 token（模拟服务端会话表）。
  late String activeToken;

  /// 登录成功次数。
  late int loginCount;

  /// 最近一次 /api/overview 请求携带的鉴权信息。
  late String? lastAuthHeader;
  late String? lastApiKeyHeader;
  late String? lastApiKeyQuery;

  Map<String, dynamic> envelope(int status, Object? data) => {
    'status': status,
    'data': data,
    'time': DateTime.now().millisecondsSinceEpoch,
  };

  setUp(() async {
    NodeApiClient.forgetAllSessions();
    activeToken = initialToken;
    loginCount = 0;
    lastAuthHeader = null;
    lastApiKeyHeader = null;
    lastApiKeyQuery = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      final response = request.response
        ..headers.set('Content-Type', 'application/json; charset=utf-8');

      if (path == '/api/auth/login') {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        if (decoded['username'] == username &&
            decoded['password'] == password) {
          loginCount++;
          activeToken = 'token-$loginCount';
          response.write(
            jsonEncode(
              envelope(200, {
                'token': activeToken,
                'username': username,
                'isAdmin': true,
                'expiresAt': DateTime.now()
                    .add(const Duration(days: 30))
                    .millisecondsSinceEpoch,
              }),
            ),
          );
        } else {
          response
            ..statusCode = 401
            ..write(jsonEncode(envelope(401, '用户名或密码错误')));
        }
      } else if (path == '/api/overview') {
        lastAuthHeader = request.headers.value('X-Auth-Token');
        lastApiKeyHeader = request.headers.value('X-Api-Key');
        lastApiKeyQuery = request.uri.queryParameters['apikey'];
        final panelKey = lastApiKeyQuery ?? lastApiKeyHeader ?? '';
        if (lastAuthHeader == activeToken || panelKey == 'panel-key') {
          response.write(jsonEncode(envelope(200, {'cpuUsage': 0.5})));
        } else {
          response
            ..statusCode = 403
            ..write(
              jsonEncode(
                envelope(403, '未认证或会话已过期（请先登录 POST /api/auth/login）'),
              ),
            );
        }
      } else if (path == '/api/load') {
        // 权限不足（非会话失效）：不应触发重登。
        response
          ..statusCode = 403
          ..write(jsonEncode(envelope(403, '权限不足: 当前账户无权访问 GET /api/load')));
      } else {
        response
          ..statusCode = 404
          ..write(jsonEncode(envelope(404, 'not found')));
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    NodeApiClient.forgetAllSessions();
  });

  /// irix-node 节点（账户认证；apiKey 仅用于验证不会被发送）。
  NodeInfo irixNode({String apiKey = ''}) => NodeInfo(
    id: 'node-auth-test',
    name: '测试节点',
    type: NodeType.node,
    address: baseUrl,
    apiKey: apiKey,
    accountUser: username,
    accountPassword: password,
  );

  test('irix-node：首次请求自动登录并携带会话 token，且不发送 X-Api-Key', () async {
    final client = NodeApiClient.of(
      irixNode(apiKey: 'legacy-key-should-be-ignored'),
    );
    final data = await client.overview();

    expect(data, isNotNull, reason: '概览请求应成功（会话自动登录）');
    expect(loginCount, 1, reason: '无缓存会话时应先登录一次');
    expect(lastAuthHeader, 'token-1', reason: '数据请求必须携带会话 token');
    expect(lastApiKeyHeader, isNull, reason: 'irix-node v1.2.0 已移除 apikey 通道');
    expect(lastApiKeyQuery, isNull, reason: 'irix-node 不使用 apikey 查询参数');
  });

  test('irix-node：会话在服务端失效后自动重登并重试一次', () async {
    await NodeApiClient.of(irixNode()).overview();
    expect(loginCount, 1);

    // 模拟服务端会话被撤销（重启 / 改密吊销 / 过期）。
    activeToken = 'rotated-by-server';

    final data = await NodeApiClient.of(irixNode()).overview();

    expect(data, isNotNull, reason: '重登后的重试请求应成功');
    expect(loginCount, 2, reason: '403 未认证应触发一次重新登录');
    expect(lastAuthHeader, 'token-2', reason: '重试请求应使用新会话');
  });

  test('irix-node：会话跨客户端实例复用（同一节点不重复登录）', () async {
    await NodeApiClient.of(irixNode()).overview();
    await NodeApiClient.of(irixNode()).overview();
    expect(loginCount, 1, reason: '会话缓存在静态表中，供后续实例复用');
  });

  test('irix-node：权限不足（403 权限不足）不触发重登', () async {
    final client = NodeApiClient.of(irixNode());
    await expectLater(
      client.nodeLoad(),
      throwsA(
        isA<NodeApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('权限不足')),
      ),
    );
    expect(loginCount, 1, reason: '只登录一次；权限不足不应重登');
  });

  test('irix-node：无凭据时不登录，直接暴露未认证错误', () async {
    final node = NodeInfo(
      id: 'no-cred',
      name: '无凭据节点',
      type: NodeType.node,
      address: baseUrl,
      apiKey: '',
    );
    await expectLater(
      NodeApiClient.of(node).overview(),
      throwsA(
        isA<NodeApiException>().having(
          (e) => e.message,
          'message',
          contains('未认证'),
        ),
      ),
    );
    expect(loginCount, 0, reason: '无账户凭据时不发起登录');
  });

  test('MCSM 面板：仍走 X-Api-Key 与 apikey 查询参数', () async {
    final node = NodeInfo(
      id: 'mcsm-node',
      name: '面板节点',
      type: NodeType.mcsm,
      address: baseUrl,
      apiKey: 'panel-key',
    );
    await NodeApiClient.of(node).overview();
    expect(lastApiKeyHeader, 'panel-key');
    expect(lastApiKeyQuery, 'panel-key');
    expect(lastAuthHeader, isNull, reason: 'MCSM 面板不使用账户会话');
    expect(loginCount, 0);
  });

  test('凭据错误时抛出节点返回的登录失败消息', () async {
    final client = NodeApiClient(
      baseUrl: baseUrl,
      accountUser: username,
      accountPassword: 'wrong-password',
    );
    await expectLater(
      client.overview(),
      throwsA(
        isA<NodeApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('用户名或密码错误')),
      ),
    );
  });
}
