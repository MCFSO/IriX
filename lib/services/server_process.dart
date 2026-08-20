// 服务器进程管理服务
// 为单个 ServerInstance 提供进程生命周期管理：启动、停止、强制终止、重启，
// 以及标准输出/错误流的合并日志流。每个运行中的实例对应一个管理器实例。
// 本文件仅负责进程层操作，不涉及 UI、状态管理或持久化（dart:io 桌面端可用）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/server_instance.dart';

/// 服务器进程管理器。
///
/// 负责单个 [ServerInstance] 的进程生命周期管理：
/// - [start]：以 [ServerInstance.rootPath] 为工作目录启动进程；
/// - [sendCommand]：向进程标准输入发送命令；
/// - [stop]：向标准输入写入 `stop` 实现优雅关闭；
/// - [forceStop]：强制终止进程；
/// - [restart]：停止后重新启动。
///
/// 通过 [logs] 获取合并 stdout/stderr 的原始日志流（不含 IriX 添加的
/// 时间戳前缀，保留 ANSI 转义序列供控制台彩色渲染）；
/// 通过 [onExit] 获取进程退出码。
class ServerProcessManager {
  /// 被管理的服务器实例。
  final ServerInstance instance;

  /// 当前关联的进程，未启动或已退出时为 null。
  Process? _process;

  /// 进程标准输入缓存，未启动或已退出时为 null。
  IOSink? _stdin;

  /// 合并 stdout/stderr 的日志流控制器（广播，允许多个监听者）。
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// 进程退出完成器；在 [start] 时创建，进程退出时完成。
  Completer<int>? _exitCompleter;

  bool _disposed = false;

  /// 创建一个进程管理器。
  ///
  /// [instance] 为该管理器所托管的服务器实例。
  ServerProcessManager({required this.instance});

  /// 进程是否正在运行（已启动且尚未退出）。
  bool get isRunning =>
      _process != null &&
      _exitCompleter != null &&
      !_exitCompleter!.isCompleted;

  /// 合并 stdout 与 stderr 的日志流。
  ///
  /// 原始输出，无额外前缀。
  Stream<String> get logs => _logController.stream;

  /// 进程退出 Future，完成时携带退出码。
  ///
  /// 若进程尚未启动，则返回一个已完成的 Future（退出码 0），避免调用方永久挂起。
  Future<int> get onExit => _exitCompleter?.future ?? Future<int>.value(0);

  /// 解析启动命令字符串为可执行文件名与参数列表。
  ///
  /// 支持双引号包裹含空格的路径，例如：
  /// `"C:\Program Files\Java\bin\java.exe" -Xmx2G -jar server.jar nogui`
  /// 会被正确拆分为 4 个 token。未配对的引号按普通字符处理。
  List<String> _parseCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      throw StateError('启动命令为空，无法启动实例 ${instance.name}');
    }

    final tokens = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if ((char == ' ' || char == '\t') && !inQuotes) {
        if (current.isNotEmpty) {
          tokens.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) {
      tokens.add(current.toString());
    }

    return tokens;
  }

  /// 将一行日志推入 [logs] 流（控制器已关闭时忽略）。
  ///
  /// 原样推送服务器输出（不添加时间戳前缀——服务器自身的日志已含时间戳；
  /// 保留 ANSI 转义序列，由控制台渲染层解析为彩色文本）。
  void _emitLog(String line) {
    if (!_logController.isClosed) {
      _logController.add(line);
    }
  }

  /// 进程退出后的清理：释放进程与 stdin 引用。
  ///
  /// 注意：不重置 [_exitCompleter]，以便 [onExit] 在退出后仍可查询到退出码。
  void _cleanup() {
    _stdin = null;
    _process = null;
  }

  /// 启动服务器进程。
  ///
  /// 解析 [ServerInstance.startCommand]，以 [ServerInstance.rootPath] 为工作目录
  /// 通过 `Process.start` 启动进程。方法在进程启动后即返回（不等待退出）。
  ///
  /// 若进程已在运行则抛出 [StateError]；若可执行文件不存在则由 `Process.start` 抛出。
  Future<void> start() async {
    if (isRunning) {
      throw StateError('服务器实例 ${instance.name} 已在运行');
    }

    final parts = _parseCommand(instance.startCommand);
    final executable = parts.first;
    final args = parts.skip(1).toList();

    // 启动进程，工作目录设为实例根目录；不做 shell 引号处理。
    final process = await Process.start(
      executable,
      args,
      workingDirectory: instance.rootPath,
    );

    _process = process;
    _stdin = process.stdin;
    _exitCompleter = Completer<int>();

    // 订阅 stdout 与 stderr，统一解码并按行推入日志流。
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_emitLog);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_emitLog);

    // 监听进程退出，完成退出完成器并清理引用。
    unawaited(
      process.exitCode.then((code) {
        _exitCompleter?.complete(code);
        _cleanup();
      }),
    );
  }

  /// 向服务器标准输入发送命令。
  ///
  /// 写入 `command\n`，不添加前导 `/`。若进程未运行则不做任何操作。
  void sendCommand(String command) {
    final sink = _stdin;
    if (sink == null || !isRunning) {
      return;
    }
    sink.writeln(command);
  }

  /// 优雅停止服务器：向标准输入写入 `stop\n`。
  ///
  /// 仅发送停止指令，不强制 kill 进程，依赖服务器自行处理。
  Future<void> stop() async {
    final sink = _stdin;
    if (sink == null || !isRunning) {
      return;
    }
    sink.writeln('stop');
  }

  /// 强制终止服务器进程。
  ///
  /// 调用进程的 `kill` 方法发送强制终止信号
  /// （Windows 上等价于 TerminateProcess 的硬终止）。
  Future<void> forceStop() async {
    _process?.kill(ProcessSignal.sigkill);
  }

  /// 重启服务器：先 [stop]，等待进程退出（[onExit]）后再 [start]。
  Future<void> restart() async {
    await stop();
    await onExit;
    await start();
  }

  /// 释放日志流资源。
  ///
  /// 由上层状态层在销毁该管理器时调用；不会终止正在运行的进程。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _logController.close();
  }
}
