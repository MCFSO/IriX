// 启动时的 JVM 参数注入
//
// 分工：可见的预设与手动内存由 [JvmCommandSync] 直接写进启动命令；
// 本文件只负责启动那一刻的补齐：
//   1. 自动分配模式下，按当次可用内存计算 -Xms/-Xmx 并写入（命令里本来没有）；
//   2. 预设参数做去重兜底（命令被手动改过时仍保证参数齐全）；
//   3. 手动模式且未设置数值时不动命令中的内存参数。
//
// 自动内存不落库的原因：可用内存在每次启动时都可能不同，
// 写死进命令会让「自动分配」退化为一次性快照。

import '../../models/jvm_preset.dart';
import '../../models/server_instance.dart';
import '../system_memory.dart';
import '../java/java_launcher.dart';
import 'memory_allocator.dart';

/// 一次启动的 JVM 决策结果。
class JvmPlan {
  const JvmPlan({
    required this.command,
    required this.maxMemoryMb,
    required this.autoMemory,
    required this.preset,
    required this.memoryInfo,
    required this.applied,
  });

  /// 最终执行的启动命令。
  final String command;

  /// 实际注入的最大堆（MiB）；null 表示未注入（手动模式尚未设置数值，
  /// 沿用启动命令中的写法）。
  final int? maxMemoryMb;

  /// 是否为自动分配。
  final bool autoMemory;

  /// 应用的优化参数预设。
  final JvmPreset preset;

  /// 本次计算依据的系统内存信息。
  final SystemMemoryInfo memoryInfo;

  /// 是否真的改写了命令（命令首项不是 java 时为 false——例如 `./start.sh`，
  /// 此时内存与优化参数都无从注入）。
  final bool applied;
}

/// JVM 参数解析与注入。
class JvmArgs {
  const JvmArgs._();

  /// java 可执行文件名（小写，含扩展名）。
  static const Set<String> _javaNames = {
    'java',
    'java.exe',
    'javaw',
    'javaw.exe',
  };

  /// 解析实例本次启动的内存与优化参数，并返回合成后的命令。
  ///
  /// [baseCommand] 用于传入已完成 Java 可执行文件替换的命令；为空时
  /// 以 [ServerInstance.startCommand] 为基准。
  /// [memory] 仅用于测试注入，生产环境走 [SystemMemory.detect]。
  static Future<JvmPlan> resolve(
    ServerInstance instance, {
    String? baseCommand,
    SystemMemoryInfo? memory,
  }) async {
    final info = memory ?? await SystemMemory.detect();
    final upperBound = MemoryAllocator.manualUpperBoundMb(info.availableBytes);

    // 手动模式且从未设置过数值时，不注入内存参数：沿用启动命令里的写法
    // （导入型实例的命令通常已带 -Xmx2G，不能被悄悄改掉）。
    final int? maxMemoryMb;
    if (instance.memoryAuto) {
      maxMemoryMb = MemoryAllocator.autoMemoryMb(info.availableBytes);
    } else if (instance.memoryMb != null) {
      maxMemoryMb = MemoryAllocator.clampMb(
        instance.memoryMb!,
        upperBoundMb: upperBound,
      );
    } else {
      maxMemoryMb = null;
    }

    final base = baseCommand ?? instance.startCommand;
    final command = inject(
      base,
      maxMemoryMb: maxMemoryMb,
      preset: instance.jvmPreset,
    );

    return JvmPlan(
      command: command,
      maxMemoryMb: maxMemoryMb,
      autoMemory: instance.memoryAuto,
      preset: instance.jvmPreset,
      memoryInfo: info,
      applied: command != base,
    );
  }

  /// 把内存参数与预设参数注入 [command]。
  ///
  /// 命令首项不是 java 时原样返回（无法安全注入）；[maxMemoryMb] 为 null
  /// 时只注入预设参数，不动命令里已有的内存参数。
  static String inject(
    String command, {
    required int? maxMemoryMb,
    required JvmPreset preset,
  }) {
    final split = JavaLauncher.splitFirstToken(command);
    if (split == null) return command;

    final executable = split.token;
    if (!_javaNames.contains(
      JavaLauncher.basenameOf(executable).toLowerCase(),
    )) {
      return command;
    }

    var rest = split.rest;
    final injected = <String>[];
    if (maxMemoryMb != null) {
      rest = _stripMemoryFlags(rest);
      injected.addAll(['-Xms${maxMemoryMb}M', '-Xmx${maxMemoryMb}M']);
    }

    final existing = _tokens(command);
    for (final flag in preset.flags) {
      if (!existing.contains(flag)) injected.add(flag);
    }
    if (injected.isEmpty) return command;

    final head = JavaLauncher.quoteExecutable(executable);
    final tail = rest.trim();
    return tail.isEmpty
        ? '$head ${injected.join(' ')}'
        : '$head ${injected.join(' ')} $tail';
  }

  /// 删除命令行中的所有 `-Xms…` / `-Xmx…` 参数。
  static String _stripMemoryFlags(String s) {
    final stripped = s.replaceAll(RegExp(r'\s+-Xm[sx]\S*'), '');
    // 命令以 -Xms 开头（首个 token 不是 java）时上面的正则覆盖不到，
    // 这里再处理一次行首情形。
    return stripped.replaceFirst(RegExp(r'^\s*-Xm[sx]\S*'), '');
  }

  /// 粗略切分命令行 token（用于判断某个参数是否已存在）。
  ///
  /// 只做空白切分，不解析引号：参数存在性判断对 `-Dkey="a b"` 这类写法
  /// 保守失败（判定为不存在 → 追加一次），不会造成语法错误。
  static Set<String> _tokens(String command) =>
      command.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
}
