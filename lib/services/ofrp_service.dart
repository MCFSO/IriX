// OpenFrp 开放映射 API 服务
//
// 基于 OpenFrp OPENAPI（https://api.openfrp.net）实现：
// Remote Login 远程安全登录（ofapi.md 推荐给第三方）、
// 用户信息、隧道列表、节点列表、新建/删除隧道。
// 注意：任意接口响应头可能返回新的 Authorization，需要自动更新保存。
//
// 本项目使用 OpenFrp OPENAPI，按条款需在明显位置注明来源。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pinenacl/x25519.dart' as nacl;

import '../services/database_manager.dart';

const _apiBase = 'https://api.openfrp.net';
const _ua = 'IriX/1.0.0 (https://github.com/MCFSO/IriX)';

/// OpenFrp 用户信息。
class OfrpUserInfo {
  final String username;
  final String email;
  final String friendlyGroup;
  final String group;
  final int proxies;
  final int used;
  final int traffic;
  final bool realname;

  const OfrpUserInfo({
    required this.username,
    required this.email,
    required this.friendlyGroup,
    required this.group,
    required this.proxies,
    required this.used,
    required this.traffic,
    required this.realname,
  });

  factory OfrpUserInfo.fromJson(Map<String, dynamic> json) => OfrpUserInfo(
    username: (json['username'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    friendlyGroup: (json['friendlyGroup'] ?? '').toString(),
    group: (json['group'] ?? '').toString(),
    proxies: (json['proxies'] as num?)?.toInt() ?? 0,
    used: (json['used'] as num?)?.toInt() ?? 0,
    traffic: (json['traffic'] as num?)?.toInt() ?? 0,
    realname: json['realname'] == true,
  );
}

/// 一条 OpenFrp 隧道。
class OfrpProxy {
  final int id;
  final String proxyName;
  final String proxyType;
  final String localIp;
  final int localPort;
  final int? remotePort;
  final String connectAddress;
  final String friendlyNode;
  final bool online;
  final bool status;
  final bool useEncryption;
  final bool useCompression;
  final String? domain;

  const OfrpProxy({
    required this.id,
    required this.proxyName,
    required this.proxyType,
    required this.localIp,
    required this.localPort,
    this.remotePort,
    required this.connectAddress,
    required this.friendlyNode,
    required this.online,
    required this.status,
    required this.useEncryption,
    required this.useCompression,
    this.domain,
  });

  factory OfrpProxy.fromJson(Map<String, dynamic> json) => OfrpProxy(
    id: (json['id'] as num).toInt(),
    proxyName: (json['proxyName'] ?? '').toString(),
    proxyType: (json['proxyType'] ?? 'tcp').toString(),
    localIp: (json['localIp'] ?? '127.0.0.1').toString(),
    localPort: (json['localPort'] as num).toInt(),
    remotePort: (json['remotePort'] as num?)?.toInt(),
    connectAddress: (json['connectAddress'] ?? '').toString(),
    friendlyNode: (json['friendlyNode'] ?? '').toString(),
    online: json['online'] == true,
    status: json['status'] == true,
    useEncryption: json['useEncryption'] == true,
    useCompression: json['useCompression'] == true,
    domain: json['domain'] as String?,
  );
}

/// 一个 OpenFrp 节点。
class OfrpNode {
  final int id;
  final String name;
  final String description;
  final String group;
  final int status;
  final bool fullyLoaded;
  final bool needRealname;
  final int classify;
  final String? allowPort;
  final Map<String, bool> protocolSupport;

  const OfrpNode({
    required this.id,
    required this.name,
    required this.description,
    required this.group,
    required this.status,
    required this.fullyLoaded,
    required this.needRealname,
    required this.classify,
    this.allowPort,
    required this.protocolSupport,
  });

  /// 是否可新建隧道（节点正常且未满载）。
  bool get available => status == 200 && !fullyLoaded;

  factory OfrpNode.fromJson(Map<String, dynamic> json) => OfrpNode(
    id: (json['id'] as num).toInt(),
    name: (json['name'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    group: (json['group'] ?? '').toString(),
    status: (json['status'] as num?)?.toInt() ?? 0,
    fullyLoaded: json['fullyLoaded'] == true,
    needRealname: json['needRealname'] == true,
    classify: (json['classify'] as num?)?.toInt() ?? 0,
    allowPort: json['allowPort'] as String?,
    protocolSupport: {
      for (final e in ((json['protocolSupport'] as Map?) ?? {}).entries)
        e.key.toString(): e.value == true,
    },
  );
}

/// OpenFrp frpc 软件资源信息。
class OfrpSoftwareInfo {
  final String latestFull;
  final List<String> sources;

  const OfrpSoftwareInfo({required this.latestFull, required this.sources});

  factory OfrpSoftwareInfo.fromJson(Map<String, dynamic> json) =>
      OfrpSoftwareInfo(
        latestFull: (json['latest_full'] ?? '').toString(),
        sources: [
          for (final e in ((json['source'] as List?) ?? []))
            if (e is Map) (e['value'] ?? '').toString(),
        ],
      );
}

/// 远程登录尚未授权（轮询中的常见状态），调用方应继续轮询。
class PendingAuthorizationException implements Exception {
  const PendingAuthorizationException();

  @override
  String toString() => '尚未授权';
}

/// OpenFrp API 服务（单例）。
class OfrpService {
  static final OfrpService instance = OfrpService._();
  OfrpService._();

  static const _keyAuth = 'ofrp_auth';

  // === 认证存储 ===

  Future<String?> getAuth() async {
    try {
      return await DatabaseManager.instance.getSetting(_keyAuth);
    } catch (e) {
      return null;
    }
  }

  Future<void> setAuth(String auth) async {
    await DatabaseManager.instance.setSetting(_keyAuth, auth.trim());
  }

  Future<void> clearAuth() async {
    await DatabaseManager.instance.setSetting(_keyAuth, '');
  }

  // === 基础请求 ===

  Map<String, String> _headers(String auth) => {
    'Content-Type': 'application/json',
    'User-Agent': _ua,
    'Authorization': auth,
  };

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body,
    String auth,
  ) async {
    final res = await http
        .post(
          Uri.parse('$_apiBase$path'),
          headers: _headers(auth),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    return res;
  }

  /// 解析统一响应结构 {flag, msg, data}，失败抛异常。
  Map<String, dynamic> _parse(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['flag'] != true) {
      throw Exception((json['msg'] ?? '请求失败').toString());
    }
    return json;
  }

  /// 文档说明：任意接口响应头有概率返回新的 Authorization，需要自动更新。
  Future<void> _maybeUpdateAuth(http.Response res) async {
    final newAuth = res.headers['authorization'];
    if (newAuth == null || newAuth.isEmpty) return;
    final current = await getAuth();
    if (current != newAuth) {
      await setAuth(newAuth);
    }
  }

  // === API ===

  /// 获取用户信息。
  Future<OfrpUserInfo> getUserInfo(String auth) async {
    final res = await _post('/frp/api/getUserInfo', {}, auth);
    await _maybeUpdateAuth(res);
    return OfrpUserInfo.fromJson(_parse(res)['data'] as Map<String, dynamic>);
  }

  /// 获取隧道列表。
  Future<List<OfrpProxy>> getProxies(String auth) async {
    final res = await _post('/frp/api/getUserProxies', {}, auth);
    await _maybeUpdateAuth(res);
    final data = _parse(res)['data'] as Map<String, dynamic>;
    return [
      for (final e in (data['list'] as List? ?? []))
        if (e is Map<String, dynamic>) OfrpProxy.fromJson(e),
    ];
  }

  /// 获取节点列表。
  Future<List<OfrpNode>> getNodes(String auth) async {
    final res = await _post('/frp/api/getNodeList', {}, auth);
    await _maybeUpdateAuth(res);
    final data = _parse(res)['data'] as Map<String, dynamic>;
    return [
      for (final e in (data['list'] as List? ?? []))
        if (e is Map<String, dynamic>) OfrpNode.fromJson(e),
    ];
  }

  /// 新建隧道。
  Future<void> newProxy(
    String auth, {
    required String name,
    required int nodeId,
    required String type,
    required String localAddr,
    required int localPort,
    int? remotePort,
    String domain = '',
    bool forceHttps = false,
    bool encrypt = false,
    bool gzip = false,
  }) async {
    final res = await _post('/frp/api/newProxy', {
      'autoTls': 'false',
      'custom': '',
      'dataEncrypt': encrypt,
      'dataGzip': gzip,
      'domain_bind': domain,
      'forceHttps': forceHttps,
      'local_addr': localAddr,
      'local_port': '$localPort',
      'name': name,
      'node_id': nodeId,
      'proxyProtocolVersion': false,
      'remote_port': remotePort ?? 0,
      'type': type,
    }, auth);
    await _maybeUpdateAuth(res);
    _parse(res);
  }

  /// 删除隧道。
  Future<void> removeProxy(String auth, int proxyId) async {
    final res = await _post('/frp/api/removeProxy', {
      'proxy_id': proxyId,
    }, auth);
    await _maybeUpdateAuth(res);
    _parse(res);
  }

  /// 获取 frpc 软件资源（下载源与最新版本）。
  Future<OfrpSoftwareInfo> getSoftwareInfo() async {
    final res = await http
        .get(
          Uri.parse('$_apiBase/commonQuery/get?key=software'),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('获取软件信息失败：服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['flag'] != true) {
      throw Exception((json['msg'] ?? '获取软件信息失败').toString());
    }
    return OfrpSoftwareInfo.fromJson(json['data'] as Map<String, dynamic>);
  }

  // === Remote Login 远程安全登录（ofapi.md 推荐方案） ===
  //
  // 流程：生成 Curve25519 密钥对 → requestLogin 提交公钥 →
  // 浏览器打开授权页授权 → 每 5s 轮询 pollLogin →
  // 解密 authorization_data 得到 Authorization。
  // 密钥生成与加解密格式参考 ofapi.md 引用的 cloudflared/encrypt.go。

  /// 生成 Curve25519 密钥对，返回 (公钥, 私钥)。
  Future<({String publicKey, SimpleKeyPair keyPair})>
  generateRemoteLoginKeys() async {
    final x25519 = X25519();
    final keyPair = await x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return (
      publicKey: base64UrlEncode(publicKey.bytes),
      keyPair: keyPair,
    );
  }

  /// 请求远程登录授权，返回 (授权 URL, 请求 UUID)。
  Future<({String authorizationUrl, String requestUuid})> requestRemoteLogin(
    String publicKey,
  ) async {
    final res = await http
        .post(
          Uri.parse('https://access.openfrp.net/argoAccess/requestLogin'),
          headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
          body: jsonEncode({'public_key': publicKey}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('请求授权失败 HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('请求授权失败：服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 200) {
      throw Exception((json['msg'] ?? '请求授权失败').toString());
    }
    final data = json['data'] as Map<String, dynamic>;
    final url = (data['authorization_url'] ?? '').toString();
    final uuid = (data['request_uuid'] ?? '').toString();
    if (url.isEmpty || uuid.isEmpty) {
      throw Exception('请求授权失败：返回数据不完整');
    }
    return (authorizationUrl: url, requestUuid: uuid);
  }

  /// 轮询授权结果，成功返回 (服务端公钥, 加密的授权数据)。
  ///
  /// 接口为 GET 请求（query 携带 request_uuid），用户尚未授权时返回
  /// HTTP 204，抛 [PendingAuthorizationException]，由调用方继续轮询。
  Future<({String serverPublicKey, String authorizationData})> pollRemoteLogin(
    String requestUuid,
  ) async {
    final res = await http
        .get(
          Uri.parse(
            'https://access.openfrp.net/argoAccess/pollLogin',
          ).replace(queryParameters: {'request_uuid': requestUuid}),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 204) {
      throw const PendingAuthorizationException();
    }
    if (res.statusCode != 200) {
      throw Exception('轮询授权失败 HTTP ${res.statusCode}');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('轮询授权失败：服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 200) {
      throw Exception((json['msg'] ?? '尚未授权').toString());
    }
    final data = json['data'] as Map<String, dynamic>;
    final authData = (data['authorization_data'] ?? '').toString();
    if (authData.isEmpty) {
      throw const PendingAuthorizationException();
    }
    final serverKey = res.headers['x-request-public-key'] ?? '';
    return (serverPublicKey: serverKey, authorizationData: authData);
  }

  /// 解密 authorization_data 得到 Authorization 明文。
  ///
  /// 服务端参考 cloudflared/token/encrypt.go 的 NaCl crypto_box 方案：
  /// authorization_data = base64(nonce 24B || 密文 || Poly1305 tag 16B)，
  /// 共享密钥 = X25519(客户端私钥, 服务端公钥)，服务端公钥来自
  /// pollLogin 响应头 X-Request-Public-Key。
  static Future<String> decryptAuthorization(
    String authorizationData,
    SimpleKeyPair keyPair,
    String serverPublicKey,
  ) async {
    final raw = base64Decode(authorizationData);
    if (raw.length < 24 + 16) {
      throw Exception('授权数据格式错误');
    }
    final serverPubBytes = base64Decode(serverPublicKey);
    if (serverPubBytes.length != 32) {
      throw Exception('服务端公钥格式错误');
    }
    final clientPriv = await keyPair.extractPrivateKeyBytes();

    final box = nacl.Box(
      myPrivateKey: nacl.PrivateKey(Uint8List.fromList(clientPriv)),
      theirPublicKey: nacl.PublicKey(serverPubBytes),
    );
    final plaintext = box.decrypt(
      nacl.EncryptedMessage(
        nonce: raw.sublist(0, 24),
        cipherText: raw.sublist(24),
      ),
    );
    final text = utf8.decode(plaintext);
    if (text.isEmpty) {
      throw Exception('授权数据解密失败');
    }
    return text;
  }

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}

/// 读取实例 server.properties 中的 server-port。
///
/// - 文件不存在返回 null（实例不出现在选择列表中）；
/// - 文件存在但未配置 server-port 时返回默认值 25565。
int? readInstanceServerPort(String rootPath) {
  final file = File(p.join(rootPath, 'server.properties'));
  if (!file.existsSync()) return null;
  try {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      if (trimmed.substring(0, eq).trim().toLowerCase() != 'server-port') {
        continue;
      }
      final port = int.tryParse(trimmed.substring(eq + 1).trim());
      if (port != null && port > 0 && port < 65536) return port;
    }
  } catch (_) {
    return null;
  }
  return 25565;
}
