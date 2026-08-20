// SIMD FFI 集成测试
// 需要 xmc_simd.dll 已编译并复制到 windows/runner/ 或项目根（c/simd/build.bat）。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/simd_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SimdNative', () {
    test('库加载与 CPU 特性查询', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到，跳过（需先编译复制）');
        return;
      }
      final caps = simd.capsJsonString();
      expect(caps, isNotNull);
      expect(caps, contains('sse2'));
    });
  });

  group('simdBase64Decode', () {
    late final Random rng;

    setUpAll(() {
      rng = Random(42);
    });

    Uint8List randomBytes(int n) {
      final b = Uint8List(n);
      for (var i = 0; i < n; i++) {
        b[i] = rng.nextInt(256);
      }
      return b;
    }

    test('与 dart:convert 一致（多种长度，含 padding）', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到');
        return;
      }
      for (final len in [0, 1, 2, 3, 4, 5, 12, 13, 47, 48, 100, 1023]) {
        final raw = randomBytes(len);
        final b64 = base64Encode(raw);
        final decoded = simdBase64Decode(b64);
        expect(decoded, isNotNull, reason: 'len=$len 解码不应失败');
        expect(decoded, equals(raw), reason: 'len=$len 内容不一致');
      }
    });

    test('非法输入返回 null（不抛异常）', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到');
        return;
      }
      expect(simdBase64Decode('!!!!'), isNull);
      expect(simdBase64Decode('a'), isNull); // 长度非法（mod 4 == 1）
      expect(simdBase64Decode('A==='), isNull);
      expect(simdBase64Decode('ab=c'), isNull);
    });

    test('大块数据往返一致（覆盖 SIMD 主循环）', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到');
        return;
      }
      final raw = randomBytes(1 << 20); // 1 MB
      final b64 = base64Encode(raw);
      final decoded = simdBase64Decode(b64)!;
      expect(decoded.length, raw.length);
      expect(decoded, equals(raw));
    });
  });

  group('SIMD CRC32', () {
    test('CRC32 IEEE 标准测试向量', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到');
        return;
      }
      final data = Uint8List.fromList(utf8.encode('123456789'));
      // 标准 CRC32（zip）测试向量
      expect(simdCrc32Ieee(data), 0xCBF43926);
      // 链式调用与一次性等价
      final half = simdCrc32Ieee(
        Uint8List.fromList(data.sublist(0, 4)),
        0,
      );
      final chained = simdCrc32Ieee(
        Uint8List.fromList(data.sublist(4)),
        half!,
      );
      expect(chained, 0xCBF43926);
    });

    test('CRC32C 标准测试向量', () {
      final simd = SimdNative.tryInit();
      if (simd == null) {
        markTestSkipped('xmc_simd 动态库未找到');
        return;
      }
      final data = Uint8List.fromList(utf8.encode('123456789'));
      expect(simdCrc32c(data), 0xE3069283);
    });
  });
}
