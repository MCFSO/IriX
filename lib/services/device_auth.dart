// 设备绑定业务服务（对应 docs/device-binding.md v1.4.0）
//
// 职责边界：
// - 本机设备密钥：生成 / 查询 / 删除（私钥留在 Rust 侧，见 device_auth_ffi.dart）；
// - 密码学原语：签名、HMAC-SHA256 逐请求证明、安全随机数、SHA-256；
// - 绑定记录：每个节点一条，只保存 **公开信息**（deviceId、用户名、TLS 指纹等），
//   存于 settings 表（key = `node_device_bindings`），不保存私钥；
// - 设备描述（descriptor）与安装 id；
// - TLS 指纹 TOFU 校验（§9：指纹不一致必须中止，不能签名、不能发密码）。
//
// 网络（挑战申请 / 注册 / 登录 / 设备列表）在 NodeApiClient 与
// NodeDeviceService 中完成，本文件不做任何 HTTP 请求。

import 'dart:convert';

import '../models/node_device.dart';
import 'app_paths.dart';
import 'database_manager.dart';
import 'device_auth_canonical.dart';
import 'device_auth_ffi.dart';

// 调用方（NodeApiClient / UI）通常只需要业务服务，故把异常类型一并导出。
export 'device_auth_ffi.dart' show DeviceAuthException, DeviceAuthFfi;

/// 应用版本（写进设备 descriptor 的 `appVersion`，与 pubspec.yaml 保持一致）。
const String kIrixAppVersion = '1.0.0';

/// 设备绑定业务服务（单例）。
class DeviceAuthService {
  DeviceAuthService._();

  /// 单例。
  static final DeviceAuthService instance = DeviceAuthService._();

  /// settings 表中保存全部节点绑定记录的 key。
  static const String bindingsSettingKey = 'node_device_bindings';

  /// settings 表中保存安装级随机 id 的 key。
  static const String installIdSettingKey = 'device_install_id';

  Future<void>? _ready;

  /// 绑定记录缓存（nodeId → 记录）。
  Map<String, NodeDeviceBinding>? _bindings;

  /// 当前密钥目录（便于日志/诊断）。
  String? _keyDir;

  /// 设备绑定是否可用（Rust 动态库是否成功加载）。
  bool get isAvailable => DeviceAuthFfi.isAvailable;

  /// 初始化（密钥目录默认取自 AppPaths：`<数据根目录>/device_keys`）。
  Future<void> ensureInitialized() => _ready ??= _initDefault();

  Future<void> _initDefault() async {
    final dir = await AppPaths.instance.deviceKeysDir();
    await _initAt(dir);
  }

  /// 测试专用：用指定目录初始化密钥库（不经过 AppPaths）。
  Future<void> initForTesting(String dir) {
    _ready = _initAt(dir);
    return _ready!;
  }

  Future<void> _initAt(String dir) async {
    DeviceAuthFfi.instance.call('init', {'dir': dir});
    _keyDir = dir;
  }

  /// 当前设备密钥的落盘目录（未初始化时为 null）。
  String? get keyDir => _keyDir;

  // ---------------------------------------------------------------------
  // 设备密钥
  // ---------------------------------------------------------------------

  /// 确保本机存在设备密钥（不存在则生成），返回设备信息。
  ///
  /// [keyType] 为 `ed25519`（默认，桌面推荐）或 `p256`（WebCrypto 兼容）。
  Future<DeviceKeyInfo> ensureKey({String keyType = 'ed25519'}) async {
    await ensureInitialized();
    return DeviceKeyInfo.fromJson(
      DeviceAuthFfi.instance.call('ensure_key', {'keyType': keyType}),
    );
  }

  /// 查询本机设备密钥（不存在时返回 null）。
  Future<DeviceKeyInfo?> keyStatus() async {
    await ensureInitialized();
    final data = DeviceAuthFfi.instance.call('key_status');
    if (data['exists'] != true) return null;
    return DeviceKeyInfo.fromJson(data);
  }

  /// 删除本机设备密钥。
  ///
  /// [clearBindings] 为 true 时同时清空所有节点绑定记录 —— 密钥删除后旧
  /// deviceId 必然失效，保留记录只会让后续登录报「密钥已变更」。
  Future<void> deleteKey({bool clearBindings = true}) async {
    await ensureInitialized();
    DeviceAuthFfi.instance.call('delete_key');
    if (clearBindings) {
      _bindings = <String, NodeDeviceBinding>{};
      await DatabaseManager.instance.deleteSetting(bindingsSettingKey);
    }
  }

  // ---------------------------------------------------------------------
  // 密码学原语（同步 FFI，微秒级）
  // ---------------------------------------------------------------------

  /// 用本机设备私钥签名，返回 base64url 无填充签名。
  Future<String> sign(String message) async {
    await ensureInitialized();
    final data = DeviceAuthFfi.instance.call('sign', {'message': message});
    final signature = data['signature'] as String? ?? '';
    if (signature.isEmpty) {
      throw const DeviceAuthException('设备签名失败：模块未返回签名值');
    }
    return signature;
  }

  /// 计算逐请求证明 `base64url(HMAC-SHA256(proofKey, canonical))`。
  Future<String> hmacSha256({
    required String proofKey,
    required String message,
  }) async {
    await ensureInitialized();
    final data = DeviceAuthFfi.instance.call('hmac_sha256', {
      'key_b64url': proofKey,
      'message': message,
    });
    final mac = data['mac'] as String? ?? '';
    if (mac.isEmpty) {
      throw const DeviceAuthException('会话证明计算失败：模块未返回 MAC');
    }
    return mac;
  }

  /// 生成 [length] 字节安全随机数（base64url 无填充）。
  Future<String> randomB64Url(int length) async {
    await ensureInitialized();
    final data = DeviceAuthFfi.instance.call('random_b64url', {'len': length});
    return data['bytes'] as String? ?? '';
  }

  /// 计算 SHA-256（小写 hex）。
  Future<String> sha256Hex(String data) async {
    await ensureInitialized();
    final result = DeviceAuthFfi.instance.call('sha256', {'data': data});
    return result['hex'] as String? ?? '';
  }

  // ---------------------------------------------------------------------
  // 描述串
  // ---------------------------------------------------------------------

  /// 安装级随机 id（hex），首次调用生成并持久化，之后稳定复用。
  Future<String> installId() async {
    final existing = await DatabaseManager.instance.getSetting(
      installIdSettingKey,
    );
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    // 用 32 字节随机数派生 32 位 hex，避免自己实现 hex 编码。
    final seed = await randomB64Url(32);
    final hex = (await sha256Hex(seed));
    final id = hex.substring(0, 32);
    await DatabaseManager.instance.setSetting(installIdSettingKey, id);
    return id;
  }

  /// 构造本机设备描述串（注册时原样提交，服务端按 UTF-8 字节取 SHA-256）。
  Future<String> descriptorJson() async {
    return DeviceAuthProtocol.buildDescriptor(
      installId: await installId(),
      appVersion: kIrixAppVersion,
    );
  }

  // ---------------------------------------------------------------------
  // TLS 指纹（TOFU）
  // ---------------------------------------------------------------------

  /// 校验挑战响应里的 `tlsFingerprint`，返回应写回绑定记录的指纹。
  ///
  /// 规则（§9）：
  /// - 服务端为空（TLS 关闭 / 反代终止 TLS）：不固定、不比较，返回已记录值；
  /// - 已记录为空：首次信任（TOFU），返回服务端指纹用于记录；
  /// - 两侧都非空且不一致：抛 [DeviceAuthException]，调用方必须立即中止，
  ///   **不得**继续签名或发送密码。
  String verifyFingerprint({
    required String serverFingerprint,
    String? pinnedFingerprint,
  }) {
    final server = serverFingerprint.trim().toLowerCase();
    final pinned = (pinnedFingerprint ?? '').trim().toLowerCase();
    if (server.isEmpty) return pinned;
    if (pinned.isEmpty) return server;
    if (pinned != server) {
      throw const DeviceAuthException(
        '节点 TLS 证书指纹与配对时记录的不一致，已中止登录。'
        '可能存在中间人攻击，或节点更换/重签了证书；'
        '确认无误后可在设备管理中解绑并重新绑定。',
      );
    }
    return pinned;
  }

  // ---------------------------------------------------------------------
  // 绑定记录（settings 表）
  // ---------------------------------------------------------------------

  /// 全部节点绑定记录。
  Future<Map<String, NodeDeviceBinding>> bindings() async {
    final cached = _bindings;
    if (cached != null) return Map.unmodifiable(cached);
    final loaded = <String, NodeDeviceBinding>{};
    final raw = await DatabaseManager.instance.getSetting(bindingsSettingKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((nodeId, value) {
            if (value is Map<String, dynamic>) {
              final binding = NodeDeviceBinding.fromJson(nodeId, value);
              if (binding.deviceId.isNotEmpty) loaded[nodeId] = binding;
            }
          });
        }
      } on FormatException catch (_) {
        // 记录损坏时按「未绑定」处理，用户重新绑定即可覆盖。
      }
    }
    _bindings = loaded;
    return Map.unmodifiable(loaded);
  }

  /// 指定节点的绑定记录（未绑定时返回 null）。
  Future<NodeDeviceBinding?> bindingFor(String nodeId) async {
    final all = await bindings();
    return all[nodeId];
  }

  /// 保存（或覆盖）某个节点的绑定记录。
  Future<void> saveBinding(NodeDeviceBinding binding) async {
    final all = await bindings();
    final next = <String, NodeDeviceBinding>{...all, binding.nodeId: binding};
    await _persist(next);
  }

  /// 删除某个节点的绑定记录（本地解绑）。
  Future<void> removeBinding(String nodeId) async {
    final all = await bindings();
    if (!all.containsKey(nodeId)) return;
    final next = Map<String, NodeDeviceBinding>.from(all)..remove(nodeId);
    await _persist(next);
  }

  Future<void> _persist(Map<String, NodeDeviceBinding> next) async {
    _bindings = next;
    final payload = <String, Object?>{
      for (final entry in next.entries) entry.key: entry.value.toJson(),
    };
    await DatabaseManager.instance.setSetting(
      bindingsSettingKey,
      jsonEncode(payload),
    );
  }
}
