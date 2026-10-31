// xmc_device_auth（Rust）FFI 集成测试
//
// 验证 docs/device-binding.md 第 2 节的密钥/编码约定与第 4/5/6 节所需的
// 密码学原语：
// - deviceId = hex(SHA-256(公钥))[:32]
// - ed25519 原始 64 字节签名、P-256 r||s（P1363）64 字节签名
// - HMAC-SHA256 逐请求证明、SHA-256、CSPRNG
// - 私钥落盘保护（Windows DPAPI / 其他平台 0600 文件）与密钥稳定性
//
// 签名/摘要**用 package:cryptography 独立复算**，避免「Rust 自己验自己」的
// 循环验证（Rust 侧另有 cargo test 覆盖 ring 自校验）。
//
// 需要先编译并复制动态库：
//   cargo build --release --manifest-path rust/Cargo.toml
//   copy rust\target\release\xmc_device_auth.dll windows\runner\（脚本已处理）

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/node_device.dart';
import 'package:irix/services/device_auth.dart';

/// base64url 无填充编码。
String b64u(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll(RegExp(r'=+$'), '');

/// base64url 无填充解码（自动补填充）。
Uint8List unb64u(String text) {
  final normalized = text.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + (4 - normalized.length % 4) % 4,
    '=',
  );
  return Uint8List.fromList(base64.decode(padded));
}

/// 小写 hex。
String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final auth = DeviceAuthService.instance;
  late Directory keyDir;

  setUpAll(() async {
    keyDir = await Directory.systemTemp.createTemp('xmc_device_auth_it_');
    await auth.initForTesting(keyDir.path);
  });

  tearDownAll(() async {
    try {
      await keyDir.delete(recursive: true);
    } catch (_) {
      // 文件可能仍被占用（Windows），临时目录留给系统清理。
    }
  });

  test('动态库自检通过（含密钥载体往返）', () {
    final report = DeviceAuthFfi.instance.call('self_test');
    expect(report['ok'], isTrue, reason: '自检项: ${report['checks']}');
    final checks = (report['checks'] as List).cast<Map<String, dynamic>>();
    expect(checks, isNotEmpty);
    for (final check in checks) {
      expect(check['ok'], isTrue, reason: '自检项 ${check['check']} 失败');
    }
  });

  test('密钥载体如实上报：Windows 为 os-keychain，其他平台为 file', () {
    final report = DeviceAuthFfi.instance.call('self_test');
    final protection = report['keyProtection'] as String;
    if (Platform.isWindows) {
      expect(protection, 'os-keychain', reason: 'Windows 应使用 DPAPI 保护私钥');
    } else {
      expect(protection, 'file');
    }
  });

  test('ed25519：deviceId 符合协议公式，签名可被独立验证', () async {
    await auth.deleteKey();
    final key = await auth.ensureKey(keyType: 'ed25519');
    expect(key.created, isTrue);
    expect(key.keyType, 'ed25519');

    final publicKey = unb64u(key.publicKey);
    expect(publicKey.length, 32, reason: 'ed25519 原始公钥为 32 字节');

    final digest = await Sha256().hash(publicKey);
    final expectedDeviceId = hex(digest.bytes).substring(0, 32);
    expect(key.deviceId, expectedDeviceId, reason: 'deviceId 必须是公钥哈希前 32 位 hex');
    expect(key.deviceId.length, 32);
    expect(key.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));

    // 再次调用不应重建密钥（deviceId 稳定，否则已绑定设备会全部失效）。
    final again = await auth.ensureKey();
    expect(again.created, isFalse);
    expect(again.deviceId, key.deviceId);

    const message = 'irix-device-login-v1\nalice\n<nonce>\n1790000000\n<proofKey>\n';
    final signature = unb64u(await auth.sign(message));
    expect(signature.length, 64, reason: 'ed25519 原始签名为 64 字节');

    final ok = await Ed25519().verify(
      utf8.encode(message),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    expect(ok, isTrue, reason: '签名必须能用本机公钥验证');

    // 篡改一个字节后必须验证失败（确认验签真的在验内容）。
    final tampered = Uint8List.fromList(utf8.encode(message));
    tampered[0] ^= 0xff;
    final bad = await Ed25519().verify(
      tampered,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    expect(bad, isFalse);
  });

  test('p256：公钥为未压缩点，签名为 64 字节 P1363', () async {
    await auth.deleteKey();
    final key = await auth.ensureKey(keyType: 'p256');
    expect(key.keyType, 'p256');
    final publicKey = unb64u(key.publicKey);
    expect([33, 65], contains(publicKey.length));
    if (publicKey.length == 65) {
      expect(publicKey.first, 0x04, reason: '未压缩点以 0x04 开头');
    }
    final digest = await Sha256().hash(publicKey);
    expect(key.deviceId, hex(digest.bytes).substring(0, 32));

    final signature = unb64u(await auth.sign('irix-proof-v1\nGET\n/x\n1\n1'));
    expect(signature.length, 64, reason: 'r||s（P1363）为 64 字节，非 DER');
  });

  test('HMAC-SHA256 与独立实现一致', () async {
    final key = b64u(List<int>.generate(32, (i) => i));
    const message = 'irix-proof-v1\nGET\n/api/overview\n1790000000\n1';
    final mac = await auth.hmacSha256(proofKey: key, message: message);
    final expected = await Hmac.sha256().calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(unb64u(key)),
    );
    expect(mac, b64u(expected.bytes));
  });

  test('SHA-256 与安全随机数', () async {
    final digest = await auth.sha256Hex('abc');
    expect(
      digest,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    final a = await auth.randomB64Url(32);
    final b = await auth.randomB64Url(32);
    expect(unb64u(a).length, 32);
    expect(a, isNot(b), reason: '两次随机数不应相同');
    expect(a.contains('='), isFalse, reason: 'base64url 必须无填充');
  });

  test('绑定记录可持久化（本进程内）', () async {
    await auth.deleteKey(clearBindings: true);
    expect(await auth.bindingFor('node-1'), isNull);

    final key = await auth.ensureKey();
    await auth.saveBinding(_bindingOf(key, 'node-1'));
    final loaded = await auth.bindingFor('node-1');
    expect(loaded, isNotNull);
    expect(loaded!.deviceId, key.deviceId);
    expect(loaded.username, 'alice');
    expect(loaded.tlsFingerprint, 'aa');

    await auth.removeBinding('node-1');
    expect(await auth.bindingFor('node-1'), isNull);
  });

  test('删除密钥同时清空绑定记录', () async {
    final key = await auth.ensureKey();
    await auth.saveBinding(_bindingOf(key, 'node-2'));
    expect(await auth.bindingFor('node-2'), isNotNull);
    await auth.deleteKey();
    expect(await auth.bindingFor('node-2'), isNull);
    expect(await auth.keyStatus(), isNull);
  });
}

/// 构造测试用绑定记录（只带流程需要的最小字段）。
NodeDeviceBinding _bindingOf(DeviceKeyInfo key, String nodeId) {
  return NodeDeviceBinding(
    nodeId: nodeId,
    deviceId: key.deviceId,
    username: 'alice',
    keyType: key.keyType,
    keyProtection: key.keyProtection,
    tlsFingerprint: 'aa',
    boundAt: DateTime.now().millisecondsSinceEpoch,
    deviceName: '测试设备',
  );
}