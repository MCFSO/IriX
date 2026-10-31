// 启动命令与 JVM 设置同步的单元测试
//
// 覆盖 [JvmCommandSync.apply]：
// - 预设切换：参数随选择增删（含幂等）
// - 手动内存：写入 / 改写 -Xms/-Xmx
// - 自动内存：从命令中移除内存参数（启动时再注入）
// - 非 java 命令不改写、自定义 Java 路径保留引号

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/models/jvm_preset.dart';
import 'package:irix/services/jvm/jvm_args.dart';
import 'package:irix/services/jvm/jvm_command_sync.dart';

void main() {
  group('JvmCommandSync.apply', () {
    test('选择 Aikar 后参数写入命令', () {
      final cmd = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.aikar,
        memoryAuto: true,
      );
      for (final flag in aikarFlags) {
        expect(cmd.contains(flag), isTrue, reason: '缺少 $flag');
      }
      expect(cmd.startsWith('java -XX:+AlwaysPreTouch'), isTrue);
      expect(cmd.endsWith('-jar server.jar nogui'), isTrue);
    });

    test('切回「无」后预设参数被移除', () {
      final withPreset = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.aikar,
        memoryAuto: true,
      );
      final cleared = JvmCommandSync.apply(
        withPreset,
        preset: JvmPreset.none,
        memoryAuto: true,
      );
      expect(cleared, 'java -jar server.jar nogui');
    });

    test('重复应用同一预设保持幂等', () {
      final once = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.aikar,
        memoryAuto: true,
      );
      final twice = JvmCommandSync.apply(
        once,
        preset: JvmPreset.aikar,
        memoryAuto: true,
      );
      expect(twice, once);
    });

    test('手动内存写入 -Xms/-Xmx', () {
      final cmd = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.none,
        memoryAuto: false,
        memoryMb: 4096,
      );
      expect(cmd, 'java -Xms4096M -Xmx4096M -jar server.jar nogui');
    });

    test('手动内存改写命令中已有的 -Xmx', () {
      final cmd = JvmCommandSync.apply(
        'java -Xmx1024M -jar server.jar nogui',
        preset: JvmPreset.none,
        memoryAuto: false,
        memoryMb: 3072,
      );
      expect(cmd, 'java -Xms3072M -Xmx3072M -jar server.jar nogui');
    });

    test('切回自动分配时移除内存参数', () {
      final manual = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.none,
        memoryAuto: false,
        memoryMb: 4096,
      );
      final auto = JvmCommandSync.apply(
        manual,
        preset: JvmPreset.none,
        memoryAuto: true,
      );
      expect(auto, 'java -jar server.jar nogui');
    });

    test('手动模式未给数值时保留命令原有内存参数', () {
      final cmd = JvmCommandSync.apply(
        'java -Xmx2G -jar server.jar nogui',
        preset: JvmPreset.none,
        memoryAuto: false,
      );
      expect(cmd, 'java -Xmx2G -jar server.jar nogui');
    });

    test('非 java 命令原样返回', () {
      const original = './start.sh --nogui';
      expect(
        JvmCommandSync.apply(
          original,
          preset: JvmPreset.aikar,
          memoryAuto: false,
          memoryMb: 4096,
        ),
        original,
      );
    });

    test('带空格的 java 路径保留引号', () {
      final cmd = JvmCommandSync.apply(
        r'"C:\Program Files\Java\jdk-17\bin\java.exe" -jar server.jar',
        preset: JvmPreset.none,
        memoryAuto: false,
        memoryMb: 2048,
      );
      expect(
        cmd,
        r'"C:\Program Files\Java\jdk-17\bin\java.exe" -Xms2048M -Xmx2048M -jar server.jar',
      );
    });

    test('同步后的命令再走启动注入不会重复参数', () async {
      final synced = JvmCommandSync.apply(
        'java -jar server.jar nogui',
        preset: JvmPreset.aikar,
        memoryAuto: true,
      );
      final injected = JvmArgs.inject(
        synced,
        maxMemoryMb: 4096,
        preset: JvmPreset.aikar,
      );
      expect('-XX:+UseG1GC'.allMatches(injected).length, 1);
      expect('-Xmx4096M'.allMatches(injected).length, 1);
    });
  });
}
