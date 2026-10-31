// 设备绑定协议规范串（对应 docs/device-binding.md v1.4.0）
//
// 本文件只做**纯字符串拼接**，不碰网络、密钥与文件系统，便于单元测试逐字节
// 校验。协议对规范串的要求极易出错，务必遵守：
// - 字段顺序固定，分隔符为单个 `\n`，**不追加结尾换行**（空字段仍占位，
//   因此当最后一个字段为空时字符串自然以 `\n` 结尾）；
// - `timestamp` / `seq` 用请求头里的**原文字符串**参与签名（前导零会影响结果）；
// - `requestURI` 必须与客户端实际发送的字节一致（含 percent-encoding，
//   不含 fragment，无查询串时只有 path）；
// - 文本编码 UTF-8，不做换行转换（不要用 \r\n）。

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// 设备绑定协议常量与规范串构造。
abstract final class DeviceAuthProtocol {
  /// 注册规范串前缀（§4）。
  static const String registerPrefix = 'irix-device-register-v1';

  /// 登录规范串前缀（§5）。
  static const String loginPrefix = 'irix-device-login-v1';

  /// 逐请求证明规范串前缀（§6）。
  static const String proofPrefix = 'irix-proof-v1';

  /// 逐请求证明请求头名（§6）。
  static const String headerDeviceId = 'X-Device-Id';
  static const String headerTimestamp = 'X-Session-Timestamp';
  static const String headerSeq = 'X-Session-Seq';
  static const String headerProof = 'X-Session-Proof';

  /// 服务端允许的时间偏差（秒），见 §4/§6。
  static const int clockSkewSeconds = 120;

  /// 注册签名规范串（逐字节，见 §4）。
  static String registerCanonical({
    required String username,
    required String deviceId,
    required String publicKey,
    required String keyType,
    required String keyProtection,
    required String descriptorHashHex,
    required String timestamp,
    required String nonce,
    required String tlsFingerprint,
  }) {
    return <String>[
      registerPrefix,
      username,
      deviceId,
      publicKey,
      keyType,
      keyProtection,
      descriptorHashHex,
      timestamp,
      nonce,
      tlsFingerprint,
    ].join('\n');
  }

  /// 登录签名规范串（逐字节，见 §5）。
  static String loginCanonical({
    required String username,
    required String deviceId,
    required String nonce,
    required String timestamp,
    required String proofKey,
    required String tlsFingerprint,
  }) {
    return <String>[
      loginPrefix,
      username,
      deviceId,
      nonce,
      timestamp,
      proofKey,
      tlsFingerprint,
    ].join('\n');
  }

  /// 逐请求证明规范串（见 §6）。
  static String proofCanonical({
    required String method,
    required String requestUri,
    required String timestamp,
    required String seq,
  }) {
    return <String>[
      proofPrefix,
      method.toUpperCase(),
      requestUri,
      timestamp,
      seq,
    ].join('\n');
  }

  /// 取出与客户端实际发送一致的 requestURI（path + `?` + 原始查询串）。
  ///
  /// [Uri.path] / [Uri.query] 都返回**已编码**的形式，与写入 HTTP 请求行的字节
  /// 一致；`uri.path` 无查询串时不能补 `?`（协议要求只有 path）。
  static String requestUriOf(Uri uri) =>
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

  /// 构造设备描述（`descriptor`）。返回值即请求里原样提交的字符串，
  /// 注册时对它的 UTF-8 字节做 SHA-256，**不要**再重新序列化。
  ///
  /// 只收集最小化的平台信息：不采集硬件序列号、用户名、主机名等敏感标识
  /// （§10.3）。`installId` 为安装级随机 hex，用于区分同一账号下的多次安装。
  static String buildDescriptor({
    required String installId,
    required String appVersion,
    String? os,
    String? osVersion,
    String? build,
    String? arch,
  }) {
    final descriptor = <String, String>{
      'os': os ?? _osName(),
      'osVersion': osVersion ?? _osVersionShort(),
      'build': build ?? _buildNumber(),
      'arch': arch ?? archLabel(),
      'appVersion': appVersion,
      'installId': installId,
      'hardwareClass':
          (Platform.isAndroid || Platform.isIOS) ? 'mobile' : 'desktop',
    };
    return jsonEncode(descriptor);
  }

  /// 生成 Unix 秒时间戳的十进制原文字符串（不得带空格或前导零）。
  static String timestampText([DateTime? now]) =>
      '${(now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000}';

  /// 运行架构标签（与 Go 服务端 `runtime.GOARCH` 风格对齐）。
  static String archLabel() {
    final abi = Abi.current().toString();
    if (abi.contains('arm64')) return 'arm64';
    if (abi.contains('x64')) return 'amd64';
    if (abi.contains('ia32')) return '386';
    if (abi.contains('arm')) return 'arm';
    if (abi.contains('riscv64')) return 'riscv64';
    return 'unknown';
  }

  static String _osName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  /// 只保留版本号部分（例如 Windows 的 `"Windows 11 家庭版" 10.0 (Build 26300)`
  /// 里取 `10.0`），避免把本地化描述写进描述串。
  static String _osVersionShort() {
    final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(_systemVersionText());
    final value = match?.group(0) ?? '';
    return value.length > 32 ? value.substring(0, 32) : value;
  }

  /// 内部版本号（Windows 为 Build 号，其他平台取版本号最后一段）。
  static String _buildNumber() {
    final matches = RegExp(r'\d+(?:\.\d+)*').allMatches(_systemVersionText());
    if (matches.isEmpty) return '';
    final last = matches.last.group(0)!;
    return last.length > 32 ? last.substring(0, 32) : last;
  }

  static String _systemVersionText() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return '';
    }
  }
}
