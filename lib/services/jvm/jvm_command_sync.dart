// 启动命令与 JVM 设置的同步
//
// 与「启动时注入」（[JvmArgs]）分工：
//   - 本文件负责把**用户能看见的**设置写进启动命令文本：
//       预设参数（无 / Aikar's）→ 命令中随之增删
//       手动内存           → 命令中写入 -Xms/-Xmx
//       自动内存           → 从命令中移除 -Xms/-Xmx（启动时再按可用内存注入）
//   - [JvmArgs] 负责启动时补上自动内存的 `-Xms/-Xmx`，并对预设做去重兜底。
//
// 这样「高级设置」里的启动命令始终是真实执行的参数集（自动内存除外，
// 它每次启动都要重算，写死会让自动分配变成一次性快照）。

import '../../models/jvm_preset.dart';
import '../java/java_launcher.dart';

/// 启动命令与 JVM 设置的双向同步。
class JvmCommandSync {
  const JvmCommandSync._();

  /// 所有预设的参数全集（用于切换预设时先清掉旧预设）。
  static List<String> get _allPresetFlags => [
    for (final preset in JvmPreset.values) ...preset.flags,
  ];

  /// 按 [preset] / [memoryAuto] / [memoryMb] 重写 [command]。
  ///
  /// 约定：
  /// - 命令首项不是 java 时原样返回（无法安全插入 JVM 参数）；
  /// - 自动内存：移除命令里的 -Xms/-Xmx；
  /// - 手动内存且 [memoryMb] 有值：写入 `-Xms{mb}M -Xmx{mb}M`；
  /// - 手动内存且 [memoryMb] 为 null：保留命令中原有内存参数（用户手写）。
  static String apply(
    String command, {
    required JvmPreset preset,
    required bool memoryAuto,
    int? memoryMb,
  }) {
    final split = JavaLauncher.splitFirstToken(command);
    if (split == null) return command;
    if (!JavaLauncher.usesJavaExecutable(command)) return command;

    final executable = split.token;
    var rest = split.rest;

    // 1. 移除命令中所有已知预设参数，避免切换预设后残留旧参数。
    for (final flag in _allPresetFlags) {
      rest = _removeToken(rest, flag);
    }

    // 2. 内存参数：自动模式移除；手动模式按已选值重写（写入动作在下方组装）。
    if (memoryAuto || memoryMb != null) {
      rest = _stripMemoryFlags(rest);
    }

    // 3. 组装：手动内存 + 当前预设 + 剩余原始参数（参数只保留一份）。
    final head = JavaLauncher.quoteExecutable(executable);
    final parts = <String>[
      if (!memoryAuto && memoryMb != null) ...[
        '-Xms${memoryMb}M',
        '-Xmx${memoryMb}M',
      ],
      ...preset.flags,
    ];
    final tail = rest.trim();
    return [head, ...parts, if (tail.isNotEmpty) tail].join(' ');
  }

  /// 从字符串中移除一个完整 token（前后需为空白或边界）。
  static String _removeToken(String source, String token) {
    final pattern = RegExp('(^|\\s)${RegExp.escape(token)}(?=\\s|\$)');
    return source.replaceAll(pattern, '');
  }

  /// 删除 `-Xms…` / `-Xmx…` 参数。
  static String _stripMemoryFlags(String source) {
    final stripped = source.replaceAll(RegExp(r'\s*-Xm[sx]\S*'), '');
    return stripped.replaceFirst(RegExp(r'^\s*-Xm[sx]\S*'), '');
  }
}
