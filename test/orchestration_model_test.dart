// 编排模型序列化测试：与 Rust xmc_orchestrator 的 JSON 契约（camelCase）一致性。

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/orchestration.dart';

void main() {
  group('McService', () {
    test('toJson 使用 camelCase 契约键', () {
      const service = McService(
        id: 's1',
        name: 'survival',
        runtime: 'bastille',
        image: '14.2-RELEASE',
        ports: ['25565:25565'],
        bastilleIpBase: '192.168.1.50',
        desiredReplicas: 2,
        minReplicas: 1,
        maxReplicas: 4,
        autoscale: true,
        targetPlayers: 20,
        autoHeal: true,
      );
      final json = service.toJson();
      expect(json['bastilleIpBase'], '192.168.1.50');
      expect(json['desiredReplicas'], 2);
      expect(json['minReplicas'], 1);
      expect(json['maxReplicas'], 4);
      expect(json['targetPlayers'], 20);
      expect(json['autoscale'], true);
      expect(json['autoHeal'], true);
      expect(json['runtime'], 'bastille');
    });

    test('fromJson 与 toJson 往返一致', () {
      const service = McService(
        id: 's1',
        name: 'survival',
        runtime: 'docker',
        image: 'itzg/minecraft-server:latest',
        volumes: ['/data/mc:/data'],
        worldDir: '/data/world',
        scaleUpPlayers: 30,
        scaleDownPlayers: 8,
        cooldownSecs: 120,
        crashThreshold: 3,
        backoffBaseSecs: 10,
        maxBackoffSecs: 120,
        nodeSelector: {'zone': 'east'},
      );
      final restored = McService.fromJson(service.toJson());
      expect(restored.id, service.id);
      expect(restored.volumes, service.volumes);
      expect(restored.worldDir, '/data/world');
      expect(restored.scaleUpPlayers, 30);
      expect(restored.scaleDownPlayers, 8);
      expect(restored.cooldownSecs, 120);
      expect(restored.crashThreshold, 3);
      expect(restored.backoffBaseSecs, 10);
      expect(restored.maxBackoffSecs, 120);
      expect(restored.nodeSelector, {'zone': 'east'});
    });
  });

  group('McReplica', () {
    test('JSON 往返（含崩溃状态）', () {
      final replica = McReplica.fromJson({
        'id': 'r1',
        'serviceId': 's1',
        'indexNo': 2,
        'nodeId': 'n1',
        'containerName': 'xmc-survival-r2',
        'hostPort': 25567,
        'ip': '192.168.1.52/24',
        'desired': 'running',
        'running': true,
        'ready': true,
        'playersOnline': 15,
        'crashCount': 2,
        'crashLoop': false,
        'backoffSecs': 40,
        'lastAttemptMs': 123,
        'stableSinceMs': 456,
      });
      expect(replica.indexNo, 2);
      expect(replica.hostPort, 25567);
      expect(replica.ip, '192.168.1.52/24');
      expect(replica.desired, ReplicaDesired.running);
      expect(replica.playersOnline, 15);
      expect(replica.crashCount, 2);
      expect(replica.backoffSecs, 40);
      final roundtrip = McReplica.fromJson(replica.toJson());
      expect(roundtrip.containerName, replica.containerName);
      expect(roundtrip.stableSinceMs, 456);
    });
  });

  group('ServiceStatus', () {
    test('解析聚合状态', () {
      final status = ServiceStatus.fromJson({
        'id': 's1',
        'name': 'survival',
        'runtime': 'docker',
        'image': 'img',
        'replicas': [
          {
            'id': 'r1',
            'serviceId': 's1',
            'indexNo': 0,
            'nodeId': 'n1',
            'containerName': 'c',
            'playersOnline': 8,
            'running': true,
            'ready': true,
          },
          {
            'id': 'r2',
            'serviceId': 's1',
            'indexNo': 1,
            'nodeId': 'n1',
            'containerName': 'c2',
            'playersOnline': 4,
            'running': true,
            'ready': true,
          },
        ],
        'runningReplicas': 2,
        'totalPlayers': 12,
        'avgPlayers': 6.0,
        'migrating': false,
      });
      expect(status.replicas.length, 2);
      expect(status.totalPlayers, 12);
      expect(status.avgPlayers, 6.0);
      expect(status.migrating, false);
    });
  });

  group('MigrationJob', () {
    test('状态标签与活跃判定', () {
      final job = MigrationJob.fromJson({
        'id': 'm1',
        'serviceId': 's1',
        'replicaId': 'r1',
        'fromNode': 'n1',
        'toNode': 'n2',
        'state': 'transferring',
        'error': '超时',
        'archiveName': 'world_s1_0.zip',
      });
      expect(job.state, MigrationState.transferring);
      expect(job.state.label, '传输存档');
      expect(job.state.isActive, true);
      expect(MigrationState.done.isActive, false);
      expect(MigrationState.failed.isActive, false);
    });
  });

  group('OrchestrationAction', () {
    test('解析动作与 payload', () {
      final action = OrchestrationAction.fromJson({
        'kind': 'restart_container',
        'serviceId': 's1',
        'replicaId': 'r1',
        'nodeId': 'n1',
        'payload': {'crashCount': 2, 'backoffSecs': 20},
        'delayMs': 20000,
        'migrationId': '',
      });
      expect(action.kind, OrchestrationActionKind.restartContainer);
      expect(action.delayMs, 20000);
      expect(action.payload['crashCount'], 2);
    });
  });
}
