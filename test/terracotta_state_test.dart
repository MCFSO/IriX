// 陶瓦联机状态模型单元测试。
//
// 覆盖 `/state` 线上协议的解析分支（对应 HMCL `TerracottaState` 的多态反序列化）
// 与「玩家列表原地刷新」（isForkOf）语义。

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/terracotta/terracotta_state.dart';

void main() {
  group('parseTerracottaReadyJson', () {
    test('waiting / host-scanning / host-starting 三种空状态', () {
      for (final entry in {
        'waiting': TerracottaWaiting,
        'host-scanning': TerracottaHostScanning,
        'host-starting': TerracottaHostStarting,
      }.entries) {
        final result = parseTerracottaReadyJson({
          'state': entry.key,
          'index': 7,
        }, port: 1234);
        expect(result.isOk, isTrue, reason: entry.key);
        final state = result.state!;
        expect(state, isA<TerracottaReady>());
        expect(state.runtimeType, entry.value);
        expect(state.port, 1234);
        expect(state.index, 7);
        expect(state.isUiFakeState, isFalse);
      }
    });

    test('index 缺省为 -1，即「UI 假状态」', () {
      final result = parseTerracottaReadyJson({'state': 'waiting'}, port: 1);
      expect(result.state!.index, -1);
      expect(result.state!.isUiFakeState, isTrue);
    });

    test('host-ok 解析邀请码与玩家列表', () {
      final result = parseTerracottaReadyJson({
        'state': 'host-ok',
        'index': 12,
        'room': '123456789',
        'profile_index': 3,
        'profiles': [
          {
            'machine_id': 'm1',
            'name': 'Alice',
            'vendor': 'HMCL',
            'kind': 'host',
          },
          {
            'machine_id': 'm2',
            'name': 'Bob',
            'vendor': 'PCL CE',
            'kind': 'guest',
          },
        ],
      }, port: 5555);
      final state = result.state! as TerracottaHostOk;
      expect(state.room, '123456789');
      expect(state.profileIndex, 3);
      expect(state.profiles, hasLength(2));
      expect(state.profiles.first.name, 'Alice');
      expect(state.profiles.first.kind, TerracottaPlayerKind.host);
      expect(state.profiles.last.kind, TerracottaPlayerKind.guest);
    });

    test('host-ok 缺少 room 或 profiles 时报错', () {
      expect(
        parseTerracottaReadyJson({
          'state': 'host-ok',
          'profiles': [],
        }, port: 1).isOk,
        isFalse,
      );
      expect(
        parseTerracottaReadyJson({
          'state': 'host-ok',
          'room': '1',
        }, port: 1).isOk,
        isFalse,
      );
    });

    test('guest-starting 解析难度估算', () {
      final state =
          parseTerracottaReadyJson({
                'state': 'guest-starting',
                'index': 4,
                'difficulty': 'Tough',
              }, port: 2).state!
              as TerracottaGuestStarting;
      expect(state.difficulty, TerracottaDifficulty.tough);

      final unknown =
          parseTerracottaReadyJson({
                'state': 'guest-starting',
                'index': 5,
              }, port: 2).state!
              as TerracottaGuestStarting;
      expect(unknown.difficulty, TerracottaDifficulty.unknown);
    });

    test('guest-ok 解析备用联机地址', () {
      final state =
          parseTerracottaReadyJson({
                'state': 'guest-ok',
                'index': 9,
                'url': '127.0.0.1:25565',
                'profile_index': 1,
                'profiles': [
                  {'machine_id': 'm1', 'name': 'Host', 'kind': 'local'},
                ],
              }, port: 3).state!
              as TerracottaGuestOk;
      expect(state.url, '127.0.0.1:25565');
      expect(state.profiles.single.kind, TerracottaPlayerKind.local);
    });

    test('exception 按序号映射，越界视为协议错误', () {
      for (var i = 0; i < TerracottaExceptionType.values.length; i++) {
        final state =
            parseTerracottaReadyJson({
                  'state': 'exception',
                  'index': i,
                  'type': i,
                }, port: 4).state!
                as TerracottaExceptionState;
        expect(state.type, TerracottaExceptionType.values[i]);
      }
      expect(
        parseTerracottaReadyJson({
          'state': 'exception',
          'type': 99,
        }, port: 4).isOk,
        isFalse,
      );
    });

    test('未知状态字符串返回错误而不是抛异常', () {
      final result = parseTerracottaReadyJson({'state': 'nonsense'}, port: 1);
      expect(result.isOk, isFalse);
      expect(result.error, contains('nonsense'));
    });

    test('profiles 里单条脏数据不影响整体解析', () {
      final state =
          parseTerracottaReadyJson({
                'state': 'host-ok',
                'room': 'x',
                'profiles': [
                  {'name': 'NoKind'},
                  42,
                ],
              }, port: 1).state!
              as TerracottaHostOk;
      expect(state.profiles, hasLength(1));
      expect(state.profiles.single.kind, TerracottaPlayerKind.guest);
    });
  });

  group('TerracottaHostOk.isForkOf', () {
    TerracottaHostOk state(int index, int profileIndex) => TerracottaHostOk(
      port: 1,
      index: index,
      room: 'room',
      profiles: const [],
      profileIndex: profileIndex,
    );

    test('玩家列表刷新视为同一房间的分叉状态', () {
      final previous = state(10, 2);
      expect(state(11, 2).isForkOf(previous), isTrue);
      expect(state(12, 2).isForkOf(previous), isTrue);
    });

    test('超出 profile_index 的跳变视为新房间', () {
      expect(state(20, 2).isForkOf(state(10, 2)), isFalse);
      expect(state(11, 0).isForkOf(state(10, 0)), isFalse);
    });

    test('非 HostOk 前置状态不算分叉', () {
      expect(
        state(11, 2).isForkOf(TerracottaWaiting(port: 1, index: 10)),
        isFalse,
      );
      expect(state(11, 2).isForkOf(null), isFalse);
    });
  });

  test('致命错误除 unknown 外都可恢复', () {
    for (final type in TerracottaFatalType.values) {
      expect(
        TerracottaFatal(type).isRecoverable,
        type != TerracottaFatalType.unknown,
      );
    }
  });

  test('只有端口相关状态携带 port', () {
    expect(const TerracottaBootstrap().isPortSpecific, isFalse);
    expect(const TerracottaLaunching().isPortSpecific, isFalse);
    expect(
      const TerracottaFatal(TerracottaFatalType.os).isPortSpecific,
      isFalse,
    );
    expect(const TerracottaUnknown(2556).isPortSpecific, isTrue);
    expect(TerracottaWaiting(port: 1, index: 0).isPortSpecific, isTrue);
  });
}
