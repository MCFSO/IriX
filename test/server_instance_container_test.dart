// ServerInstance 容器化模型测试：RunMode / ContainerConfig 序列化与兼容性。

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/server_instance.dart';

void main() {
  group('ContainerConfig', () {
    test('序列化往返保持一致', () {
      const config = ContainerConfig(
        image: 'itzg/minecraft-server:latest',
        containerName: 'xmc-survival',
        ports: ['25565:25565', '8123:8123'],
        volumes: ['/data/mc:/data'],
        env: {'MEMORY': '2G', 'EULA': 'TRUE'},
        restartPolicy: 'unless-stopped',
        memoryLimitMb: 4096,
        cpus: 4,
        diskLimitMb: 20480,
        workdir: '/data',
      );
      final restored = ContainerConfig.fromJson(config.toJson());
      expect(restored.image, config.image);
      expect(restored.containerName, config.containerName);
      expect(restored.ports, config.ports);
      expect(restored.volumes, config.volumes);
      expect(restored.env, config.env);
      expect(restored.restartPolicy, config.restartPolicy);
      expect(restored.memoryLimitMb, config.memoryLimitMb);
      expect(restored.cpus, config.cpus);
      expect(restored.diskLimitMb, config.diskLimitMb);
      expect(restored.workdir, config.workdir);
    });

    test('空 JSON 使用默认值', () {
      final config = ContainerConfig.fromJson('{}');
      expect(config.image, 'itzg/minecraft-server:latest');
      expect(config.ports, ['25565:25565']);
      expect(config.containerName, isNull);
      expect(config.memoryLimitMb, isNull);
      expect(config.diskLimitMb, isNull);
      expect(config.workdir, isNull);
    });

    test('校验端口与卷格式', () {
      const good = ContainerConfig();
      expect(good.validate(), isNull);

      const badPort = ContainerConfig(ports: ['not-a-port']);
      expect(badPort.validate(), contains('端口映射格式错误'));

      const badVolume = ContainerConfig(volumes: ['/only/host/path']);
      expect(badVolume.validate(), contains('卷挂载格式错误'));

      const badImage = ContainerConfig(image: '  ');
      expect(badImage.validate(), contains('镜像不能为空'));
    });

    test('copyWith 支持清除可空字段', () {
      const config = ContainerConfig(
        containerName: 'abc',
        restartPolicy: 'always',
        memoryLimitMb: 1024,
        cpus: 2,
        diskLimitMb: 5120,
        workdir: '/data',
      );
      final cleared = config.copyWith(
        clearContainerName: true,
        clearRestartPolicy: true,
        clearMemory: true,
        clearCpus: true,
        clearDiskLimit: true,
        clearWorkdir: true,
      );
      expect(cleared.containerName, isNull);
      expect(cleared.restartPolicy, isNull);
      expect(cleared.memoryLimitMb, isNull);
      expect(cleared.cpus, isNull);
      expect(cleared.diskLimitMb, isNull);
      expect(cleared.workdir, isNull);
      expect(cleared.image, config.image);
    });
  });

  group('ServerInstance', () {
    final base = ServerInstance(
      id: 'id-1',
      name: '生存服',
      rootPath: '/data/mc',
      coreFilePath: '/data/mc/paper.jar',
      startCommand: 'java -Xmx2G -jar paper.jar nogui',
    );

    test('默认原生运行、无容器配置', () {
      expect(base.runMode, RunMode.native);
      expect(base.container, isNull);
    });

    test('docker 模式序列化往返', () {
      final docker = ServerInstance(
        id: base.id,
        name: base.name,
        rootPath: base.rootPath,
        coreFilePath: base.coreFilePath,
        startCommand: base.startCommand,
        runMode: RunMode.docker,
        container: const ContainerConfig(image: 'paper:1.21'),
      );
      final restored = ServerInstance.fromJson(docker.toJson());
      expect(restored.runMode, RunMode.docker);
      expect(restored.container!.image, 'paper:1.21');
    });

    test('旧 JSON（无 runMode 字段）回退为原生运行', () {
      final oldJson =
          '{"id":"a","name":"n","rootPath":"/p","coreFilePath":"/p/j.jar",'
          '"startCommand":"java -jar j.jar","createdAt":"2026-01-01T00:00:00.000"}';
      final restored = ServerInstance.fromJson(oldJson);
      expect(restored.runMode, RunMode.native);
      expect(restored.container, isNull);
    });

    test('未知 runMode 值回退为原生', () {
      final restored = ServerInstance.fromJson(
        '{"id":"a","name":"n","rootPath":"/p","coreFilePath":"/p/j.jar",'
        '"startCommand":"java -jar j.jar","runMode":"kubernetes",'
        '"createdAt":"2026-01-01T00:00:00.000"}',
      );
      expect(restored.runMode, RunMode.native);
    });

    test('RunMode.fromString 未知值回退', () {
      expect(RunMode.fromString('docker'), RunMode.docker);
      expect(RunMode.fromString('native'), RunMode.native);
      expect(RunMode.fromString(null), RunMode.native);
      expect(RunMode.fromString('xyz'), RunMode.native);
    });
  });
}
