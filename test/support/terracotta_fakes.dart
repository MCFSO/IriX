// 陶瓦联机测试替身：假控制 API / 假启动器 / 合成联机核心包。
//
// 供 `terracotta_manager_test.dart` 与 `instance_multiplayer_tab_test.dart` 共用，
// 让状态机与界面都能在离线环境（不下载 8MiB 核心、不起子进程）下测试。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:irix/services/terracotta/terracotta_bundle.dart';
import 'package:irix/services/terracotta/terracotta_control_api.dart';
import 'package:irix/services/terracotta/terracotta_launcher.dart';
import 'package:irix/services/terracotta/terracotta_metadata.dart';
import 'package:path/path.dart' as p;

/// 假子进程：可控的运行状态与日志流。
class FakeChildProcess implements TerracottaChildProcess {
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  bool running = true;
  int? _exitCode;

  @override
  Stream<String> get logs => controller.stream;

  @override
  bool get isRunning => running;

  @override
  int? get exitCode => _exitCode;

  @override
  Future<void> kill() async {
    running = false;
    _exitCode = 0;
    if (!controller.isClosed) await controller.close();
  }
}

/// 假启动器：不真正起进程，只把端口文件写出来。
class FakeLauncher implements TerracottaLauncher {
  FakeLauncher(this.port);

  int port;
  int launches = 0;
  String? lastExecutable;
  FakeChildProcess process = FakeChildProcess();

  @override
  Future<TerracottaLaunchResult> launch({
    required String executable,
    required String workingDir,
    required String portFilePath,
  }) async {
    launches++;
    lastExecutable = executable;
    Directory(p.dirname(portFilePath)).createSync(recursive: true);
    File(portFilePath).writeAsStringSync(jsonEncode({'port': port}));
    process = FakeChildProcess();
    return TerracottaLaunchResult(port: port, process: process);
  }
}

/// 假控制 API：按脚本返回 `/state`，并记录调用情况。
class FakeControlApi implements TerracottaControlApi {
  FakeControlApi([List<Map<String, dynamic>> states = const []])
    : _states = [...states];

  final List<Map<String, dynamic>> _states;

  int stateCalls = 0;
  int scanningCalls = 0;
  int guestingCalls = 0;
  int ideCalls = 0;
  bool throwOnState = false;
  bool throwOnGuesting = false;
  String? lastScanningPlayer;
  String? lastGuestingRoom;
  String? lastGuestingPlayer;
  List<String> lastNodes = const [];
  List<String> nodes = const ['wss://node-a.example'];

  /// 固定返回的状态（优先于队列）。
  Map<String, dynamic>? nextState;

  @override
  Future<Map<String, dynamic>> fetchState(int port) async {
    stateCalls++;
    if (throwOnState) throw const SocketException('connection refused');
    final next =
        nextState ??
        (_states.isEmpty
            ? {'state': 'waiting', 'index': 1}
            : _states.removeAt(0));
    return next;
  }

  @override
  Future<void> setWaiting(int port) async {
    ideCalls++;
  }

  @override
  Future<void> setScanning(
    int port, {
    required String player,
    required List<String> publicNodes,
  }) async {
    scanningCalls++;
    lastScanningPlayer = player;
    lastNodes = publicNodes;
  }

  @override
  Future<void> setGuesting(
    int port, {
    required String room,
    required String player,
    required List<String> publicNodes,
  }) async {
    guestingCalls++;
    lastGuestingRoom = room;
    lastGuestingPlayer = player;
    lastNodes = publicNodes;
    if (throwOnGuesting) throw const SocketException('bad request');
  }

  @override
  Future<String?> exportLog(int port) async => 'core log line';

  @override
  Future<List<String>> fetchPublicNodes() async => nodes;
}

/// 生成一个「元数据自洽」的已安装联机核心包（内容为假的二进制）。
TerracottaBundle buildTestBundle(String rootPath) {
  final classifier = TerracottaMetadata.currentClassifier();
  if (classifier == null) {
    throw StateError('当前平台不支持陶瓦联机，无法运行该测试');
  }
  final exeName = Platform.isWindows
      ? 'terracotta-0.4.2-$classifier.exe'
      : 'terracotta-0.4.2-$classifier';
  final content = Uint8List.fromList(utf8.encode('fake core'));
  final bundle = TerracottaBundle(
    version: '0.4.2',
    classifier: classifier,
    rootPath: p.join(rootPath, '0.4.2'),
    package: TerracottaPackage(
      hash: 'pkg',
      files: {exeName: crypto.sha512.convert(content).toString()},
    ),
  );
  final dir = Directory(bundle.rootPath)..createSync(recursive: true);
  File(p.join(dir.path, exeName)).writeAsBytesSync(content);
  return bundle;
}
