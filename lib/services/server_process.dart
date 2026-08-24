// 服务器进程管理服务
// 为单个 ServerInstance 提供进程生命周期管理：启动、停止、强制终止、重启，
// 以及日志输出流。每个运行中的实例对应一个管理器实例。
//
// 启动方式（按可用性降级）：
// 1. Rust 托管启动（xmc_logger::spawn_with_log）：stdout/stderr 直接重定向到
//    日志文件（<应用文档目录>/logs/<id>.log），stdin 保留管道。启动器退出/崩溃后
//    服务器仍可持续写日志，重启启动器后可按 PID 接管并继续尾随该文件（终端接管）。
// 2. dart:io Process.start 管道启动（旧 DLL 回退）：stdout/stderr 解码后转写
//    同一日志文件，控制台经日志尾随器统一读取。
//
// 进程退出检测统一为 PID 存活轮询（ProcessRegistry），两条路径行为一致。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/server_instance.dart';
import 'log_persistence.dart';
import 'log_tailer.dart';
import 'logger_ffi.dart';
import 'process_registry.dart';

/// 服务器进程管理器。
///
/// 负责单个 [ServerInstance] 的进程生命周期管理：
/// - [start]：以 [ServerInstance.rootPath] 为工作目录启动进程（输出重定向到日志文件）；
/// - [attach]：接管一个由上次启动器会话遗留、仍在运行的进程（按 PID）；
/// - [sendCommand]：向进程标准输入发送命令（接管进程的 stdin 已断开，不可用）；
/// - [stop]：向标准输入写入 `stop` 实现优雅关闭；
/// - [forceStop]：强制终止进程；
/// - [restart]：停止后重新启动。
///
/// 通过 [logs] 获取日志流：每个监听者先收到日志文件的历史尾部回放，
/// 再收到实时行（原始输出，保留 ANSI 转义序列供控制台彩色渲染）；
/// 通过 [onExit] 获取进程退出码。
class ServerProcessManager {
  /// 被管理的服务器实例。
  final ServerInstance instance;

  /// dart:io 回退路径的进程对象。
  Process? _process;

  /// dart:io 回退路径的标准输入。
  IOSink? _stdin;

  /// 回退路径下向日志文件的转写流。
  IOSink? _logSink;

  /// 当前托管的服务器进程 PID（Rust 启动 / 回退 / 接管均适用）。
  int? _pid;

  /// 进程镜像名（如 `java.exe`），供存活检测防 PID 复用。
  String? _imageName;

  /// 是否为「接管」的外部进程（非本次启动器会话启动，stdin 不可用）。
  bool _attached = false;

  /// 日志广播控制器：管理器创建即存在，订阅者可跨启动阶段接入
  /// （启动中订阅也能收到后续日志），由日志文件尾随器桥接喂入。
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// 日志文件尾随器（控制台数据源）。
  LogFileTailer? _tailer;

  /// 尾随器 → 日志广播的桥接订阅。
  StreamSubscription<String>? _tailerSubscription;

  /// 尾随器是否正在初始化（防并发重复创建）。
  bool _tailerStarting = false;

  /// 进程退出完成器；在 [start]/[attach] 时创建，进程退出时完成。
  Completer<int>? _exitCompleter;

  /// PID 存活轮询定时器。
  Timer? _livenessTimer;

  bool _disposed = false;

  /// Rust 进程托管 FFI 是否可用（旧 DLL 缺失时回退管道启动）。
  static bool get _nativeSpawnAvailable => LoggerNative.instance.spawnAvailable;

  /// 创建一个进程管理器。
  ///
  /// [instance] 为该管理器所托管的服务器实例。
  ServerProcessManager({required this.instance});

  /// 进程是否正在运行（已启动且尚未退出）。
  bool get isRunning =>
      _exitCompleter != null && !_exitCompleter!.isCompleted;

  /// 当前托管进程的 PID；未运行时为 null。
  int? get pid => _pid;

  /// 进程镜像名（如 `java.exe`）；未运行时为 null。
  String? get imageName => _imageName;

  /// 是否为接管的外部进程。
  bool get isAttached => _attached;

  /// 是否可向进程发送指令（接管进程的 stdin 已随上次会话断开）。
  bool get canSendCommands => isRunning && !_attached;

  /// 日志流（稳定广播流）。
  ///
  /// 管理器创建即存在：即使在进程启动完成前订阅（如「启动中」状态），
  /// 也能收到日志。尾随器就绪时会先推入日志文件的历史尾部，
  /// 之后实时推送（原始输出，保留 ANSI 转义序列供控制台彩色渲染）。
  Stream<String> get logs => _logController.stream;

  /// 确保日志文件尾随器就绪并桥接到日志广播。
  ///
  /// 首次调用时创建尾随器（从文件当前末尾开始实时尾随）并桥接其流；
  /// 历史内容由 UI 层在订阅时自行回放（见 InstanceDetailScreen._seedHistory）。
  Future<void> _ensureTailer() async {
    if (_tailer != null || _tailerStarting) return;
    _tailerStarting = true;
    try {
      final logPath = await LogPersistence.logFilePath(instance.id);
      final tailer = LogFileTailer(logPath);
      await tailer.start();
      if (_disposed || _logController.isClosed) {
        tailer.dispose();
        return;
      }
      _tailer = tailer;
      _tailerSubscription = tailer.stream.listen((line) {
        if (!_logController.isClosed) {
          _logController.add(line);
        }
      });
    } catch (_) {
      // 日志文件暂不可用时保持空流，进程本身不受影响。
    } finally {
      _tailerStarting = false;
    }
  }

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

  /// 启动服务器进程。
  ///
  /// 优先走 Rust 托管启动（输出直写日志文件）；FFI 不可用时回退
  /// `Process.start` 管道启动并将输出转写同一日志文件。
  /// 方法在进程启动后即返回（不等待退出）。
  ///
  /// 若进程已在运行则抛出 [StateError]；若可执行文件不存在则由底层抛出。
  Future<void> start() async {
    if (isRunning) {
      throw StateError('服务器实例 ${instance.name} 已在运行');
    }

    // 完成器先行创建：进程可能瞬间退出（如启动参数错误），
    // 避免退出回调先于完成器触发导致 onExit 永久悬挂。
    _exitCompleter = Completer<int>();

    try {
      final parts = _parseCommand(instance.startCommand);
      final executable = parts.first;
      final args = parts.skip(1).toList();
      final logPath = await LogPersistence.logFilePath(instance.id);

      await _ensureTailer();

      if (_nativeSpawnAvailable) {
        await _startNativeRedirect(executable, logPath);
      } else {
        await _startPipeFallback(executable, args);
      }
    } catch (e) {
      _completeExit(-1);
      rethrow;
    }

    _startLivenessPolling();
    // 立即补查一轮，快速回收瞬间退出的进程。
    unawaited(_checkAlive());
  }

  /// Rust 托管启动：stdout/stderr 直写日志文件，stdin 保留管道。
  Future<void> _startNativeRedirect(String executable, String logPath) async {
    final spawnedPid = LoggerNative.instance.spawnProcess(
      instance.startCommand,
      instance.rootPath,
      logPath,
    );
    if (spawnedPid <= 0) {
      final error = LoggerNative.instance.getLastErrorMessage() ?? '未知错误';
      throw StateError('启动失败：$error');
    }
    _pid = spawnedPid;
    _imageName = p.basename(executable);
  }

  /// dart:io 管道启动回退：输出解码后转写日志文件（尾随器统一读取）。
  Future<void> _startPipeFallback(
    String executable,
    List<String> args,
  ) async {
    // 启动进程，工作目录设为实例根目录；不做 shell 引号处理。
    final process = await Process.start(
      executable,
      args,
      workingDirectory: instance.rootPath,
    );

    _process = process;
    _stdin = process.stdin;
    _pid = process.pid;
    _imageName = p.basename(executable);

    final logSink = File(
      await LogPersistence.logFilePath(instance.id),
    ).openWrite(mode: FileMode.append);
    _logSink = logSink;

    void tee(Stream<List<int>> raw) {
      raw
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            logSink.writeln(line);
            // 逐行冲刷，避免 IOSink 缓冲导致控制台/日志文件滞后。
            unawaited(logSink.flush());
          });
    }

    tee(process.stdout);
    tee(process.stderr);

    // 退出码即时可用（存活轮询作为兜底）。
    unawaited(
      process.exitCode.then((code) {
        _completeExit(code);
      }).catchError((_) {
        _completeExit(-1);
      }),
    );
  }

  /// 接管一个仍在运行的外部进程（上次启动器会话遗留）。
  ///
  /// 接管后：状态视为运行中、日志继续尾随该实例的日志文件、
  /// 支持强制停止；由于 stdin 已随上次会话断开，无法发送指令。
  Future<void> attach(int existingPid) async {
    if (isRunning) {
      throw StateError('服务器实例 ${instance.name} 已在运行');
    }
    _exitCompleter = Completer<int>();
    try {
      await _ensureTailer();
    } catch (e) {
      _completeExit(-1);
      rethrow;
    }

    _attached = true;
    _pid = existingPid;
    _startLivenessPolling();
    // 立即补查一轮：接管前进程可能已退出。
    unawaited(_checkAlive());
  }

  /// 启动 PID 存活轮询（每 2 秒），进程退出时完成退出完成器。
  void _startLivenessPolling() {
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_checkAlive());
    });
  }

  Future<void> _checkAlive() async {
    final currentPid = _pid;
    if (currentPid == null) return;
    final alive = await ProcessRegistry.isAlive(
      currentPid,
      imageName: _imageName,
    );
    if (alive) return;
    if (_exitCompleter == null || _exitCompleter!.isCompleted) return;

    var code = -1;
    // Rust 托管的子进程先回收句柄取得退出码（接管/回退进程返回 -1/-2）。
    if (_nativeSpawnAvailable && !_attached) {
      final reaped = LoggerNative.instance.spawnTryReap(currentPid);
      if (reaped == -2) return; // 竞态：再等下一轮
      if (reaped != -1) {
        code = reaped;
      }
    }
    _completeExit(code);
  }

  /// 进程退出后的清理：停止轮询、释放进程/stdin 引用与转写流。
  ///
  /// 注意：不重置 [_exitCompleter]，以便 [onExit] 在退出后仍可查询到退出码。
  void _completeExit(int code) {
    if (_exitCompleter == null || _exitCompleter!.isCompleted) return;
    _livenessTimer?.cancel();
    _livenessTimer = null;

    final logSink = _logSink;
    _logSink = null;
    if (logSink != null) {
      unawaited(
        logSink.flush().then((_) => logSink.close()).catchError((_) {
          return logSink.close();
        }),
      );
    }

    _process = null;
    _stdin = null;
    _pid = null;
    _imageName = null;
    _attached = false;
    _exitCompleter!.complete(code);
  }

  /// 向服务器标准输入发送一行（不添加前导 `/`）。
  ///
  /// 接管的外部进程 stdin 不可用，为空操作。
  void _writeStdin(String line) {
    if (!isRunning || _attached) return;
    final currentPid = _pid;
    if (_nativeSpawnAvailable && currentPid != null) {
      LoggerNative.instance.spawnSendStdin(currentPid, line);
      return;
    }
    _stdin?.writeln(line);
  }

  /// 向服务器标准输入发送命令。
  ///
  /// 写入 `command\n`，不添加前导 `/`。若进程未运行或为接管进程则不做任何操作。
  void sendCommand(String command) {
    _writeStdin(command);
  }

  /// 优雅停止服务器：向标准输入写入 `stop\n`。
  ///
  /// 仅发送停止指令，不强制 kill 进程，依赖服务器自行处理。
  /// 接管的外部进程 stdin 不可用，为空操作（UI 会直接提供强制停止）。
  Future<void> stop() async {
    _writeStdin('stop');
  }

  /// 强制终止服务器进程。
  ///
  /// 优先经 Rust 托管句柄终止；接管进程（非本会话启动）直接用 killPid。
  /// Windows 上等价于 TerminateProcess 的硬终止。
  Future<void> forceStop() async {
    final currentPid = _pid;
    if (currentPid != null) {
      if (_nativeSpawnAvailable && !_attached) {
        LoggerNative.instance.spawnKill(currentPid);
      } else {
        Process.killPid(currentPid, ProcessSignal.sigkill);
      }
      return;
    }
    _process?.kill(ProcessSignal.sigkill);
  }

  /// 重启服务器：先 [stop]，等待进程退出（[onExit]）后再 [start]。
  Future<void> restart() async {
    await stop();
    await onExit;
    await start();
  }

  /// 释放日志流资源与轮询定时器。
  ///
  /// 由上层状态层在销毁该管理器时调用；不会终止正在运行的进程。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _livenessTimer?.cancel();
    _livenessTimer = null;
    unawaited(_tailerSubscription?.cancel());
    _tailerSubscription = null;
    _tailer?.dispose();
    _tailer = null;
    _logController.close();
    final logSink = _logSink;
    _logSink = null;
    unawaited(logSink?.close());
  }
}
