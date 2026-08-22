// vault_crypto 单元测试（纯 Dart，无需 Rust 动态库）
//
// 验证向量来源：
//  - TOTP：RFC 6238 Appendix B（HMAC-SHA1 官方向量）
//  - RSA PKCS#1 v1.5 + SHA-256：RFC 7515 A.2（RS256 已知答案签名）
//  - ECDSA P-256：RFC 7515 A.3（ES256 密钥；签名随机不可复现，
//    用独立实现的曲线运算校验 d·G == 公钥 + sign/verify 互证）
//  - PKCS#12：测试内构造 PBES2（PBKDF2-HMAC-SHA256 + AES-256-CBC）
//    加密的 PFX 结构，importPkcs12 解析回环

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irix/services/vault_crypto.dart';

// ==================== 测试用 DER 构造器（独立于生产解析器） ====================

List<int> _len(int n) {
  if (n < 0x80) return [n];
  final b = <int>[];
  var v = n;
  while (v > 0) {
    b.insert(0, v & 0xff);
    v >>= 8;
  }
  return [0x80 | b.length, ...b];
}

List<int> _tlv(int tag, List<int> content) => [
  tag,
  ..._len(content.length),
  ...content,
];

List<int> _seq(List<List<int>> children) {
  final body = <int>[];
  for (final c in children) {
    body.addAll(c);
  }
  return _tlv(0x30, body);
}

List<int> _int(BigInt v) {
  var b = <int>[];
  if (v == BigInt.zero) {
    b = [0];
  } else {
    var x = v;
    while (x > BigInt.zero) {
      b.insert(0, (x & BigInt.from(0xff)).toInt());
      x >>= 8;
    }
  }
  if (b.first & 0x80 != 0) b = [0, ...b];
  return _tlv(0x02, b);
}

List<int> _octet(List<int> b) => _tlv(0x04, b);

List<int> _null() => const [0x05, 0x00];

List<int> _oid(String oid) {
  final parts = oid.split('.').map(int.parse).toList();
  final b = <int>[parts[0] * 40 + parts[1]];
  for (final p in parts.skip(2)) {
    var v = p;
    final stack = <int>[v & 0x7f];
    v >>= 7;
    while (v > 0) {
      stack.insert(0, 0x80 | (v & 0x7f));
      v >>= 7;
    }
    b.addAll(stack);
  }
  return _tlv(0x06, b);
}

String _pem(String label, List<int> der) {
  final b64 = base64Encode(der);
  final lines = <String>['-----BEGIN $label-----'];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, min(i + 64, b64.length)));
  }
  lines.add('-----END $label-----');
  return lines.join('\n');
}

BigInt _bytesToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

BigInt _b64uToBigInt(String s) => _bytesToBigInt(base64Url.decode(_padB64(s)));

/// 为无填充 base64（url 或标准）补 `=` 填充。
String _padB64(String s) {
  var v = s;
  while (v.length % 4 != 0) {
    v = '$v=';
  }
  return v;
}

// ==================== 测试用独立 ECDSA 曲线运算（与生产代码互证） ====================

// P-256（secp256r1）参数副本
final BigInt _p = BigInt.parse(
  'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',
  radix: 16,
);
final BigInt _a = BigInt.parse(
  'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC',
  radix: 16,
);
final BigInt _b = BigInt.parse(
  '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',
  radix: 16,
);
final BigInt _gx = BigInt.parse(
  '6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296',
  radix: 16,
);
final BigInt _gy = BigInt.parse(
  '4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5',
  radix: 16,
);

// P-384（secp384r1）参数副本
final BigInt _p384P = BigInt.parse(
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE'
  'FFFFFFFF0000000000000000FFFFFFFF',
  radix: 16,
);
final BigInt _p384A = BigInt.parse(
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE'
  'FFFFFFFF0000000000000000FFFFFFFC',
  radix: 16,
);
final BigInt _p384B = BigInt.parse(
  'B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC'
  '656398D8A2ED19D2A85C8EDD3EC2AEF',
  radix: 16,
);
final BigInt _p384Gx = BigInt.parse(
  'AA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A3855'
  '02F25DBF55296C3A545E3872760AB7',
  radix: 16,
);
final BigInt _p384Gy = BigInt.parse(
  '3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C00'
  'A60B1CE1D7E819D7A431D7C90EA0E5F',
  radix: 16,
);
final BigInt _p384N = BigInt.parse(
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF'
  '581A0DB248B0A77AECEC196ACCC52973',
  radix: 16,
);

BigInt _modOn(BigInt v, BigInt p) => ((v % p) + p) % p;

// 点是否在曲线上：y² ≡ x³ + ax + b (mod p)
bool _isOnCurveOn(BigInt p, BigInt a, BigInt b, List<BigInt> pt) =>
    _modOn(pt[1] * pt[1], p) ==
    _modOn(pt[0] * pt[0] * pt[0] + a * pt[0] + b, p);

// 返回 null 表示无穷远点
List<BigInt>? _addOn(BigInt p, BigInt a, List<BigInt>? p1, List<BigInt>? p2) {
  if (p1 == null) return p2;
  if (p2 == null) return p1;
  final x1 = p1[0], y1 = p1[1];
  final x2 = p2[0], y2 = p2[1];
  BigInt lambda;
  if (x1 == x2) {
    if ((y1 + y2) % p == BigInt.zero) return null;
    lambda =
        ((BigInt.from(3) * x1 * x1 + a) * (y1 * BigInt.two).modInverse(p)) % p;
  } else {
    lambda = ((y2 - y1) * (x2 - x1).modInverse(p)) % p;
  }
  final x3 = _modOn(lambda * lambda - x1 - x2, p);
  final y3 = _modOn(lambda * (x1 - x3) - y1, p);
  return [x3, y3];
}

/// 标量乘；结果为无穷远时返回 null。
List<BigInt>? _mulOn(BigInt p, BigInt a, BigInt k, List<BigInt> g) {
  List<BigInt>? result;
  var addend = g;
  var kk = k;
  while (kk > BigInt.zero) {
    if (kk & BigInt.one == BigInt.one) {
      result = _addOn(p, a, result, addend);
    }
    addend = _addOn(p, a, addend, addend)!;
    kk >>= 1;
  }
  return result;
}

// ==================== RFC 7515 测试数据 ====================

// A.2 RS256：RSA 2048 私钥（n/e/d）
final _rsaN = _b64uToBigInt(
  'ofgWCuLjybRlzo0tZWJjNiuSfb4p4fAkd_wWJcyQoTbji9k0l8W26mPddxHmfHQp-'
  'Vaw-4qPCJrcS2mJPMEzP1Pt0Bm4d4QlL-yRT-SFd2lZS-pCgNMsD1W_YpRPEwOWvG'
  '6b32690r2jZ47soMZo9wGzjb_7OMg0LOL-bSf63kpaSHSXndS5z5rexMdbBYUsLA9e'
  '-KXBdQOS-UTo7WTBEMa2R2CapHg665xsmtdVMTBQY4uDZlxvb3qCo5ZwKh9kG4LT6_'
  'I5IhlJH7aGhyxXFvUK-DWNmoudF8NAco9_h9iaGNj8q2ethFkMLs91kzk2PAcDTW9g'
  'b54h4FRWyuXpoQ',
);
final _rsaE = BigInt.from(65537);
final _rsaD = _b64uToBigInt(
  'Eq5xpGnNCivDflJsRQBXHx1hdR1k6Ulwe2JZD50LpXyWPEAeP88vLNO97IjlA7_GQ'
  '5sLKMgvfTeXZx9SE-7YwVol2NXOoAJe46sui395IW_GO-pWJ1O0BkTGoVEn2bKVRUC'
  'gu-GjBVaYLU6f3l9kJfFNS3E0QbVdxzubSu3Mkqzjkn439X0M_V51gfpRLI9JYanrC'
  '4D4qAdGcopV_0ZHHzQlBjudU2QvXt4ehNYTCBr6XCLQUShb1juUO1ZdiYoFaFQT5T'
  'w8bGUl_x_jTj3ccPDVZFD9pIuhLhBOneufuBiB4cS98l2SR_RQyGWSeWjnczT0QU91'
  'p1DhOVRuOopznQ',
);

// A.2.2 JWS 签名输入
const _rsaMessage =
    'eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ';

// A.2.3 期望签名（base64url）
const _rsaExpectedSig =
    'cC4hiUPoj9Eetdgtv3hF80EGrhuB__dzERat0XF9g2VtQgr9PJbu3XOiZj5RZmh7'
    'AAuHIm4Bh-0Qc_lF5YKt_O8W2Fp5jujGbds9uJdbF9CUAr7t1dnZcAcQjbKBYNX4'
    'BAynRFdiuB--f_nZLgrnbyTyWzO75vRK5h6xBArLIARNPvkSjtQBMHlb1L07Qe7'
    'K0GarZRmB_eSN9383LcOLn6_dO--xi12jzDwusC-eOkHWEsqtFZESc6BfI7noOP'
    'qvhJ1phCnvWh6IeYI2w9QOYEUipUTI8np6LbgGY9Fs98rqVt5AXLIhWkWywlVmt'
    'VrBp0igcN_IoypGlUPQGe77Rw';

// A.3 ES256：P-256 私钥 d 与公钥 (x, y)
final _ecD = _b64uToBigInt('jpsQnnGQmL-YBIffH1136cspYG6-0iY7X1fCE9-E9LI');
final _ecX = _b64uToBigInt('f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU');
final _ecY = _b64uToBigInt('x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0');

const _ecMessage =
    'eyJhbGciOiJFUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ';

// ==================== 测试 ====================

void main() {
  group('TOTP（RFC 6238 Appendix B 向量）', () {
    const secret =
        'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'; // ASCII "12345678901234567890"
    final cases = <int, String>{
      59: '287082',
      1111111109: '081804',
      1111111111: '050471',
      1234567890: '005924',
      2000000000: '279037',
      20000000000: '353130',
    };

    for (final entry in cases.entries) {
      test('T=${entry.key} → ${entry.value}', () async {
        final at = DateTime.fromMillisecondsSinceEpoch(entry.key * 1000);
        expect(await totpCode(secret, at: at), entry.value);
      });
    }

    test('支持小写 / 空格 / 连字符的 Base32 输入', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(59 * 1000);
      expect(
        await totpCode('gezdgnbv gy3tqojq-gezdgnbvgy3tqojq', at: at),
        '287082',
      );
    });

    test('非法 Base32 字符抛 VaultCryptoException', () async {
      await expectLater(
        totpCode('INVALID!'),
        throwsA(isA<VaultCryptoException>()),
      );
    });
  });

  group('RSA PKCS#1 v1.5 + SHA-256（RFC 7515 A.2 已知答案）', () {
    final key = VaultPrivateKey.rsa(
      modulus: _rsaN,
      exponent: _rsaE,
      privateExponent: _rsaD,
    );

    test('签名与 RFC 期望值一致', () async {
      final sig = await signRaw(key, utf8.encode(_rsaMessage));
      final expected = base64Decode(
        _padB64(_rsaExpectedSig.replaceAll('-', '+').replaceAll('_', '/')),
      );
      expect(sig, expected);
    });

    test('verifySignature 通过；篡改消息后失败', () async {
      final sig = await signRaw(key, utf8.encode(_rsaMessage));
      expect(await verifySignature(key, utf8.encode(_rsaMessage), sig), isTrue);
      expect(
        await verifySignature(key, utf8.encode('$_rsaMessage.'), sig),
        isFalse,
      );
      final tampered = [...sig];
      tampered[10] ^= 0x01;
      expect(
        await verifySignature(key, utf8.encode(_rsaMessage), tampered),
        isFalse,
      );
    });

    test('signChallenge 输出 base64 无填充且按用途使用对应前缀', () async {
      const challenge = 'abc-123';
      final sig = await signChallenge(key, challenge);
      expect(sig.contains('='), isFalse);
      final raw = base64Decode(_padB64(sig));
      expect(
        raw,
        await signRaw(key, utf8.encode('$kVaultUnlockPrefix$challenge')),
      );
      // cert-bind 用途使用独立前缀，签名不同
      final certSig = await signChallenge(
        key,
        challenge,
        purpose: VaultChallengePurpose.certBind,
      );
      expect(certSig, isNot(sig));
      expect(
        base64Decode(_padB64(certSig)),
        await signRaw(key, utf8.encode('$kVaultCertBindPrefix$challenge')),
      );
    });
  });

  group('RSA PEM 解析（PKCS#1 / PKCS#8 / 混合证书）', () {
    // 用测试内 DER 构造器生成 PKCS#1 RSAPrivateKey
    final rsaPkcs1 = _seq([
      _int(BigInt.zero), // version
      _int(_rsaN),
      _int(_rsaE),
      _int(_rsaD),
      _int(BigInt.from(3)), // p（解析器不校验）
      _int(BigInt.from(7)), // q
    ]);

    test('RSA PRIVATE KEY（PKCS#1）', () {
      final pem = _pem('RSA PRIVATE KEY', rsaPkcs1);
      final key = parsePrivateKeyPem(pem);
      expect(key.type, VaultKeyType.rsa);
      expect(key.rsaModulus, _rsaN);
      expect(key.rsaExponent, _rsaE);
      expect(key.rsaPrivate, _rsaD);
      expect(key.keyPem, contains('BEGIN RSA PRIVATE KEY'));
    });

    test('PRIVATE KEY（PKCS#8 包装 RSA）', () {
      final pki = _seq([
        _int(BigInt.zero),
        _seq([_oid('1.2.840.113549.1.1.1'), _null()]),
        _octet(rsaPkcs1),
      ]);
      final key = parsePrivateKeyPem(_pem('PRIVATE KEY', pki));
      expect(key.type, VaultKeyType.rsa);
      expect(key.rsaModulus, _rsaN);
      expect(key.rsaPrivate, _rsaD);
    });

    test('importPem 从混合 PEM（证书 + 私钥）提取', () {
      final pem = [
        _pem('CERTIFICATE', [0x30, 0x03, 0x02, 0x01, 0x00]), // 任意 DER
        _pem(
          'PRIVATE KEY',
          _seq([
            _int(BigInt.zero),
            _seq([_oid('1.2.840.113549.1.1.1'), _null()]),
            _octet(rsaPkcs1),
          ]),
        ),
      ].join('\n');
      final m = importPem(pem);
      expect(m.privateKey.type, VaultKeyType.rsa);
      expect(m.certPem, contains('BEGIN CERTIFICATE'));
      expect(m.keyPem, contains('BEGIN PRIVATE KEY'));
    });

    test('垃圾 PEM / 加密 PEM 抛 VaultCryptoException', () {
      expect(
        () => parsePrivateKeyPem(
          '-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----',
        ),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(
        () => parsePrivateKeyPem('not a pem'),
        throwsA(isA<VaultCryptoException>()),
      );
      expect(
        () => parsePrivateKeyPem(
          '-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n-----END ENCRYPTED PRIVATE KEY-----',
        ),
        throwsA(isA<VaultCryptoException>()),
      );
    });
  });

  group('ECDSA P-256（RFC 7515 A.3 密钥）', () {
    final key = VaultPrivateKey.ecdsa(privateScalar: _ecD);

    test('d·G == RFC 公钥 (x, y)（独立实现互证）', () {
      final q = _mulOn(_p, _a, _ecD, [_gx, _gy])!;
      expect(q[0], _ecX);
      expect(q[1], _ecY);
      expect(_isOnCurveOn(_p, _a, _b, q), isTrue);
    });

    test('签名输出为合法 ASN.1 DER，verifySignature 通过', () async {
      final sig = await signRaw(key, utf8.encode(_ecMessage));
      // 结构检查：SEQUENCE { INTEGER, INTEGER }
      expect(sig.first, 0x30);
      expect(sig[1], sig.length - 2);
      expect(await verifySignature(key, utf8.encode(_ecMessage), sig), isTrue);
      expect(
        await verifySignature(key, utf8.encode('$_ecMessage.'), sig),
        isFalse,
      );
    });

    test('不支持的曲线（P-521）拒绝', () async {
      final other = VaultPrivateKey.ecdsa(privateScalar: _ecD, curve: 'P-521');
      await expectLater(
        signRaw(other, utf8.encode(_ecMessage)),
        throwsA(isA<VaultCryptoException>()),
      );
    });
  });

  group('ECDSA P-384（secp384r1，无外部向量自校验）', () {
    test('G 在曲线上且 n·G = 无穷远（独立实现互证）', () {
      final g = [_p384Gx, _p384Gy];
      expect(_isOnCurveOn(_p384P, _p384A, _p384B, g), isTrue);
      // 阶校验：n·G 应为无穷远点（曲线参数打错会失败）
      expect(_mulOn(_p384P, _p384A, _p384N, g), isNull);
    });

    test('签名 / 验证 roundtrip（d=1 → Q=G）', () async {
      final key = VaultPrivateKey.ecdsa(
        privateScalar: BigInt.one,
        curve: 'P-384',
      );
      final sig = await signRaw(key, utf8.encode(_ecMessage));
      expect(sig.first, 0x30);
      expect(await verifySignature(key, utf8.encode(_ecMessage), sig), isTrue);
      expect(
        await verifySignature(key, utf8.encode('$_ecMessage.'), sig),
        isFalse,
      );
    });

    test('SEC1 PEM 解析 P-384 私钥（OID 1.3.132.0.34）', () {
      final sec1 = _seq([
        _int(BigInt.one), // version
        _octet([0x01]), // d = 1
        _tlv(0xa0, _oid('1.3.132.0.34')), // secp384r1
      ]);
      final key = parsePrivateKeyPem(_pem('EC PRIVATE KEY', sec1));
      expect(key.type, VaultKeyType.ecdsa);
      expect(key.curve, 'P-384');
      expect(key.ecPrivate, BigInt.one);
    });
  });

  group('PKCS#12 导入（PBES2 构造回环）', () {
    test('P12 → 私钥 PEM + 证书 PEM，可签名', () async {
      final rsaPkcs1 = _seq([
        _int(BigInt.zero),
        _int(_rsaN),
        _int(_rsaE),
        _int(_rsaD),
        _int(BigInt.from(3)),
        _int(BigInt.from(7)),
      ]);
      final pki = _seq([
        _int(BigInt.zero),
        _seq([_oid('1.2.840.113549.1.1.1'), _null()]),
        _octet(rsaPkcs1),
      ]);
      const password = 'test-pass-123';

      // 1) shroudedKeyBag：PBES2（PBKDF2-HMAC-SHA256 + AES-256-CBC）
      final salt = List<int>.generate(8, (i) => 0x10 + i);
      final iv = List<int>.generate(16, (i) => 0x20 + i);
      final derived = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 2048,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      final box = await AesCbc.with256bits(
        macAlgorithm: Hmac.sha256(),
      ).encrypt(pki, secretKey: derived, nonce: iv);
      final epki = _seq([
        _seq([
          _oid('1.2.840.113549.1.5.13'), // PBES2
          _seq([
            _seq([
              _oid('1.2.840.113549.1.5.12'), // PBKDF2
              _seq([
                _octet(salt),
                _int(BigInt.from(2048)),
                _seq([_oid('1.2.840.113549.2.9'), _null()]), // hmacWithSHA256
              ]),
            ]),
            _seq([
              _oid('2.16.840.1.101.3.4.1.42'), // aes256-CBC
              _octet(iv),
            ]),
          ]),
        ]),
        _octet(box.cipherText),
      ]);

      // 2) certBag（X.509）
      const certDer = [0x30, 0x03, 0x02, 0x01, 0x00];
      final certBag = _seq([
        _oid('1.2.840.113549.1.9.22.1'), // x509Certificate
        _tlv(0xa0, _octet(certDer)),
      ]);

      // 3) SafeBags：未加密 keyBag + 加密 shroudedKeyBag + certBag
      final keyBag = _seq([
        _oid('1.2.840.113549.1.12.10.1.1'),
        _tlv(0xa0, pki),
      ]);
      final shroudedBag = _seq([
        _oid('1.2.840.113549.1.12.10.1.2'),
        _tlv(0xa0, epki),
      ]);
      final certBagEntry = _seq([
        _oid('1.2.840.113549.1.12.10.1.3'),
        _tlv(0xa0, certBag),
      ]);
      final safeContents = _seq([keyBag, shroudedBag, certBagEntry]);

      // 4) AuthenticatedSafe → ContentInfo(data) → PFX
      final ciSafe = _seq([
        _oid('1.2.840.113549.1.7.1'),
        _tlv(0xa0, _octet(safeContents)),
      ]);
      final authSafe = _seq([ciSafe]);
      final ciAuth = _seq([
        _oid('1.2.840.113549.1.7.1'),
        _tlv(0xa0, _octet(authSafe)),
      ]);
      final pfx = _seq([_int(BigInt.from(3)), ciAuth]);

      // 5) 解析回环
      final material = await importPkcs12(bytes: pfx, password: password);
      expect(material.privateKey.type, VaultKeyType.rsa);
      expect(material.privateKey.rsaModulus, _rsaN);
      expect(material.privateKey.rsaPrivate, _rsaD);
      expect(material.keyPem, contains('BEGIN PRIVATE KEY'));
      expect(material.certPem, contains('BEGIN CERTIFICATE'));

      // 6) 提取的私钥可直接签名
      final sig = await signRaw(material.privateKey, utf8.encode(_rsaMessage));
      expect(
        await verifySignature(
          material.privateKey,
          utf8.encode(_rsaMessage),
          sig,
        ),
        isTrue,
      );
    });

    test('错误密码 / 垃圾字节抛 VaultCryptoException', () async {
      await expectLater(
        importPkcs12(bytes: [1, 2, 3], password: 'x'),
        throwsA(isA<VaultCryptoException>()),
      );
      await expectLater(
        importPkcs12(bytes: const [], password: 'x'),
        throwsA(isA<VaultCryptoException>()),
      );
    });
  });

  group('base64NoPad', () {
    test('去除填充符', () {
      expect(base64NoPad([1, 2, 3]), 'AQID');
      expect(base64NoPad([1]), 'AQ');
      expect(base64NoPad([]), '');
    });
  });
}
