// DockerCliBackend 测试：用 fake runner 验证参数组装与输出解析。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/container/container_backend.dart';
import 'package:irix/services/container/docker_cli_backend.dart';

/// 记录所有 docker 调用参数。
class FakeDockerRunner {
  final List<List<String>> calls = [];

  /// 按命令分支返回伪造输出。
  Future<DockerRunResult> call(
    List<String> args, {
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add(args);
    final cmd = args.join(' ');
    if (cmd.startsWith('version --format')) {
      return (
        exitCode: 0,
        stdout: jsonEncode({
          'Client': {'Version': '27.0.3'},
          'Server': {'Version': '27.0.3', 'ApiVersion': '1.46'},
        }),
        stderr: '',
      );
    }
    if (cmd.startsWith('ps -a --format')) {
      return (
        exitCode: 0,
        stdout: [
          {
            'Id': 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3',
            'Names': ['xmc-survival-0000'],
            'Image': 'itzg/minecraft-server:latest',
            'Status': 'Up 5 minutes',
            'State': 'running',
            'Ports': '0.0.0.0:25565->25565/tcp',
            'CreatedAt': '2026-08-13 10:00:00',
          },
          {
            'Id': 'deadbeef00000000000000000000000000000000',
            'Names': ['xmc-stopped-0001'],
            'Image': 'paper:1.21',
            'Status': 'Exited (0) 2 hours ago',
            'State': 'exited',
            'Ports': '',
            'CreatedAt': '2026-08-12 10:00:00',
          },
        ].map((e) => jsonEncode(e)).join('\n'),
        stderr: '',
      );
    }
    if (cmd.startsWith('stats --no-stream')) {
      return (
        exitCode: 0,
        stdout: jsonEncode({
          'CPUPerc': '12.34%',
          'MemUsage': '512.3MiB / 2GiB',
          'NetIO': '1.5kB / 2.3MB',
        }),
        stderr: '',
      );
    }
    if (cmd.startsWith('images --format')) {
      return (
        exitCode: 0,
        stdout: jsonEncode({
          'Id': 'sha256:abc123',
          'Repository': 'itzg/minecraft-server',
          'Tag': 'latest',
          'Size': '512MB',
          'CreatedAt': '2026-08-01 10:00:00',
        }),
        stderr: '',
      );
    }
    if (cmd.startsWith('volume ls --format')) {
      return (
        exitCode: 0,
        stdout: jsonEncode({
          'Name': 'mc-data',
          'Driver': 'local',
          'Mountpoint': '/var/lib/docker/volumes/mc-data/_data',
        }),
        stderr: '',
      );
    }
    if (cmd.startsWith('network ls --format')) {
      return (
        exitCode: 0,
        stdout: jsonEncode({'Name': 'bridge', 'Driver': 'bridge'}),
        stderr: '',
      );
    }
    if (cmd.startsWith('logs --tail')) {
      return (exitCode: 0, stdout: 'line1\nline2\nline3\n', stderr: '');
    }
    return (exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  late FakeDockerRunner runner;
  late DockerCliBackend backend;

  setUp(() {
    runner = FakeDockerRunner();
    backend = DockerCliBackend(cli: DockerCli(runner: runner.call));
  });

  group('environment', () {
    test('docker 可用时返回版本信息', () async {
      final env = await backend.environment();
      expect(env.available, isTrue);
      expect(env.version, '27.0.3');
      expect(env.runtime, ContainerRuntime.docker);
    });

    test('server 段缺失时标记不可用', () async {
      final offline = DockerCliBackend(
        cli: DockerCli(
          runner: (args, {stdin, timeout}) async => (
            exitCode: 0,
            stdout: jsonEncode({
              'Client': {'Version': '27.0.3'},
            }),
            stderr: '',
          ),
        ),
      );
      final env = await offline.environment();
      expect(env.available, isFalse);
      expect(env.errorMessage, contains('Docker 服务未运行'));
    });

    test('命令失败时标记不可用', () async {
      final broken = DockerCliBackend(
        cli: DockerCli(
          runner: (args, {stdin, timeout}) async =>
              (exitCode: 1, stdout: '', stderr: 'docker: command not found'),
        ),
      );
      final env = await broken.environment();
      expect(env.available, isFalse);
      expect(env.errorMessage, isNotNull);
    });
  });

  group('listContainers', () {
    test('解析容器列表与运行状态', () async {
      final containers = await backend.listContainers();
      expect(containers.length, 2);
      final running = containers.first;
      expect(running.name, 'xmc-survival-0000');
      expect(running.image, 'itzg/minecraft-server:latest');
      expect(running.isRunning, isTrue);
      expect(running.ports.single, '0.0.0.0:25565->25565/tcp');
      expect(containers.last.isRunning, isFalse);
    });
  });

  group('createContainer', () {
    test('参数组装：名称/端口/卷/环境变量/资源限制', () async {
      await backend.createContainer(
        const CreateContainerRequest(
          name: 'xmc-test',
          image: 'itzg/minecraft-server:latest',
          ports: ['25565:25565'],
          volumes: ['/data/mc:/data'],
          env: {'MEMORY': '2G'},
          restartPolicy: 'unless-stopped',
          memoryLimitMb: 4096,
          cpus: 4,
        ),
      );
      final args = runner.calls.last;
      expect(args.first, 'create');
      expect(args, containsAll(['--name', 'xmc-test']));
      expect(args, containsAll(['-p', '25565:25565']));
      expect(args, containsAll(['-v', '/data/mc:/data']));
      expect(args, containsAll(['-e', 'MEMORY=2G']));
      expect(args, containsAll(['--restart', 'unless-stopped']));
      expect(args, containsAll(['-m', '4096m']));
      expect(args, containsAll(['--cpus', '4']));
      expect(args.last, 'itzg/minecraft-server:latest');
    });

    test('带启动命令时按空白拆分追加', () async {
      await backend.createContainer(
        const CreateContainerRequest(
          name: 'xmc-test',
          image: 'java:21',
          command: 'java -Xmx2G -jar server.jar nogui',
        ),
      );
      final args = runner.calls.last;
      expect(args, contains('java:21'));
      expect(args.sublist(args.length - 5), [
        'java',
        '-Xmx2G',
        '-jar',
        'server.jar',
        'nogui',
      ]);
    });
  });

  group('containerStats', () {
    test('解析 CPU / 内存 / 网络', () async {
      final stats = await backend.containerStats('xmc-test');
      expect(stats, isNotNull);
      expect(stats!.cpuPercent, 12.34);
      expect(stats.memoryBytes, (512.3 * 1024 * 1024).round());
      expect(stats.memoryLimitBytes, 2 * 1024 * 1024 * 1024);
      expect(stats.netRxBytes, 1500);
      expect(stats.netTxBytes, 2300000);
      expect(stats.memoryPercent, closeTo(0.25, 0.01));
    });
  });

  group('listImages / listVolumes / listNetworks', () {
    test('镜像解析', () async {
      final images = await backend.listImages();
      expect(images.single.tags, ['itzg/minecraft-server:latest']);
      expect(images.single.sizeBytes, 512 * 1000 * 1000);
    });

    test('卷与网络解析', () async {
      final volumes = await backend.listVolumes();
      expect(volumes.single.name, 'mc-data');
      final networks = await backend.listNetworks();
      expect(networks.single.name, 'bridge');
    });
  });

  group('logs', () {
    test('容器日志尾部', () async {
      final log = await backend.containerLogs('xmc-test', tail: 100);
      expect(log, contains('line3'));
      final args = runner.calls.last;
      expect(args, containsAll(['logs', '--tail', '100']));
    });
  });

  group('exec', () {
    test('经 sh -c 执行避免拆散命令', () async {
      await backend.execInContainer('xmc-test', 'say hello world');
      final args = runner.calls.last;
      expect(args, ['exec', 'xmc-test', 'sh', '-c', 'say hello world']);
    });
  });
}
