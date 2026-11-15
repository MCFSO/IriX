// 陶瓦联机（Terracotta）联机核心进程的启动、端口握手与日志泵。
//
// 对应 HMCL `TerracottaManager#launch` + `provider.GeneralProvider`：
//   terracotta-<版本>-<平台>[.exe] --hmcl <端口文件路径>
// 联机核心启动后会把本地控制端口写入该文件（JSON: `{"port": 12345}`），
// 之后所有操作都通过 `http://127.0.0.1:<port>/...` 进行。
//
// 这里把「进程」抽象成 [TerracottaChildProcess]、把「启动器」抽象成
// [TerracottaLauncher]，便于测试注入假实现（假进程 + 固定端口）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../dev_log.dart';

/// 启动联机核心失败。
class TerracottaLaunchException implements Exception {
  TerracottaLaunchException(this.message);

  final String message;

  @override
  String toString() => 'TerracottaLaunchException: $message';
}

/// 联机核心子进程抽象。
abstract class TerracottaChildProcess {
  /// 合并后的 stdout/stderr 文本流（逐行）。
  Stream<String> get logs;

  /// 进程是否仍在运行。
  bool get isRunning;

  /// 退出码（未退出时为 null）。
  int? get exitCode;

  /// 结束进程。
  Future<void> kill();
}

/// 启动结果：控制端口 + 子进程句柄。
class TerracottaLaunchResult {
  const TerracottaLaunchResult({required this.port, required this.process});

  final int port;
  final TerracottaChildProcess process;
}

/// 启动器抽象（测试可注入假实现）。
abstract class TerracottaLauncher {
  /// 启动联机核心并等待端口文件出现。
  ///
  /// [executable] 联机核心可执行文件绝对路径；
  /// [workingDir] 工作目录（联机核心所在目录，Windows 靠它找 VCRUNTIME140.DLL）；
  /// [portFilePath] 端口文件路径（`--hmcl` 参数）。
  Future<TerracottaLaunchResult> launch({
    required String executable,
    required String workingDir,
    required String portFilePath,
  }) async {
    throw UnimplementedError('launch 未实现');
  }
}

/// 真实实现：`Process.start` + 端口文件轮询。
class SystemTerracottaLauncher extends TerracottaLauncher {
  SystemTerracottaLauncher({
    this.handshakeTimeout = const Duration(seconds: 60),
    this.exitGrace = const Duration(seconds: 10),
    this.pollInterval = const Duration(milliseconds: 100),
  });

  /// 等待端口文件的最长时间。
  final Duration handshakeTimeout;

  /// 进程退出后继续等待端口文件的宽限时间（对齐 HMCL 的 10s）。
  final Duration exitGrace;

  /// 轮询间隔。
  final Duration pollInterval;

  @override
  Future<TerracottaLaunchResult> launch({
    required String executable,
    required String workingDir,
    required String portFilePath,
  }) async {
    if (!File(executable).existsSync()) {
      throw TerracottaLaunchException('联机核心不存在: $executable');
    }
    // 上一次异常退出残留的端口文件会让握手读到过期端口。
    final stale = File(portFilePath);
    if (stale.existsSync()) {
      try {
        stale.deleteSync();
      } catch (_) {}
    }

    DevLog.instance.devInfo(
      'terracotta',
      '启动联机核心: $executable --hmcl $portFilePath',
    );

    final Process process;
    try {
      process = await Process.start(executable, [
        '--hmcl',
        portFilePath,
      ], workingDirectory: workingDir);
    } catch (e) {
      throw TerracottaLaunchException('启动联机核心失败: $e');
    }

    final handle = _SystemTerracottaChildProcess(process);

    final started = DateTime.now();
    DateTime? exitSeenAt;
    while (true) {
      final file = File(portFilePath);
      if (file.existsSync()) {
        try {
          final raw = jsonDecode(await file.readAsString());
          if (raw is Map && raw['port'] is num) {
            final port = (raw['port'] as num).toInt();
            if (port > 0 && port < 65536) {
              DevLog.instance.devInfo('terracotta', '联机核心控制端口: $port');
              return TerracottaLaunchResult(port: port, process: handle);
            }
          }
          DevLog.instance.devWarn('terracotta', '端口文件内容非法: $raw');
        } catch (e) {
          // 文件可能正被写入，下一轮再读。
          DevLog.instance.devWarn('terracotta', '读取端口文件失败（稍后重试）: $e');
        }
      }

      if (!handle.isRunning) {
        exitSeenAt ??= DateTime.now();
        if (DateTime.now().difference(exitSeenAt) >= exitGrace) {
          await handle.kill();
          throw TerracottaLaunchException(
            '联机核心已退出（退出码 ${handle.exitCode}），未能取得控制端口',
          );
        }
      }

      if (DateTime.now().difference(started) >= handshakeTimeout) {
        await handle.kill();
        throw TerracottaLaunchException('等待联机核心控制端口超时');
      }

      await Future<void>.delayed(pollInterval);
    }
  }
}

/// `dart:io` 进程的薄封装：把 stdout/stderr 合并成逐行文本流。
class _SystemTerracottaChildProcess implements TerracottaChildProcess {
  _SystemTerracottaChildProcess(this._process) {
    _subs.add(
      _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_emit),
    );
    _subs.add(
      _process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_emit),
    );
    unawaited(
      _process.exitCode.then((code) {
        _exitCode = code;
        _emit('[联机核心已退出，退出码 $code]');
        _logController.close();
      }),
    );
  }

  final Process _process;
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  final List<StreamSubscription<String>> _subs = [];
  int? _exitCode;

  void _emit(String line) {
    if (line.isEmpty) return;
    DevLog.instance.devInfo('terracotta', line);
    if (!_logController.isClosed) _logController.add(line);
  }

  @override
  Stream<String> get logs => _logController.stream;

  @override
  bool get isRunning => _exitCode == null;

  @override
  int? get exitCode => _exitCode;

  @override
  Future<void> kill() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    try {
      _process.kill();
    } catch (_) {}
    try {
      if (!_logController.isClosed) await _logController.close();
    } catch (_) {}
  }
}

/// 便于拼接「运行期临时目录」里的端口文件路径。
String terracottaPortFilePath(String tempDir) => p.join(tempDir, 'http');
