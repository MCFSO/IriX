// OpenFrp 提供商实现
// 基于 OpenFrp OPENAPI（ofrp_service.dart），
// 登录方式：面板「第三方客户端安全登录」复制的 Authorization。
//
// 注意：API 请求用 Authorization；frpc 简易启动（-u）必须用
// getUserInfo 返回的用户密钥 token（32 位 hex），两者不同。

import '../services/database_manager.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';
import '../services/ofrp_service.dart';

class OpenFrpProvider extends FrpProvider {
  final OfrpService _api = OfrpService.instance;

  /// 用户密钥 token（frpc -u 用），登录时从 getUserInfo 保存。
  static const _keyUserToken = 'ofrp_user_token';

  Future<String?> _userToken() =>
      DatabaseManager.instance.getSetting(_keyUserToken);

  Future<void> _saveUserToken(String token) =>
      DatabaseManager.instance.setSetting(_keyUserToken, token.trim());

  @override
  String get id => 'openfrp';

  @override
  String get label => 'OpenFrp';

  @override
  Future<FrpAccountInfo?> loadAccount() async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) return null;
    try {
      final user = await _api.getUserInfo(auth);
      await _saveUserToken(user.token);
      return _toAccount(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FrpAccountInfo> login(Map<String, String> credentials) async {
    // Remote Login 流程在登录对话框中完成，这里拿到 Authorization 后验证并保存。
    final auth = credentials['authorization'];
    if (auth == null || auth.isEmpty) {
      throw Exception('登录失败：未获取到 Authorization');
    }
    await _api.setAuth(auth);
    final user = await _api.getUserInfo(auth);
    await _saveUserToken(user.token);
    return _toAccount(user);
  }

  FrpAccountInfo _toAccount(OfrpUserInfo user) => FrpAccountInfo(
    title: user.username,
    subtitle: user.email,
    group: user.friendlyGroup,
    traffic: '${user.traffic} Mib',
    usage: '${user.used}/${user.proxies}',
    extra: user.realname ? '已实名' : '未实名',
  );

  @override
  Future<void> logout() => _api.clearAuth();

  @override
  Future<List<FrpTunnel>> listTunnels() async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) return [];
    final proxies = await _api.getProxies(auth);
    return [
      for (final proxy in proxies)
        FrpTunnel(
          id: '${proxy.id}',
          name: proxy.proxyName,
          type: proxy.proxyType,
          localAddr: proxy.localIp,
          localPort: proxy.localPort,
          remotePort: proxy.remotePort,
          remoteAddress: proxy.connectAddress,
          nodeName: proxy.friendlyNode,
          online: proxy.online,
          enabled: proxy.status,
          useEncryption: proxy.useEncryption,
          useCompression: proxy.useCompression,
          domain: proxy.domain,
        ),
    ];
  }

  @override
  Future<List<FrpNode>> listNodes() async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) return [];
    final nodes = await _api.getNodes(auth);
    return [
      for (final node in nodes.where((n) => n.available))
        FrpNode(id: node.id, name: node.name),
    ];
  }

  @override
  Future<void> createTunnel(FrpTunnelDraft draft) async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) {
      throw Exception('未登录');
    }
    await _api.newProxy(
      auth,
      name: draft.name,
      nodeId: draft.nodeId ?? 0,
      type: draft.type,
      localAddr: draft.localAddr,
      localPort: draft.localPort,
      remotePort: draft.remotePort,
      domain: draft.domain,
      forceHttps: draft.type == 'https',
      encrypt: draft.encrypt,
      gzip: draft.gzip,
    );
  }

  @override
  Future<void> deleteTunnel(String tunnelId) async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) return;
    await FrpcManager.instance.stop('ofrp-$tunnelId');
    await _api.removeProxy(auth, int.tryParse(tunnelId) ?? 0);
  }

  @override
  Future<void> startTunnel(String tunnelId) async {
    final auth = await _api.getAuth();
    if (auth == null || auth.isEmpty) {
      throw Exception('未登录');
    }
    // 简易启动 -u 需要用户密钥 token，而不是 Authorization。
    var token = await _userToken();
    if (token == null || token.isEmpty) {
      final user = await _api.getUserInfo(auth);
      token = user.token;
      await _saveUserToken(token);
    }
    if (token.isEmpty) {
      throw Exception('未获取到用户密钥，请重新登录');
    }
    await FrpcManager.instance.startOpenFrp(token, tunnelId);
  }

  @override
  Future<void> stopTunnel(String tunnelId) =>
      FrpcManager.instance.stop('ofrp-$tunnelId');

  @override
  bool isTunnelRunning(String tunnelId) =>
      FrpcManager.instance.isRunning('ofrp-$tunnelId');

  @override
  String tunnelKey(String tunnelId) => 'ofrp-$tunnelId';

  @override
  String? tunnelOutput(String tunnelId) =>
      FrpcManager.instance.outputFor('ofrp-$tunnelId');
}
