// 实例级 Java 解析（启动链路的唯一决策点）
//
// 两档语义见 [InstanceJavaMode]：
//   auto   —— 不覆盖启动命令，执行命令首项（通常是 PATH 上的 java）
//   custom —— 使用实例从已检测列表指定的可执行文件；路径失效时启动报错
//
// 只在启动命令首项确为 java 可执行文件时才替换：`./start.sh`、`bash run.sh`
// 这类命令无法靠改首项换 Java，静默替换会直接破坏启动，因此一律不接管。
//
// 替换实现只改动首个 token，其后参数原样保留（不重新拼接），
// 避免破坏含空格或引号的 JVM 参数。

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/server_instance.dart';

/// 实例指定的 Java 不存在时抛出（不静默回退，避免「改了却没生效」）。
class JavaBinaryMissingException implements Exception {
  JavaBinaryMissingException({required this.path, required this.instanceName});

  /// 失效的可执行文件路径。
  final String path;

  /// 实例名称（用于提示文案）。
  final String instanceName;

  @override
  String toString() => '实例「$instanceName」指定的 Java 不存在：$path';
}

/// Java 解析结果。
class JavaResolution {
  const JavaResolution({required this.executable, required this.mode});

  /// 实际使用的 java 可执行文件路径。
  final String executable;

  /// 解析所依据的模式（[InstanceJavaMode.custom]）。
  final InstanceJavaMode mode;
}

/// 把实例的 Java 选择解析为可执行文件，并改写启动命令。
class JavaLauncher {
  const JavaLauncher._();

  /// 被视为 java 可执行文件的名字（小写，含扩展名）。
  static const Set<String> _javaExecutableNames = {
    'java',
    'java.exe',
    'javaw',
    'javaw.exe',
  };

  /// 启动命令首项是否为 java 可执行文件。
  ///
  /// 仅识别文件名（允许带路径与引号），不解析 PATH，也不执行进程。
  static bool usesJavaExecutable(String command) {
    final token = splitFirstToken(command)?.token;
    if (token == null) return false;
    final name = p.basename(token.trim()).toLowerCase();
    return _javaExecutableNames.contains(name);
  }

  /// 解析实例实际应使用的 Java。
  ///
  /// 返回 null 表示不覆盖启动命令（跟随命令、命令首项不是 java、
  /// 或未指定可执行文件）。
  ///
  /// [InstanceJavaMode.custom] 下路径不存在时抛
  /// [JavaBinaryMissingException]。
  static Future<JavaResolution?> resolveFor(ServerInstance instance) async {
    if (instance.javaMode == InstanceJavaMode.auto) return null;
    if (!usesJavaExecutable(instance.startCommand)) return null;

    final path = instance.javaBinary?.trim();
    if (path == null || path.isEmpty) return null;

    if (!File(path).existsSync()) {
      throw JavaBinaryMissingException(path: path, instanceName: instance.name);
    }
    return JavaResolution(executable: path, mode: instance.javaMode);
  }

  /// 把启动命令的首个 token 替换为 [executable]，其余部分原样保留。
  ///
  /// 首项含空格时加双引号（Windows 下的 `C:\Program Files\...`）。
  static String replaceExecutable(String command, String executable) {
    final split = splitFirstToken(command);
    if (split == null) return command;
    return '${quoteExecutable(executable)}${split.rest}';
  }

  /// 需要时用双引号包裹路径。
  static String quoteExecutable(String path) {
    if (path.contains(' ') || path.contains('\t')) return '"$path"';
    return path;
  }

  /// 切出命令的首个 token 与剩余原文（剩余部分保留原始空白）。
  ///
  /// 支持单/双引号包裹的路径；未闭合引号时按到行尾处理。
  static ({String token, String rest})? splitFirstToken(String command) {
    final trimmed = command.trimLeft();
    if (trimmed.isEmpty) return null;

    final quote = trimmed[0];
    if (quote == '"' || quote == "'") {
      final end = trimmed.indexOf(quote, 1);
      if (end < 0) return (token: trimmed.substring(1), rest: '');
      return (
        token: trimmed.substring(1, end),
        rest: trimmed.substring(end + 1),
      );
    }

    var end = trimmed.length;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      if (c == ' ' || c == '\t') {
        end = i;
        break;
      }
    }
    return (token: trimmed.substring(0, end), rest: trimmed.substring(end));
  }
}
