// HayFrp 提供商实现
//
// 基于 HayFrp API（https://api.hayfrp.1zyq1.com）：
// - 登录：用户名/邮箱 + 密码（POST /user type=login），获取 CSRF Token（7 天有效）；
// - 隧道：列表 / 添加 / 删除（POST /proxy），支持 tcp/udp/http/https；
// - 节点：公共接口 GET /nodes（无需鉴权）；
// - 启动：通过 /proxy type=config 获取 frpc 配置文件（toml），由 frpc -c 运行。
// 所有请求需携带请求头 `waf: off`。

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';

/// HayFrp API 基础地址。
const hayFrpApiBase = 'https://api.hayfrp.1zyq1.com';

class HayFrpProvider extends FrpProvider {
  static const _keyToken = 'hayfrp_token';

  @override
  String get id => 'hayfrp';

  @override
  String get label => 'HayFrp';

  Future<String?> _token() => DatabaseManager.instance.getSetting(_keyToken);

  Future<Map<String, dynamic>> _userPost(Map<String, dynamic> body) =>
      _post('/user', body);

  Future<Map<String, dynamic>> _proxyPost(Map<String, dynamic> body) =>
      _post('/proxy', body);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await http
        .post(
          Uri.parse('$hayFrpApiBase$path'),
          headers: {
            'Content-Type': 'application/json;charset=UTF-8',
            'waf': 'off',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http
        .get(Uri.parse('$hayFrpApiBase$path'), headers: {'waf': 'off'})
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('服务器返回空响应');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('响应格式错误');
    }
    return decoded;
  }

  /// 检查请求是否成功（status 为 200 或 true）。
  void _checkOk(Map<String, dynamic> json) {
    final status = json['status'];
    if (status != 200 && status != true) {
      throw Exception((json['message'] ?? '请求失败').toString());
    }
  }

  FrpAccountInfo _toAccount(Map<String, dynamic> data) => FrpAccountInfo(
    title: (data['username'] ?? '').toString(),
    subtitle: (data['email'] ?? '').toString(),
    group: data['realname'] == true ? '已实名' : null,
    traffic: data['traffic'] != null ? '${data['traffic']} MB' : null,
    usage: '${data['useproxies']}/${data['proxies']}',
  );

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final token = await _token();
    if (token == null || token.isEmpty) return null;
    try {
      final json = await _userPost({'type': 'info', 'csrf': token});
      if (json['status'] != true) return null;
      return _toAccount(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FrpAccountInfo> login(Map<String, String> credentials) async {
    final username = (credentials['username'] ?? '').trim();
    final password = credentials['password'] ?? '';
    if (username.isEmpty || password.isEmpty) {
      throw Exception('请输入用户名和密码');
    }
    final json = await _userPost({
      'type': 'login',
      'user': username,
      'passwd': password,
    });
    _checkOk(json);
    final token = (json['token'] ?? '').toString();
    if (token.isEmpty) throw Exception('登录失败：未获取到 Token');
    await DatabaseManager.instance.setSetting(_keyToken, token);
    final info = await _userPost({'type': 'info', 'csrf': token});
    if (info['status'] != true) {
      throw Exception('登录失败：无法获取用户信息');
    }
    return _toAccount(info);
  }

  @override
  Future<void> logout() async {
    await FrpcManager.instance.stopAll();
    await DatabaseManager.instance.setSetting(_keyToken, '');
  }

  @override
  Future<List<FrpTunnel>> listTunnels() async {
    final token = await _token();
    if (token == null || token.isEmpty) return [];
    final json = await _proxyPost({'type': 'list', 'csrf': token});
    _checkOk(json);
    final list = (json['proxies'] as List?) ?? [];
    final tunnels = <FrpTunnel>[];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      tunnels.add(_toTunnel(e));
    }
    // 并行检查在线状态。
    final onlineStates = await Future.wait([
      for (final t in tunnels) _checkOnline(token, t.id),
    ]);
    for (var i = 0; i < tunnels.length; i++) {
      tunnels[i] = _copyWithOnline(tunnels[i], onlineStates[i]);
    }
    return tunnels;
  }

  FrpTunnel _toTunnel(Map<String, dynamic> json) {
    final type = (json['proxy_type'] ?? 'tcp').toString().toLowerCase();
    final remotePort = int.tryParse((json['remote_port'] ?? '').toString());
    final nodeDomain = (json['node_domain'] ?? '').toString();
    final isWeb = type == 'http' || type == 'https';
    return FrpTunnel(
      id: (json['id'] ?? '').toString(),
      name: (json['proxy_name'] ?? '').toString(),
      type: type,
      localAddr: (json['local_ip'] ?? '127.0.0.1').toString(),
      localPort: int.tryParse((json['local_port'] ?? '').toString()) ?? 0,
      remotePort: isWeb ? null : remotePort,
      remoteAddress: isWeb
          ? (json['domain'] ?? '').toString()
          : nodeDomain.isEmpty
          ? ''
          : '$nodeDomain:$remotePort',
      nodeName: (json['node_name'] ?? '').toString(),
      enabled: (json['status'] ?? '').toString() == 'true',
      useEncryption: (json['use_encryption'] ?? '').toString() == 'true',
      useCompression: (json['use_compression'] ?? '').toString() == 'true',
    );
  }

  FrpTunnel _copyWithOnline(FrpTunnel tunnel, bool online) => FrpTunnel(
    id: tunnel.id,
    name: tunnel.name,
    type: tunnel.type,
    localAddr: tunnel.localAddr,
    localPort: tunnel.localPort,
    remotePort: tunnel.remotePort,
    remoteAddress: tunnel.remoteAddress,
    nodeName: tunnel.nodeName,
    online: online,
    enabled: tunnel.enabled,
    useEncryption: tunnel.useEncryption,
    useCompression: tunnel.useCompression,
    domain: tunnel.domain,
  );

  Future<bool> _checkOnline(String token, String tunnelId) async {
    try {
      final json = await _proxyPost({
        'type': 'check',
        'csrf': token,
        'id': tunnelId,
      });
      return (json['ostatus'] ?? '').toString() == 'online';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<FrpNode>> listNodes() async {
    final json = await _get('/nodes');
    final list = (json['servers'] as List?) ?? [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>)
          FrpNode(
            id: int.tryParse((e['id'] ?? '').toString()) ?? 0,
            name: (e['name'] ?? '').toString(),
          ),
    ];
  }

  @override
  Future<void> createTunnel(FrpTunnelDraft draft) async {
    final token = await _token();
    if (token == null || token.isEmpty) throw Exception('未登录');
    final isWeb = draft.type == 'http' || draft.type == 'https';
    final json = await _proxyPost({
      'type': 'add',
      'csrf': token,
      'proxy_name': draft.name,
      'proxy_type': draft.type,
      'local_ip': draft.localAddr,
      'local_port': draft.localPort,
      if (isWeb) 'domain': draft.domain,
      if (!isWeb) 'remote_port': draft.remotePort ?? 0,
      'use_encryption': draft.encrypt.toString(),
      'use_compression': draft.gzip.toString(),
      'node': '${draft.nodeId}',
    });
    _checkOk(json);
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    final token = await _token();
    if (token == null || token.isEmpty) return;
    await FrpcManager.instance.stop('hayfrp-$tunnelId');
    final json = await _proxyPost({
      'type': 'remove',
      'csrf': token,
      'id': tunnelId,
    });
    _checkOk(json);
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final token = await _token();
    if (token == null || token.isEmpty) throw Exception('未登录');
    final json = await _proxyPost({
      'type': 'config',
      'format': 'toml',
      'csrf': token,
      'node': tunnelId,
    });
    final config =
        json['config']?.toString() ?? (json['data']?.toString() ?? '');
    if (config.trim().isEmpty) throw Exception('获取隧道配置失败');
    await FrpcManager.instance.startWithConfig(config, 'hayfrp-$tunnelId');
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('hayfrp-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('hayfrp-$tunnelId');

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('hayfrp-$tunnelId');

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
