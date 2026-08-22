// 加密保险库 Vault 数据模型（irix-node，见 NODE_API.md §9）
// 解析保险库会话 / 挑战 / 初始化 / 用户 / 迁移等 API 返回的 JSON。
// 纯 Dart 模型，不依赖 Flutter；所有解析均带容错默认值。

/// 保险库状态（GET /api/vault/status）。
class VaultStatus {
  /// 保险库功能是否启用（节点以 `-vault` 开启，见 vault-design.md D7）。
  final bool enabled;

  /// 是否已完成初始化（创建过用户）。
  final bool initialized;

  /// 是否处于锁定状态（数据面被门禁拦截）。
  final bool locked;

  /// 当前解锁用户（锁定态可能为空）。
  final String? user;

  /// 会话剩余有效期（秒，未解锁/已过期时为空）。
  final int? expiresIn;

  /// 是否要求修改密码（如恢复会话后强制改密）。
  final bool passwordExpired;

  /// 是否处于迁移中（两阶段迁移进行时数据面 403 `vault migrating`）。
  final bool migrating;

  const VaultStatus({
    this.enabled = false,
    this.initialized = false,
    this.locked = true,
    this.user,
    this.expiresIn,
    this.passwordExpired = false,
    this.migrating = false,
  });

  factory VaultStatus.fromJson(Map<String, dynamic> json) {
    return VaultStatus(
      enabled: json['enabled'] as bool? ?? false,
      initialized: json['initialized'] as bool? ?? false,
      locked: json['locked'] as bool? ?? true,
      user: json['user'] as String?,
      expiresIn: (json['expiresIn'] as num?)?.toInt(),
      passwordExpired: json['passwordExpired'] as bool? ?? false,
      migrating: json['migrating'] as bool? ?? false,
    );
  }
}

/// 签名挑战（POST /api/vault/challenge）。
///
/// 一次性使用，5 分钟有效；`signature` 由客户端对
/// 「前缀 + [challenge]」（见 vault_crypto.dart 的 kVaultSignaturePrefix）
/// 签名后回传，私钥永不上送。
class VaultChallenge {
  final String challengeId;
  final String challenge;

  const VaultChallenge({required this.challengeId, required this.challenge});

  factory VaultChallenge.fromJson(Map<String, dynamic> json) {
    return VaultChallenge(
      challengeId: json['challengeId'] as String? ?? '',
      challenge: json['challenge'] as String? ?? '',
    );
  }
}

/// 解锁 / 恢复会话（POST /api/vault/unlock、/api/vault/recovery）。
class VaultSession {
  /// 会话令牌：后续数据面请求经 `X-Vault-Token` 头携带。
  final String sessionToken;

  /// 有效期（秒）。
  final int expiresIn;

  /// 密码是否到期（仅解锁响应携带；配合 forceExpire 需同请求改密）。
  final bool passwordExpired;

  const VaultSession({
    required this.sessionToken,
    this.expiresIn = 0,
    this.passwordExpired = false,
  });

  factory VaultSession.fromJson(Map<String, dynamic> json) {
    return VaultSession(
      sessionToken: json['sessionToken'] as String? ?? '',
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
      passwordExpired: json['passwordExpired'] as bool? ?? false,
    );
  }

  /// 是否持有有效令牌。
  bool get isValid => sessionToken.isNotEmpty;
}

/// 初始化结果（POST /api/vault/init，仅未初始化时可用）。
class VaultInitResult {
  /// 初始化令牌：后续 TOTP 校验 / 证书绑定请求以 `X-Vault-Token` 携带。
  final String initToken;

  /// TOTP 密钥（Base32，供客户端生成二维码 / 手动录入）。
  final String totpSecret;

  /// otpauth:// URI（可生成二维码供手机扫码）。
  final String otpauthUri;

  /// 恢复令牌（仅此一次展示，丢失需重新初始化）。
  final String recoveryToken;

  const VaultInitResult({
    required this.initToken,
    required this.totpSecret,
    required this.otpauthUri,
    required this.recoveryToken,
  });

  factory VaultInitResult.fromJson(Map<String, dynamic> json) {
    return VaultInitResult(
      initToken: json['initToken'] as String? ?? '',
      totpSecret: json['totpSecret'] as String? ?? '',
      otpauthUri: json['otpauthURI'] as String? ?? '',
      recoveryToken: json['recoveryToken'] as String? ?? '',
    );
  }
}

/// 保险库用户（GET /api/vault/users）。
///
/// 服务端字段未在 NODE_API.md 中逐一固定，本模型容错解析常见字段，
/// 并保留原始 JSON 供展示扩展。
class VaultUser {
  /// 用户名。
  final String user;

  /// 是否绑定 TOTP。
  final bool totpEnabled;

  /// 是否绑定证书（SPKI 指纹）。
  final bool certBound;

  /// 原始 JSON（服务端扩展字段透传）。
  final Map<String, dynamic> raw;

  const VaultUser({
    required this.user,
    this.totpEnabled = false,
    this.certBound = false,
    this.raw = const {},
  });

  factory VaultUser.fromJson(Map<String, dynamic> json) {
    return VaultUser(
      user: (json['user'] ?? json['username'] ?? json['name']) as String? ?? '',
      totpEnabled: json['totpEnabled'] as bool? ?? false,
      certBound: json['certBound'] as bool? ?? false,
      raw: json,
    );
  }
}

/// 迁移状态（GET /api/vault/migrate/status）。
///
/// 两阶段迁移（instances.json + vaultFiles 文件树），幂等续跑。
class VaultMigrateStatus {
  /// 当前阶段（如 `instances` / `files` / `done`）。
  final String phase;

  /// 已完成条目数。
  final int done;

  /// 总条目数（未知时为 0）。
  final int total;

  /// 已迁移字节数。
  final int bytes;

  /// 迁移完成时间（迁移中 / 未开始为空）。
  final DateTime? completedAt;

  const VaultMigrateStatus({
    this.phase = '',
    this.done = 0,
    this.total = 0,
    this.bytes = 0,
    this.completedAt,
  });

  factory VaultMigrateStatus.fromJson(Map<String, dynamic> json) {
    final completed = json['completedAt'] as String?;
    return VaultMigrateStatus(
      phase: json['phase'] as String? ?? '',
      done: (json['done'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      completedAt: completed == null || completed.isEmpty
          ? null
          : DateTime.tryParse(completed),
    );
  }

  /// 是否处于进行中（done < total 且阶段非 done/空）。
  bool get inProgress =>
      phase.isNotEmpty && phase != 'done' && (total == 0 || done < total);
}
