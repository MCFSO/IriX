// 陶瓦联机（Terracotta）全局管理器。
//
// 移植自 HMCL `TerracottaManager`：把「安装联机核心 → 启动子进程 → 轮询
// `/state` → 房主/房客操作」串成一条状态机，供界面订阅。
//
// 关键设计（与 HMCL 一致，便于对照排查）：
// - 联机核心进程是**应用级全局**的：整个应用只跑一个，页面切换不会重启它；
// - 后台守护线程按「页面是否可见」在 500ms / 15s 之间切换轮询间隔；
// - 状态快照带自增 `index`，只有更新的快照才会覆盖当前状态（防止乱序回退）；
// - 进程日志落开发者日志，并在内存里保留最近若干行，导出日志时一起打包。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../dev_log.dart';
import 'terracotta_bundle.dart';
import 'terracotta_control_api.dart';
import 'terracotta_launcher.dart';
import 'terracotta_metadata.dart';
import 'terracotta_state.dart';

/// 本地安装包的安装结果。
enum TerracottaInstallResult {
  /// 安装完成并已启动联机核心。
  ok,

  /// 文件名不是官方包名（用户选错了文件）。
  invalidPackage,

  /// 解包 / 摘要校验失败，具体原因见 [TerracottaManager.lastActionError]。
  failed,
}

/// 房客加入房间的结果。
enum TerracottaJoinResult {
  /// 已发起连接（状态机会继续推进）。
  accepted,

  /// 邀请码被联机核心拒绝（通常是不存在/已过期）。
  invalidRoom,

  /// 当前没有可用的联机核心端口。
  notReady,
}

/// 陶瓦联机管理器。
class TerracottaManager extends ChangeNotifier {
  TerracottaManager({
    TerracottaControlApi? api,
    TerracottaLauncher? launcher,
    Future<String> Function()? terracottaRootProvider,
    TerracottaBundle? Function(String root)? bundleBuilder,
    this.pollActive = const Duration(milliseconds: 500),
    this.pollIdle = const Duration(seconds: 15),
  }) : _api = api ?? HttpTerracottaControlApi(),
       _launcher = launcher ?? SystemTerracottaLauncher(),
       _rootProvider =
           terracottaRootProvider ?? AppPaths.instance.terracottaRoot,
       _bundleBuilder = bundleBuilder ?? TerracottaBundle.forCurrentPlatform;

  /// 单例：整个应用共用一个联机核心进程。
  static final TerracottaManager instance = TerracottaManager();

  final TerracottaControlApi _api;
  final TerracottaLauncher _launcher;
  final Future<String> Function() _rootProvider;

  /// 联机核心包解析器（测试可注入合成包）。
  final TerracottaBundle? Function(String root) _bundleBuilder;

  /// 页面可见时的轮询间隔。
  final Duration pollActive;

  /// 页面不可见时的轮询间隔。
  final Duration pollIdle;

  TerracottaState _state = const TerracottaBootstrap();
  TerracottaBundle? _bundle;
  TerracottaChildProcess? _process;
  int? _port;
  String? _portFilePath;
  Timer? _daemon;
  bool _active = false;
  bool _initializing = false;
  bool _downloading = false;
  bool _disposed = false;
  int _consecutivePollFailures = 0;
  final List<String> _processLogs = [];
  StreamSubscription<String>? _logSub;

  /// 玩家名（出现在房主/房客的玩家列表里）。
  String playerName = 'IriX';

  /// 最近一次操作失败的原因（界面用 SnackBar 呈现）。
  String? lastActionError;

  /// 当前状态。
  TerracottaState get state => _state;

  /// 本地控制端口（未启动时为 null）。
  int? get port => _port;

  /// 联机核心进程日志（最近的在后）。
  List<String> get processLogs => List.unmodifiable(_processLogs);

  /// 联机核心是否已就绪（拿到控制端口）。
  bool get coreReady => _port != null;

  @override
  void dispose() {
    _disposed = true;
    _daemon?.cancel();
    _daemon = null;
    unawaited(_logSub?.cancel());
    unawaited(_process?.kill());
    super.dispose();
  }

  /// 应用退出前调用：结束联机核心进程。
  ///
  /// 联机核心是独立子进程，父进程直接退出不会连带结束它，必须显式 kill，
  /// 否则会留下常驻的孤儿进程（还占着本地控制端口）。
  Future<void> shutdown() async {
    _daemon?.cancel();
    _daemon = null;
    await _killProcess();
  }

  /// 测试专用：直接把状态机推进到指定状态（绕过真实安装/启动流程）。
  ///
  /// 组件测试只关心「状态 → 界面」的映射，用它可以不启动联机核心、
  /// 也不创建任何轮询定时器。
  @visibleForTesting
  void debugForceState(TerracottaState next, {int? port}) {
    _port = port ?? (next.isPortSpecific ? next.port : null);
    _state = next;
    notifyListeners();
  }

  /// 页面可见性变化：可见时高频轮询，不可见时降到 15s。
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (_daemon != null) _restartDaemon();
  }

  /// 首次进入联机页时调用：幂等地完成「检测 → 安装 → 启动」流程。
  Future<void> ensureInitialized({bool force = false}) async {
    if (_initializing) return;
    if (!force && _state is! TerracottaBootstrap) return;
    if (force && _port != null) return;
    _initializing = true;
    try {
      if (TerracottaMetadata.checkSupport() != TerracottaSupportReason.ok) {
        _setState(const TerracottaFatal(TerracottaFatalType.os));
        return;
      }
      final root = await _rootProvider();
      final bundle = _bundleBuilder(root);
      if (bundle == null) {
        _setState(const TerracottaFatal(TerracottaFatalType.os));
        return;
      }
      _bundle = bundle;

      final status = await bundle.status();
      switch (status) {
        case TerracottaBundleStatus.ready:
          _setState(const TerracottaLaunching());
          await _launch();
        case TerracottaBundleStatus.legacyVersion:
          _setState(const TerracottaUninitialized(hasLegacy: true));
        case TerracottaBundleStatus.notExist:
          _setState(const TerracottaUninitialized(hasLegacy: false));
      }
    } catch (e, st) {
      DevLog.instance.devError('terracotta', '初始化失败: $e\n$st');
      _setState(const TerracottaFatal(TerracottaFatalType.unknown));
    } finally {
      _initializing = false;
    }
  }

  /// 下载并安装联机核心，完成后自动启动。
  Future<void> downloadBundle() async {
    if (_downloading) return;
    final bundle = _bundle;
    if (bundle == null) {
      lastActionError = '当前平台没有可用的联机核心';
      notifyListeners();
      return;
    }
    _downloading = true;
    _setState(const TerracottaPreparing(progress: null));
    String? pkgPath;
    try {
      pkgPath = await bundle.download(
        onProgress: (progress) {
          final current = _state;
          if (current is TerracottaPreparing) {
            _setState(current.copyWith(progress: progress));
          }
        },
      );
      final current = _state;
      if (current is TerracottaPreparing && !current.hasInstallFence) {
        // 用户已经手动安装，本次下载作废。
        return;
      }
      final installState = _state;
      if (installState is TerracottaPreparing) {
        _setState(installState.copyWith(statusText: 'install'));
      }
      await bundle.install(pkgPath);
      await bundle.removeLegacyVersions();
      _setState(const TerracottaLaunching());
      await _launch();
    } on TerracottaDownloadException catch (e) {
      DevLog.instance.devWarn('terracotta', '下载联机核心失败: $e');
      _setState(const TerracottaFatal(TerracottaFatalType.network));
    } catch (e, st) {
      DevLog.instance.devError('terracotta', '安装联机核心失败: $e\n$st');
      _setState(const TerracottaFatal(TerracottaFatalType.install));
    } finally {
      _downloading = false;
      if (pkgPath != null) {
        final file = File(pkgPath);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
        // 连下载用的临时目录一起清掉（AppPaths.createTempDir 每次新建一个）。
        try {
          final dir = file.parent;
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// 从本地 tar.gz 安装（用户手动下载的官方包）。
  Future<TerracottaInstallResult> installFromLocalBundle(String path) async {
    final bundle = _bundle;
    if (bundle == null) {
      lastActionError = '当前平台没有可用的联机核心';
      notifyListeners();
      return TerracottaInstallResult.invalidPackage;
    }
    if (bundle.isInvalidLocalBundle(path)) {
      lastActionError = '包名不匹配，应为 ${bundle.packageName}';
      notifyListeners();
      return TerracottaInstallResult.invalidPackage;
    }
    // 若正在下载，先撤销「安装后自动启动」的许可，避免覆盖手动安装。
    final current = _state;
    if (current is TerracottaPreparing) {
      _setState(current.copyWith(hasInstallFence: false));
    } else {
      _setState(const TerracottaPreparing(progress: null));
    }
    try {
      await bundle.install(path);
      await bundle.removeLegacyVersions();
      _setState(const TerracottaLaunching());
      await _launch();
      return TerracottaInstallResult.ok;
    } catch (e) {
      DevLog.instance.devError('terracotta', '本地安装失败: $e');
      lastActionError = '$e';
      _setState(const TerracottaFatal(TerracottaFatalType.install));
      return TerracottaInstallResult.failed;
    }
  }

  /// 房主：开始扫描局域网世界。
  Future<void> startHostScanning() async {
    final port = _port;
    if (port == null) {
      lastActionError = '联机核心尚未就绪';
      notifyListeners();
      return;
    }
    _setState(TerracottaHostScanning(port: port, index: -1));
    try {
      final nodes = await _api.fetchPublicNodes();
      await _api.setScanning(port, player: playerName, publicNodes: nodes);
      _restartDaemon();
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '发起房主扫描失败: $e');
      lastActionError = '$e';
      _setState(TerracottaWaiting(port: port, index: -1));
      notifyListeners();
    }
  }

  /// 房客：用邀请码加入房间。
  Future<TerracottaJoinResult> joinRoom(String room) async {
    final port = _port;
    if (port == null) return TerracottaJoinResult.notReady;
    final code = room.trim();
    if (code.isEmpty) return TerracottaJoinResult.invalidRoom;
    try {
      final nodes = await _api.fetchPublicNodes();
      await _api.setGuesting(
        port,
        room: code,
        player: playerName,
        publicNodes: nodes,
      );
      _setState(TerracottaGuestConnecting(port: port, index: -1));
      _restartDaemon();
      return TerracottaJoinResult.accepted;
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '加入房间失败: $e');
      return TerracottaJoinResult.invalidRoom;
    }
  }

  /// 回到空闲态（退出房间 / 停止扫描）。
  Future<void> backToWaiting() async {
    final port = _port;
    if (port == null) return;
    try {
      await _api.setWaiting(port);
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '/state/ide 失败: $e');
    }
    _setState(TerracottaWaiting(port: port, index: -1));
    _restartDaemon();
  }

  /// 致命错误后的恢复：已安装就直接重启核心，否则重新下载。
  Future<void> recover() async {
    final current = _state;
    if (current is! TerracottaFatal || !current.isRecoverable) return;
    await _killProcess();
    _setState(const TerracottaBootstrap());
    await ensureInitialized(force: true);
  }

  /// 杀掉并重新启动联机核心（「重置联机核心」按钮）。
  Future<void> resetCore() async {
    await _killProcess();
    _port = null;
    _setState(const TerracottaBootstrap());
    notifyListeners();
    await ensureInitialized(force: true);
  }

  /// 导出联机核心日志（ZIP：`terracotta.log` + 本应用捕获的进程日志）。
  ///
  /// [outputDir] 仅供测试指定落盘目录；默认写到 `<数据根>/terracotta/logs/`。
  /// 返回生成的 ZIP 路径；失败返回 null。
  Future<String?> exportLogs({String? outputDir}) async {
    final port = _port;
    String? coreLog;
    if (port != null) {
      try {
        coreLog = await _api.exportLog(port);
      } catch (e) {
        DevLog.instance.devWarn('terracotta', '导出联机核心日志失败: $e');
      }
    }
    final logsDir = Directory(
      outputDir ?? await AppPaths.instance.terracottaLogsDir(),
    );
    try {
      if (!logsDir.existsSync()) logsDir.createSync(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final target = File(p.join(logsDir.path, 'terracotta-log-$stamp.zip'));
      final archive = Archive();
      final coreText = coreLog ?? '（联机核心未返回日志）';
      final coreBytes = utf8.encode(coreText);
      archive.addFile(
        ArchiveFile('terracotta.log', coreBytes.length, coreBytes),
      );
      final hostBytes = utf8.encode(_processLogs.join('\n'));
      archive.addFile(
        ArchiveFile('irix-terracotta.log', hostBytes.length, hostBytes),
      );
      final zipped = ZipEncoder().encode(archive);
      target.writeAsBytesSync(zipped, flush: true);
      return target.path;
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '写日志归档失败: $e');
      return null;
    }
  }

  /// 启动联机核心进程并等待控制端口。
  Future<void> _launch() async {
    final bundle = _bundle;
    if (bundle == null) {
      _setState(const TerracottaFatal(TerracottaFatalType.os));
      return;
    }
    await _killProcess();
    final tempRoot = await _rootProvider();
    final runDir = Directory(p.join(tempRoot, 'temp'));
    if (!runDir.existsSync()) runDir.createSync(recursive: true);
    _pruneStaleRunDirs(runDir);
    _portFilePath = terracottaPortFilePath(
      p.join(runDir.path, 'run-${DateTime.now().millisecondsSinceEpoch}'),
    );
    Directory(p.dirname(_portFilePath!)).createSync(recursive: true);

    final TerracottaLaunchResult result;
    try {
      result = await _launcher.launch(
        executable: bundle.executablePath,
        workingDir: bundle.rootPath,
        portFilePath: _portFilePath!,
      );
    } catch (e) {
      DevLog.instance.devError('terracotta', '启动联机核心失败: $e');
      _setState(const TerracottaFatal(TerracottaFatalType.terracotta));
      return;
    }

    _process = result.process;
    _port = result.port;
    _logSub = result.process.logs.listen(_onProcessLog);
    _setState(TerracottaUnknown(result.port));
    _restartDaemon();
    // 立刻拉一次 /state，让界面尽快从「初始化」跳到真实状态。
    unawaited(_pollOnce());
  }

  /// 清理上一次启动留下的运行目录（端口文件已无意义，留着只会占空间）。
  ///
  /// 只删 1 小时前的目录：同一台机器上可能同时开着另一个 IriX 实例，
  /// 它的联机核心也在用 `temp/run-*`，不能误删。
  void _pruneStaleRunDirs(Directory runDir) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    try {
      for (final entity in runDir.listSync()) {
        if (entity is! Directory) continue;
        if (!p.basename(entity.path).startsWith('run-')) continue;
        if (entity.statSync().modified.isAfter(cutoff)) continue;
        entity.deleteSync(recursive: true);
      }
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '清理旧运行目录失败: $e');
    }
  }

  void _onProcessLog(String line) {
    _processLogs.add(line);
    if (_processLogs.length > 400) {
      _processLogs.removeRange(0, _processLogs.length - 400);
    }
    if (line.contains('退出，退出码')) {
      // 进程自行退出：只有当前状态还依赖这个端口时才报通讯失败。
      if (_port != null && _state.isPortSpecific) {
        _setState(const TerracottaFatal(TerracottaFatalType.terracotta));
      }
    }
  }

  Future<void> _killProcess() async {
    _daemon?.cancel();
    _daemon = null;
    await _logSub?.cancel();
    _logSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.kill();
      } catch (_) {}
    }
    _port = null;
  }

  void _restartDaemon() {
    _daemon?.cancel();
    if (_disposed) return;
    final interval = _active ? pollActive : pollIdle;
    _daemon = Timer.periodic(interval, (_) => unawaited(_pollOnce()));
  }

  /// 轮询一次 `/state`，并把新状态合并进状态机。
  Future<void> _pollOnce() async {
    final port = _port;
    if (port == null) return;
    if (!_state.isPortSpecific) return;
    try {
      final json = await _api.fetchState(port);
      _consecutivePollFailures = 0;
      final result = parseTerracottaReadyJson(json, port: port);
      if (!result.isOk) {
        DevLog.instance.devWarn('terracotta', '解析状态失败: ${result.error}');
        _setState(const TerracottaFatal(TerracottaFatalType.terracotta));
        return;
      }
      final next = result.state!;
      final current = _state;
      final currentIndex = current is TerracottaReady ? current.index : -2;
      // 只接受更新的快照（index 单调递增），避免乱序响应把界面拉回旧状态。
      if (next.index <= currentIndex) return;
      _setState(next);
    } catch (e) {
      _consecutivePollFailures++;
      DevLog.instance.devWarn(
        'terracotta',
        '拉取状态失败($_consecutivePollFailures): $e',
      );
      // 单次失败可能只是核心忙；连续失败或进程已退出才判定通讯失败。
      if (_consecutivePollFailures >= 5 ||
          (_process != null && !_process!.isRunning)) {
        _setState(const TerracottaFatal(TerracottaFatalType.terracotta));
      }
    }
  }

  void _setState(TerracottaState next) {
    if (_disposed) return;
    _state = next;
    DevLog.instance.devInfo('terracotta', '状态 → ${next.runtimeType}');
    notifyListeners();
  }
}
