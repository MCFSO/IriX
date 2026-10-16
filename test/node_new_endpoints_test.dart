// irix-node 新增端点（v1.2.0）客户端契约回归测试
//
// 覆盖本轮补齐的 6 项节点能力：容器导出、镜像导入、Bastille 长任务进度、
// 模板应用（返回 jobId）、集群原生迁移（发起 / 进度）、节点间心跳与事件。
// 本地 HttpServer 记录每个请求的方法 / 路径 / 请求体，断言客户端契约。
//
// 需要先构建 Rust http_client 模块并复制动态库到 windows/runner/ 或项目根目录。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/node_ops.dart';
import 'package:irix/services/node_api_client.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  /// 最近一次请求的方法 / 路径 / 查询 / 请求体。
  late String method;
  late String path;
  late Map<String, String> query;
  late Map<String, dynamic> body;

  Map<String, dynamic> envelope(int status, Object? data) => {
    'status': status,
    'data': data,
    'time': DateTime.now().millisecondsSinceEpoch,
  };

  setUp(() async {
    NodeApiClient.forgetAllSessions();
    method = '';
    path = '';
    query = {};
    body = {};

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      method = request.method;
      path = request.uri.path;
      query = request.uri.queryParameters;
      final raw = await utf8.decoder.bind(request).join();
      body = raw.isEmpty
          ? {}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();

      final response = request.response
        ..headers.set('Content-Type', 'application/json; charset=utf-8');
      switch (path) {
        case '/api/container/abc123/export':
          response.write(
            jsonEncode(
              envelope(200, {
                'password': 'ticket-1',
                'addr': '127.0.0.1:${server.port}',
                'fileName': '.exports/abc123-1700000000000.tar',
              }),
            ),
          );
        case '/api/image/import':
          response.write(jsonEncode(envelope(200, true)));
        case '/api/bastille/jobs/job-9':
          response.write(
            jsonEncode(
              envelope(200, {
                'status': 'failed',
                'log': ['step 1 ok', 'step 2 failed'],
              }),
            ),
          );
        case '/api/bastille/templates/apply':
          response.write(jsonEncode(envelope(200, {'jobId': 'job-42'})));
        case '/api/cluster/transfer':
          if (method == 'POST') {
            response.write(jsonEncode(envelope(200, {'jobId': 'xfer-1'})));
          } else {
            response.write(
              jsonEncode(envelope(200, {'status': 'done', 'bytes': 4096})),
            );
          }
        default:
          response.write(jsonEncode(envelope(200, true)));
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  NodeApiClient client() => NodeApiClient(baseUrl: baseUrl);

  test('容器导出：POST /api/container/{id}/export 并解析下载票据', () async {
    final ticket = await client().containerExport('abc123');
    expect(method, 'POST');
    expect(path, '/api/container/abc123/export');
    expect(ticket.password, 'ticket-1');
    expect(ticket.fileName, '.exports/abc123-1700000000000.tar');
    expect(
      ticket.url,
      'http://127.0.0.1:${server.port}/download/ticket-1/.exports/abc123-1700000000000.tar',
      reason: '票据 URL 需保留 .exports/ 目录层级',
    );
  });

  test('镜像导入：POST /api/image/import 携带 fileName 与 name', () async {
    await client().imageImport(fileName: 'mc.tar', name: 'mc:latest');
    expect(method, 'POST');
    expect(path, '/api/image/import');
    expect(body['fileName'], 'mc.tar');
    expect(body['name'], 'mc:latest');
  });

  test('Bastille 长任务进度：GET /api/bastille/jobs/{jobId} 解析 status/log', () async {
    final progress = await client().bastilleJobProgress('job-9');
    expect(method, 'GET');
    expect(path, '/api/bastille/jobs/job-9');
    expect(progress.status, 'failed');
    expect(progress.isFailed, isTrue);
    expect(progress.log, hasLength(2));
    expect(progress.tailLog(), contains('step 2 failed'));
  });

  test('模板应用：POST /api/bastille/templates/apply 返回 jobId', () async {
    final jobId = await client().bastilleTemplateApply(
      jail: 'mc',
      template: 'Minecraft/server',
      args: {'MC_VERSION': '1.21.1'},
    );
    expect(method, 'POST');
    expect(path, '/api/bastille/templates/apply');
    expect(body['jail'], 'mc');
    expect(body['template'], 'Minecraft/server');
    expect(body['args'], {'MC_VERSION': '1.21.1'});
    expect(jobId, 'job-42', reason: '模板应用为长任务，必须回传 jobId');
  });

  test('集群迁移：POST /api/cluster/transfer 嵌套 source，GET 查询进度', () async {
    final api = client();
    final jobId = await api.clusterTransfer(
      instanceId: 'inst-1',
      source: const ClusterTransferSource(
        address: '10.0.0.2:12346',
        token: 'tok',
        uuid: 'uuid-1',
        daemonId: 'd-1',
      ),
      dest: '/mirrors/inst-1',
    );
    expect(method, 'POST');
    expect(path, '/api/cluster/transfer');
    expect(body['instanceId'], 'inst-1');
    expect(body['dest'], '/mirrors/inst-1');
    expect(body['source'], {
      'address': '10.0.0.2:12346',
      'token': 'tok',
      'uuid': 'uuid-1',
      'daemonId': 'd-1',
    });
    expect(jobId, 'xfer-1');

    final progress = await api.clusterTransferStatus('xfer-1');
    expect(method, 'GET');
    expect(path, '/api/cluster/transfer');
    expect(query['jobId'], 'xfer-1');
    expect(progress.status, 'done');
    expect(progress.isDone, isTrue);
    expect(progress.bytes, 4096);
  });

  test('节点间心跳与事件：POST /api/cluster/heartbeat 与 /api/cluster/events', () async {
    final api = client();
    await api.clusterHeartbeat({'id': 'node-a', 'address': '10.0.0.3:12346'});
    expect(method, 'POST');
    expect(path, '/api/cluster/heartbeat');
    expect(body['id'], 'node-a');

    await api.clusterEvents({'type': 'sync-done', 'uuid': 'inst-1'});
    expect(path, '/api/cluster/events');
    expect(body['type'], 'sync-done');
  });

  test('NodeJobProgress 兼容 log 为整段文本的形态', () {
    final progress = NodeJobProgress.fromJson({
      'status': 'done',
      'log': 'line-1\nline-2',
    });
    expect(progress.isDone, isTrue);
    expect(progress.log, ['line-1', 'line-2']);
  });
}
