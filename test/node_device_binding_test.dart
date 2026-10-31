// 设备绑定客户端协议测试（对照 docs/device-binding.md v1.4.0）
//
// 本地 HttpServer 按文档实现一个最小的 irix-node v1.4 设备绑定服务端：
//   POST /api/auth/device/challenge   挑战（login / register，60s、一次性）
//   POST /api/auth/devices            设备注册（校验密码、挑战、签名、deviceId）
//   POST /api/auth/devices/revoke     撤销设备（撤销后注销该账户全部会话）
//   POST /api/auth/login              密码登录 / 密码+设备签名登录
//   GET  /api/auth/devices            设备列表
//   GET  /api/overview                已绑定会话必须带 4 个证明头（含序号窗口）
// 服务端侧用 package:cryptography 独立验签与验 HMAC，能真正验证客户端拼接的
// 规范串逐字节正确（Ed25519 验签 + HMAC-SHA256 比对）。
//
// 覆盖：兼容旧密码登录、绑定全流程、required 策略、逐请求证明与序号递增、
// TLS 指纹 TOFU 不一致时中止且不发密码、设备列表/撤销、本机密钥失效。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/models/node.dart';
import 'package:irix/services/device_auth.dart';
import 'package:irix/services/node_api_client.dart';
import 'package:irix/services/node_device_service.dart';

/// base64url 无填充。
String b64u(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll(RegExp(r'=+$'), '');

/// base64url 无填充解码。
Uint8List unb64u(String text) {
  final normalized = text.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + (4 - normalized.length % 4) % 4,
    '=',
  );
  return Uint8List.fromList(base64.decode(padded));
}

/// 小写 hex。
String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 服务端账号。
class _Account {
  _Account({required this.username, required this.password});

  final String username;
  final String password;
  String policy = 'optional';
}

/// 服务端设备记录（只存公钥，与协议一致）。
class _Device {
  _Device({
    required this.deviceId,
    required this.publicKey,
    required this.keyType,
    required this.keyProtection,
    required this.descriptor,
    required this.name,
  });

  final String deviceId;
  final List<int> publicKey;
  final String keyType;
  final String keyProtection;
  final String descriptor;
  final String name;
  int lastSeen = 0;
}

/// 一次性挑战。
class _Challenge {
  const _Challenge({
    required this.nonce,
    required this.username,
    required this.deviceId,
    required this.purpose,
    required this.expiresAt,
    required this.tlsFingerprint,
  });

  final String nonce;
  final String username;
  final String deviceId;
  final String purpose;
  final int expiresAt;
  final String tlsFingerprint;
}

/// 服务端会话。
class _Session {
  _Session({required this.token, required this.username, this.deviceId = ''});

  final String token;
  final String username;
  final String deviceId;
  List<int>? proofKey;
  bool get deviceBound => deviceId.isNotEmpty && proofKey != null;
  final Set<int> seenSeq = <int>{};
  int maxSeq = 0;
}

/// 最小的 irix-node v1.4 设备绑定服务端。
class _FakeIrixNode {
  _FakeIrixNode._(this._server, this._accounts);

  final HttpServer _server;
  final Map<String, _Account> _accounts;

  static Future<_FakeIrixNode> start() async {
    final node = _FakeIrixNode._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      {
        'alice': _Account(username: 'alice', password: 'secret-pass'),
      },
    );
    node._server.listen(node._handle);
    return node;
  }

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);

  /// 当前服务端证书指纹（模拟 tlsFingerprint；测试里可改）。
  String tlsFingerprint = 'fp-abc123';

  final Map<String, _Device> devices = {};
  final Map<String, _Session> sessions = {};
  final Map<String, _Challenge> challenges = {};

  /// 计数与最近一次请求的可观测状态。
  int loginRequests = 0;
  int challengeRequests = 0;
  int registerRequests = 0;
  bool? lastLoginHadDevice;
  bool lastRegisterVerified = false;
  int proofVerifiedCount = 0;
  int proofFailures = 0;
  final List<int> seenProofSeq = [];
  String? lastProofDeviceId;

  _Account get alice => _accounts['alice']!;

  String get policy => alice.policy;
  set policy(String value) => alice.policy = value;

  void revokeSessionsOf(String username) {
    sessions.removeWhere((_, session) => session.username == username);
  }

  _Session _newSession(String username, {String deviceId = '', List<int>? proofKey}) {
    final token =
        'tok-${DateTime.now().microsecondsSinceEpoch}-${sessions.length + 1}';
    final session = _Session(token: token, username: username, deviceId: deviceId)
      ..proofKey = proofKey;
    sessions[token] = session;
    return session;
  }

  _Session? _sessionOf(HttpRequest request) {
    final token = request.headers.value('X-Auth-Token');
    if (token == null || token.isEmpty) return null;
    return sessions[token];
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final raw = await utf8.decoder.bind(request).join();
    final body = raw.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    try {
      switch (path) {
        case '/api/auth/device/challenge':
          await _challenge(request, body);
        case '/api/auth/devices':
          if (request.method == 'POST') {
            await _register(request, body);
          } else {
            await _listDevices(request);
          }
        case '/api/auth/devices/revoke':
          await _revoke(request, body);
        case '/api/auth/login':
          await _login(request, body);
        case '/api/auth/logout':
          sessions.remove(request.headers.value('X-Auth-Token'));
          await _ok(request, '');
        case '/api/overview':
          await _overview(request);
        case '/api/accounts/me':
          await _me(request);
        default:
          await _fail(request, 404, 'not found');
      }
    } catch (e) {
      await _fail(request, 500, '服务端测试桩异常: $e');
    }
  }

  // ---------------------------------------------------------------- 挑战

  Future<void> _challenge(HttpRequest request, Map<String, dynamic> body) async {
    challengeRequests++;
    final username = body['username'] as String? ?? '';
    final deviceId = body['deviceId'] as String? ?? '';
    final purpose = body['purpose'] as String? ?? 'login';
    // 不泄漏账户是否存在（§3）：无论账户在不在都返回挑战。
    final nonce = b64u(List<int>.generate(32, (i) => (i * 7 + challengeRequests) % 256));
    challenges['$purpose|$username|$deviceId'] = _Challenge(
      nonce: nonce,
      username: username,
      deviceId: deviceId,
      purpose: purpose,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60 * 1000,
      tlsFingerprint: tlsFingerprint,
    );
    await _ok(request, {
      'nonce': nonce,
      'expiresAt': DateTime.now().millisecondsSinceEpoch + 60 * 1000,
      'purpose': purpose,
      'tlsFingerprint': tlsFingerprint,
    });
  }

  _Challenge? _consume(String purpose, String username, String deviceId) {
    final key = '$purpose|$username|$deviceId';
    final challenge = challenges.remove(key);
    if (challenge == null) return null;
    if (challenge.expiresAt < DateTime.now().millisecondsSinceEpoch) {
      return null;
    }
    return challenge;
  }

  // ---------------------------------------------------------------- 注册

  Future<void> _register(HttpRequest request, Map<String, dynamic> body) async {
    registerRequests++;
    final session = _sessionOf(request);
    if (session == null) {
      return _fail(request, 403, '未认证或会话已过期（请先登录 POST /api/auth/login）');
    }
    final account = _accounts[session.username];
    if (account == null) return _fail(request, 403, '账户不存在');
    if ((body['password'] as String? ?? '') != account.password) {
      return _fail(request, 403, '密码错误');
    }

    final deviceId = body['deviceId'] as String? ?? '';
    final publicKeyB64 = body['publicKey'] as String? ?? '';
    final keyType = body['keyType'] as String? ?? '';
    final keyProtection = body['keyProtection'] as String? ?? '';
    final descriptor = body['descriptor'] as String? ?? '';
    final name = body['name'] as String? ?? '';
    final nonce = body['nonce'] as String? ?? '';
    final timestamp = (body['timestamp'] as num?)?.toInt() ?? 0;
    final signature = body['signature'] as String? ?? '';

    if (keyType != 'ed25519') return _fail(request, 400, 'keyType 仅支持 ed25519（测试桩）');
    final publicKey = unb64u(publicKeyB64);
    if (publicKey.length != 32) return _fail(request, 400, '公钥长度非法');
    final expectedId = hexOf((await Sha256().hash(publicKey)).bytes).substring(0, 32);
    if (deviceId != expectedId) {
      return _fail(request, 400, 'deviceId 必须等于 hex(SHA-256(公钥))[:32]');
    }
    if (descriptor.isEmpty) return _fail(request, 400, 'descriptor 不能为空');
    try {
      jsonDecode(descriptor);
    } on FormatException {
      return _fail(request, 400, 'descriptor 必须是合法 JSON');
    }
    if ((_nowSeconds() - timestamp).abs() > 120) {
      return _fail(request, 403, '设备绑定校验失败: 时间戳超出允许范围');
    }
    final challenge = _consume('register', account.username, deviceId);
    if (challenge == null || challenge.nonce != nonce) {
      return _fail(request, 403, '设备绑定校验失败: 挑战无效或已过期');
    }
    if (devices.length >= 5) return _fail(request, 403, '设备数量已达上限 5');

    final descriptorHash = hexOf((await Sha256().hash(utf8.encode(descriptor))).bytes);
    final canonical = <String>[
      'irix-device-register-v1',
      account.username,
      deviceId,
      publicKeyB64,
      keyType,
      keyProtection,
      descriptorHash,
      '$timestamp',
      nonce,
      challenge.tlsFingerprint,
    ].join('\n');
    final verified = await _verifyEd25519(
      publicKey,
      utf8.encode(canonical),
      unb64u(signature),
    );
    lastRegisterVerified = verified;
    if (!verified) return _fail(request, 403, '设备绑定校验失败: 注册签名校验失败');

    devices[deviceId] = _Device(
      deviceId: deviceId,
      publicKey: publicKey,
      keyType: keyType,
      keyProtection: keyProtection,
      descriptor: descriptor,
      name: name,
    );
    await _ok(request, {
      'deviceId': deviceId,
      'keyType': keyType,
      'keyProtection': keyProtection,
      'descriptor': descriptor,
      'name': name,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'lastSeen': 0,
    });
  }

  // ---------------------------------------------------------------- 列表 / 撤销

  Future<void> _listDevices(HttpRequest request) async {
    final session = _sessionOf(request);
    if (session == null) {
      return _fail(request, 403, '未认证或会话已过期（请先登录 POST /api/auth/login）');
    }
    await _ok(request, [
      for (final device in devices.values)
        {
          'deviceId': device.deviceId,
          'keyType': device.keyType,
          'keyProtection': device.keyProtection,
          'descriptor': device.descriptor,
          'name': device.name,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'lastSeen': device.lastSeen,
        },
    ]);
  }

  Future<void> _revoke(HttpRequest request, Map<String, dynamic> body) async {
    final session = _sessionOf(request);
    if (session == null) {
      return _fail(request, 403, '未认证或会话已过期（请先登录 POST /api/auth/login）');
    }
    if ((body['password'] as String? ?? '') != alice.password) {
      return _fail(request, 403, '密码错误');
    }
    final deviceId = body['deviceId'] as String? ?? '';
    if (!devices.containsKey(deviceId)) return _fail(request, 404, '设备不存在');
    if (alice.policy == 'required' && devices.length == 1) {
      return _fail(request, 403, 'required 策略下不能撤销最后一台设备');
    }
    devices.remove(deviceId);
    revokeSessionsOf(session.username);
    await _ok(request, '');
  }

  // ---------------------------------------------------------------- 登录

  Future<void> _login(HttpRequest request, Map<String, dynamic> body) async {
    loginRequests++;
    final username = body['username'] as String? ?? '';
    final password = body['password'] as String? ?? '';
    final account = _accounts[username];
    if (account == null || password != account.password) {
      return _fail(request, 401, '用户名或密码错误');
    }
    final device = body['device'];
    lastLoginHadDevice = device is Map<String, dynamic>;
    if (device is! Map<String, dynamic>) {
      if (account.policy == 'required') {
        return _fail(request, 403, '必须使用已绑定设备（账户已启用 required 策略）');
      }
      final session = _newSession(username);
      return _ok(request, _loginPayload(session, account));
    }

    // 设备登录：节点 TLS 关闭时不允许（§9）。
    if (tlsFingerprint.isEmpty) {
      return _fail(request, 403, '设备登录需要节点启用 TLS');
    }
    final deviceId = device['deviceId'] as String? ?? '';
    final nonce = device['nonce'] as String? ?? '';
    final timestamp = (device['timestamp'] as num?)?.toInt() ?? 0;
    final signature = device['signature'] as String? ?? '';
    if ((_nowSeconds() - timestamp).abs() > 120) {
      return _fail(request, 403, '设备绑定校验失败: 时间戳超出允许范围');
    }
    final proofKey = unb64u(device['proofKey'] as String? ?? '');
    if (proofKey.length != 32) {
      return _fail(request, 403, '设备绑定校验失败: proofKey 格式非法');
    }
    final challenge = _consume('login', username, deviceId);
    if (challenge == null || challenge.nonce != nonce) {
      return _fail(request, 403, '设备绑定校验失败: 挑战无效或已过期');
    }
    final record = devices[deviceId];
    if (record == null) {
      return _fail(request, 403, '设备绑定校验失败: 设备未注册');
    }
    final canonical = <String>[
      'irix-device-login-v1',
      username,
      deviceId,
      nonce,
      '$timestamp',
      device['proofKey'] as String? ?? '',
      challenge.tlsFingerprint,
    ].join('\n');
    if (!await _verifyEd25519(record.publicKey, utf8.encode(canonical), unb64u(signature))) {
      return _fail(request, 403, '设备绑定校验失败: 登录签名校验失败');
    }
    record.lastSeen = DateTime.now().millisecondsSinceEpoch;
    final session = _newSession(username, deviceId: deviceId, proofKey: proofKey);
    await _ok(request, _loginPayload(session, account));
  }

  Map<String, dynamic> _loginPayload(_Session session, _Account account) => {
    'token': session.token,
    'username': account.username,
    'isAdmin': true,
    'expiresAt': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    if (session.deviceBound) 'deviceBound': true,
    if (session.deviceBound) 'deviceId': session.deviceId,
  };

  // ---------------------------------------------------------------- 业务请求

  Future<void> _overview(HttpRequest request) async {
    final session = _sessionOf(request);
    if (session == null) {
      return _fail(request, 403, '未认证或会话已过期（请先登录 POST /api/auth/login）');
    }
    if (session.deviceBound) {
      final error = await _verifyProof(request, session);
      if (error != null) {
        proofFailures++;
        return _fail(request, 403, error);
      }
      proofVerifiedCount++;
    }
    await _ok(request, {'cpuUsage': 0.5, 'deviceBound': session.deviceBound});
  }

  Future<void> _me(HttpRequest request) async {
    final session = _sessionOf(request);
    if (session == null) {
      return _fail(request, 403, '未认证或会话已过期（请先登录 POST /api/auth/login）');
    }
    final error = session.deviceBound ? await _verifyProof(request, session) : null;
    if (error != null) {
      proofFailures++;
      return _fail(request, 403, error);
    }
    if (session.deviceBound) proofVerifiedCount++;
    await _ok(request, {
      'username': session.username,
      'isAdmin': true,
      'devicePolicy': alice.policy,
      'deviceCount': devices.length,
      'deviceBound': session.deviceBound,
    });
  }

  /// 校验 4 个证明头（§6）。返回 null 表示通过，否则为服务端错误文案。
  Future<String?> _verifyProof(HttpRequest request, _Session session) async {
    const failure = '设备凭据校验失败（缺少或无效的 X-Device-Id / X-Session-* 请求头）';
    final deviceId = request.headers.value('X-Device-Id');
    final timestampText = request.headers.value('X-Session-Timestamp');
    final seqText = request.headers.value('X-Session-Seq');
    final proof = request.headers.value('X-Session-Proof');
    if (deviceId == null ||
        timestampText == null ||
        seqText == null ||
        proof == null ||
        deviceId.isEmpty ||
        timestampText.isEmpty ||
        seqText.isEmpty ||
        proof.isEmpty) {
      return failure;
    }
    if (deviceId != session.deviceId) {
      return '设备凭据校验失败：X-Device-Id 与会话绑定值不一致';
    }
    lastProofDeviceId = deviceId;

    final timestamp = int.tryParse(timestampText);
    if (timestamp == null || (_nowSeconds() - timestamp).abs() > 120) {
      return failure;
    }
    final seq = int.tryParse(seqText);
    if (seq == null || seq <= 0) return failure;
    if (session.seenSeq.contains(seq)) return '设备凭据校验失败：请求序号重复（重放）';
    if (session.maxSeq - seq >= 1024) return '设备凭据校验失败：请求序号超出窗口';
    final requestUri = request.uri.hasQuery
        ? '${request.uri.path}?${request.uri.query}'
        : request.uri.path;
    final canonical = <String>[
      'irix-proof-v1',
      request.method.toUpperCase(),
      requestUri,
      timestampText,
      seqText,
    ].join('\n');
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(canonical),
      secretKey: SecretKey(session.proofKey!),
    );
    if (b64u(mac.bytes) != proof) {
      return '设备凭据校验失败：X-Session-Proof 与服务端计算结果不一致';
    }

    session.seenSeq.add(seq);
    if (seq > session.maxSeq) session.maxSeq = seq;
    seenProofSeq.add(seq);
    return null;
  }

  // ---------------------------------------------------------------- 工具

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static Future<bool> _verifyEd25519(
    List<int> publicKey,
    List<int> message,
    List<int> signature,
  ) async {
    try {
      return await Ed25519().verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _ok(HttpRequest request, Object? data) =>
      _write(request, 200, data);

  Future<void> _fail(HttpRequest request, int status, String message) =>
      _write(request, status, message);

  Future<void> _write(HttpRequest request, int status, Object? data) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'status': status,
          'data': data,
          'time': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    await request.response.close();
  }
}

void main() {
  late Directory keyDir;
  late _FakeIrixNode server;

  const nodeId = 'node-device-test';

  NodeInfo nodeOf({String id = nodeId}) => NodeInfo(
    id: id,
    name: '测试节点',
    type: NodeType.node,
    address: server.baseUrl,
    apiKey: '',
    accountUser: 'alice',
    accountPassword: 'secret-pass',
  );

  setUpAll(() async {
    keyDir = await Directory.systemTemp.createTemp('xmc_device_binding_it_');
    await DeviceAuthService.instance.initForTesting(keyDir.path);
  });

  tearDownAll(() async {
    try {
      await keyDir.delete(recursive: true);
    } catch (_) {
      // Windows 上文件可能仍被占用，交给系统清理。
    }
  });

  setUp(() async {
    NodeApiClient.forgetAllSessions();
    await DeviceAuthService.instance.deleteKey(clearBindings: true);
    server = await _FakeIrixNode.start();
  });

  tearDown(() async {
    NodeApiClient.forgetAllSessions();
    await server.stop();
  });

  test('未绑定设备时保持旧行为：纯密码登录、不带证明头', () async {
    final data = await NodeApiClient.of(nodeOf()).overview();
    expect(data, isNotNull);
    expect(server.loginRequests, 1);
    expect(server.lastLoginHadDevice, isFalse);
    expect(server.seenProofSeq, isEmpty);
    expect(DeviceAuthService.instance.isAvailable, isTrue,
        reason: '设备绑定模块应可加载；不可用时本用例会退化为密码登录');
  });

  test('optional 策略：绑定设备后登录响应 deviceBound=true，请求带有效证明头', () async {
    final node = nodeOf();
    final client = NodeApiClient.of(node);
    final service = NodeDeviceService(client: client, nodeId: node.id);

    final binding = await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );
    expect(binding.deviceId.length, 32);
    expect(binding.tlsFingerprint, server.tlsFingerprint);
    expect(server.devices.keys, contains(binding.deviceId));
    expect(server.lastRegisterVerified, isTrue, reason: '注册签名必须可被服务端验证');

    // 绑定后会话必须是 deviceBound（bind 内部重新登录并校验过）。
    final session = NodeApiClient.of(node).session;
    expect(session, isNotNull);
    expect(session!.deviceBound, isTrue);
    expect(session.deviceId, binding.deviceId);

    // 后续请求必须带 4 个证明头并通过服务端校验（HMAC 规范串逐字节正确）。
    await NodeApiClient.of(node).overview();
    expect(server.proofVerifiedCount, greaterThanOrEqualTo(1));
    expect(server.proofFailures, 0);
    expect(server.lastProofDeviceId, binding.deviceId);
  });

  test('逐请求证明：每个请求分配新序号且递增', () async {
    final node = nodeOf();
    final service = NodeDeviceService(
      client: NodeApiClient.of(node),
      nodeId: node.id,
    );
    await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );

    await NodeApiClient.of(node).overview();
    await NodeApiClient.of(node).overview();
    expect(server.seenProofSeq.length, greaterThanOrEqualTo(2));
    final seqs = server.seenProofSeq;
    for (var i = 1; i < seqs.length; i++) {
      expect(seqs[i], isNot(seqs[i - 1]), reason: '序号不得复用（服务端会判重放）');
      expect(seqs[i], greaterThan(seqs[i - 1]));
    }
  });

  test('required 策略：已绑定设备可登录，未绑定则 403 并给出可操作错误', () async {
    final node = nodeOf();
    final service = NodeDeviceService(
      client: NodeApiClient.of(node),
      nodeId: node.id,
    );
    await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );

    server.policy = 'required';
    NodeApiClient.forgetSession(node.id);
    final data = await NodeApiClient.of(node).overview();
    expect(data, isNotNull, reason: 'required + 已绑定设备必须能登录');
    expect(NodeApiClient.of(node).session!.deviceBound, isTrue);

    // 另一台「未绑定」的客户端（清掉绑定记录模拟）登录应被拒绝。
    await DeviceAuthService.instance.removeBinding(node.id);
    NodeApiClient.forgetSession(node.id);
    await expectLater(
      NodeApiClient.of(node).overview(),
      throwsA(
        isA<NodeDeviceBindingException>().having(
          (e) => e.message,
          'message',
          contains('必须使用已绑定设备'),
        ),
      ),
    );
  });

  test('TLS 指纹不一致时中止登录，且不向服务端发送密码', () async {
    final node = nodeOf();
    final service = NodeDeviceService(
      client: NodeApiClient.of(node),
      nodeId: node.id,
    );
    final binding = await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );
    expect(binding.tlsFingerprint, isNotEmpty);

    // 服务端换证书（或中间人）：指纹与配对时记录的不一致。
    server.tlsFingerprint = 'fp-changed-by-attacker';
    NodeApiClient.forgetSession(node.id);
    final loginsBefore = server.loginRequests;

    await expectLater(
      NodeApiClient.of(node).overview(),
      throwsA(
        isA<DeviceAuthException>().having(
          (e) => e.message,
          'message',
          contains('指纹'),
        ),
      ),
    );
    expect(
      server.loginRequests,
      loginsBefore,
      reason: '指纹校验失败必须在发送密码之前中止（协议 §9）',
    );
  });

  test('设备列表与撤销：撤销后本地记录清除并回到密码登录', () async {
    final node = nodeOf();
    final client = NodeApiClient.of(node);
    final service = NodeDeviceService(client: client, nodeId: node.id);
    final binding = await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );

    final devices = await service.listDevices();
    expect(devices, hasLength(1));
    expect(devices.first.deviceId, binding.deviceId);
    expect(devices.first.name, '测试机');

    await service.revoke(deviceId: binding.deviceId, password: 'secret-pass');
    expect(server.devices, isEmpty);
    expect(await DeviceAuthService.instance.bindingFor(node.id), isNull);

    // 撤销会注销全部会话；绑定记录已清除，后续回到密码登录（optional）。
    final data = await NodeApiClient.of(node).overview();
    expect(data, isNotNull);
    expect(server.lastLoginHadDevice, isFalse);
  });

  test('本机密钥被删除后：optional 账户退回密码登录，可重新绑定新密钥', () async {
    final node = nodeOf();
    final oldKey = await DeviceAuthService.instance.ensureKey();
    final service = NodeDeviceService(
      client: NodeApiClient.of(node),
      nodeId: node.id,
    );
    final oldBinding = await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );
    expect(oldBinding.deviceId, oldKey.deviceId);

    // 删除密钥但保留绑定记录（模拟换机器 / 密钥文件损坏）。
    await DeviceAuthService.instance.deleteKey(clearBindings: false);
    NodeApiClient.forgetSession(node.id);

    // optional 策略下仍能用密码登录（不会卡死在不可用的设备签名上）。
    final data = await NodeApiClient.of(node).overview();
    expect(data, isNotNull);
    expect(server.lastLoginHadDevice, isFalse, reason: '密钥缺失时应退回密码登录');

    // 重新绑定会生成新密钥、注册新设备并覆盖本地记录。
    final newBinding = await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '新机器',
    );
    expect(newBinding.deviceId, isNot(oldKey.deviceId));
    expect(server.devices.keys, contains(newBinding.deviceId));
    await NodeApiClient.of(node).overview();
    expect(server.proofFailures, 0);
    expect(server.lastProofDeviceId, newBinding.deviceId);
  });

  test('required 策略 + 本机密钥缺失：提示重新绑定设备', () async {
    final node = nodeOf();
    final service = NodeDeviceService(
      client: NodeApiClient.of(node),
      nodeId: node.id,
    );
    await service.bind(
      username: 'alice',
      password: 'secret-pass',
      deviceName: '测试机',
    );
    await DeviceAuthService.instance.deleteKey(clearBindings: false);
    server.policy = 'required';
    NodeApiClient.forgetSession(node.id);

    await expectLater(
      NodeApiClient.of(node).overview(),
      throwsA(
        isA<NodeDeviceBindingException>()
            .having((e) => e.message, 'message', contains('必须使用已绑定设备'))
            .having((e) => e.message, 'message', contains('重新绑定设备')),
      ),
    );
  });

  test('注册接口本身要求账户密码（仅有会话 token 不能偷偷加设备）', () async {
    final node = nodeOf();
    final key = await DeviceAuthService.instance.ensureKey();
    final challenge = await NodeApiClient.of(node).deviceChallenge(
      username: 'alice',
      deviceId: key.deviceId,
      purpose: 'register',
    );
    final descriptor = await DeviceAuthService.instance.descriptorJson();
    final hash = await DeviceAuthService.instance.sha256Hex(descriptor);
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final canonical = <String>[
      'irix-device-register-v1',
      'alice',
      key.deviceId,
      key.publicKey,
      key.keyType,
      key.keyProtection,
      hash,
      timestamp,
      challenge.nonce,
      challenge.tlsFingerprint,
    ].join('\n');
    final signature = await DeviceAuthService.instance.sign(canonical);

    await expectLater(
      NodeApiClient.of(node).registerDevice(
        deviceId: key.deviceId,
        publicKey: key.publicKey,
        keyType: key.keyType,
        keyProtection: key.keyProtection,
        descriptor: descriptor,
        name: '测试机',
        nonce: challenge.nonce,
        timestamp: timestamp,
        signature: signature,
        password: 'wrong-password',
      ),
      throwsA(
        isA<NodeApiException>().having(
          (e) => e.message,
          'message',
          contains('密码错误'),
        ),
      ),
    );
    expect(server.devices, isEmpty);
  });
}
