// 自建 frps 提供商实现
//
// 面向用户自己的 frp 服务器：配置 服务地址 + 认证 token，
// 隧道保存在本地（SQLite settings），启动时生成 frpc TOML 配置并运行。
// 无远程隧道管理接口，删除仅移除本地记录。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';

class CustomFrpProvider extends FrpProvider {
  static const _keyServer = 'frp_custom_server';
  static const _keyToken = 'frp_custom_token';
  static const _keyTunnels = 'frp_custom_tunnels';

  @override
  String get id => 'custom';

  @override
  String get label => '自建 frps';

  Future<String?> _server() => DatabaseManager.instance.getSetting(_keyServer);

  Future<String?> _token() => DatabaseManager.instance.getSetting(_keyToken);

  Future<List<Map<String, dynamic>>> _loadTunnels() async {
    try {
      final raw = await DatabaseManager.instance.getSetting(_keyTunnels);
      if (raw == null || raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return [for (final e in list) Map<String, dynamic>.from(e as Map)];
    } catch (e) {
      debugPrint('Failed to load custom tunnels: $e');
      return [];
    }
  }

  Future<void> _saveTunnels(List<Map<String, dynamic>> tunnels) async {
    await DatabaseManager.instance.setSetting(_keyTunnels, jsonEncode(tunnels));
  }

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final server = await _server();
    if (server == null || server.trim().isEmpty) return null;
    final token = await _token();
    final tunnels = await _loadTunnels();
    return FrpAccountInfo(
      title: server,
      subtitle: token == null || token.isEmpty ? '未设置 token' : '已配置 token',
      group: '自建 frps',
      usage: '${tunnels.length} 条本地隧道',
    );
  }

  @override
  Future<FrpAccountInfo> login(Map<String, String> credentials) async {
    final server = (credentials['server'] ?? '').trim();
    final token = (credentials['token'] ?? '').trim();
    if (server.isEmpty) {
      throw Exception('请输入 frps 服务器地址');
    }
    await DatabaseManager.instance.setSetting(_keyServer, server);
    await DatabaseManager.instance.setSetting(_keyToken, token);
    return FrpAccountInfo(
      title: server,
      subtitle: token.isEmpty ? '未设置 token' : '已配置 token',
      group: '自建 frps',
      usage: '${(await _loadTunnels()).length} 条本地隧道',
    );
  }

  @override
  Future<void> logout() async {
    await DatabaseManager.instance.setSetting(_keyServer, '');
    await DatabaseManager.instance.setSetting(_keyToken, '');
    await FrpcManager.instance.stopAll();
  }

  @override
  Future<List<FrpTunnel>> listTunnels() async {
    final tunnels = await _loadTunnels();
    return [
      for (final t in tunnels)
        FrpTunnel(
          id: (t['name'] ?? '').toString(),
          name: (t['name'] ?? '').toString(),
          type: (t['type'] ?? 'tcp').toString(),
          localAddr: (t['localAddr'] ?? '127.0.0.1').toString(),
          localPort: (t['localPort'] as num?)?.toInt() ?? 0,
          remotePort: (t['remotePort'] as num?)?.toInt(),
          domain: t['domain'] as String?,
          enabled: true,
          online: FrpcManager.instance.isRunning('custom-${t['name']}'),
        ),
    ];
  }

  @override
  Future<List<FrpNode>> listNodes() async => const [];

  @override
  Future<void> createTunnel(FrpTunnelDraft draft) async {
    final tunnels = await _loadTunnels();
    if (tunnels.any((t) => t['name'] == draft.name)) {
      throw Exception('隧道名称已存在: ${draft.name}');
    }
    tunnels.add({
      'name': draft.name,
      'type': draft.type,
      'localAddr': draft.localAddr,
      'localPort': draft.localPort,
      if (draft.remotePort != null) 'remotePort': draft.remotePort,
      if (draft.domain.isNotEmpty) 'domain': draft.domain,
      'encrypt': draft.encrypt,
      'gzip': draft.gzip,
    });
    await _saveTunnels(tunnels);
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    await FrpcManager.instance.stop('custom-$tunnelId');
    final tunnels = (await _loadTunnels())
        .where((t) => t['name'] != tunnelId)
        .toList();
    await _saveTunnels(tunnels);
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final server = await _server();
    if (server == null || server.isEmpty) {
      throw Exception('未配置 frps 服务器');
    }
    final tunnels = await _loadTunnels();
    final tunnel = tunnels.where((t) => t['name'] == tunnelId).firstOrNull;
    if (tunnel == null) throw Exception('隧道不存在');

    final token = (await _token()) ?? '';
    final config = _buildToml(
      server: server,
      token: token,
      name: tunnelId,
      type: (tunnel['type'] ?? 'tcp').toString(),
      localAddr: (tunnel['localAddr'] ?? '127.0.0.1').toString(),
      localPort: (tunnel['localPort'] as num).toInt(),
      remotePort: (tunnel['remotePort'] as num?)?.toInt(),
      domain: tunnel['domain'] as String?,
      encrypt: tunnel['encrypt'] == true,
      gzip: tunnel['gzip'] == true,
    );
    await FrpcManager.instance.startWithConfig(config, 'custom-$tunnelId');
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('custom-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('custom-$tunnelId');

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('custom-$tunnelId');

  /// 生成 frpc TOML 配置。
  static String _buildToml({
    required String server,
    required String token,
    required String name,
    required String type,
    required String localAddr,
    required int localPort,
    int? remotePort,
    String? domain,
    bool encrypt = false,
    bool gzip = false,
  }) {
    final parts = server.trim().split(':');
    final host = parts.first.trim();
    final port = parts.length > 1 ? parts[1].trim() : '7000';

    final buf = StringBuffer()
      ..writeln('serverAddr = "${_esc(host)}"')
      ..writeln('serverPort = $port');
    if (token.isNotEmpty) {
      buf.writeln('auth.token = "${_esc(token)}"');
    }
    buf.writeln();
    buf.writeln('[[proxies]]');
    buf.writeln('name = "${_esc(name)}"');
    buf.writeln('type = "${_esc(type)}"');
    buf.writeln('localIP = "${_esc(localAddr)}"');
    buf.writeln('localPort = $localPort');
    final isWeb = type == 'http' || type == 'https';
    if (isWeb) {
      if (domain != null && domain.isNotEmpty) {
        buf.writeln('customDomains = ["${_esc(domain)}"]');
      }
    } else if (remotePort != null && remotePort > 0) {
      buf.writeln('remotePort = $remotePort');
    }
    if (encrypt) {
      buf.writeln('transport.encryption.enable = true');
    }
    if (gzip) {
      buf.writeln('transport.compression.enable = true');
    }
    return buf.toString();
  }

  static String _esc(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
