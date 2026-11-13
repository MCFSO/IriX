// IriX 时间系统业务入口（Dart 侧）
//
// 所有“现在”都应优先走这里，而不是 DateTime.now()：
//   - X-Session-Timestamp / 登录签名时间戳（防重放窗口）
//   - 设备绑定注册时间、挑战过期判断
//   - TOTP、Token 过期、集群迁移超时等对时钟敏感的逻辑
//   - 日志/备份/临时文件命名等展示性时间
//
// 后端 Rust xmc_time 用 NTP（rusty_time-core）校准、用单调时钟保持、
// 用回归斜率补偿晶振漂移；本类在动态库不可用时优雅退化为 DateTime.now()，
// 保证单元测试/未编译 Rust 的环境仍能运行。

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'database_manager.dart';
import 'time_ffi.dart';

/// 时间系统业务入口（单例）。
class TimeService {
  TimeService._();

  static final TimeService instance = TimeService._();

  static const String settingKey = 'time_config';
  static const List<String> defaultServers = <String>[
    'ntp.aliyun.com',
    'ntp.tencent.com',
    'cn.pool.ntp.org',
    'time.cloudflare.com',
  ];

  TimeFfi? _ffi;
  bool _initialized = false;
  String? _lastError;
  Map<String, Object?> _config = <String, Object?>{
    'servers': defaultServers,
    'min_poll_log2': 4,
    'max_poll_log2': 8,
    'samples_per_poll': 2,
    'timeout_ms': 1200,
    'precision': true,
    'auto_start': true,
    'holdover_ppm': 15.0,
  };

  bool get available => _ffi != null;

  bool get synced => _ffi?.synced ?? false;

  int get uncertaintyNs =>
      _ffi?.uncertaintyNs ??
      const Duration(milliseconds: 250).inMicroseconds * 1000;

  String? get lastError => _lastError;

  Map<String, Object?> get config => Map<String, Object?>.unmodifiable(_config);

  /// 应用启动时调用一次（在 AppPaths / DatabaseManager 初始化之后）。
  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    try {
      _ffi = TimeFfi.instance;
    } on TimeFfiException catch (e) {
      _lastError = e.message;
      _ffi = null;
      return;
    } catch (e) {
      _lastError = '$e';
      _ffi = null;
      return;
    }

    final config = await _loadConfig();
    final statePath = p.join(await AppPaths.instance.clockStateDir(), 'state.json');
    _config = <String, Object?>{
      ...config,
      'state_path': statePath,
    };
    try {
      final data = _ffi!.callMap('start', _config);
      _applyStatusConfig(data);
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
    }
    // 本机 ADB reverse 时间桥：手机 App 通过 USB 连到 127.0.0.1:47820。
    // 只绑定回环地址；失败（端口占用等）不影响时间系统本身。
    try {
      _ffi!.call('gnss_bridge_start', <String, Object?>{'token': 'irix-adb'});
    } catch (e) {
      _lastError = 'GNSS 时间桥: $e';
    }
  }

  Future<Map<String, Object?>> _loadConfig() async {
    try {
      final raw = await DatabaseManager.instance.getSetting(settingKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecodeMap(raw);
        if (decoded != null) return decoded;
      }
    } catch (_) {
      // 设置读取失败时使用默认值
    }
    return <String, Object?>{};
  }

  static Map<String, Object?>? jsonDecodeMap(String raw) {
    try {
      final value = const JsonCodec().decode(raw);
      if (value is Map<String, dynamic>) {
        return value.map((k, v) => MapEntry(k, v as Object?));
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  /// 当前 Unix 毫秒（NTP 校准后的应用时间）。
  int nowUnixMs() {
    final ffi = _ffi;
    if (ffi != null) {
      try {
        return ffi.nowUnixMs();
      } catch (_) {
        // 动态库异常时退回系统时间
      }
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  int nowUnixSeconds() => nowUnixMs() ~/ 1000;

  int nowUnixMicros() {
    final ffi = _ffi;
    if (ffi != null) {
      try {
        return ffi.nowUnixNs() ~/ 1000;
      } catch (_) {
        // fallthrough
      }
    }
    return DateTime.now().microsecondsSinceEpoch;
  }

  int nowUnixNs() {
    final ffi = _ffi;
    if (ffi != null) {
      try {
        return ffi.nowUnixNs();
      } catch (_) {
        // fallthrough
      }
    }
    return DateTime.now().microsecondsSinceEpoch * 1000;
  }

  DateTime nowUtc() =>
      DateTime.fromMillisecondsSinceEpoch(nowUnixMs(), isUtc: true);

  DateTime nowLocal() => nowUtc().toLocal();

  /// ISO8601（毫秒，UTC）。
  String nowIso8601() => formatIso8601(nowUnixMs());

  static String formatIso8601(int unixMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true);
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-${d}T$h:$mi:$s.${ms}Z';
  }

  /// 标准 HTTP 日期（IMF-fixdate）。
  String httpDate() {
    final ffi = _ffi;
    if (ffi != null) {
      try {
        final data = ffi.callMap('now');
        final value = data['http_date'];
        if (value is String && value.isNotEmpty) return value;
      } catch (_) {
        // fallback
      }
    }
    return _formatHttpDate(nowUnixMs() ~/ 1000);
  }

  static String _formatHttpDate(int unixSeconds) {
    const weekdays = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dt = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
      isUtc: true,
    );
    final wd = weekdays[dt.weekday % 7];
    final mo = months[dt.month - 1];
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$wd, $d $mo ${dt.year.toString().padLeft(4, '0')} $h:$mi:$s GMT';
  }

  /// 详细状态（同步调用，读取原子状态，耗时为微秒级）。
  Map<String, dynamic> status() {
    final ffi = _ffi;
    if (ffi == null) {
      return <String, dynamic>{
        'available': false,
        'error': _lastError ?? 'xmc_time 动态库不可用',
        'clock': <String, dynamic>{
          'unix_ns': nowUnixNs(),
          'synced': false,
          'source': 'system',
        },
      };
    }
    try {
      final data = ffi.callMap('status');
      data['available'] = true;
      return data;
    } catch (e) {
      _lastError = '$e';
      return <String, dynamic>{'available': true, 'error': _lastError};
    }
  }

  /// 立即同步一轮 NTP。在后台 isolate 执行，避免阻塞 UI。
  Future<Map<String, dynamic>> syncNow() async {
    if (_ffi == null) {
      throw const TimeFfiException('时间系统不可用（缺少 xmc_time 动态库）');
    }
    final data = await Isolate.run(_syncInIsolate);
    data['available'] = true;
    return data;
  }

  /// 人工强制重置：无视防倒退/step 限制，直接硬切到 NTP 共识。
  Future<Map<String, dynamic>> forceReanchor() async {
    if (_ffi == null) {
      throw const TimeFfiException('时间系统不可用（缺少 xmc_time 动态库）');
    }
    final data = await Isolate.run(_forceReanchorInIsolate);
    data['available'] = true;
    return data;
  }

  /// 探测各服务器（不拨钟），后台 isolate。
  Future<List<dynamic>> probe() async {
    if (_ffi == null) {
      throw const TimeFfiException('时间系统不可用（缺少 xmc_time 动态库）');
    }
    return Isolate.run(_probeInIsolate);
  }

  /// 测量“应用时钟 vs NTP 共识”的偏差（中位数/极差）以及应用时钟与系统时钟的差值。
  /// 不拨钟，后台 isolate。
  Future<Map<String, dynamic>> measureAccuracy() async {
    if (_ffi == null) {
      throw const TimeFfiException('时间系统不可用（缺少 xmc_time 动态库）');
    }
    final data = await Isolate.run(_accuracyInIsolate);
    data['available'] = true;
    return data;
  }

  /// 保存配置并立即生效。
  Future<void> configure(Map<String, Object?> next) async {
    _config = <String, Object?>{..._config, ...next};
    final persistent = Map<String, Object?>.from(_config)
      ..remove('state_path');
    try {
      await DatabaseManager.instance.setSetting(
        settingKey,
        const JsonEncoder().convert(persistent),
      );
    } catch (_) {
      // 设置持久化失败不影响本次生效
    }
    final ffi = _ffi;
    if (ffi != null) {
      try {
        ffi.callMap('configure', next);
      } catch (e) {
        _lastError = '$e';
      }
    }
  }

  /// 外部注入温度（Windows/macOS 没有稳定内核温度接口时使用）。
  Future<void> setTemperature(double celsius) async {
    final ffi = _ffi;
    if (ffi == null) return;
    try {
      ffi.call('temperature', {'celsius': celsius});
    } catch (e) {
      _lastError = '$e';
    }
  }

  /// 注入一帧 Android GPS/北斗时间样本。
  ///
  /// `monoNs` 必须是 `SystemClock.elapsedRealtimeNanos()`（BOOTTIME），
  /// 且与 `utcNs` 属于同一帧；详见 docs/android-gnss-time-calibration.md。
  Map<String, dynamic> ingestGnssSample({
    required int utcNs,
    required int monoNs,
    required int uncertaintyNs,
    String constellation = 'gps',
    int svCount = 0,
    String fix = 'none',
    int? leapSeconds,
    String source = 'raw',
    int? clockDiscontinuity,
    int ageMs = 0,
    String? alignment,
    int? transportDelayNs,
    int? transportDelayUncertaintyNs,
  }) {
    final ffi = _ffi;
    if (ffi == null) {
      throw const TimeFfiException('时间系统不可用（缺少 xmc_time 动态库）');
    }
    return ffi.callMap('gnss_sample', {
      'utc_ns': utcNs,
      'mono_ns': monoNs,
      'uncertainty_ns': uncertaintyNs,
      'constellation': constellation,
      'sv_count': svCount,
      'fix': fix,
      'leap_seconds': leapSeconds,
      'source': source,
      'clock_discontinuity': clockDiscontinuity,
      'age_ms': ageMs,
      'alignment': alignment,
      'transport_delay_ns': transportDelayNs,
      'transport_delay_uncertainty_ns': transportDelayUncertaintyNs,
    });
  }

  /// 退出前调用：停止后台线程并落盘。
  Future<void> shutdown() async {
    final ffi = _ffi;
    if (ffi == null) return;
    try {
      ffi.call('gnss_bridge_stop');
    } catch (_) {
      // ignore
    }
    try {
      ffi.call('stop');
    } catch (_) {
      // ignore
    }
  }

  void _applyStatusConfig(Map<String, dynamic> data) {
    final config = data['config'];
    if (config is Map<String, dynamic>) {
      _config = <String, Object?>{..._config, ...config};
    }
  }
}

/// isolate 入口：重新打开同一个 DLL（同进程共享静态状态），执行阻塞同步。
Map<String, dynamic> _syncInIsolate() {
  final ffi = TimeFfi.instance;
  return ffi.callMap('sync');
}

Map<String, dynamic> _forceReanchorInIsolate() {
  final ffi = TimeFfi.instance;
  return ffi.callMap('force_reanchor');
}

List<dynamic> _probeInIsolate() {
  final ffi = TimeFfi.instance;
  return ffi.callList('probe');
}

Map<String, dynamic> _accuracyInIsolate() {
  final ffi = TimeFfi.instance;
  return ffi.callMap('accuracy');
}
