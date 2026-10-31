// JVM 调参相关单元测试（纯 Dart，不依赖 Rust 动态库与真实系统信息）
//
// 覆盖：
// - MemoryAllocator：HMCL 的推荐值公式与自动分配公式
// - JvmArgs.inject：-Xms/-Xmx 覆盖、预设去重、非 java 命令不改写
// - JavaLauncher：首 token 切分、java 识别、可执行文件替换与引号
// - ServerInstance：新字段的序列化往返与旧数据默认值

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/jvm_preset.dart';
import 'package:irix/models/server_instance.dart';
import 'package:irix/services/java/java_launcher.dart';
import 'package:irix/services/jvm/jvm_args.dart';
import 'package:irix/services/jvm/memory_allocator.dart';
import 'package:irix/services/system_memory.dart';

ServerInstance makeInstance({
  String startCommand = 'java -jar server.jar nogui',
  bool memoryAuto = true,
  int? memoryMb,
  JvmPreset preset = JvmPreset.none,
}) {
  return ServerInstance(
    id: 'id-1',
    name: '生存服',
    rootPath: '/data/mc',
    coreFilePath: '/data/mc/server.jar',
    startCommand: startCommand,
    memoryAuto: memoryAuto,
    memoryMb: memoryMb,
    jvmPreset: preset,
  );
}

void main() {
  group('MemoryAllocator.suggestedMemoryMb（HMCL SUGGESTED_MEMORY）', () {
    test('按内存总量取 1/4 并 128 MiB 对齐', () {
      expect(MemoryAllocator.suggestedMemoryMb(16384), 4096);
      expect(MemoryAllocator.suggestedMemoryMb(8192), 2048);
    });

    test('32 GiB 及以上固定 8192 MiB', () {
      expect(MemoryAllocator.suggestedMemoryMb(32768), 8192);
      expect(MemoryAllocator.suggestedMemoryMb(65536), 8192);
    });

    test('极小内存不低于 256 MiB', () {
      expect(MemoryAllocator.suggestedMemoryMb(512), 256);
      expect(MemoryAllocator.suggestedMemoryMb(1024), 256);
    });
  });

  group('MemoryAllocator.autoMemoryMb（HMCL getAutoAllocatedMemory）', () {
    const gb = 1024 * 1024 * 1024;

    test('8 GiB 可用：扣 512 MiB 预留后取 80%', () {
      // usable = 7680 MiB → 6144 MiB
      expect(MemoryAllocator.autoMemoryMb(8 * gb), 6144);
    });

    test('32 GiB 可用：超出 8 GiB 的部分按 20% 计入', () {
      // usable = 32256 → 6553 + 24064*0.2 = 11365 → 向下对齐 128 → 11264
      expect(MemoryAllocator.autoMemoryMb(32 * gb), 11264);
    });

    test('低内存不低于 512 MiB', () {
      expect(MemoryAllocator.autoMemoryMb(1 * gb), 512);
      expect(MemoryAllocator.autoMemoryMb(400 * 1024 * 1024), 512);
    });

    test('上限不超过 16 GiB', () {
      expect(MemoryAllocator.autoMemoryMb(128 * gb), 16384);
    });
  });

  group('MemoryAllocator 手动模式边界', () {
    const gb = 1024 * 1024 * 1024;

    test('上限为可用内存扣预留', () {
      expect(MemoryAllocator.manualUpperBoundMb(8 * gb), 7680);
    });

    test('clamp 到最小/上限并对齐', () {
      expect(MemoryAllocator.clampMb(100, upperBoundMb: 7680), minMemoryMb);
      expect(MemoryAllocator.clampMb(99999, upperBoundMb: 7680), 7680);
      expect(MemoryAllocator.clampMb(4097, upperBoundMb: 7680), 4096);
    });
  });

  group('JvmArgs.inject', () {
    test('在 java 之后插入 -Xms/-Xmx，原参数保留', () {
      final cmd = JvmArgs.inject(
        'java -jar server.jar nogui',
        maxMemoryMb: 4096,
        preset: JvmPreset.none,
      );
      expect(cmd, 'java -Xms4096M -Xmx4096M -jar server.jar nogui');
    });

    test('命令里已有的 -Xmx/-Xms 被覆盖而不是重复', () {
      final cmd = JvmArgs.inject(
        'java -Xms512M -Xmx1024M -jar server.jar nogui',
        maxMemoryMb: 4096,
        preset: JvmPreset.none,
      );
      expect(cmd, 'java -Xms4096M -Xmx4096M -jar server.jar nogui');
    });

    test('Aikar 预设全量追加', () {
      final cmd = JvmArgs.inject(
        'java -jar server.jar nogui',
        maxMemoryMb: 2048,
        preset: JvmPreset.aikar,
      );
      for (final flag in aikarFlags) {
        expect(cmd.contains(flag), isTrue, reason: '缺少 $flag');
      }
      expect(aikarFlags.length, 20);
    });

    test('命令中已存在的预设参数不会重复追加', () {
      final cmd = JvmArgs.inject(
        'java -XX:+UseG1GC -jar server.jar nogui',
        maxMemoryMb: 2048,
        preset: JvmPreset.aikar,
      );
      expect('-XX:+UseG1GC'.allMatches(cmd).length, 1);
    });

    test('非 java 命令原样返回', () {
      const original = './start.sh --nogui';
      final cmd = JvmArgs.inject(
        original,
        maxMemoryMb: 4096,
        preset: JvmPreset.aikar,
      );
      expect(cmd, original);
    });

    test('带空格的 java 路径保持引号', () {
      final cmd = JvmArgs.inject(
        r'"C:\Program Files\Java\jdk-17\bin\java.exe" -jar server.jar',
        maxMemoryMb: 1024,
        preset: JvmPreset.none,
      );
      expect(
        cmd,
        r'"C:\Program Files\Java\jdk-17\bin\java.exe" -Xms1024M -Xmx1024M -jar server.jar',
      );
    });
  });

  group('JavaLauncher', () {
    test('识别 java 可执行文件（含路径与大小写）', () {
      expect(JavaLauncher.usesJavaExecutable('java -jar a.jar'), isTrue);
      expect(
        JavaLauncher.usesJavaExecutable(r'C:\jdk\bin\java.exe -jar a.jar'),
        isTrue,
      );
      expect(
        JavaLauncher.usesJavaExecutable('/opt/jdk/bin/java -version'),
        isTrue,
      );
      expect(JavaLauncher.usesJavaExecutable('./start.sh'), isFalse);
      expect(JavaLauncher.usesJavaExecutable('bash run.sh'), isFalse);
      expect(JavaLauncher.usesJavaExecutable(''), isFalse);
    });

    test('splitFirstToken 保留剩余原文', () {
      final split = JavaLauncher.splitFirstToken('  java   -jar a.jar ');
      expect(split!.token, 'java');
      expect(split.rest, '   -jar a.jar ');
    });

    test('replaceExecutable 替换首项并保留参数', () {
      final cmd = JavaLauncher.replaceExecutable(
        'java -Xmx2G -jar a.jar nogui',
        r'C:\Program Files\Java\bin\java.exe',
      );
      expect(
        cmd,
        r'"C:\Program Files\Java\bin\java.exe" -Xmx2G -jar a.jar nogui',
      );
    });

    test('无空格的路径不加引号', () {
      expect(JavaLauncher.quoteExecutable('/usr/bin/java'), '/usr/bin/java');
    });
  });

  group('JvmArgs.resolve', () {
    const gib = 1024 * 1024 * 1024;
    const memory = SystemMemoryInfo(
      totalBytes: 16 * gib,
      availableBytes: 8 * gib,
      source: 'test',
    );

    test('自动模式按可用内存计算并注入', () async {
      final plan = await JvmArgs.resolve(
        makeInstance(memoryAuto: true),
        memory: memory,
      );
      expect(plan.maxMemoryMb, 6144);
      expect(plan.command, 'java -Xms6144M -Xmx6144M -jar server.jar nogui');
      expect(plan.applied, isTrue);
    });

    test('手动模式未设置数值时不注入内存参数', () async {
      final instance = makeInstance(memoryAuto: false);
      final plan = await JvmArgs.resolve(instance, memory: memory);
      expect(plan.maxMemoryMb, isNull);
      expect(plan.command, instance.startCommand);
      expect(plan.applied, isFalse);
    });

    test('手动模式设置数值后覆盖命令中的 -Xmx', () async {
      final plan = await JvmArgs.resolve(
        makeInstance(
          startCommand: 'java -Xmx1024M -jar server.jar nogui',
          memoryAuto: false,
          memoryMb: 3072,
        ),
        memory: memory,
      );
      expect(plan.maxMemoryMb, 3072);
      expect(plan.command, 'java -Xms3072M -Xmx3072M -jar server.jar nogui');
    });

    test('预设参数在自动/手动模式下都会注入', () async {
      final plan = await JvmArgs.resolve(
        makeInstance(memoryAuto: false, preset: JvmPreset.aikar),
        memory: memory,
      );
      expect(plan.maxMemoryMb, isNull);
      expect(plan.command.contains('-XX:+UseG1GC'), isTrue);
      expect(plan.command.startsWith('java -XX:+AlwaysPreTouch'), isTrue);
    });

    test('启动命令首项不是 java 时，计划同样不改写命令', () async {
      const original = './start.sh';
      final plan = await JvmArgs.resolve(
        makeInstance(
          startCommand: original,
          memoryAuto: true,
          preset: JvmPreset.aikar,
        ),
        memory: memory,
      );
      expect(plan.command, original);
      expect(plan.applied, isFalse);
      // 计算值仍会展示给 UI（设置页需要显示「将分配」）。
      expect(plan.maxMemoryMb, 6144);
    });
  });

  group('ServerInstance JVM 字段', () {
    test('序列化往返保留设置', () {
      final instance = makeInstance(
        memoryAuto: false,
        memoryMb: 6144,
        preset: JvmPreset.aikar,
      );
      final restored = ServerInstance.fromJson(instance.toJson());
      expect(restored.memoryAuto, isFalse);
      expect(restored.memoryMb, 6144);
      expect(restored.jvmPreset, JvmPreset.aikar);
    });

    test('旧 JSON 缺失字段时默认自动分配 + 无预设', () {
      const legacy =
          '{"id":"a","name":"n","rootPath":"/p","coreFilePath":"/p/j.jar",'
          '"startCommand":"java -jar j.jar","createdAt":"2026-01-01T00:00:00.000"}';
      final restored = ServerInstance.fromJson(legacy);
      expect(restored.memoryAuto, isTrue);
      expect(restored.memoryMb, isNull);
      expect(restored.jvmPreset, JvmPreset.none);
      expect(restored.javaMode, InstanceJavaMode.auto);
    });

    test('未知预设值回退为无', () {
      expect(JvmPreset.fromString('zgc'), JvmPreset.none);
      expect(JvmPreset.fromString(null), JvmPreset.none);
      expect(JvmPreset.fromString('aikar'), JvmPreset.aikar);
    });
  });
}
