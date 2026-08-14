// 容器后端测试：DockerCliBackend 参数组装与 Bastille 专属能力边界。
// 通过注入 fake runner 验证 docker 命令参数，不依赖真实 docker 环境。

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/container/container_backend.dart';
import 'package:irix/services/container/docker_cli_backend.dart';

/// 记录调用参数的 fake runner。
class _FakeRunner {
  final List<(List<String>, String?)> calls = [];
  int exitCode = 0;
  String stdout = '';
  String stderr = '';

  Future<DockerRunResult> call(
    List<String> args, {
    String? stdin,
    Duration? timeout,
  }) async {
    calls.add((List<String>.of(args), stdin));
    return (exitCode: exitCode, stdout: stdout, stderr: stderr);
  }
}

void main() {
  late _FakeRunner fake;
  late DockerCliBackend backend;

  setUp(() {
    fake = _FakeRunner();
    backend = DockerCliBackend(cli: DockerCli(runner: fake.call));
  });

  group('CreateContainerRequest', () {
    test('BastilleSetupRequest.toJson 携带完整字段', () {
      const request = BastilleSetupRequest(
        mode: 'vnet',
        extIf: 'em0',
        tunIf: 'bastille0',
        addr: '10.99.0.0/24',
      );
      expect(request.toJson(), {
        'mode': 'vnet',
        'extIf': 'em0',
        'tunIf': 'bastille0',
        'addr': '10.99.0.0/24',
      });
    });

    test('BastilleSetupRequest.toJson 忽略空字段', () {
      const request = BastilleSetupRequest(mode: 'linux');
      expect(request.toJson(), {'mode': 'linux'});
    });

    test('PortMappingInfo.display 格式', () {
      const mapping = PortMappingInfo(
        container: 'mc',
        proto: 'tcp',
        hostPort: 25565,
        containerPort: 25565,
      );
      expect(mapping.display, 'tcp 25565 -> 25565');
    });
  });

  group('DockerCliBackend.createContainer', () {
    test('组装完整参数（含磁盘上限与工作目录）', () async {
      await backend.createContainer(
        const CreateContainerRequest(
          name: 'mc',
          image: 'img:latest',
          ports: ['25565:25565'],
          volumes: ['/host:/data'],
          env: {'EULA': 'TRUE'},
          restartPolicy: 'unless-stopped',
          memoryLimitMb: 2048,
          cpus: 2,
          diskLimitMb: 10240,
          workdir: '/data',
          command: 'java -jar server.jar nogui',
        ),
      );
      expect(fake.calls.single.$1, [
        'create',
        '--name',
        'mc',
        '-p',
        '25565:25565',
        '-v',
        '/host:/data',
        '-e',
        'EULA=TRUE',
        '--restart',
        'unless-stopped',
        '-m',
        '2048m',
        '--cpus',
        '2',
        '--storage-opt',
        'size=10240m',
        '-w',
        '/data',
        'img:latest',
        'java',
        '-jar',
        'server.jar',
        'nogui',
      ]);
    });

    test('最小请求不带可选参数', () async {
      await backend.createContainer(
        const CreateContainerRequest(name: 'mc', image: 'img'),
      );
      expect(fake.calls.single.$1, ['create', '--name', 'mc', 'img']);
    });
  });

  group('DockerCliBackend.cloneContainer', () {
    test('commit 源容器后按新名称 create', () async {
      final info = await backend.cloneContainer('src', newName: 'dst');
      expect(fake.calls, hasLength(2));
      expect(fake.calls[0].$1[0], 'commit');
      expect(fake.calls[0].$1[1], 'src');
      expect(fake.calls[0].$1[2], startsWith('dst:'));
      expect(fake.calls[1].$1[0], 'create');
      expect(fake.calls[1].$1[1], '--name');
      expect(fake.calls[1].$1[2], 'dst');
      expect(info.name, 'dst');
      expect(info.status, 'created');
    });
  });

  group('DockerCliBackend.updateContainerLimits', () {
    test('同时设置内存与 CPU', () async {
      await backend.updateContainerLimits('mc', memoryLimitMb: 4096, cpus: 4);
      expect(fake.calls.single.$1, ['update', '-m', '4096m', '--cpus', '4', 'mc']);
    });

    test('磁盘上限热更新抛异常', () async {
      expect(
        () => backend.updateContainerLimits('mc', diskLimitMb: 1024),
        throwsA(isA<ContainerBackendException>()),
      );
    });

    test('无任何限制时不执行命令', () async {
      await backend.updateContainerLimits('mc');
      expect(fake.calls, isEmpty);
    });
  });

  group('DockerCliBackend Bastille 专属能力', () {
    test('setupEnvironment 抛异常', () {
      expect(
        () => backend.setupEnvironment(const BastilleSetupRequest(mode: 'pf')),
        throwsA(isA<ContainerBackendException>()),
      );
    });

    test('exportContainer 抛异常', () {
      expect(
        () => backend.exportContainer('mc'),
        throwsA(isA<ContainerBackendException>()),
      );
    });

    test('importContainer 抛异常', () {
      expect(
        () => backend.importContainer('/tmp/x.txz'),
        throwsA(isA<ContainerBackendException>()),
      );
    });

    test('listPortMappings 抛异常', () {
      expect(
        () => backend.listPortMappings(),
        throwsA(isA<ContainerBackendException>()),
      );
    });
  });
}
