// SIMD 加速基础函数 (C FFI 实现)
// 通过 dart:ffi 调用 C 编译的动态库 (xmc_simd.dll / libxmc_simd.so / libxmc_simd.dylib)
//
// C 端实现位于 c/simd/：
//   - base64 编码/解码（AVX2 / SSSE3 / 标量，运行时 CPUID 自动分发）
//   - CRC32 IEEE（PCLMULQDQ）与 CRC32C（SSE4.2）
//
// 所有函数为纯同步计算，可在任意 isolate 中安全调用。

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef Base64DecodeNative =
    Uint64 Function(Pointer<Uint8> inPtr, Uint64 inLen, Pointer<Uint8> outPtr);
typedef Base64DecodeDart =
    int Function(Pointer<Uint8> inPtr, int inLen, Pointer<Uint8> outPtr);

typedef Crc32Native = Uint32 Function(Pointer<Uint8> data, Uint64 len, Uint32 seed);
typedef Crc32Dart = int Function(Pointer<Uint8> data, int len, int seed);

typedef CapsJsonNative = Pointer<Utf8> Function();
typedef CapsJsonDart = Pointer<Utf8> Function();

/// SIMD 原生库封装（单例）。库缺失或加载失败时 [available] 为 false，
/// 调用方应回退到 Dart 自带实现（dart:convert base64 / crypto 包）。
class SimdNative {
  static SimdNative? _instance;

  late final DynamicLibrary _lib;
  late final Base64DecodeDart base64Decode;
  late final Crc32Dart crc32Ieee;
  late final Crc32Dart crc32c;
  late final CapsJsonDart capsJson;

  bool get available => _instance != null;

  SimdNative._(this._lib) {
    base64Decode = _lib.lookupFunction<Base64DecodeNative, Base64DecodeDart>(
      'xmc_base64_decode',
    );
    crc32Ieee = _lib.lookupFunction<Crc32Native, Crc32Dart>('xmc_crc32_ieee');
    crc32c = _lib.lookupFunction<Crc32Native, Crc32Dart>('xmc_crc32c');
    capsJson = _lib.lookupFunction<CapsJsonNative, CapsJsonDart>(
      'xmc_simd_caps_json',
    );
  }

  static String get _libName {
    if (Platform.isWindows) return 'xmc_simd.dll';
    if (Platform.isMacOS) return 'libxmc_simd.dylib';
    return 'libxmc_simd.so';
  }

  /// 尝试加载原生库；失败返回 null（调用方回退 Dart 实现）。
  static SimdNative? tryInit() {
    if (_instance != null) return _instance;
    final libName = _libName;

    DynamicLibrary? lib;
    try {
      lib = DynamicLibrary.open(libName);
    } catch (_) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final attempts = <String>[
        p.join(exeDir, libName),
        p.join(exeDir, 'lib', libName),
        p.join(Directory.current.path, libName),
      ];
      for (final path in attempts) {
        if (File(path).existsSync()) {
          lib = DynamicLibrary.open(path);
          break;
        }
      }

      if (lib == null) {
        var dir = Directory.current;
        for (int i = 0; i < 10; i++) {
          final path = p.join(dir.path, libName);
          if (File(path).existsSync()) {
            lib = DynamicLibrary.open(path);
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
      }
    }

    if (lib == null) return null;
    try {
      _instance = SimdNative._(lib);
    } catch (_) {
      return null; // 符号缺失（版本不匹配）时回退
    }
    return _instance;
  }

  /// 当前 CPU 支持的 SIMD 特性（JSON 字符串），用于诊断。
  String? capsJsonString() {
    try {
      final ptr = capsJson();
      if (ptr == nullptr) return null;
      return ptr.toDartString();
    } catch (_) {
      return null;
    }
  }
}

/// SIMD base64 解码（标准 RFC 4648，支持 '=' padding）。
///
/// 返回解码后的字节；输入非法时返回 null（与 dart:convert 行为一致，
/// dart:convert 对非法输入抛 FormatException）。
/// 使用 Dart 侧 [bufferProvider] 提供的缓冲以避免重复分配（可选）。
Uint8List? simdBase64Decode(
  String base64, {
  Uint8List Function(int length)? bufferProvider,
}) {
  final simd = SimdNative.tryInit();
  if (simd == null) return null;

  final bytes = base64.codeUnits; // ASCII 场景，字符值 0-127
  final inPtr = calloc<Uint8>(bytes.length);
  final outLen = ((bytes.length + 3) ~/ 4) * 3 + 3;
  final outPtr = calloc<Uint8>(outLen);
  try {
    inPtr.asTypedList(bytes.length).setAll(0, bytes);
    final written = simd.base64Decode(inPtr, bytes.length, outPtr);
    if (written == -1) return null; // SIZE_MAX = 非法输入
    final result = bufferProvider?.call(written) ?? Uint8List(written);
    result.setAll(0, outPtr.asTypedList(written));
    return result;
  } finally {
    calloc.free(inPtr);
    calloc.free(outPtr);
  }
}

/// SIMD CRC32 IEEE（zip/gzip 兼容，poly 0xEDB88320）。
/// [seed] 为链式初始值（通常 0）。库不可用时返回 null。
int? simdCrc32Ieee(Uint8List data, [int seed = 0]) {
  final simd = SimdNative.tryInit();
  if (simd == null) return null;
  return _crc32Call(simd.crc32Ieee, data, seed);
}

/// SIMD CRC32C（Castagnoli，poly 0x82F63B78，SSE4.2 硬件指令）。
int? simdCrc32c(Uint8List data, [int seed = 0]) {
  final simd = SimdNative.tryInit();
  if (simd == null) return null;
  return _crc32Call(simd.crc32c, data, seed);
}

int _crc32Call(Crc32Dart fn, Uint8List data, int seed) {
  final ptr = calloc<Uint8>(data.length);
  try {
    ptr.asTypedList(data.length).setAll(0, data);
    return fn(ptr, data.length, seed);
  } finally {
    calloc.free(ptr);
  }
}
