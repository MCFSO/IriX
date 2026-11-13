// 时间系统 FFI 集成测试
//
// 需要先编译 Rust 动态库并复制到 windows/runner/ 或项目根目录：
//   build_rust.bat（Windows）/ ./build_rust.sh（Linux/macOS）
//
// 测试不依赖公网：本地起一个 UDP NTP 服务器，返回“真实时间 + 12.5s”，
// 然后让 Rust 时间系统同步，验证应用时钟确实被拨到偏移后的时间，
// 且状态/精度/服务器列表都正确。动态库缺失时整组 skip。

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/time_ffi.dart';

bool _libraryAvailable() {
  final name = Platform.isWindows
      ? 'xmc_time.dll'
      : Platform.isMacOS
      ? 'libxmc_time.dylib'
      : 'libxmc_time.so';
  final candidates = <String>[
    '${Directory.current.path}${Platform.pathSeparator}$name',
    '${Directory.current.path}${Platform.pathSeparator}windows${Platform.pathSeparator}runner${Platform.pathSeparator}$name',
    '${Directory.current.path}${Platform.pathSeparator}linux${Platform.pathSeparator}$name',
    '${Directory.current.path}${Platform.pathSeparator}macos${Platform.pathSeparator}$name',
  ];
  return candidates.any((p) => File(p).existsSync());
}

/// 本地 NTP 服务器：只实现客户端需要的字段，返回固定偏移。
class _MockNtpServer {
  _MockNtpServer._(this._socket, this.offsetSeconds);

  final RawDatagramSocket _socket;
  final double offsetSeconds;

  int get port => _socket.port;

  static Future<_MockNtpServer> start({required double offsetSeconds}) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final server = _MockNtpServer._(socket, offsetSeconds);
    server._listen();
    return server;
  }

  void _listen() {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      final request = datagram.data;
      if (request.length < 48) return;
      final response = _buildResponse(request);
      _socket.send(response, datagram.address, datagram.port);
    });
  }

  Uint8List _buildResponse(Uint8List request) {
    final out = Uint8List(48);
    final view = ByteData.sublistView(out);
    out[0] = (4 << 3) | 4; // version 4, mode server
    out[1] = 2; // stratum
    out[2] = 4;
    out[3] = 0xEC; // precision -20
    // reference id "LOCL"
    out[12] = 0x4C;
    out[13] = 0x4F;
    out[14] = 0x43;
    out[15] = 0x4C;
    // origin = client's transmit timestamp
    out.setRange(24, 32, request, 40);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final fakeUnixMs = nowMs + (offsetSeconds * 1000).round();
    final secs = fakeUnixMs ~/ 1000;
    final millis = fakeUnixMs % 1000;
    final ntpSecs = (secs + 2208988800) & 0xFFFFFFFF;
    final ntpFrac = ((millis / 1000.0) * 4294967296.0).toInt() & 0xFFFFFFFF;
    view.setUint32(32, ntpSecs); // receive seconds
    view.setUint32(36, ntpFrac); // receive fraction
    view.setUint32(40, ntpSecs); // transmit seconds
    view.setUint32(44, ntpFrac); // transmit fraction
    return out;
  }

  Future<void> close() async {
    _socket.close();
  }
}

Map<String, dynamic> _syncInIsolate() => TimeFfi.instance.callMap('sync');

List<dynamic> _probeInIsolate() => TimeFfi.instance.callList('probe');

Map<String, dynamic> _accuracyInIsolate() => TimeFfi.instance.callMap('accuracy');

void main() {
  final available = _libraryAvailable();
  final skipReason = available
      ? null
      : '未找到 xmc_time 动态库（先运行 build_rust.bat / ./build_rust.sh）';

  test('now 返回合理且单调的时间', () async {
    final ffi = TimeFfi.instance;
    final a = ffi.nowUnixMs();
    final b = ffi.nowUnixMs();
    expect(a, greaterThan(1577836800000)); // 2020-01-01
    expect(b, greaterThanOrEqualTo(a));
    final map = ffi.callMap('now');
    expect(map['iso8601'], endsWith('Z'));
    expect(map['http_date'], endsWith('GMT'));
  }, skip: skipReason);

  test('本地 NTP 服务器同步后应用时钟带偏移且状态一致', () async {
    final server = await _MockNtpServer.start(offsetSeconds: 12.5);
    final ffi = TimeFfi.instance;
    try {
      ffi.call('reset');
      ffi.call('configure', {
        'servers': ['127.0.0.1:${server.port}'],
        'samples_per_poll': 2,
        'timeout_ms': 800,
        'auto_start': false,
      });
      final status = await Isolate.run(_syncInIsolate);
      final clock = status['clock'] as Map<String, dynamic>;
      final sync = status['sync'] as Map<String, dynamic>;
      expect(clock['synced'], isTrue, reason: '$status');
      expect(sync['stratum'], 2);
      expect((sync['offset_ns'] as num).abs() / 1e6, closeTo(12500, 800));

      final nowMs = ffi.nowUnixMs();
      final systemMs = DateTime.now().millisecondsSinceEpoch;
      expect(nowMs - systemMs, closeTo(12500, 800));

      final servers = status['servers'] as List<dynamic>;
      expect(servers, hasLength(1));
      expect((servers.first as Map<String, dynamic>)['reachable'], isTrue);

      final probe = await Isolate.run(_probeInIsolate);
      expect(probe, hasLength(1));
      expect((probe.first as Map<String, dynamic>)['ok'], isTrue);

      final accuracy = await Isolate.run(_accuracyInIsolate);
      expect(accuracy['ok'], isTrue, reason: '$accuracy');
      expect(
        (accuracy['median_offset_ms'] as num).abs(),
        lessThan(50),
        reason: '同步后应用时钟应贴近本地 mock 服务器: $accuracy',
      );
    } finally {
      ffi.call('reset');
      await server.close();
    }
  }, skip: skipReason);

  test('GNSS 样本可被采纳并更新状态', () async {
    final ffi = TimeFfi.instance;
    ffi.call('reset');
    try {
      final mono = (ffi.callMap('mono')['mono_ns'] as num).toInt();
      final now = ffi.callMap('now');
      final appNs = (now['unix_ns'] as num).toInt();
      final result = ffi.callMap('gnss_sample', {
        'utc_ns': appNs + 1000000000,
        'mono_ns': mono,
        'uncertainty_ns': 500,
        'constellation': 'gps',
        'sv_count': 12,
        'fix': '3d',
        'leap_seconds': 18,
        'source': 'raw',
        'clock_discontinuity': 0,
        'age_ms': 0,
      });
      expect(result['accepted'], isTrue, reason: '$result');
      final status = ffi.callMap('status');
      final gnss = status['gnss'] as Map<String, dynamic>;
      expect(gnss['accepted'], isTrue);
      expect(gnss['accepted_samples'], 1);
      expect(gnss['constellation'], 'gps');
    } finally {
      ffi.call('reset');
    }
  }, skip: skipReason);

  test('无法达成一致或全部不可达时不宣称已同步', () async {
    final ffi = TimeFfi.instance;
    ffi.call('reset');
    ffi.call('configure', {
      'servers': ['127.0.0.1:9'],
      'samples_per_poll': 1,
      'timeout_ms': 300,
      'auto_start': false,
    });
    final status = await Isolate.run(_syncInIsolate);
    final clock = status['clock'] as Map<String, dynamic>;
    expect(clock['synced'], isFalse);
    ffi.call('reset');
  }, skip: skipReason);

  test('self_test 全部通过', () async {
    final data = TimeFfi.instance.callMap('self_test');
    expect(data['ok'], isTrue, reason: '$data');
    final checks = data['checks'] as List<dynamic>;
    expect(checks, isNotEmpty);
    for (final check in checks) {
      expect((check as Map<String, dynamic>)['ok'], isTrue, reason: '$check');
    }
  }, skip: skipReason);
}
