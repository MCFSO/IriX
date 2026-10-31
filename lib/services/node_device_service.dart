// 设备绑定的业务流程编排（对应 docs/device-binding.md v1.4.0）
//
// 把「本地密钥 + 挑战申请 + 签名 + 注册/撤销 + 绑定记录」串起来，UI 只需调用
// 本服务；HTTP 细节仍在 NodeApiClient，密码学与持久化在 DeviceAuthService。
//
// 典型用法（节点凭据对话框 / 设备管理对话框）：
//   1. final svc = NodeDeviceService(client: NodeApiClient.of(node), nodeId: node.id);
//   2. await svc.bind(username: ..., password: ..., deviceName: '我的电脑');
//   3. await svc.listDevices();          // 已绑定设备列表
//   4. await svc.revoke(deviceId: ..., password: ...);   // 撤销（服务端）
//   5. await svc.unbindLocal();          // 仅本地解绑（不调用服务端）

import '../models/node_device.dart';
import 'device_auth.dart';
import 'device_auth_canonical.dart';
import 'node_api_client.dart';

/// 设备绑定 / 解绑 / 设备管理业务流程。
class NodeDeviceService {
  /// [client] 必须指向 [nodeId] 对应节点且带账户凭据；[nodeId] 用于绑定记录键。
  NodeDeviceService({required this.client, required this.nodeId});

  final NodeApiClient client;
  final String nodeId;

  DeviceAuthService get _auth => DeviceAuthService.instance;

  /// 本机设备密钥信息（不存在则生成）。
  Future<DeviceKeyInfo> keyInfo() => _auth.ensureKey();

  /// 本机对当前节点的绑定记录。
  Future<NodeDeviceBinding?> binding() => _auth.bindingFor(nodeId);

  /// 本机是否已完成设备绑定。
  Future<bool> get isBound async => (await binding())?.isActive ?? false;

  /// 绑定本机设备（协议 §4 注册流程）。
  ///
  /// [username] / [password] 必须与节点账户一致：密码既用于注册请求本身
  /// （防止「仅拿到被窃会话 token 的人偷偷添加设备」），也用于注册前登录。
  ///
  /// 成功后主动丢弃旧会话并用设备签名重新登录，确认 `deviceBound=true`；
  /// 任一环节失败都不会留下半绑定的本地记录。
  Future<NodeDeviceBinding> bind({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final user = username.trim();
    if (user.isEmpty || password.isEmpty) {
      throw const NodeDeviceBindingException(400, '绑定设备需要节点账户用户名与密码');
    }

    final key = await _auth.ensureKey();
    if (!key.isValid) {
      throw const NodeDeviceBindingException(400, '本机设备密钥生成失败，无法绑定设备');
    }

    // 1) 先确保有可用会话（设备注册接口要求 X-Auth-Token）。
    try {
      await client.ensureSession(force: true);
    } on NodeDeviceBindingException catch (e) {
      // 典型场景：账户已开启 required 但本机尚未绑定 —— 此时无法用密码登录，
      // 也就无法注册新设备，只能由管理员临时把策略切回 optional。
      throw NodeDeviceBindingException(
        e.statusCode,
        '${e.message}；账户若已启用 required 策略，请让管理员先临时切回 optional 再绑定',
      );
    }

    // 2) 申请注册挑战 + TLS 指纹校验（签名前必须完成）。
    final challenge = await client.deviceChallenge(
      username: user,
      deviceId: key.deviceId,
      purpose: 'register',
    );
    final existing = await _auth.bindingFor(nodeId);
    final pinned = _auth.verifyFingerprint(
      serverFingerprint: challenge.tlsFingerprint,
      pinnedFingerprint: existing?.tlsFingerprint,
    );

    // 3) 构造规范串并签名（descriptor 的哈希按提交的原始字符串计算）。
    final descriptor = await _auth.descriptorJson();
    final descriptorHash = await _auth.sha256Hex(descriptor);
    final timestamp = DeviceAuthProtocol.timestampText();
    final canonical = DeviceAuthProtocol.registerCanonical(
      username: user,
      deviceId: key.deviceId,
      publicKey: key.publicKey,
      keyType: key.keyType,
      keyProtection: key.keyProtection,
      descriptorHashHex: descriptorHash,
      timestamp: timestamp,
      nonce: challenge.nonce,
      tlsFingerprint: challenge.tlsFingerprint,
    );
    final signature = await _auth.sign(canonical);

    // 4) 注册设备（挑战一次性：失败后必须重新申请，不能重放）。
    final result = await client.registerDevice(
      deviceId: key.deviceId,
      publicKey: key.publicKey,
      keyType: key.keyType,
      keyProtection: key.keyProtection,
      descriptor: descriptor,
      name: deviceName.trim().isEmpty ? 'IriX 桌面端' : deviceName.trim(),
      nonce: challenge.nonce,
      timestamp: timestamp,
      signature: signature,
      password: password,
    );

    final binding = NodeDeviceBinding(
      nodeId: nodeId,
      deviceId: key.deviceId,
      username: user,
      keyType: key.keyType,
      keyProtection: key.keyProtection,
      tlsFingerprint: challenge.tlsFingerprint.isNotEmpty
          ? pinned
          : (existing?.tlsFingerprint ?? ''),
      boundAt: DateTime.now().millisecondsSinceEpoch,
      deviceName:
          (result['name'] as String?)?.trim().isNotEmpty == true
          ? (result['name'] as String).trim()
          : (deviceName.trim().isEmpty ? 'IriX 桌面端' : deviceName.trim()),
    );
    await _auth.saveBinding(binding);

    // 5) 用设备签名重新登录，确认服务端已把会话与设备绑定。
    NodeApiClient.forgetSession(client.sessionKey);
    try {
      await client.login();
    } catch (e) {
      // 回滚本地记录，避免出现「本地以为绑好了、服务端却不认」的状态。
      await _auth.removeBinding(nodeId);
      rethrow;
    }
    return binding;
  }

  /// 仅删除本地绑定记录（服务端设备仍保留，可稍后再用同一密钥重新登录）。
  Future<void> unbindLocal() async {
    await _auth.removeBinding(nodeId);
    NodeApiClient.forgetSession(client.sessionKey);
  }

  /// 撤销服务端设备并删除本地记录（协议 §4：撤销会注销该账户全部会话）。
  ///
  /// [password] 为账户密码；`required` 策略下撤销最后一台设备会被服务端拒绝
  /// （403），调用方需提示用户先绑定另一台设备。
  Future<void> revoke({
    required String deviceId,
    required String password,
  }) async {
    await client.revokeDevice(deviceId: deviceId, password: password);
    final current = await _auth.bindingFor(nodeId);
    if (current != null && current.deviceId == deviceId) {
      await _auth.removeBinding(nodeId);
    }
    NodeApiClient.forgetSession(client.sessionKey);
  }

  /// 节点侧已注册的设备列表。
  Future<List<NodeDevice>> listDevices() => client.listDevices();

  /// 设备绑定模块是否可用（Rust 动态库缺失时 UI 应禁用入口）。
  bool get isAvailable => DeviceAuthFfi.isAvailable;
}
