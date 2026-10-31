// 设备绑定数据模型（对应 docs/device-binding.md v1.4.0）
//
// 纯数据模型，不含网络与密码学逻辑：
// - [DeviceChallenge]   挑战申请响应（§3）
// - [DeviceKeyInfo]     本机设备密钥信息（§2）
// - [NodeDeviceBinding] 本机对某个节点的绑定记录（仅存公开信息，不存私钥）
// - [NodeDevice]        节点侧已注册设备列表项（§4）

/// 设备挑战（`POST /api/auth/device/challenge` 的 data）。
class DeviceChallenge {
  /// 一次性随机挑战（base64url 无填充，32 字节）。
  final String nonce;

  /// 过期时间（unix 毫秒）。
  final int expiresAt;

  /// 用途：`login` / `register`。
  final String purpose;

  /// 服务端证书 SHA-256 指纹；节点 TLS 关闭时为空。
  ///
  /// 客户端必须与配对时记录的指纹比对（TOFU），不一致立即中止，
  /// 既不能签名也不能发送密码（§9）。
  final String tlsFingerprint;

  const DeviceChallenge({
    required this.nonce,
    required this.expiresAt,
    required this.purpose,
    required this.tlsFingerprint,
  });

  factory DeviceChallenge.fromJson(Map<String, dynamic> data) {
    return DeviceChallenge(
      nonce: data['nonce'] as String? ?? '',
      expiresAt: (data['expiresAt'] as num?)?.toInt() ?? 0,
      purpose: data['purpose'] as String? ?? 'login',
      tlsFingerprint: (data['tlsFingerprint'] as String? ?? '').trim(),
    );
  }

  /// 挑战是否还在有效期内（留 5s 余量，避免边界请求被拒）。
  bool get isValid =>
      nonce.isNotEmpty &&
      DateTime.now().millisecondsSinceEpoch < expiresAt - 5 * 1000;
}

/// 本机设备密钥信息（`xmc_device_auth` 的 `ensure_key` / `key_status` 返回值）。
class DeviceKeyInfo {
  /// `deviceId = hex(SHA-256(公钥))[:32]`。
  final String deviceId;

  /// 公钥（base64url 无填充；ed25519 为 32 字节，P-256 为 65 字节未压缩点）。
  final String publicKey;

  /// 密钥类型：`ed25519` / `p256`。
  final String keyType;

  /// 密钥载体：`os-keychain`（Windows DPAPI）/ `file`（0600 文件）。
  final String keyProtection;

  /// 本次调用是否新建了密钥。
  final bool created;

  const DeviceKeyInfo({
    required this.deviceId,
    required this.publicKey,
    required this.keyType,
    required this.keyProtection,
    this.created = false,
  });

  factory DeviceKeyInfo.fromJson(Map<String, dynamic> data) {
    return DeviceKeyInfo(
      deviceId: data['deviceId'] as String? ?? '',
      publicKey: data['publicKey'] as String? ?? '',
      keyType: data['keyType'] as String? ?? 'ed25519',
      keyProtection: data['keyProtection'] as String? ?? 'file',
      created: data['created'] as bool? ?? false,
    );
  }

  /// 密钥是否可用（deviceId 与公钥都存在）。
  bool get isValid => deviceId.isNotEmpty && publicKey.isNotEmpty;
}

/// 本机对某个节点的设备绑定记录。
///
/// 只保存**公开信息**：设备私钥始终留在 Rust 侧的密钥文件里。记录存在即表示
/// 该节点+账户已经完成设备注册，后续登录会带 `device` 字段做签名校验。
class NodeDeviceBinding {
  /// 节点 id（[NodeInfo.id]）。
  final String nodeId;

  /// 已注册设备 id。
  final String deviceId;

  /// 绑定时的账户用户名（账户改名/换账号后需要重新绑定）。
  final String username;

  /// 密钥类型。
  final String keyType;

  /// 密钥载体。
  final String keyProtection;

  /// 配对时记录的节点 TLS 证书指纹（TOFU）；空串表示尚未固定。
  final String tlsFingerprint;

  /// 绑定时间（unix 毫秒）。
  final int boundAt;

  /// 设备名称（注册时提交给节点，用于设备列表展示）。
  final String deviceName;

  const NodeDeviceBinding({
    required this.nodeId,
    required this.deviceId,
    required this.username,
    required this.keyType,
    required this.keyProtection,
    required this.tlsFingerprint,
    required this.boundAt,
    required this.deviceName,
  });

  /// 记录是否可用来做设备登录。
  bool get isActive => nodeId.isNotEmpty && deviceId.isNotEmpty;

  NodeDeviceBinding copyWith({
    String? deviceId,
    String? username,
    String? keyType,
    String? keyProtection,
    String? tlsFingerprint,
    int? boundAt,
    String? deviceName,
  }) {
    return NodeDeviceBinding(
      nodeId: nodeId,
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
      keyType: keyType ?? this.keyType,
      keyProtection: keyProtection ?? this.keyProtection,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
      boundAt: boundAt ?? this.boundAt,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'username': username,
    'keyType': keyType,
    'keyProtection': keyProtection,
    'tlsFingerprint': tlsFingerprint,
    'boundAt': boundAt,
    'deviceName': deviceName,
  };

  factory NodeDeviceBinding.fromJson(String nodeId, Map<String, dynamic> json) {
    return NodeDeviceBinding(
      nodeId: nodeId,
      deviceId: json['deviceId'] as String? ?? '',
      username: json['username'] as String? ?? '',
      keyType: json['keyType'] as String? ?? 'ed25519',
      keyProtection: json['keyProtection'] as String? ?? 'file',
      tlsFingerprint: json['tlsFingerprint'] as String? ?? '',
      boundAt: (json['boundAt'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName'] as String? ?? '',
    );
  }
}

/// 节点侧已注册设备（`GET /api/auth/devices` 列表项）。
class NodeDevice {
  final String deviceId;
  final String keyType;
  final String keyProtection;
  final String descriptor;
  final String name;
  final int createdAt;
  final int lastSeen;

  const NodeDevice({
    required this.deviceId,
    required this.keyType,
    required this.keyProtection,
    required this.descriptor,
    required this.name,
    required this.createdAt,
    required this.lastSeen,
  });

  factory NodeDevice.fromJson(Map<String, dynamic> data) {
    return NodeDevice(
      deviceId: data['deviceId'] as String? ?? '',
      keyType: data['keyType'] as String? ?? '',
      keyProtection: data['keyProtection'] as String? ?? '',
      descriptor: data['descriptor'] as String? ?? '',
      name: data['name'] as String? ?? '',
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
      lastSeen: (data['lastSeen'] as num?)?.toInt() ?? 0,
    );
  }

  /// 是否当前这台设备（与本地绑定记录比对）。
  bool isCurrent(String? localDeviceId) =>
      localDeviceId != null && localDeviceId.isNotEmpty && deviceId == localDeviceId;
}
