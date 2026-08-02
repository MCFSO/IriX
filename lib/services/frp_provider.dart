// FRP 提供商抽象层
//
// OpenFrp 只是其中一个 FRP 提供商。本文件定义统一的提供商接口与
// 公共数据模型，UI 只依赖此抽象；具体实现见
// openfrp_provider.dart（OpenFrp OPENAPI）与 custom_frp_provider.dart（自建 frps）。
// 当前选中的提供商持久化在设置中，切换入口位于 FRP 页面顶部。

import '../services/chmlfrp_provider.dart';
import '../services/custom_frp_provider.dart';
import '../services/database_manager.dart';
import '../services/openfrp_provider.dart';
import '../services/sakurafrp_provider.dart';

/// 提供商种类。
enum FrpProviderKind {
  openfrp('openfrp', 'OpenFrp'),
  custom('custom', '自建 frps'),
  chmlfrp('chmlfrp', 'ChmlFrp'),
  sakurafrp('sakurafrp', 'SakuraFrp');

  const FrpProviderKind(this.id, this.label);

  final String id;
  final String label;

  static FrpProviderKind fromId(String id) => FrpProviderKind.values.firstWhere(
    (k) => k.id == id,
    orElse: () => FrpProviderKind.openfrp,
  );
}

/// 统一隧道模型。
class FrpTunnel {
  final String id;
  final String name;
  final String type;
  final String localAddr;
  final int localPort;
  final int? remotePort;
  final String remoteAddress;
  final String nodeName;
  final bool online;
  final bool enabled;
  final bool useEncryption;
  final bool useCompression;
  final String? domain;

  const FrpTunnel({
    required this.id,
    required this.name,
    required this.type,
    required this.localAddr,
    required this.localPort,
    this.remotePort,
    this.remoteAddress = '',
    this.nodeName = '',
    this.online = false,
    this.enabled = true,
    this.useEncryption = false,
    this.useCompression = false,
    this.domain,
  });
}

/// 统一账户信息（用户卡展示用）。
class FrpAccountInfo {
  final String title;
  final String subtitle;
  final String? group;
  final String? traffic;
  final String? usage;
  final String? extra;

  const FrpAccountInfo({
    required this.title,
    required this.subtitle,
    this.group,
    this.traffic,
    this.usage,
    this.extra,
  });
}

/// 统一节点模型。
class FrpNode {
  final int id;
  final String name;

  /// 节点地址（部分提供商返回，用于拼接连接地址）。
  final String host;

  const FrpNode({required this.id, required this.name, this.host = ''});
}

/// 新建隧道的提交参数。
class FrpTunnelDraft {
  final String name;
  final int? nodeId;
  final String type;
  final String localAddr;
  final int localPort;
  final int? remotePort;
  final String domain;
  final bool encrypt;
  final bool gzip;

  const FrpTunnelDraft({
    required this.name,
    this.nodeId,
    required this.type,
    required this.localAddr,
    required this.localPort,
    this.remotePort,
    this.domain = '',
    required this.encrypt,
    required this.gzip,
  });
}

/// FRP 提供商接口。
///
/// 各提供商自行持久化登录凭据与隧道数据；
/// frpc 进程统一由 FrpcManager 管理，本接口负责编排启动方式。
abstract class FrpProvider {
  String get id;

  String get label;

  /// 已登录账户信息；未登录返回 null。
  Future<FrpAccountInfo?> loadAccount();

  /// 使用凭据登录（凭据由 UI 按提供商类型收集）。
  Future<FrpAccountInfo> login(Map<String, String> credentials);

  /// 退出登录。
  Future<void> logout();

  /// 隧道列表。
  Future<List<FrpTunnel>> listTunnels();

  /// 可用节点列表（无节点概念的提供商返回空列表）。
  Future<List<FrpNode>> listNodes();

  /// 新建隧道。
  Future<void> createTunnel(FrpTunnelDraft draft);

  /// 删除隧道。
  Future<void> deleteTunnel(String tunnelId);

  /// 启动隧道（内部调用 FrpcManager 运行 frpc）。
  Future<void> startTunnel(String tunnelId);

  /// 停止隧道。
  Future<void> stopTunnel(String tunnelId);

  /// 隧道是否正在运行（本地进程）。
  bool isTunnelRunning(String tunnelId);

  /// 隧道运行输出（最近一段）。
  String? tunnelOutput(String tunnelId);

  /// 是否支持 HTTP/HTTPS（域名绑定）隧道；不支持的提供商仅允许 tcp/udp。
  bool get supportsWebTunnels => true;
}

/// 提供商注册与当前选择持久化。
class FrpProviderRegistry {
  static const _keyCurrent = 'frp_provider';

  /// 创建指定 id 的提供商实例。
  static FrpProvider create(String id) => switch (FrpProviderKind.fromId(id)) {
    FrpProviderKind.openfrp => OpenFrpProvider(),
    FrpProviderKind.custom => CustomFrpProvider(),
    FrpProviderKind.chmlfrp => ChmlFrpProvider(),
    FrpProviderKind.sakurafrp => SakuraFrpProvider(),
  };

  /// 当前选中的提供商 id。
  static Future<String> getCurrentId() async {
    try {
      final v = await DatabaseManager.instance.getSetting(_keyCurrent);
      return (v == null || v.isEmpty) ? FrpProviderKind.openfrp.id : v;
    } catch (_) {
      return FrpProviderKind.openfrp.id;
    }
  }

  /// 保存当前选中的提供商 id。
  static Future<void> setCurrentId(String id) async {
    await DatabaseManager.instance.setSetting(_keyCurrent, id);
  }
}
