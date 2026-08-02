// ChmlFrp 提供商实现
//
// 基于 ChmlFrp 面板 API（http://cf-v2.uapis.cn）：
// - 登录：用户名/邮箱 + 密码（GET /login），不提供注册功能；
// - 隧道：列表 / 创建 / 删除；
// - 节点：列表；
// - 启动：通过 /tunnel_config 获取 INI 配置，由 frpc -c 运行。
// 按需求不接入域名管理（二级域名）功能，仅支持 tcp / udp 隧道。

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';

/// ChmlFrp 面板 API 基础地址。
const chmlFrpApiBase = 'http://cf-v2.uapis.cn';

/// 注册跳转地址（IriX 不提供注册，引导用户前往官网注册）。
const chmlFrpRegisterUrl = 'https://account.qzhua.net/register';

class ChmlFrpProvider extends FrpProvider {
  static const _keyToken = 'chmlfrp_token';

  @override
  String get id => 'chmlfrp';

  @override
  String get label => 'ChmlFrp';

  /// 不接入域名（二级域名）功能，仅 tcp / udp。
  @override
  bool get supportsWebTunnels => false;

  Future<String?> _token() => DatabaseManager.instance.getSetting(_keyToken);

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse(
      '$chmlFrpApiBase$path',
    ).replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['code'] != 200 || json['state'] != 'success') {
      throw Exception((json['msg'] ?? '请求失败').toString());
    }
    return json;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('$chmlFrpApiBase/create_tunnel'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${_snippet(res.body)}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['code'] != 200 || json['state'] != 'success') {
      throw Exception((json['msg'] ?? '创建失败').toString());
    }
    return json;
  }

  FrpAccountInfo _toAccount(Map<String, dynamic> data) => FrpAccountInfo(
    title: (data['userName'] ?? '').toString(),
    subtitle: (data['mail'] ?? '').toString(),
    group: (data['userGroup'] ?? '').toString(),
    usage: '${data['usedTunnel']}/${data['tunnel']}',
    extra: '积分 ${data['integral']}',
  );

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final token = await _token();
    if (token == null || token.isEmpty) return null;
    try {
      final json = await _get('/userinfo', {'token': token});
      return _toAccount(json['data'] as Map<String, dynamic>);
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
    final json = await _get('/login', {
      'username': username,
      'password': password,
    });
    final data = json['data'] as Map<String, dynamic>;
    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) {
      throw Exception('登录失败：未获取到 token');
    }
    await DatabaseManager.instance.setSetting(_keyToken, token);
    return _toAccount(data);
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
    final json = await _get('/tunnel', {'token': token});
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
    final json = await _get('/node', {});
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
    final token = await _token();
    if (token == null || token.isEmpty) throw Exception('未登录');
    final nodes = await listNodes();
    final nodeName = nodes.where((n) => n.id == draft.nodeId).firstOrNull?.name;
    if (nodeName == null || nodeName.isEmpty) {
      throw Exception('请选择节点');
    }
    final isWeb = draft.type == 'http' || draft.type == 'https';
    await _post({
      'token': token,
      'tunnelname': draft.name,
      'node': nodeName,
      'localip': draft.localAddr,
      'porttype': draft.type,
      'localport': draft.localPort,
      if (isWeb) 'banddomain': draft.domain,
      if (!isWeb) 'remoteport': draft.remotePort ?? 0,
      'encryption': draft.encrypt,
      'compression': draft.gzip,
    });
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    final token = await _token();
    if (token == null || token.isEmpty) return;
    await FrpcManager.instance.stop('chmlfrp-$tunnelId');
    await _get('/delete_tunnel', {'token': token, 'tunnelid': tunnelId});
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final token = await _token();
    if (token == null || token.isEmpty) throw Exception('未登录');
    final tunnels = await listTunnels();
    final tunnel = tunnels.where((t) => t.id == tunnelId).firstOrNull;
    if (tunnel == null) throw Exception('隧道不存在');
    final json = await _get('/tunnel_config', {
      'token': token,
      'node': tunnel.nodeName,
      'tunnel_names': tunnel.name,
    });
    final config = (json['data'] ?? '').toString();
    if (config.trim().isEmpty) throw Exception('获取隧道配置失败');
    await FrpcManager.instance.startWithConfig(config, 'chmlfrp-$tunnelId');
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('chmlfrp-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('chmlfrp-$tunnelId');

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('chmlfrp-$tunnelId');

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
