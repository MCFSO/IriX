// 编排引擎 FFI 集成测试：需要 Rust 动态库已编译并复制到 windows/runner/
// （或项目根目录），与其它 *_ffi_test.dart 一致。覆盖：
// 服务 CRUD、对账创建副本、mc_ping、迁移状态机首步推进、状态聚合。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/models/orchestration.dart';
import 'package:irix/services/orchestrator_ffi.dart';

void main() {
  final dbPath = p.join(
    Directory.systemTemp.path,
    'xmc_orchestrator_test_${DateTime.now().microsecondsSinceEpoch}.db',
  );

  tearDownAll(() {
    try {
      File(dbPath).deleteSync();
    } catch (_) {}
  });

  Future<dynamic> req(String op, Map<String, dynamic> args) => OrchestratorFfi
      .instance
      .request(op: op, args: {'dbPath': dbPath, ...args});

  group('编排引擎 FFI', () {
    test('服务 upsert 与列表往返', () async {
      await req('init', {});
      final service = McService(
        id: 's1',
        name: 'survival',
        runtime: 'docker',
        image: 'itzg/minecraft-server:latest',
        ports: ['25565:25565'],
        desiredReplicas: 2,
        minReplicas: 1,
        maxReplicas: 4,
      );
      await req('upsert_service', {'service': service.toJson()});
      final list = await req('list_services', {}) as List<dynamic>;
      expect(list, hasLength(1));
      final restored = McService.fromJson(list.first as Map<String, dynamic>);
      expect(restored.id, 's1');
      expect(restored.desiredReplicas, 2);
      expect(restored.ports, ['25565:25565']);
    });

    test('对账创建副本并调度到匹配节点', () async {
      final result =
          await req('reconcile', {
                'observed': {
                  'nodes': [
                    {
                      'id': 'n1',
                      'runtime': 'docker',
                      'platform': 'linux',
                      'available': true,
                      'freeMemMb': 8192,
                      'freeCpus': 4,
                    },
                  ],
                  'replicas': <Map<String, dynamic>>[],
                },
              })
              as Map<String, dynamic>;
      final actions = (result['actions'] as List<dynamic>)
          .map((e) => OrchestrationAction.fromJson(e as Map<String, dynamic>))
          .toList();
      final creates = actions
          .where((a) => a.kind == OrchestrationActionKind.createContainer)
          .toList();
      expect(creates, hasLength(2), reason: '期望 2 副本');
      expect(creates.first.nodeId, 'n1');
      expect(creates.first.payload['ports'], ['25565:25565']);
      // 状态聚合
      final statusList = await req('status', {}) as List<dynamic>;
      final status = ServiceStatus.fromJson(
        statusList.first as Map<String, dynamic>,
      );
      expect(status.replicas, hasLength(2));
      expect(status.runningReplicas, 0);
    });

    test('Bastille 服务调度到 FreeBSD 节点并分配 IP', () async {
      await req('upsert_service', {
        'service': McService(
          id: 's2',
          name: 'bsd-sky',
          runtime: 'bastille',
          image: '14.2-RELEASE',
          ports: ['25565:25565'],
          bastilleIpBase: '192.168.1.50',
          desiredReplicas: 1,
        ).toJson(),
      });
      final result =
          await req('reconcile', {
                'observed': {
                  'nodes': [
                    {
                      'id': 'n2',
                      'runtime': 'bastille',
                      'platform': 'freebsd',
                      'available': true,
                      'freeMemMb': 4096,
                    },
                  ],
                  'replicas': <Map<String, dynamic>>[],
                },
              })
              as Map<String, dynamic>;
      final actions = (result['actions'] as List<dynamic>)
          .map((e) => OrchestrationAction.fromJson(e as Map<String, dynamic>))
          .toList();
      final creates = actions
          .where(
            (a) =>
                a.kind == OrchestrationActionKind.createContainer &&
                a.serviceId == 's2',
          )
          .toList();
      expect(creates, hasLength(1));
      expect(creates.first.nodeId, 'n2');
      expect(creates.first.payload['ip'], '192.168.1.50/24');
      expect(creates.first.payload['runtime'], 'bastille');
    });

    test('迁移状态机：启动→停止动作→推进', () async {
      final statusList =
          await req('status', {'serviceId': 's1'}) as List<dynamic>;
      final status = ServiceStatus.fromJson(
        statusList.first as Map<String, dynamic>,
      );
      final replica = status.replicas.first;
      final started =
          await req('migrate_start', {
                'serviceId': 's1',
                'replicaId': replica.id,
                'toNode': 'n9',
              })
              as Map<String, dynamic>;
      final job = MigrationJob.fromJson(started['job'] as Map<String, dynamic>);
      expect(job.state, MigrationState.stopping);
      final action = OrchestrationAction.fromJson(
        started['action'] as Map<String, dynamic>,
      );
      expect(action.kind, OrchestrationActionKind.stopContainer);
      expect(action.nodeId, 'n1');
      // 回报成功 → 推进到 archiving
      final next =
          await req('report_migration', {'jobId': job.id, 'ok': true})
              as Map<String, dynamic>;
      final nextJob = MigrationJob.fromJson(
        next['job'] as Map<String, dynamic>,
      );
      expect(nextJob.state, MigrationState.archiving);
      final nextAction = OrchestrationAction.fromJson(
        next['action'] as Map<String, dynamic>,
      );
      expect(nextAction.kind, OrchestrationActionKind.archiveWorld);
      // 取消
      await req('migrate_cancel', {'jobId': job.id});
      final jobs = await req('list_migrations', {}) as List<dynamic>;
      final cancelled = MigrationJob.fromJson(
        jobs.first as Map<String, dynamic>,
      );
      expect(cancelled.state, MigrationState.failed);
    });

    test('mc_ping 不可达主机返回离线', () async {
      final result =
          await req('mc_ping', {
                'host': '127.0.0.1',
                'port': 1,
                'timeoutMs': 500,
              })
              as Map<String, dynamic>;
      final status = McStatus.fromJson(result);
      expect(status.online, false);
      expect(status.players, 0);
    });

    test('清理 reset', () async {
      final result = await req('reset', {}) as Map<String, dynamic>;
      expect(result['reset'], true);
    });
  });
}
