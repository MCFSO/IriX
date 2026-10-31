// 设备绑定密码学 FFI 封装（Rust xmc_device_auth 动态库）
//
// 统一入口 dev_auth_request(op, args_json) -> JSON，与 db_client / nbt 等 crate
// 保持同一风格。**私钥永不进入 Dart 堆内存**：密钥生成、DPAPI 加解封、签名与
// HMAC 全部在 Rust 侧完成，这里只经手公钥、deviceId、签名值与 MAC。
//
// 调用均为微秒级同步操作（Ed25519 签名 / HMAC-SHA256），因此直接在主 isolate
// 调用：逐请求证明会在每个 HTTP 请求上执行一次，若走后台 isolate 反而把
// 往返开销放大到百微秒级。

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

/// 设备绑定模块异常（动态库缺失、密钥不可用、参数非法等）。
class DeviceAuthException implements Exception {
  /// 可读错误原因。
  final String message;

  const DeviceAuthException(this.message);

  @override
  String toString() => message;
}

typedef _DevAuthRequestC =
    Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> argsJson);
typedef _DevAuthRequestDart =
    Pointer<Utf8> Function(Pointer<Utf8> op, Pointer<Utf8> argsJson);

/// `xmc_device_auth` 动态库绑定（单例）。
class DeviceAuthFfi {
  DeviceAuthFfi._(this._lib) {
    _request = _lib.lookupFunction<_DevAuthRequestC, _DevAuthRequestDart>(
      'dev_auth_request',
    );
  }

  final DynamicLibrary _lib;
  late final _DevAuthRequestDart _request;

  static DeviceAuthFfi? _instance;

  /// 单例（首次访问时加载动态库）。
  static DeviceAuthFfi get instance => _instance ??= _open();

  static DeviceAuthFfi _open() {
    try {
      return DeviceAuthFfi._(
        openRustLibrary(
          'device_auth',
          notFoundHint:
              '设备绑定功能需要 xmc_device_auth 动态库：'
              '请先运行 build_rust.bat（Windows）或 ./build_rust.sh（Linux/macOS）。',
        ),
      );
    } on UnsupportedError catch (e) {
      throw DeviceAuthException('$e');
    }
  }

  /// 动态库是否可用（不抛异常，供 UI 判断是否展示设备绑定入口）。
  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 调用一个 op，返回 `data` 字段；失败抛 [DeviceAuthException]。
  ///
  /// [args] 中的值必须是 JSON 可序列化类型。
  Map<String, dynamic> call(String op, [Map<String, Object?> args = const {}]) {
    final opPtr = op.toNativeUtf8();
    final argsPtr = jsonEncode(args).toNativeUtf8();
    Pointer<Utf8> resultPtr = nullptr;
    try {
      resultPtr = _request(opPtr, argsPtr);
      if (resultPtr == nullptr) {
        throw DeviceAuthException('设备绑定模块返回空指针（op=$op）');
      }
      final text = resultPtr.toDartString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw DeviceAuthException('设备绑定模块返回了非对象 JSON（op=$op）');
      }
      if (decoded['ok'] != true) {
        throw DeviceAuthException(
          decoded['error'] as String? ?? '设备绑定模块调用失败（op=$op）',
        );
      }
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on FormatException catch (e) {
      throw DeviceAuthException('设备绑定模块返回了无法解析的结果（op=$op）: $e');
    } finally {
      calloc.free(opPtr);
      calloc.free(argsPtr);
      if (resultPtr != nullptr) {
        freeRustString(_lib, resultPtr);
      }
    }
  }
}
