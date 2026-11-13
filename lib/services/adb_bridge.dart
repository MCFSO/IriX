import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';

class AdbDevice {
  const AdbDevice(this.serial, this.state);

  final String serial;
  final String state;

  bool get authorized => state == 'device';
}

class AdbReverseResult {
  const AdbReverseResult({
    required this.ok,
    required this.message,
    required this.at,
    this.adbPath,
    this.devices = const [],
    this.applied = const [],
    this.errors = const [],
  });

  final bool ok;
  final String message;
  final DateTime at;
  final String? adbPath;
  final List<AdbDevice> devices;
  final List<String> applied;
  final List<String> errors;
}

/// 打包在应用内的 adb（Windows），用于自动执行：
///
///     adb reverse tcp:47820 tcp:47820
///
/// 只对 `adb devices` 中状态为 `device`（已授权）的设备执行；多设备逐个 `-s`。
class AdbBridge {
  AdbBridge._();

  static final AdbBridge instance = AdbBridge._();

  static const int reversePort = 47820;

  final ValueNotifier<AdbReverseResult?> result =
      ValueNotifier<AdbReverseResult?>(null);

  Future<AdbReverseResult> applyReverse({int port = reversePort}) async {
    final at = DateTime.now();
    try {
      final adb = await _ensureAdb();
      final devicesOut = await _run(adb, <String>['devices', '-l']);
      final devices = _parseDevices(devicesOut);
      if (devices.isEmpty) {
        return _finish(
          AdbReverseResult(
            ok: false,
            message: '未发现 USB 设备：请连接手机并开启 USB 调试',
            at: at,
            adbPath: adb,
          ),
        );
      }
      final authorized = devices.where((d) => d.authorized).toList();
      if (authorized.isEmpty) {
        return _finish(
          AdbReverseResult(
            ok: false,
            message: '设备未授权：请在手机上确认 USB 调试 RSA 指纹',
            at: at,
            adbPath: adb,
            devices: devices,
          ),
        );
      }

      final applied = <String>[];
      final errors = <String>[];
      for (final device in authorized) {
        try {
          await _run(adb, <String>[
            '-s',
            device.serial,
            'reverse',
            'tcp:$port',
            'tcp:$port',
          ]);
          applied.add(device.serial);
        } catch (e) {
          errors.add('${device.serial}: $e');
        }
      }
      return _finish(
        AdbReverseResult(
          ok: applied.isNotEmpty,
          message: applied.isNotEmpty
              ? '已对 ${applied.length} 台设备应用 reverse tcp:$port'
              : 'adb reverse 失败',
          at: at,
          adbPath: adb,
          devices: devices,
          applied: applied,
          errors: errors,
        ),
      );
    } catch (e) {
      return _finish(
        AdbReverseResult(
          ok: false,
          message: 'ADB 不可用：$e',
          at: at,
        ),
      );
    }
  }

  AdbReverseResult _finish(AdbReverseResult value) {
    result.value = value;
    return value;
  }

  Future<String> _ensureAdb() async {
    if (!Platform.isWindows) {
      return 'adb';
    }
    final root = await AppPaths.instance.root();
    final dir = Directory(p.join(root, 'tools', 'adb', 'windows'));
    await dir.create(recursive: true);
    final adb = File(p.join(dir.path, 'adb.exe'));
    if (!await adb.exists() || await adb.length() < 1_000_000) {
      await _extractAsset('adb.exe', adb);
      await _extractAsset('AdbWinApi.dll', File(p.join(dir.path, 'AdbWinApi.dll')));
      await _extractAsset(
        'AdbWinUsbApi.dll',
        File(p.join(dir.path, 'AdbWinUsbApi.dll')),
      );
      await _extractAsset('NOTICE.txt', File(p.join(dir.path, 'NOTICE.txt')));
    }
    return adb.path;
  }

  Future<void> _extractAsset(String name, File target) async {
    final data = await rootBundle.load('assets/adb/windows/$name');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await target.writeAsBytes(bytes, flush: true);
  }

  Future<String> _run(String executable, List<String> args) async {
    final result = await Process.run(
      executable,
      args,
      runInShell: false,
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      final text = '${result.stdout}${result.stderr}'.trim();
      throw StateError(
        '$executable ${args.join(' ')} 退出码 ${result.exitCode}: $text',
      );
    }
    return '${result.stdout}';
  }

  List<AdbDevice> _parseDevices(String output) {
    final devices = <AdbDevice>[];
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('List of devices')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final serial = parts[0];
      final state = parts[1];
      if (serial.isEmpty) continue;
      devices.add(AdbDevice(serial, state));
    }
    return devices;
  }
}
