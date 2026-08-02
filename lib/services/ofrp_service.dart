// OpenFrp 开放映射 API 服务
//
// 基于 OpenFrp OPENAPI（https://api.openfrp.net）实现：
// 会话密钥登录（Authorization）、用户信息、隧道列表、节点列表、新建/删除隧道。
// 登录方式采用官方推荐的「第三方客户端安全登录」：
// 用户在 OpenFrp 面板复制 Authorization 后粘贴即可。
// 注意：任意接口响应头可能返回新的 Authorization，需要自动更新保存。
//
// 本项目使用 OpenFrp OPENAPI，按条款需在明显位置注明来源。

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

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
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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

  /// 登录验证：携带 Authorization 请求用户信息，成功则保存认证。
  Future<OfrpUserInfo> login(String auth) async {
    final res = await _post('/frp/api/getUserInfo', {}, auth);
    await _maybeUpdateAuth(res);
    final json = _parse(res);
    await setAuth(auth);
    return OfrpUserInfo.fromJson(json['data'] as Map<String, dynamic>);
  }

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
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['flag'] != true) {
      throw Exception((json['msg'] ?? '获取软件信息失败').toString());
    }
    return OfrpSoftwareInfo.fromJson(json['data'] as Map<String, dynamic>);
  }

  // === OAuth 网页登录 ===

  /// 生成网页授权登录地址（Natayark ID OAuth2）。
  ///
  /// [port] 为本地回调服务器端口，授权完成后浏览器会跳转到
  /// `http://127.0.0.1:<port>/callback?code=xxx`。
  static String buildOAuthAuthorizeUrl(int port) {
    final redirect = Uri.encodeComponent('http://127.0.0.1:$port/callback');
    return 'https://account.naids.com/oauth2/authorize'
        '?response_type=code&redirect_uri=$redirect&client_id=openfrp';
  }

  /// 用回调 code 换取 Authorization（读取响应头）。
  Future<String> exchangeOAuthCode(String code) async {
    final res = await http
        .post(
          Uri.parse('https://api.openfrp.net/oauth2/callback?code=$code'),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('登录回调失败 HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    final auth = res.headers['authorization'];
    if (auth == null || auth.isEmpty) {
      throw Exception('回调响应中未找到 Authorization，请重试');
    }
    return auth;
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
