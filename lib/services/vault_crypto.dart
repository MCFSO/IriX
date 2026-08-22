// 加密保险库 Vault 客户端密码学工具（docs/vault-design.md §5–§7 客户端对接要点）
//
// 职责（私钥永不上送：仅在本进程内用于挑战签名）：
//  1. 证书 / 密钥导入：P12（PKCS#12）→ PEM；PEM（PKCS#1 / PKCS#8 / SEC1）直接导入
//  2. 挑战签名：RSA PKCS#1 v1.5 + SHA-256 / ECDSA（P-256 / P-384）+ SHA-256
//     （ASN.1 DER 输出），签名消息 = 分用途前缀 + 挑战字符串（§7.1 定案）
//  3. TOTP 动态码（RFC 6238，HMAC-SHA1）
//
// 实现说明：
//  - 纯 Dart 实现，不新增依赖；RSA 用 dart:core BigInt（modPow），
//    ECDSA 用 BigInt 曲线运算（cryptography 包的纯 Dart RSA/ECDSA
//    实现抛 UnimplementedError，仅浏览器可用，桌面端不可依赖）。
//  - HMAC / SHA-256 / PBKDF2 / AES-CBC 复用 package:cryptography 的
//    纯 Dart 实现（DartHmac / DartPbkdf2 / DartAesCbc）。
//  - P12 仅支持 PBES2（PBKDF2-HMAC-SHA1/SHA256 + AES-128/192/256-CBC），
//    即 OpenSSL 3.x / 现代浏览器导出的默认格式；旧式
//    pbeWithSHA1And3-KeyTripleDES-CBC 等 PKCS#12 v1 PBE 返回明确错误。
//  - GPG 证书不在本期（vault-design.md §12）：只支持标准 PEM/X.509，
//    P12 由客户端转换后导入。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 解锁挑战签名消息前缀（与 irix-node 服务端约定，docs/vault-design.md §7.1）。
///
/// 签名消息 = 前缀 + 挑战字符串（UTF-8 编码后签名，base64 无填充输出）。
/// 前缀按用途区分（S4），两端必须一致，修改需服务端同步。
const kVaultUnlockPrefix = 'IRIX-VAULT-UNLOCK:1:';

/// 证书绑定挑战签名消息前缀（同上）。
const kVaultCertBindPrefix = 'IRIX-VAULT-CERT-BIND:1:';

/// 挑战用途（对应 `POST /api/vault/challenge` 的 purpose 字段，
/// 与签名前缀一一对应，docs/vault-design.md §10）。
enum VaultChallengePurpose {
  /// 解锁：`IRIX-VAULT-UNLOCK:1:` + challenge。
  unlock(kVaultUnlockPrefix, 'unlock'),

  /// 绑定 / 换绑证书：`IRIX-VAULT-CERT-BIND:1:` + challenge。
  certBind(kVaultCertBindPrefix, 'cert-bind');

  const VaultChallengePurpose(this.prefix, this.apiValue);

  /// 签名消息前缀。
  final String prefix;

  /// API purpose 字段值。
  final String apiValue;
}

/// 保险库密码学异常（导入 / 解析 / 签名失败时抛出）。
class VaultCryptoException implements Exception {
  final String message;

  const VaultCryptoException(this.message);

  @override
  String toString() => message;
}

// ==================== PEM ====================

/// 一个 PEM 块（label + DER 字节）。
class PemBlock {
  final String label;
  final List<int> bytes;

  const PemBlock({required this.label, required this.bytes});
}

/// 解析 PEM 文本中的全部块（`-----BEGIN X----- ... -----END X-----`）。
List<PemBlock> parsePemBlocks(String pem) {
  final blocks = <PemBlock>[];
  final re = RegExp(
    r'-----BEGIN ([A-Z0-9 ]+)-----(.*?)-----END \1-----',
    dotAll: true,
  );
  for (final m in re.allMatches(pem)) {
    final body = m.group(2)!.replaceAll(RegExp(r'\s'), '');
    try {
      blocks.add(PemBlock(label: m.group(1)!, bytes: base64Decode(body)));
    } on FormatException {
      throw const VaultCryptoException('PEM 内容不是合法 Base64');
    }
  }
  if (blocks.isEmpty) {
    throw const VaultCryptoException('未找到 PEM 块');
  }
  return blocks;
}

String _pemWrap(String label, List<int> der) {
  final b64 = base64Encode(der);
  final lines = <String>['-----BEGIN $label-----'];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, min(i + 64, b64.length)));
  }
  lines.add('-----END $label-----');
  return lines.join('\n');
}

// ==================== DER（TLV）解析 ====================

class _Der {
  final int tag;

  /// 载荷字节（不含 tag / 长度头）。
  final List<int> content;

  /// 完整 TLV 字节（含 tag / 长度头）。
  final List<int> full;

  const _Der(this.tag, this.content, this.full);

  /// 解析 content 为子 TLV 序列。
  List<_Der> get children {
    final list = <_Der>[];
    var off = 0;
    while (off < content.length) {
      final (node, next) = _readTlv(content, off);
      list.add(node);
      off = next;
    }
    return list;
  }
}

(_Der, int) _readTlv(List<int> bytes, int offset) {
  var pos = offset;
  if (pos >= bytes.length) {
    throw const VaultCryptoException('DER 数据截断');
  }
  final tag = bytes[pos++];
  var len = bytes[pos++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    if (n == 0 || pos + n > bytes.length) {
      throw const VaultCryptoException('DER 长度非法');
    }
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | bytes[pos++];
    }
  }
  if (pos + len > bytes.length) {
    throw const VaultCryptoException('DER 数据截断');
  }
  final start = pos;
  final end = pos + len;
  return (
    _Der(tag, bytes.sublist(start, end), bytes.sublist(offset, end)),
    end,
  );
}

BigInt _derInt(_Der node) {
  final b = node.content;
  if (b.isEmpty) return BigInt.zero;
  final neg = b[0] & 0x80 != 0;
  var v = BigInt.zero;
  for (final x in b) {
    v = (v << 8) | BigInt.from(x);
  }
  if (neg) v -= BigInt.one << (b.length * 8);
  return v;
}

String _derOid(_Der node) {
  final b = node.content;
  if (b.isEmpty) return '';
  final parts = <int>[b[0] ~/ 40, b[0] % 40];
  var v = 0;
  for (var i = 1; i < b.length; i++) {
    v = (v << 7) | (b[i] & 0x7f);
    if (b[i] & 0x80 == 0) {
      parts.add(v);
      v = 0;
    }
  }
  return parts.join('.');
}

// ==================== 大整数字节转换 ====================

BigInt _bytesToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

/// 无符号大整数 → 定长大端字节（I2OSP）。
List<int> _bigIntToBytes(BigInt v, int length) {
  final out = List<int>.filled(length, 0);
  var i = length - 1;
  var x = v;
  while (x > BigInt.zero && i >= 0) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
    i--;
  }
  return out;
}

/// Base64 无填充（签名格式约定）。
String base64NoPad(List<int> bytes) => base64Encode(bytes).replaceAll('=', '');

// ==================== 私钥模型 ====================

enum VaultKeyType { rsa, ecdsa }

/// 客户端持有的私钥（从 PEM / P12 解析，仅内存使用，不持久化）。
class VaultPrivateKey {
  final VaultKeyType type;

  /// RSA 参数（type == rsa）。
  final BigInt? rsaModulus;
  final BigInt? rsaExponent;
  final BigInt? rsaPrivate;

  /// ECDSA 私钥标量 d（type == ecdsa）。
  final BigInt? ecPrivate;

  /// 曲线名（`P-256` / `P-384`）。
  final String curve;

  /// 私钥 PKCS#8 PEM 文本（P12 提取时生成；私钥敏感，勿持久化）。
  final String? keyPem;

  const VaultPrivateKey._({
    required this.type,
    this.rsaModulus,
    this.rsaExponent,
    this.rsaPrivate,
    this.ecPrivate,
    this.curve = 'P-256',
    this.keyPem,
  });

  factory VaultPrivateKey.rsa({
    required BigInt modulus,
    required BigInt exponent,
    required BigInt privateExponent,
    String? keyPem,
  }) {
    return VaultPrivateKey._(
      type: VaultKeyType.rsa,
      rsaModulus: modulus,
      rsaExponent: exponent,
      rsaPrivate: privateExponent,
      keyPem: keyPem,
    );
  }

  factory VaultPrivateKey.ecdsa({
    required BigInt privateScalar,
    String curve = 'P-256',
    String? keyPem,
  }) {
    return VaultPrivateKey._(
      type: VaultKeyType.ecdsa,
      ecPrivate: privateScalar,
      curve: curve,
      keyPem: keyPem,
    );
  }
}

/// 导入结果：私钥 + 可选证书 PEM（cert-bind 上传用）。
class VaultKeyMaterial {
  final VaultPrivateKey privateKey;

  /// 私钥 PEM（PKCS#8 或原始格式；敏感，勿持久化）。
  final String? keyPem;

  /// X.509 证书 PEM（POST /api/vault/cert 的 certPem 字段）。
  final String? certPem;

  const VaultKeyMaterial({required this.privateKey, this.keyPem, this.certPem});
}

// ==================== 私钥解析 ====================

const _oidRsaEncryption = '1.2.840.113549.1.1.1';
const _oidEcPublicKey = '1.2.840.10045.2.1';
const _oidPrime256v1 = '1.2.840.10045.3.1.7';
const _oidSecp384r1 = '1.3.132.0.34';

/// 解析 PEM 私钥（支持 `RSA PRIVATE KEY` / `PRIVATE KEY` / `EC PRIVATE KEY`）。
VaultPrivateKey parsePrivateKeyPem(String pem) {
  final blocks = parsePemBlocks(pem);
  for (final b in blocks) {
    switch (b.label) {
      case 'RSA PRIVATE KEY':
        return _parseRsaPkcs1(b.bytes, _pemWrap(b.label, b.bytes));
      case 'PRIVATE KEY':
        return _parsePkcs8(b.bytes, _pemWrap(b.label, b.bytes));
      case 'EC PRIVATE KEY':
        return _parseSec1(b.bytes, _pemWrap(b.label, b.bytes));
      case 'ENCRYPTED PRIVATE KEY':
        throw const VaultCryptoException(
          '私钥已加密，请先解密为 PEM（如 openssl pkcs8 -in key.pem -nocrypt）',
        );
    }
  }
  throw const VaultCryptoException('未找到可识别的私钥 PEM 块');
}

/// 解析带密码的 PEM 私钥（`ENCRYPTED PRIVATE KEY`，PBES2 子集）。
Future<VaultPrivateKey> parseEncryptedPrivateKeyPem(
  String pem,
  String password,
) async {
  final blocks = parsePemBlocks(pem);
  for (final b in blocks) {
    if (b.label != 'ENCRYPTED PRIVATE KEY') continue;
    final (epki, _) = _readTlv(b.bytes, 0);
    final pki = await _decryptEncryptedPrivateKeyInfo(epki, password);
    return _parsePkcs8(pki, _pemWrap('PRIVATE KEY', pki));
  }
  throw const VaultCryptoException('未找到 ENCRYPTED PRIVATE KEY 块');
}

/// PKCS#1 RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, ... }。
VaultPrivateKey _parseRsaPkcs1(List<int> der, String keyPem) {
  final (node, _) = _readTlv(der, 0);
  if (node.tag != 0x30 || node.children.length < 4) {
    throw const VaultCryptoException('RSA PKCS#1 私钥结构非法');
  }
  final kids = node.children;
  return VaultPrivateKey.rsa(
    modulus: _derInt(kids[1]),
    exponent: _derInt(kids[2]),
    privateExponent: _derInt(kids[3]),
    keyPem: keyPem,
  );
}

/// PKCS#8 PrivateKeyInfo ::= SEQUENCE { version, algid, OCTET STRING }。
VaultPrivateKey _parsePkcs8(List<int> der, String keyPem) {
  final (node, _) = _readTlv(der, 0);
  if (node.tag != 0x30 || node.children.length < 3) {
    throw const VaultCryptoException('PKCS#8 私钥结构非法');
  }
  final kids = node.children;
  final algid = kids[1].children;
  final oid = _derOid(algid[0]);
  final inner = kids[2].content;
  switch (oid) {
    case _oidRsaEncryption:
      return _parseRsaPkcs1(inner, keyPem);
    case _oidEcPublicKey:
      return _parseSec1(inner, keyPem);
    default:
      throw VaultCryptoException('不支持的私钥算法（OID $oid）');
  }
}

/// SEC1 ECPrivateKey ::= SEQUENCE { version, privateKey OCTET STRING,
/// [0] parameters OPTIONAL, [1] publicKey OPTIONAL }。
VaultPrivateKey _parseSec1(List<int> der, String keyPem) {
  final (node, _) = _readTlv(der, 0);
  if (node.tag != 0x30 || node.children.length < 2) {
    throw const VaultCryptoException('EC 私钥结构非法');
  }
  final kids = node.children;
  var curve = 'P-256';
  for (final k in kids.skip(2)) {
    if (k.tag == 0xa0) {
      final oid = _derOid(k.children.single);
      curve = switch (oid) {
        _oidPrime256v1 => 'P-256',
        _oidSecp384r1 => 'P-384',
        _ => throw VaultCryptoException('不支持的椭圆曲线（OID $oid，仅支持 P-256 / P-384）'),
      };
    }
  }
  return VaultPrivateKey.ecdsa(
    privateScalar: _derInt(kids[1]),
    curve: curve,
    keyPem: keyPem,
  );
}

/// 从 PEM 文本导入证书 + 私钥（PEM 文件可同时含 CERTIFICATE 与私钥块）。
VaultKeyMaterial importPem(String pem) {
  final blocks = parsePemBlocks(pem);
  String? certPem;
  VaultPrivateKey? key;
  for (final b in blocks) {
    switch (b.label) {
      case 'CERTIFICATE':
        certPem ??= _pemWrap('CERTIFICATE', b.bytes);
      case 'RSA PRIVATE KEY':
      case 'PRIVATE KEY':
      case 'EC PRIVATE KEY':
        key ??= _parseKeyBlock(b);
      case 'ENCRYPTED PRIVATE KEY':
        throw const VaultCryptoException(
          '私钥已加密，请使用 parseEncryptedPrivateKeyPem 或先解密',
        );
    }
  }
  if (key == null) {
    throw const VaultCryptoException('PEM 中未找到私钥');
  }
  return VaultKeyMaterial(
    privateKey: key,
    keyPem: key.keyPem,
    certPem: certPem,
  );
}

VaultPrivateKey _parseKeyBlock(PemBlock b) {
  switch (b.label) {
    case 'RSA PRIVATE KEY':
      return _parseRsaPkcs1(b.bytes, _pemWrap(b.label, b.bytes));
    case 'PRIVATE KEY':
      return _parsePkcs8(b.bytes, _pemWrap(b.label, b.bytes));
    case 'EC PRIVATE KEY':
      return _parseSec1(b.bytes, _pemWrap(b.label, b.bytes));
  }
  throw VaultCryptoException('不支持的私钥块（${b.label}）');
}

// ==================== PKCS#12（P12）导入 ====================

const _oidData = '1.2.840.113549.1.7.1';
const _oidKeyBag = '1.2.840.113549.1.12.10.1.1';
const _oidShroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
const _oidCertBag = '1.2.840.113549.1.12.10.1.3';
const _oidX509Cert = '1.2.840.113549.1.9.22.1';
const _oidPbes2 = '1.2.840.113549.1.5.13';
const _oidPbkdf2 = '1.2.840.113549.1.5.12';
const _oidHmacSha1 = '1.2.840.113549.2.7';
const _oidHmacSha256 = '1.2.840.113549.2.9';
const _oidAes128Cbc = '2.16.840.1.101.3.4.1.2';
const _oidAes192Cbc = '2.16.840.1.101.3.4.1.22';
const _oidAes256Cbc = '2.16.840.1.101.3.4.1.42';

/// 导入 PKCS#12 文件（.p12/.pfx），返回私钥 + 证书 PEM。
///
/// 支持现代 PBES2 加密（OpenSSL 3 / 浏览器导出的默认格式）；
/// 旧式 PKCS#12 v1 PBE（3DES/RC2）抛 [VaultCryptoException]。
Future<VaultKeyMaterial> importPkcs12({
  required List<int> bytes,
  required String password,
}) async {
  final (pfx, _) = _readTlv(bytes, 0);
  if (pfx.tag != 0x30 || pfx.children.length < 2) {
    throw const VaultCryptoException('不是合法的 PKCS#12 文件');
  }
  // PFX ::= SEQUENCE { version INTEGER, authSafe ContentInfo, macData OPTIONAL }
  final authSafe = pfx.children[1];
  final (safeNode, _) = _readTlv(_contentInfoData(authSafe), 0);

  String? keyPem;
  String? certPem;
  for (final ci in safeNode.children) {
    final (sc, _) = _readTlv(_contentInfoData(ci), 0);
    for (final bag in sc.children) {
      final bagKids = bag.children;
      if (bagKids.length < 2) continue;
      final bagOid = _derOid(bagKids[0]);
      final bagValue = bagKids[1]; // [0] EXPLICIT
      switch (bagOid) {
        case _oidKeyBag: // 未加密私钥（PrivateKeyInfo）
          final pki = bagValue.children.single;
          keyPem ??= _pemWrap('PRIVATE KEY', pki.full);
        case _oidShroudedKeyBag: // 加密私钥（EncryptedPrivateKeyInfo）
          final epki = bagValue.children.single;
          final pki = await _decryptEncryptedPrivateKeyInfo(epki, password);
          keyPem ??= _pemWrap('PRIVATE KEY', pki);
        case _oidCertBag:
          final certBag = bagValue.children.single;
          final certKids = certBag.children;
          if (certKids.length >= 2 && _derOid(certKids[0]) == _oidX509Cert) {
            final certValue = certKids[1].children.single; // [0] → OCTET STRING
            certPem ??= _pemWrap('CERTIFICATE', certValue.content);
          }
      }
    }
  }
  if (keyPem == null) {
    throw const VaultCryptoException('P12 中未找到私钥');
  }
  return VaultKeyMaterial(
    privateKey: parsePrivateKeyPem(keyPem),
    keyPem: keyPem,
    certPem: certPem,
  );
}

/// ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT OCTET STRING }。
/// 返回 OCTET STRING 载荷。
List<int> _contentInfoData(_Der node) {
  final kids = node.children;
  if (kids.length < 2 || _derOid(kids[0]) != _oidData) {
    throw const VaultCryptoException('PKCS#12 结构非法（ContentInfo）');
  }
  final content = kids[1];
  if (content.children.length != 1) {
    throw const VaultCryptoException('PKCS#12 结构非法（content）');
  }
  return content.children.single.content;
}

/// 解密 EncryptedPrivateKeyInfo（仅 PBES2：PBKDF2-HMAC-SHA1/SHA256 +
/// AES-128/192/256-CBC），返回 PrivateKeyInfo DER。
Future<List<int>> _decryptEncryptedPrivateKeyInfo(
  _Der epki,
  String password,
) async {
  final kids = epki.children;
  if (kids.length < 2) {
    throw const VaultCryptoException('EncryptedPrivateKeyInfo 结构非法');
  }
  final algid = kids[0].children;
  final oid = _derOid(algid[0]);
  if (oid != _oidPbes2) {
    throw VaultCryptoException(
      '不支持的私钥加密算法（OID $oid）；仅支持 PBES2，'
      '旧式 P12 请用 openssl 转换为 PEM 后导入',
    );
  }
  final params = algid[1].children; // SEQUENCE { kdf PBKDF2-params, encScheme }
  if (params.length < 2) {
    throw const VaultCryptoException('PBES2 参数结构非法');
  }

  // PBKDF2 AlgorithmIdentifier ::= SEQUENCE { OID, PBKDF2-params }
  // PBKDF2-params ::= SEQUENCE { salt OCTET STRING, iterations INTEGER,
  //   keyLength INTEGER OPTIONAL, prf AlgorithmIdentifier OPTIONAL }
  final kdf = params[0].children;
  if (_derOid(kdf[0]) != _oidPbkdf2) {
    throw const VaultCryptoException('PBES2 仅支持 PBKDF2 密钥派生');
  }
  final p2 = kdf[1].children;
  final salt = p2[0].content;
  final iterations = _derInt(p2[1]).toInt();
  var keyLength = 0;
  var prfOid = _oidHmacSha1;
  for (final p in p2.skip(2)) {
    if (p.tag == 0x02) {
      keyLength = _derInt(p).toInt();
    } else if (p.tag == 0x30) {
      prfOid = _derOid(p.children[0]);
    }
  }

  // encScheme AlgorithmIdentifier（AES-CBC + IV）
  final encScheme = params[1].children;
  final encOid = _derOid(encScheme[0]);
  final iv = encScheme[1].content;
  // cryptography 包要求 AES-CBC 携带 macAlgorithm（decrypt 强制校验 MAC），
  // 而 P12 PBES2 密文本身没有 MAC —— 解密前先计算"必然通过"的 HMAC 塞入
  // SecretBox（PBES2 无认证需求，解密结果再经结构解析 / 签名验证兜底）。
  final (AesCbc aes, int bits) = switch (encOid) {
    _oidAes128Cbc => (AesCbc.with128bits(macAlgorithm: Hmac.sha256()), 128),
    _oidAes192Cbc => (AesCbc.with192bits(macAlgorithm: Hmac.sha256()), 192),
    _oidAes256Cbc => (AesCbc.with256bits(macAlgorithm: Hmac.sha256()), 256),
    _ => throw VaultCryptoException('不支持的加密方案（OID $encOid）'),
  };

  final mac = prfOid == _oidHmacSha256 ? Hmac.sha256() : Hmac.sha1();
  final pbkdf2 = Pbkdf2(
    macAlgorithm: mac,
    iterations: iterations,
    bits: keyLength > 0 ? keyLength * 8 : bits,
  );
  final key = await pbkdf2.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );
  final cipherText = kids[1].content;
  final expectedMac = await Hmac.sha256().calculateMac(
    cipherText,
    secretKey: key,
    nonce: iv,
  );
  return aes.decrypt(
    SecretBox(cipherText, nonce: iv, mac: Mac(expectedMac.bytes)),
    secretKey: key,
  );
}

// ==================== 挑战签名 ====================

/// SHA-256 DigestInfo 前缀（EMSA-PKCS1-v1_5 的 DER 编码）。
const _sha256DigestInfo = <int>[
  0x30,
  0x31,
  0x30,
  0x0d,
  0x06,
  0x09,
  0x60,
  0x86,
  0x48,
  0x01,
  0x65,
  0x03,
  0x04,
  0x02,
  0x01,
  0x05,
  0x00,
  0x04,
  0x20,
];

/// 对消息签名，返回原始签名（RSA：k 字节大端；ECDSA：ASN.1 DER）。
Future<List<int>> signRaw(VaultPrivateKey key, List<int> message) async {
  switch (key.type) {
    case VaultKeyType.rsa:
      return _rsaPkcs1v15Sign(key, message);
    case VaultKeyType.ecdsa:
      return _ecdsaDerSign(key, message);
  }
}

/// 校验签名（与 [signRaw] 对应）。
///
/// 用于导入密钥后的自检（确认私钥可用、与证书匹配）以及单元测试；
/// ECDSA 公钥由私钥标量 d 推导（Q = d·G）。
Future<bool> verifySignature(
  VaultPrivateKey key,
  List<int> message,
  List<int> signature,
) async {
  switch (key.type) {
    case VaultKeyType.rsa:
      return _rsaPkcs1v15Verify(key, message, signature);
    case VaultKeyType.ecdsa:
      return _ecdsaVerify(key, message, signature);
  }
}

/// 对挑战字符串签名，返回 base64（无填充）——即解锁 / 证书绑定请求的
/// `signature` 字段。
///
/// 签名消息 = `purpose` 对应前缀 + challenge（docs/vault-design.md §7.1 定案）：
/// 解锁用 [VaultChallengePurpose.unlock]（`IRIX-VAULT-UNLOCK:1:`），
/// 绑定 / 换绑证书用 [VaultChallengePurpose.certBind]（`IRIX-VAULT-CERT-BIND:1:`）。
Future<String> signChallenge(
  VaultPrivateKey key,
  String challenge, {
  VaultChallengePurpose purpose = VaultChallengePurpose.unlock,
}) async {
  final message = utf8.encode('${purpose.prefix}$challenge');
  return base64NoPad(await signRaw(key, message));
}

/// RSA PKCS#1 v1.5 + SHA-256。
Future<List<int>> _rsaPkcs1v15Sign(
  VaultPrivateKey key,
  List<int> message,
) async {
  final n = key.rsaModulus!;
  final d = key.rsaPrivate!;
  final k = (n.bitLength + 7) >> 3; // 模长字节数
  final hash = await Sha256().hash(message);
  final tLen = _sha256DigestInfo.length + hash.bytes.length;
  if (k < tLen + 11) {
    throw const VaultCryptoException('RSA 密钥长度过短（至少 1024 位）');
  }
  final em = BytesBuilder()
    ..addByte(0x00)
    ..addByte(0x01)
    ..add(List.filled(k - tLen - 3, 0xff))
    ..addByte(0x00)
    ..add(_sha256DigestInfo)
    ..add(hash.bytes);
  final m = _bytesToBigInt(em.takeBytes());
  final s = m.modPow(d, n);
  return _bigIntToBytes(s, k);
}

/// RSA PKCS#1 v1.5 校验：还原 EM 并与期望编码逐字节比较。
Future<bool> _rsaPkcs1v15Verify(
  VaultPrivateKey key,
  List<int> message,
  List<int> signature,
) async {
  final n = key.rsaModulus!;
  final e = key.rsaExponent!;
  final k = (n.bitLength + 7) >> 3;
  if (signature.length != k) return false;
  final s = _bytesToBigInt(signature);
  if (s >= n) return false;
  final em = _bigIntToBytes(s.modPow(e, n), k);
  final hash = await Sha256().hash(message);
  final tLen = _sha256DigestInfo.length + hash.bytes.length;
  final expected = BytesBuilder()
    ..addByte(0x00)
    ..addByte(0x01)
    ..add(List.filled(k - tLen - 3, 0xff))
    ..addByte(0x00)
    ..add(_sha256DigestInfo)
    ..add(hash.bytes);
  final exp = expected.takeBytes();
  if (em.length != exp.length) return false;
  for (var i = 0; i < em.length; i++) {
    if (em[i] != exp[i]) return false;
  }
  return true;
}

// ==================== ECDSA（P-256 / P-384，ASN.1 DER 输出） ====================

/// 椭圆曲线参数（FIPS 186-4）。
class _Curve {
  final String name;
  final BigInt p;
  final BigInt a;
  final BigInt b;
  final BigInt gx;
  final BigInt gy;
  final BigInt n;

  const _Curve({
    required this.name,
    required this.p,
    required this.a,
    required this.b,
    required this.gx,
    required this.gy,
    required this.n,
  });
}

final Map<String, _Curve> _curves = {
  // P-256（secp256r1 / prime256v1）
  'P-256': _Curve(
    name: 'P-256',
    p: BigInt.parse(
      'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',
      radix: 16,
    ),
    a: BigInt.parse(
      'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC',
      radix: 16,
    ),
    b: BigInt.parse(
      '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',
      radix: 16,
    ),
    gx: BigInt.parse(
      '6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296',
      radix: 16,
    ),
    gy: BigInt.parse(
      '4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5',
      radix: 16,
    ),
    n: BigInt.parse(
      'FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',
      radix: 16,
    ),
  ),
  // P-384（secp384r1）
  'P-384': _Curve(
    name: 'P-384',
    p: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE'
      'FFFFFFFF0000000000000000FFFFFFFF',
      radix: 16,
    ),
    a: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE'
      'FFFFFFFF0000000000000000FFFFFFFC',
      radix: 16,
    ),
    b: BigInt.parse(
      'B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC'
      '656398D8A2ED19D2A85C8EDD3EC2AEF',
      radix: 16,
    ),
    gx: BigInt.parse(
      'AA87CA22BE8B05378EB1C71EF320AD746E1D3B628BA79B9859F741E082542A3855'
      '02F25DBF55296C3A545E3872760AB7',
      radix: 16,
    ),
    gy: BigInt.parse(
      '3617DE4A96262C6F5D9E98BF9292DC29F8F41DBD289A147CE9DA3113B5F0B8C00'
      'A60B1CE1D7E819D7A431D7C90EA0E5F',
      radix: 16,
    ),
    n: BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC7634D81F4372DDF'
      '581A0DB248B0A77AECEC196ACCC52973',
      radix: 16,
    ),
  ),
};

class _EcPoint {
  final BigInt x;
  final BigInt y;

  const _EcPoint(this.x, this.y);
}

/// ECDSA + SHA-256，输出 ASN.1 DER（SEQUENCE { INTEGER r, INTEGER s }）。
Future<List<int>> _ecdsaDerSign(VaultPrivateKey key, List<int> message) async {
  final curve = _curves[key.curve];
  if (curve == null) {
    throw VaultCryptoException('不支持的曲线（${key.curve}；支持 P-256 / P-384）');
  }
  final d = key.ecPrivate!;
  final hash = await Sha256().hash(message);
  final z = _bytesToBigInt(hash.bytes);
  final g = _EcPoint(curve.gx, curve.gy);
  var r = BigInt.zero;
  var s = BigInt.zero;
  var attempts = 0;
  while (attempts++ < 100) {
    final k = _randomScalar(curve.n);
    final kp = _ecMul(curve, k, g);
    r = kp.x % curve.n;
    if (r == BigInt.zero) continue;
    s = ((z + r * d) * k.modInverse(curve.n)) % curve.n;
    if (s != BigInt.zero) break;
  }
  if (s == BigInt.zero) {
    throw const VaultCryptoException('ECDSA 签名失败');
  }
  return _derSequence([_derInteger(r), _derInteger(s)]);
}

/// 随机标量 k ∈ [1, n-1]（密码学安全随机源）。
BigInt _randomScalar(BigInt n) {
  final rng = Random.secure();
  final len = (n.bitLength + 7) >> 3;
  final bytes = List<int>.generate(len, (_) => rng.nextInt(256));
  final k = _bytesToBigInt(bytes) % (n - BigInt.one) + BigInt.one;
  return k;
}

/// ECDSA 校验（DER 输入；公钥 Q = d·G）。
Future<bool> _ecdsaVerify(
  VaultPrivateKey key,
  List<int> message,
  List<int> signature,
) async {
  final curve = _curves[key.curve];
  if (curve == null) return false;
  try {
    final (node, end) = _readTlv(signature, 0);
    if (node.tag != 0x30 || end != signature.length) return false;
    final kids = node.children;
    if (kids.length != 2) return false;
    final r = _derInt(kids[0]);
    final s = _derInt(kids[1]);
    if (r <= BigInt.zero || r >= curve.n || s <= BigInt.zero || s >= curve.n) {
      return false;
    }
    final z = _bytesToBigInt((await Sha256().hash(message)).bytes);
    final w = s.modInverse(curve.n);
    final u1 = (z * w) % curve.n;
    final u2 = (r * w) % curve.n;
    final g = _EcPoint(curve.gx, curve.gy);
    final q = _ecMul(curve, key.ecPrivate!, g);
    // 公钥须在曲线上：y² ≡ x³ + ax + b (mod p)
    if ((q.y * q.y) % curve.p !=
        (q.x * q.x * q.x + curve.a * q.x + curve.b) % curve.p) {
      return false;
    }
    final p = _ecAdd(curve, _ecMul(curve, u1, g), _ecMul(curve, u2, q));
    if (p == null) return false;
    return p.x % curve.n == r;
  } on VaultCryptoException {
    return false;
  }
}

// --- 曲线点运算（仿射坐标） ---

_EcPoint? _ecAdd(_Curve curve, _EcPoint? a, _EcPoint? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.x == b.x) {
    // 互逆点 → 无穷远
    if ((a.y + b.y) % curve.p == BigInt.zero) return null;
    return _ecDouble(curve, a);
  }
  final lambda = ((b.y - a.y) * (b.x - a.x).modInverse(curve.p)) % curve.p;
  final x = (lambda * lambda - a.x - b.x) % curve.p;
  final y = (lambda * (a.x - x) - a.y) % curve.p;
  return _EcPoint(x, y);
}

_EcPoint? _ecDouble(_Curve curve, _EcPoint a) {
  if (a.y == BigInt.zero) return null;
  final lambda =
      ((BigInt.from(3) * a.x * a.x + curve.a) *
          (a.y * BigInt.two).modInverse(curve.p)) %
      curve.p;
  final x = (lambda * lambda - a.x * BigInt.two) % curve.p;
  final y = (lambda * (a.x - x) - a.y) % curve.p;
  return _EcPoint(x, y);
}

/// 标量乘（double-and-add）。
_EcPoint _ecMul(_Curve curve, BigInt k, _EcPoint g) {
  _EcPoint? result;
  var addend = g;
  var kk = k;
  while (kk > BigInt.zero) {
    if (kk & BigInt.one == BigInt.one) {
      result = _ecAdd(curve, result, addend);
    }
    addend = _ecAdd(curve, addend, addend)!;
    kk >>= 1;
  }
  return result!;
}

// --- DER 编码（签名输出） ---

List<int> _derLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  var v = length;
  while (v > 0) {
    bytes.insert(0, v & 0xff);
    v >>= 8;
  }
  return [0x80 | bytes.length, ...bytes];
}

List<int> _derInteger(BigInt v) {
  var bytes = _bigIntToBytes(v, (v.bitLength + 7) >> 3);
  if (bytes.isEmpty) bytes = [0];
  if (bytes[0] & 0x80 != 0) bytes = [0, ...bytes];
  return [0x02, ..._derLength(bytes.length), ...bytes];
}

List<int> _derSequence(List<List<int>> children) {
  final body = <int>[];
  for (final c in children) {
    body.addAll(c);
  }
  return [0x30, ..._derLength(body.length), ...body];
}

// ==================== TOTP（RFC 6238） ====================

/// 生成 TOTP 动态码（HMAC-SHA1，默认 6 位 / 30 秒周期）。
Future<String> totpCode(
  String base32Secret, {
  DateTime? at,
  int digits = 6,
  int period = 30,
}) async {
  final key = _base32Decode(
    base32Secret.toUpperCase().replaceAll(RegExp(r'[\s\-]'), ''),
  );
  if (key.isEmpty) {
    throw const VaultCryptoException('TOTP 密钥为空');
  }
  final counter =
      ((at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) ~/ period;
  final msg = _bigIntToBytes(BigInt.from(counter), 8);
  final mac = await Hmac.sha1().calculateMac(msg, secretKey: SecretKey(key));
  final h = mac.bytes;
  final off = h[19] & 0x0f;
  final bin =
      ((h[off] & 0x7f) << 24) |
      ((h[off + 1] & 0xff) << 16) |
      ((h[off + 2] & 0xff) << 8) |
      (h[off + 3] & 0xff);
  final code = (BigInt.from(bin) % BigInt.from(10).pow(digits))
      .toString()
      .padLeft(digits, '0');
  return code;
}

/// RFC 4648 Base32 解码。
List<int> _base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (final ch in input.split('')) {
    if (ch == '=') break;
    final idx = alphabet.indexOf(ch);
    if (idx < 0) {
      throw VaultCryptoException('Base32 字符非法: $ch');
    }
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return out;
}
