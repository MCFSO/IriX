// ChmlFrp 提供商实现
//
// 认证方式（2026 新版）：SSO 网页授权登录。
// - 浏览器打开 cf-v2.uapis.cn/sso/authorize?return_url=<本地回调>，
//   登录授权后跳回 `回调#access_token=...&refresh_token=...&expires_in=...`；
// - 所有 API 请求携带 `Authorization: Bearer <access_token>`（需 `waf: off` 头）；
// - access_token 失效时自动用 refresh_token 调 /sso/refresh 刷新并重试。
// 隧道管理（列表/创建/删除/配置）与节点列表沿用 v2 API，不接入域名管理。

import 'dart:convert';

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';
import '../services/http_ffi.dart';

/// ChmlFrp 面板 API 基础地址。
///
/// 安全说明（H-5）：必须使用 HTTPS——access_token / refresh_token 等
/// 长期凭据经明文 HTTP 传输可被同网段嗅探窃取。
const chmlFrpApiBase = 'https://cf-v2.uapis.cn';

/// 注册跳转地址（IriX 不提供注册，引导用户前往官网注册）。
const chmlFrpRegisterUrl = 'https://account.qzhua.net/register';

class ChmlFrpProvider extends FrpProvider {
  static const _keyAccessToken = 'chmlfrp_access_token';
  static const _keyRefreshToken = 'chmlfrp_refresh_token';
  static const _keyExpiresAt = 'chmlfrp_token_expires_at';

  @override
  String get id => 'chmlfrp';

  @override
  String get label => 'ChmlFrp';

  /// ChmlFrp 服务端返回 INI 配置，需用其官方 INI 版 frpc。
  @override
  String get frpcFlavor => 'chmlfrp';

  /// 不接入域名（二级域名）功能，仅 tcp / udp。
  @override
  bool get supportsWebTunnels => false;

  Future<String?> _accessToken() =>
      DatabaseManager.instance.getSetting(_keyAccessToken);

  Future<String?> _refreshToken() =>
      DatabaseManager.instance.getSetting(_keyRefreshToken);

  Future<Map<String, String>> _headers() async {
    final token = await _accessToken();
    return {
      'Content-Type': 'application/json;charset=UTF-8',
      'waf': 'off',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 请求是否因登录态失效需要刷新。
  bool _needsRefresh(HttpFfiResponse res) {
    if (res.statusCode == 401) return true;
    try {
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = (json['msg'] ?? '').toString();
      return msg.contains('登录态') || msg.contains('令牌');
    } catch (_) {
      return false;
    }
  }

  /// 用 refresh_token 刷新 access_token，成功返回 true。
  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _refreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await HttpFfiService.instance.post(
        '$chmlFrpApiBase/sso/refresh',
        headers: await _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
        timeout: const Duration(seconds: 30),
      );
      if (res.statusCode != 200) return false;
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = json['data'] is Map ? json['data'] as Map : null;
      final accessToken = data?['access_token']?.toString();
      if (accessToken == null || accessToken.isEmpty) return false;
      await _saveTokens(
        accessToken: accessToken,
        refreshToken: (data?['refresh_token'] ?? refreshToken).toString(),
        expiresAt: data?['expires_at'],
        expiresIn: data?['expires_in'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var res = await _send(method, path, body: body);
    if (_needsRefresh(res)) {
      // 自动刷新并重试一次。
      if (await _refreshAccessToken()) {
        res = await _send(method, path, body: body);
      }
    }
    return _parse(res);
  }

  Future<HttpFfiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = '$chmlFrpApiBase$path';
    final headers = await _headers();
    final res = method == 'GET'
        ? await HttpFfiService.instance.get(
            uri,
            headers: headers,
            timeout: const Duration(seconds: 30),
          )
        : await HttpFfiService.instance.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
            timeout: const Duration(seconds: 30),
          );
    if (res.statusCode >= 500) {
      throw Exception('HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    return res;
  }

  Map<String, dynamic> _parse(HttpFfiResponse res) {
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('服务器返回空响应');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 200 || json['state'] != 'success') {
      throw Exception((json['msg'] ?? '请求失败').toString());
    }
    return json;
  }

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    Object? expiresAt,
    Object? expiresIn,
  }) async {
    await DatabaseManager.instance.setSetting(
      _keyAccessToken,
      accessToken.trim(),
    );
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await DatabaseManager.instance.setSetting(_keyRefreshToken, refreshToken);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    int? expires = expiresAt is num ? expiresAt.toInt() : null;
    if (expires == null && expiresIn is num) {
      expires = now + expiresIn.toInt() * 1000;
    }
    await DatabaseManager.instance.setSetting(
      _keyExpiresAt,
      '${expires ?? now}',
    );
  }

  FrpAccountInfo _toAccount(Map<String, dynamic> data) => FrpAccountInfo(
    title: (data['username'] ?? '').toString(),
    subtitle: (data['email'] ?? '').toString(),
    group: (data['usergroup'] ?? '').toString(),
    usage: '${data['tunnel']}/${data['tunnnelCount'] ?? data['tunnel']}',
    extra: '积分 ${data['integral']}',
  );

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) return null;
    try {
      final json = await _request('GET', '/userinfo');
      return _toAccount(json['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FrpAccountInfo> login(Map<String, String> credentials) async {
    final accessToken = (credentials['access_token'] ?? '').trim();
    if (accessToken.isEmpty) {
      throw Exception('登录失败：未获取到访问令牌');
    }
    await _saveTokens(
      accessToken: accessToken,
      refreshToken: credentials['refresh_token'],
      expiresAt: credentials['expires_at'],
      expiresIn: credentials['expires_in'],
    );
    final json = await _request('GET', '/userinfo');
    return _toAccount(json['data'] as Map<String, dynamic>);
  }

  @override
  Future<void> logout() async {
    await FrpcManager.instance.stopAll();
    await DatabaseManager.instance.setSetting(_keyAccessToken, '');
    await DatabaseManager.instance.setSetting(_keyRefreshToken, '');
    await DatabaseManager.instance.setSetting(_keyExpiresAt, '');
  }

  @override
  Future<List<FrpTunnel>> listTunnels() async {
    final json = await _request('GET', '/tunnel');
    final list = (json['data'] as List?) ?? [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>)
          FrpTunnel(
            id: (e['tunnelID'] ?? 0).toString(),
            name: (e['tunnelName'] ?? '').toString(),
            type: (e['portType'] ?? 'tcp').toString().toLowerCase(),
            localAddr: (e['localIP'] ?? '127.0.0.1').toString(),
            localPort: (e['localPort'] as num?)?.toInt() ?? 0,
            remotePort: (e['remotePort'] as num?)?.toInt(),
            remoteAddress: (e['ip'] ?? '').toString(),
            nodeName: (e['node'] ?? '').toString(),
            online: (e['tunnelState'] ?? '').toString() == 'true',
            enabled: (e['tunnelState'] ?? '').toString() == 'true',
            useEncryption: (e['encryption'] ?? '').toString() == 'true',
            useCompression: (e['compression'] ?? '').toString() == 'true',
          ),
    ];
  }

  @override
  Future<List<FrpNode>> listNodes() async {
    final json = await _request('GET', '/node');
    final list = (json['data'] as List?) ?? [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>)
          FrpNode(
            id: (e['id'] as num?)?.toInt() ?? 0,
            name: (e['name'] ?? '').toString(),
          ),
    ];
  }

  @override
  Future<void> createTunnel(FrpTunnelDraft draft) async {
    final nodes = await listNodes();
    final nodeName = nodes.where((n) => n.id == draft.nodeId).firstOrNull?.name;
    if (nodeName == null || nodeName.isEmpty) {
      throw Exception('请选择节点');
    }
    final isWeb = draft.type == 'http' || draft.type == 'https';
    await _request(
      'POST',
      '/create_tunnel',
      body: {
        'tunnelname': draft.name,
        'node': nodeName,
        'localip': draft.localAddr,
        'porttype': draft.type,
        'localport': draft.localPort,
        if (isWeb) 'banddomain': draft.domain,
        if (!isWeb) 'remoteport': draft.remotePort ?? 0,
        'encryption': draft.encrypt,
        'compression': draft.gzip,
      },
    );
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    await FrpcManager.instance.stop('chmlfrp-$tunnelId');
    await _request('POST', '/delete_tunnel', body: {'tunnelid': tunnelId});
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final tunnels = await listTunnels();
    final tunnel = tunnels.where((t) => t.id == tunnelId).firstOrNull;
    if (tunnel == null) throw Exception('隧道不存在');
    final json = await _request(
      'POST',
      '/tunnel_config',
      body: {'node': tunnel.nodeName, 'tunnel_names': tunnel.name},
    );
    final config = (json['data'] ?? '').toString();
    if (config.trim().isEmpty) throw Exception('获取隧道配置失败');
    // ChmlFrp 服务端返回 frpc.ini（INI 格式），需用其官方 INI 版 frpc 启动。
    await FrpcManager.instance.startWithConfig(
      config,
      'chmlfrp-$tunnelId',
      flavor: frpcFlavor,
    );
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('chmlfrp-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('chmlfrp-$tunnelId');

  @override
  String tunnelKey(String tunnelId) => 'chmlfrp-$tunnelId';

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('chmlfrp-$tunnelId');

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
