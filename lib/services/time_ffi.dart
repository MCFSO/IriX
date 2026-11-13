// IriX 时间系统 FFI 封装（Rust xmc_time 动态库）
//
// 统一入口 time_request(op, args_json) -> {"ok":true,"data":...}，与
// device_auth / backup / orchestrator 保持同一风格；另外直接绑定几个热路径导出：
//   xmc_time_now_unix_ms / xmc_time_now_unix_ns / xmc_time_synced /
//   xmc_time_uncertainty_ns
// 这样逐请求的 X-Session-Timestamp、TOTP、日志时间戳都只花一次 FFI 调用
// （约 100ns），不必 JSON 往返。库不存在时 TimeService 退化为 DateTime.now()，
// 界面与单元测试仍可用。

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

/// 时间系统异常（动态库缺失、参数非法、op 失败等）。
class TimeFfiException implements Exception {
  final String message;

  const TimeFfiException(this.message);

  @override
  String toString() => message;
}

typedef _TimeRequestC =
    Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> argsJson);
typedef _TimeRequestDart =
    Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> argsJson);

typedef _I64C = Int64 Function();
typedef _I64Dart = int Function();

typedef _I32C = Int32 Function();
typedef _I32Dart = int Function();

/// `xmc_time` 动态库绑定（单例，主 isolate 使用；调用均为微秒级）。
class TimeFfi {
  TimeFfi._(this._lib) {
    _request = _lib.lookupFunction<_TimeRequestC, _TimeRequestDart>(
      'time_request',
    );
    _nowMs = _lib.lookupFunction<_I64C, _I64Dart>('xmc_time_now_unix_ms');
    _nowNs = _lib.lookupFunction<_I64C, _I64Dart>('xmc_time_now_unix_ns');
    _synced = _lib.lookupFunction<_I32C, _I32Dart>('xmc_time_synced');
    _uncertainty = _lib.lookupFunction<_I64C, _I64Dart>(
      'xmc_time_uncertainty_ns',
    );
  }

  final DynamicLibrary _lib;
  late final _TimeRequestDart _request;
  late final _I64Dart _nowMs;
  late final _I64Dart _nowNs;
  late final _I32Dart _synced;
  late final _I64Dart _uncertainty;

  static TimeFfi? _instance;

  static TimeFfi get instance => _instance ??= _open();

  static TimeFfi _open() {
    try {
      return TimeFfi._(
        openRustLibrary(
          'time',
          notFoundHint:
              '时间系统需要 xmc_time 动态库：'
              '请先运行 build_rust.bat（Windows）或 ./build_rust.sh（Linux/macOS）。',
        ),
      );
    } on UnsupportedError catch (e) {
      throw TimeFfiException('$e');
    }
  }

  /// 动态库是否可用（不抛异常）。
  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 当前 Unix 毫秒（NTP 校准后的应用时间）。
  int nowUnixMs() => _nowMs();

  /// 当前 Unix 纳秒。
  int nowUnixNs() => _nowNs();

  int nowUnixSeconds() => _nowMs() ~/ 1000;

  int nowUnixMicros() => _nowMs() * 1000;

  bool get synced => _synced() != 0;

  int get uncertaintyNs => _uncertainty();

  /// 调用一个 op，返回 `data`（对象或数组）；失败抛 [TimeFfiException]。
  Object? call(String op, [Map<String, Object?> args = const {}]) {
    final opPtr = op.toNativeUtf8();
    final argsPtr = jsonEncode(args).toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = _request(opPtr, argsPtr);
      if (resultPtr == nullptr) {
        throw TimeFfiException('时间系统返回空指针（op=$op）');
      }
      final text = resultPtr.toDartString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw TimeFfiException('时间系统返回了非对象 JSON（op=$op）');
      }
      if (decoded['ok'] != true) {
        throw TimeFfiException(
          decoded['error'] as String? ?? '时间系统调用失败（op=$op）',
        );
      }
      return decoded['data'];
    } on FormatException catch (e) {
      throw TimeFfiException('时间系统返回了无法解析的结果（op=$op）: $e');
    } finally {
      calloc.free(opPtr);
      calloc.free(argsPtr);
      if (resultPtr != nullptr) {
        freeRustString(_lib, resultPtr, symbolName: 'xmc_time_free_string');
      }
    }
  }

  /// 调用返回对象的 op。
  Map<String, dynamic> callMap(
    String op, [
    Map<String, Object?> args = const {},
  ]) {
    final data = call(op, args);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// 调用返回数组的 op（probe）。
  List<dynamic> callList(
    String op, [
    Map<String, Object?> args = const {},
  ]) {
    final data = call(op, args);
    return data is List<dynamic> ? data : const <dynamic>[];
  }
}
