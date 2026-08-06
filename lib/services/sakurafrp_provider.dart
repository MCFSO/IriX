// SakuraFrp 提供商实现
//
// 基于 SakuraFrp API v4（https://api.natfrp.com/v4）：
// - 认证：访问密钥（Access Token），Bearer 头；
// - 隧道：列表 / 创建 / 删除（支持 tcp/udp/http/https，不接入子域绑定）；
// - 启动：官方 frpc（nya.globalslb.net 下载）以 `frpc -f <访问密钥>:<隧道ID>` 运行。

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';

/// SakuraFrp API 基础地址。
const sakuraFrpApiBase = 'https://api.natfrp.com/v4';

class SakuraFrpProvider extends FrpProvider {
  static const _keyToken = 'sakurafrp_token';

  @override
  String get id => 'sakurafrp';

  @override
  String get label => 'SakuraFrp';

  /// SakuraFrp 官方定制 frpc（0.51.0-sakura 系列，-f 参数启动）。
  @override
  String get frpcFlavor => 'sakurafrp';

  Future<String?> _token() => DatabaseManager.instance.getSetting(_keyToken);

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw Exception('未登录');
    }
    final uri = Uri.parse('$sakuraFrpApiBase$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final res = method == 'GET'
        ? await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 30))
        : await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) {
      throw Exception(_errorMessage(res));
    }
    return res;
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = utf8.decode(res.bodyBytes);
    if (body.trim().isEmpty) {
      throw Exception('服务器返回空响应');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response res) {
    try {
      final json = _decode(res);
      if (json['msg'] != null) return json['msg'].toString();
    } catch (_) {}
    return 'HTTP ${res.statusCode}: ${_snippet(res.body)}';
  }

  FrpAccountInfo _toAccount(Map<String, dynamic> data) {
    final traffic = data['traffic'];
    String? trafficText;
    if (traffic is List && traffic.length >= 2) {
      trafficText = '剩余 ${_formatBytes((traffic[1] as num?)?.toInt() ?? 0)}';
    }
    final group = data['group'];
    final groupName = group is Map ? (group['name'] ?? '').toString() : null;
    return FrpAccountInfo(
      title: (data['name'] ?? '').toString(),
      subtitle: 'UID ${data['id']} · 限速 ${data['speed'] ?? '-'}',
      group: groupName == null || groupName.isEmpty ? null : groupName,
      traffic: trafficText,
      usage: data['tunnels'] != null ? '上限 ${data['tunnels']} 条' : null,
      extra: (data['realname'] as num?)?.toInt() == 1 ? '已实名' : '未实名',
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final token = await _token();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await _send('GET', '/user/info');
      return _toAccount(_decode(res));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FrpAccountInfo> login(Map<String, String> credentials) async {
    final token = (credentials['token'] ?? '').trim();
    if (token.isEmpty) {
      throw Exception('请输入访问密钥');
    }
    await DatabaseManager.instance.setSetting(_keyToken, token);
    final res = await _send('GET', '/user/info');
    return _toAccount(_decode(res));
  }

  @override
  Future<void> logout() async {
    await FrpcManager.instance.stopAll();
    await DatabaseManager.instance.setSetting(_keyToken, '');
  }

  @override
  Future<List<FrpTunnel>> listTunnels() async {
    final res = await _send('GET', '/tunnels');
    // v4 接口直接返回隧道数组（无 data 包装）。
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final rawList = decoded is List ? decoded : <dynamic>[];
    final nodes = await _nodeMap();
    return [
      for (final e in rawList)
        if (e is Map<String, dynamic>) _toTunnel(e, nodes),
    ];
  }

  FrpTunnel _toTunnel(Map<String, dynamic> json, Map<int, FrpNode> nodes) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final type = (json['type'] ?? 'tcp').toString().toLowerCase();
    final nodeId = (json['node'] as num?)?.toInt() ?? 0;
    final remote = (json['remote'] ?? '').toString();
    final isWeb = type == 'http' || type == 'https';
    final node = nodes[nodeId];
    return FrpTunnel(
      id: '$id',
      name: (json['name'] ?? '').toString(),
      type: type,
      localAddr: (json['local_ip'] ?? '127.0.0.1').toString(),
      localPort: (json['local_port'] as num?)?.toInt() ?? 0,
      remotePort: isWeb ? null : int.tryParse(remote),
      remoteAddress: isWeb ? remote : '${node?.host ?? ''}:$remote',
      nodeName: node?.name ?? '',
      online: json['online'] == true,
      enabled: (json['status'] as num?)?.toInt() == 0,
      domain: isWeb ? remote : null,
    );
  }

  Future<Map<int, FrpNode>> _nodeMap() async {
    final res = await _send('GET', '/nodes');
    // v4 接口直接返回 节点id -> 节点信息 的 Map（无 data 包装）。
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    return {
      for (final entry in data.entries)
        if (entry.value is Map)
          int.tryParse(entry.key) ?? 0: FrpNode(
            id: int.tryParse(entry.key) ?? 0,
            name: ((entry.value as Map)['name'] ?? '').toString(),
            host: ((entry.value as Map)['host'] ?? '').toString(),
          ),
    };
  }

  @override
  Future<List<FrpNode>> listNodes() async {
    final res = await _send('GET', '/nodes');
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final nodes = <FrpNode>[];
    for (final entry in data.entries) {
      if (entry.value is! Map) continue;
      final info = entry.value as Map;
      final flag = (info['flag'] as num?)?.toInt() ?? 0;
      final id = int.tryParse(entry.key) ?? 0;
      // flag: 1<<2 允许创建（满载为 0），1<<9 是否离线。
      final available = (flag & 4) != 0 && (flag & 512) == 0;
      if (!available) continue;
      nodes.add(FrpNode(id: id, name: (info['name'] ?? '').toString()));
    }
    return nodes;
  }

  @override
  Future<void> createTunnel(FrpTunnelDraft draft) async {
    final isWeb = draft.type == 'http' || draft.type == 'https';
    await _send(
      'POST',
      '/tunnels',
      body: {
        'name': draft.name,
        'type': draft.type,
        'node': draft.nodeId ?? 0,
        'local_ip': draft.localAddr,
        'local_port': draft.localPort,
        if (isWeb) 'remote': draft.domain,
        if (!isWeb && draft.remotePort != null) 'remote': '${draft.remotePort}',
      },
    );
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    await FrpcManager.instance.stop('sakurafrp-$tunnelId');
    await _send('POST', '/tunnel/delete', body: {'ids': tunnelId});
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final token = await _token();
    if (token == null || token.isEmpty) throw Exception('未登录');
    await FrpcManager.instance.startSakuraFrp(token, tunnelId);
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('sakurafrp-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('sakurafrp-$tunnelId');

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('sakurafrp-$tunnelId');

  @override
  String tunnelKey(String tunnelId) => 'sakurafrp-$tunnelId';

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}
