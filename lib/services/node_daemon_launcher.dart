// 本地节点守护进程启动器
// 尝试定位并启动项目根目录 node/ 下构建的 Go 守护进程（irix-node）。
// 仅用于"本地"（Node 类型、127.0.0.1 地址）节点。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 本地节点守护进程启动结果。
class NodeDaemonLaunchResult {
  final bool launched;
  final String message;

  const NodeDaemonLaunchResult(this.launched, this.message);
}

/// 本地 Go 守护进程启动器。
class NodeDaemonLauncher {
  /// 当前启动的守护进程（防止重复启动）。
  static Process? _process;

  /// 守护进程是否已退出。
  static bool _exited = true;

  /// 是否已尝试启动（避免重复搜索失败）。
  static bool _attempted = false;

  /// 停止已启动的守护进程（应用退出前调用）。
  static Future<void> stop() async {
    final proc = _process;
    _process = null;
    _attempted = false;
    _exited = true;
    if (proc != null && !_exited) {
      try {
        proc.kill();
      } catch (_) {}
    }
  }

  /// 守护进程是否正在运行（本进程启动的）。
  static bool get isRunning => _process != null && !_exited;

  /// 尝试定位并启动守护进程。
  ///
  /// [port] 节点地址中的端口；[address] 完整地址。
  /// 若已运行或找不到二进制文件，返回对应的提示消息。
  static Future<NodeDaemonLaunchResult> ensureRunning({
    required String address,
    required int port,
  }) async {
    if (isRunning) {
      return const NodeDaemonLaunchResult(true, '本地节点守护进程已在运行');
    }
    final binary = _locateBinary();
    if (binary == null) {
      return NodeDaemonLaunchResult(
        false,
        '未找到 irix-node 可执行文件。\n请先在项目根目录构建：\n'
        'cd node && go build -o irix-node .\n'
        '然后将 irix-node(.exe) 放到应用目录或项目 node/ 目录，'
        '或手动运行：irix-node -port $port',
      );
    }
    if (_attempted) {
      return NodeDaemonLaunchResult(
        false,
        '守护进程启动失败，请检查端口 $port 是否被占用，'
        '或手动运行：irix-node -port $port',
      );
    }
    _attempted = true;
    try {
      _exited = false;
      _process = await Process.start(binary, [
        '-port',
        '$port',
        '-data',
        _dataDir(),
      ], mode: ProcessStartMode.normal);
      _process!.stdout.listen((_) {});
      _process!.stderr.listen((_) {});
      _process!.exitCode.then((_) {
        _exited = true;
        _process = null;
        _attempted = false;
      });
      return NodeDaemonLaunchResult(true, '已启动本地节点守护进程（端口 $port）');
    } catch (e) {
      _exited = true;
      debugPrint('启动本地节点失败: $e');
      return NodeDaemonLaunchResult(false, '启动失败: $e');
    }
  }

  /// 守护进程数据目录（应用文档目录下，避免污染工作目录）。
  static String _dataDir() {
    final dir = Directory(
      Platform.environment['APPDATA'] != null
          ? '${Platform.environment['APPDATA']}\\irix-node'
          : '.irix-node',
    );
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return dir.path;
  }

  /// 在常见位置查找 irix-node 可执行文件。
  static String? _locateBinary() {
    final name = Platform.isWindows ? 'irix-node.exe' : 'irix-node';
    final cwd = Directory.current.path;
    final exeDir = p.dirname(Platform.resolvedExecutable);

    final candidates = <String>[
      // 应用同目录 / 其 node 子目录
      p.join(exeDir, name),
      p.join(exeDir, 'node', name),
      // 开发目录：项目根 / node 子目录 / 构建产物
      p.join(cwd, name),
      p.join(cwd, 'node', name),
      p.join(cwd, 'node', 'bin', name),
      p.join(cwd, 'build', 'node', name),
    ];
    for (final candidate in candidates) {
      try {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }
}
