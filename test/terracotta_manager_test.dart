// 陶瓦联机管理器状态机测试。
//
// 用假的控制 API 与假的启动器把 `TerracottaManager` 的完整流程跑一遍：
// 初始化 → 启动核心 → 轮询 /state → 房主扫描 → 房客加入 → 回退 → 通讯失败恢复。
// 这样不用真的下载 8MiB 联机核心、也不用真的起子进程，保持 CI 离线可跑。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/terracotta/terracotta_manager.dart';
import 'package:irix/services/terracotta/terracotta_state.dart';
import 'package:path/path.dart' as p;

import 'support/terracotta_fakes.dart';

void main() {
  late Directory tempDir;
  late FakeControlApi api;
  late FakeLauncher launcher;
  late TerracottaManager manager;

  void build({List<Map<String, dynamic>> states = const []}) {
    api = FakeControlApi(states);
    launcher = FakeLauncher(25566);
    final bundle = buildTestBundle(tempDir.path);
    manager = TerracottaManager(
      api: api,
      launcher: launcher,
      terracottaRootProvider: () async => tempDir.path,
      bundleBuilder: (_) => bundle,
      pollActive: const Duration(milliseconds: 10),
      pollIdle: const Duration(milliseconds: 10),
    );
    manager.playerName = 'TestInstance';
    addTearDown(manager.dispose);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('irix-terracotta-mgr-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  test('已安装 → 启动核心 → 轮询到空闲态', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    expect(launcher.launches, 1);
    expect(manager.coreReady, isTrue);

    await settle();
    expect(manager.state, isA<TerracottaWaiting>());
    expect((manager.state as TerracottaWaiting).index, 1);
  });

  test('未安装时进入「未下载联机核心」状态且不启动进程', () async {
    build();
    Directory(p.join(tempDir.path, '0.4.2')).deleteSync(recursive: true);
    manager.setActive(true);
    await manager.ensureInitialized();
    expect(manager.state, isA<TerracottaUninitialized>());
    expect((manager.state as TerracottaUninitialized).hasLegacy, isFalse);
    expect(launcher.launches, 0);
  });

  test('存在旧版本目录时提示「需更新联机核心」', () async {
    build();
    Directory(p.join(tempDir.path, '0.4.2')).deleteSync(recursive: true);
    Directory(p.join(tempDir.path, '0.4.1')).createSync(recursive: true);
    manager.setActive(true);
    await manager.ensureInitialized();
    expect((manager.state as TerracottaUninitialized).hasLegacy, isTrue);
  });

  test('房主扫描 → 房间创建成功（邀请码 + 玩家列表）', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();
    expect(manager.state, isA<TerracottaWaiting>());

    api.nextState = {'state': 'host-scanning', 'index': 2};
    await manager.startHostScanning();
    expect(api.scanningCalls, 1);
    expect(api.lastScanningPlayer, 'TestInstance');
    expect(api.lastNodes, ['wss://node-a.example']);
    expect(manager.state, isA<TerracottaHostScanning>());

    api.nextState = {
      'state': 'host-ok',
      'index': 3,
      'room': '246813579',
      'profile_index': 1,
      'profiles': [
        {'machine_id': 'a', 'name': 'Alice', 'vendor': 'HMCL', 'kind': 'host'},
      ],
    };
    await settle();
    final state = manager.state;
    expect(state, isA<TerracottaHostOk>());
    expect((state as TerracottaHostOk).room, '246813579');
    expect(state.profiles.single.name, 'Alice');
  });

  test('房客：邀请码被拒绝时返回 invalidRoom，成功时进入连接中', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();

    api.throwOnGuesting = true;
    expect(await manager.joinRoom('123'), TerracottaJoinResult.invalidRoom);
    expect(manager.state, isA<TerracottaWaiting>());

    api.throwOnGuesting = false;
    expect(
      await manager.joinRoom(' 246813579 '),
      TerracottaJoinResult.accepted,
    );
    expect(api.lastGuestingRoom, '246813579');
    expect(api.lastGuestingPlayer, 'TestInstance');
    expect(manager.state, isA<TerracottaGuestConnecting>());
  });

  test('回到空闲态会调用 /state/ide', () async {
    build(
      states: [
        {'state': 'host-scanning', 'index': 5},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();
    await manager.backToWaiting();
    expect(api.ideCalls, 1);
    expect(manager.state, isA<TerracottaWaiting>());
  });

  test('乱序的旧状态快照不会覆盖当前状态', () async {
    build(
      states: [
        {'state': 'host-ok', 'index': 9, 'room': '777', 'profiles': []},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();
    expect((manager.state as TerracottaHostOk).room, '777');

    api.nextState = {'state': 'waiting', 'index': 4};
    await settle();
    expect(manager.state, isA<TerracottaHostOk>());
  });

  test('连续拉取失败判定为「无法与联机核心通讯」，恢复后重新启动', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();

    api.throwOnState = true;
    await settle();
    expect(manager.state, isA<TerracottaFatal>());
    expect(
      (manager.state as TerracottaFatal).type,
      TerracottaFatalType.terracotta,
    );

    api.throwOnState = false;
    api.nextState = {'state': 'waiting', 'index': 2};
    await manager.recover();
    expect(launcher.launches, 2);
    await settle();
    expect(manager.state, isA<TerracottaWaiting>());
  });

  test('本地安装包名不匹配时直接拒绝', () async {
    build();
    manager.setActive(true);
    await manager.ensureInitialized();
    final result = await manager.installFromLocalBundle('D:/tmp/hmcl.zip');
    expect(result, TerracottaInstallResult.invalidPackage);
    expect(manager.lastActionError, contains('pkg.tar.gz'));
  });

  test('shutdown 结束联机核心进程并清空端口（不留孤儿进程）', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();
    final process = launcher.process;
    expect(process.isRunning, isTrue);

    await manager.shutdown();
    expect(process.isRunning, isFalse);
    expect(manager.coreReady, isFalse);
  });

  test('导出日志生成可解压的 ZIP（含核心日志与进程日志）', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();

    final logsDir = p.join(tempDir.path, 'logs');
    final path = await manager.exportLogs(outputDir: logsDir);
    expect(path, isNotNull);
    final file = File(path!);
    expect(file.existsSync(), isTrue);

    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, contains('terracotta.log'));
    expect(names, contains('irix-terracotta.log'));
    final core = archive.files.firstWhere((f) => f.name == 'terracotta.log');
    expect(utf8.decode(core.content), contains('core log line'));
  });

  test('进程退出后判为通讯失败', () async {
    build(
      states: [
        {'state': 'waiting', 'index': 1},
      ],
    );
    manager.setActive(true);
    await manager.ensureInitialized();
    await settle();
    expect(manager.state, isA<TerracottaWaiting>());

    api.throwOnState = true;
    await launcher.process.kill();
    await settle();
    expect(manager.state, isA<TerracottaFatal>());
  });
}
