// 服务端核心目录数据层
// 定义 Minecraft 服务端核心的分类、元数据以及 FastMirror 下载地址映射。
// 数据来源：need.md 中的「核心目录表」与「FastMirror 核心下载渠道表」。

import '../services/locale_settings.dart';

/// 服务端核心分类枚举。
///
/// 对应 need.md 表格中的「分类」列：
/// 原版 / 插件服 / Mod服 / 混合服（插件+Mod）。
enum CoreCategory {
  /// 原版
  vanilla('原版', 'Vanilla'),

  /// 插件服
  plugin('插件服', 'Plugin'),

  /// Mod服
  mod('Mod服', 'Mod'),

  /// 混合服（插件 + Mod）
  hybrid('混合服', 'Hybrid');

  const CoreCategory(this.displayNameZh, this.displayNameEn);

  /// 该分类的中文展示名称。
  final String displayNameZh;

  /// 该分类的英文展示名称。
  final String displayNameEn;

  /// 根据当前界面语言返回展示名称。
  String get displayName =>
      LocaleSettings.instance.localeCode == 'en' ? displayNameEn : displayNameZh;
}

/// 单个核心版本的下载信息。
///
/// 包含版本号与对应的 FastMirror 下载地址。
class CoreVersionInfo {
  /// Minecraft 版本号，例如 `1.20.1`、`26.2`。
  final String version;

  /// 该版本的 FastMirror 下载地址。
  final String downloadUrl;

  const CoreVersionInfo(this.version, this.downloadUrl);
}

/// 服务端核心元数据。
///
/// 描述一个服务端核心的分类、适用场景以及可选的版本/下载地址列表。
class ServerCore {
  /// 核心唯一标识，如 `Vanilla`、`Paper`。
  final String id;

  /// 核心展示名称。
  final String name;

  /// 核心分类。
  final CoreCategory category;

  /// 适用场景描述（中文，来自 need.md 表格「适用场景」列）。
  final String scenarioZh;

  /// 适用场景描述（英文）。
  final String scenarioEn;

  /// 可用版本及其下载地址列表。
  ///
  /// 无 FastMirror 下载地址的核心此列表为空（`const []`）。
  final List<CoreVersionInfo> versions;

  const ServerCore({
    required this.id,
    required this.name,
    required this.category,
    required this.scenarioZh,
    required this.scenarioEn,
    required this.versions,
  });

  /// 根据当前界面语言返回适用场景描述。
  String get scenario =>
      LocaleSettings.instance.localeCode == 'en' ? scenarioEn : scenarioZh;
}

/// 全部服务端核心目录。
///
/// 依据 need.md 表格整理，共 22 个核心。
/// 其中含 FastMirror 下载地址的核心已填充 versions，
/// 未提供地址的核心 versions 为空列表。
const List<ServerCore> serverCores = [
  // ============ 原版 ============
  ServerCore(
    id: 'Vanilla',
    name: 'Vanilla',
    category: CoreCategory.vanilla,
    scenarioZh: '超小型纯净生存服，不加插件/Mod',
    scenarioEn: 'Tiny vanilla survival server, no plugins/Mods',
    versions: [
      CoreVersionInfo(
        '26.2',
        'https://download.fastmirror.net/download/Vanilla/26.2/release',
      ),
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/Vanilla/26.1.2/release',
      ),
      CoreVersionInfo(
        '26.1',
        'https://download.fastmirror.net/download/Vanilla/26.1/release',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/Vanilla/1.21.11/release',
      ),
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Vanilla/1.21.8/release',
      ),
      CoreVersionInfo(
        '1.20.1',
        'https://download.fastmirror.net/download/Vanilla/1.20.1/release',
      ),
    ],
  ),

  // ============ 插件服 ============
  ServerCore(
    id: 'Spigot',
    name: 'Spigot',
    category: CoreCategory.plugin,
    scenarioZh: '中小型插件服务器',
    scenarioEn: 'Small to medium plugin server',
    versions: [],
  ),
  ServerCore(
    id: 'Paper',
    name: 'Paper',
    category: CoreCategory.plugin,
    scenarioZh: '中大型插件服',
    scenarioEn: 'Medium to large plugin server',
    versions: [
      CoreVersionInfo(
        '26.2',
        'https://download.fastmirror.net/download/Paper/26.2/build60',
      ),
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/Paper/26.1.2/build74',
      ),
      CoreVersionInfo(
        '26.1.1',
        'https://download.fastmirror.net/download/Paper/26.1.1/build29',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/Paper/1.21.11/build132',
      ),
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Paper/1.21.8/build60',
      ),
      CoreVersionInfo(
        '1.20.1',
        'https://download.fastmirror.net/download/Paper/1.20.1/build196',
      ),
      CoreVersionInfo(
        '1.12.2',
        'https://download.fastmirror.net/download/Paper/1.12.2/build1620',
      ),
      CoreVersionInfo(
        '1.8.8',
        'https://download.fastmirror.net/download/Paper/1.8.8/build445',
      ),
    ],
  ),
  ServerCore(
    id: 'Purpur',
    name: 'Purpur',
    category: CoreCategory.plugin,
    scenarioZh: '追求极致自定义的插件服',
    scenarioEn: 'Plugin server with maximum customization',
    versions: [
      CoreVersionInfo(
        '26.2',
        'https://download.fastmirror.net/download/Purpur/26.2/buildlatest',
      ),
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/Purpur/26.1.2/buildlatest',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/Purpur/1.21.11/buildlatest',
      ),
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Purpur/1.21.8/buildlatest',
      ),
      CoreVersionInfo(
        '1.20.1',
        'https://download.fastmirror.net/download/Purpur/1.20.1/buildlatest',
      ),
    ],
  ),
  ServerCore(
    id: 'Folia',
    name: 'Folia',
    category: CoreCategory.plugin,
    scenarioZh: '高性能CPU（16核+）大型生电服',
    scenarioEn: 'Large technical/factory server on high-core CPU (16+ cores)',
    versions: [
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/Folia/26.1.2/build8',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/Folia/1.21.11/build14',
      ),
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Folia/1.21.8/build6',
      ),
      CoreVersionInfo(
        '1.20.1',
        'https://download.fastmirror.net/download/Folia/1.20.1/build17',
      ),
    ],
  ),
  ServerCore(
    id: 'Mint',
    name: 'Mint',
    category: CoreCategory.plugin,
    scenarioZh: '多核高性能服务器，追求原版特性还原的大型服',
    scenarioEn: 'Multi-core high-performance server, large vanilla-faithful server',
    versions: [],
  ),
  ServerCore(
    id: 'Leaves',
    name: 'Leaves',
    category: CoreCategory.plugin,
    scenarioZh: '生电服玩家的插件端',
    scenarioEn: 'Plugin build for technical/factory players',
    versions: [
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Leaves/1.21.8/138-9331167',
      ),
    ],
  ),
  ServerCore(
    id: 'Leaf',
    name: 'Leaf',
    category: CoreCategory.plugin,
    scenarioZh: '大型高负载插件服',
    scenarioEn: 'Large high-load plugin server',
    versions: [],
  ),
  ServerCore(
    id: 'Glowstone',
    name: 'Glowstone',
    category: CoreCategory.plugin,
    scenarioZh: '开发者研究/实验性项目',
    scenarioEn: 'Developer research / experimental projects',
    versions: [],
  ),
  ServerCore(
    id: 'SpongeVanilla',
    name: 'SpongeVanilla',
    category: CoreCategory.plugin,
    scenarioZh: '使用Sponge插件体系的服务器',
    scenarioEn: 'Server using the Sponge plugin platform',
    versions: [
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/SpongeVanilla/26.1.2/19.0.0-RC2596',
      ),
      CoreVersionInfo(
        '26.1.1',
        'https://download.fastmirror.net/download/SpongeVanilla/26.1.1/19.0.0-RC2589',
      ),
      CoreVersionInfo(
        '26.1',
        'https://download.fastmirror.net/download/SpongeVanilla/26.1/19.0.0-RC2578',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/SpongeVanilla/1.21.11/18.0.0-RC2522',
      ),
    ],
  ),
  ServerCore(
    id: 'Pufferfish',
    name: 'Pufferfish',
    category: CoreCategory.plugin,
    scenarioZh: '需要极致稳定性的超大型插件服',
    scenarioEn: 'Extra-large plugin server needing maximum stability',
    versions: [],
  ),

  // ============ Mod服 ============
  ServerCore(
    id: 'Forge',
    name: 'Forge',
    category: CoreCategory.mod,
    scenarioZh: '经典整合包（1.12.2~1.20.1）',
    scenarioEn: 'Classic modpacks (1.12.2~1.20.1)',
    versions: [],
  ),
  ServerCore(
    id: 'Fabric',
    name: 'Fabric',
    category: CoreCategory.mod,
    scenarioZh: '高版本（1.17+）轻量Mod服',
    scenarioEn: 'Lightweight mod server on newer versions (1.17+)',
    versions: [
      CoreVersionInfo(
        '26.2',
        'https://download.fastmirror.net/download/Fabric/26.2/0.19.3-0.10.2',
      ),
      CoreVersionInfo(
        '26.1.2',
        'https://download.fastmirror.net/download/Fabric/26.1.2/0.19.3-1.0.1',
      ),
      CoreVersionInfo(
        '26.1.1',
        'https://download.fastmirror.net/download/Fabric/26.1.1/0.19.3-1.0.1',
      ),
      CoreVersionInfo(
        '26.1',
        'https://download.fastmirror.net/download/Fabric/26.1/0.19.3-1.0.1',
      ),
      CoreVersionInfo(
        '1.21.11',
        'https://download.fastmirror.net/download/Fabric/1.21.11/0.19.3-1.1.1',
      ),
      CoreVersionInfo(
        '1.21.8',
        'https://download.fastmirror.net/download/Fabric/1.21.8/0.19.3-0.11.1',
      ),
    ],
  ),
  ServerCore(
    id: 'NeoForge',
    name: 'NeoForge',
    category: CoreCategory.mod,
    scenarioZh: '1.20.1+ 新世代Forge整合包',
    scenarioEn: 'New-generation Forge modpacks (1.20.1+)',
    versions: [],
  ),
  ServerCore(
    id: 'Quilt',
    name: 'Quilt',
    category: CoreCategory.mod,
    scenarioZh: '完全兼容Fabric Mod',
    scenarioEn: 'Fully compatible with Fabric Mods',
    versions: [],
  ),

  // ============ 混合服（插件 + Mod） ============
  ServerCore(
    id: 'Mohist',
    name: 'Mohist',
    category: CoreCategory.hybrid,
    scenarioZh: '1.16.5~1.20.1 高版本混合服',
    scenarioEn: 'Hybrid server on newer versions (1.16.5~1.20.1)',
    versions: [],
  ),
  ServerCore(
    id: 'Arclight',
    name: 'Arclight',
    category: CoreCategory.hybrid,
    scenarioZh: '1.18+ 高版本混合服',
    scenarioEn: 'Hybrid server on versions 1.18+',
    versions: [
      CoreVersionInfo(
        '1.20.1',
        'https://download.fastmirror.net/download/Arclight/1.20.1/1.0.6-6de9fec',
      ),
    ],
  ),
  ServerCore(
    id: 'CatServer',
    name: 'CatServer',
    category: CoreCategory.hybrid,
    scenarioZh: '1.12.2 怀旧混合服',
    scenarioEn: 'Nostalgic hybrid server on 1.12.2',
    versions: [
      CoreVersionInfo(
        '1.18.2',
        'https://download.fastmirror.net/download/CatServer/1.18.2/build170',
      ),
      CoreVersionInfo(
        '1.16.5',
        'https://download.fastmirror.net/download/CatServer/1.16.5/build79',
      ),
      CoreVersionInfo(
        '1.12.2',
        'https://download.fastmirror.net/download/CatServer/1.12.2/build31',
      ),
    ],
  ),
  ServerCore(
    id: 'Banner',
    name: 'Banner',
    category: CoreCategory.hybrid,
    scenarioZh: '1.19.4~1.20.1 Fabric系混合服',
    scenarioEn: 'Fabric-based hybrid server (1.19.4~1.20.1)',
    versions: [],
  ),
  ServerCore(
    id: 'SpongeForge',
    name: 'SpongeForge',
    category: CoreCategory.hybrid,
    scenarioZh: '使用Sponge插件+Forge Mod的混合服',
    scenarioEn: 'Hybrid server using Sponge plugins + Forge Mods',
    versions: [
      CoreVersionInfo(
        '1.12.2',
        'https://download.fastmirror.net/download/SpongeForge/1.12.2/2838-7.4.8-RC4138',
      ),
    ],
  ),
  ServerCore(
    id: 'SpongeNeoForge',
    name: 'SpongeNeoForge',
    category: CoreCategory.hybrid,
    scenarioZh: '使用Sponge插件+NeoForge Mod的混合服',
    scenarioEn: 'Hybrid server using Sponge plugins + NeoForge Mods',
    versions: [],
  ),
  ServerCore(
    id: 'Cardboard',
    name: 'Cardboard',
    category: CoreCategory.hybrid,
    scenarioZh: '在Fabric Mod服上运行Bukkit插件',
    scenarioEn: 'Run Bukkit plugins on a Fabric Mod server',
    versions: [],
  ),
];

/// 根据核心 id 查找核心，未找到返回 null。
ServerCore? findCoreById(String id) {
  for (final core in serverCores) {
    if (core.id == id) {
      return core;
    }
  }
  return null;
}

/// 返回指定分类下的所有核心。
List<ServerCore> coresByCategory(CoreCategory category) {
  return serverCores.where((core) => core.category == category).toList();
}

/// 根据核心与版本信息生成下载后的核心文件名。
///
/// 命名规则：`<核心名小写>-<版本>-<下载地址最后一段>.jar`
/// 例如 Paper 1.20.1，地址为 `.../Paper/1.20.1/build196`
/// 将生成 `paper-1.20.1-build196.jar`。
String buildCoreFileName(ServerCore core, CoreVersionInfo v) {
  final url = v.downloadUrl;
  final lastSlash = url.lastIndexOf('/');
  // 提取最后一个 `/` 之后的路径段作为文件标识。
  final lastSegment = lastSlash >= 0 ? url.substring(lastSlash + 1) : '';
  return '${core.name.toLowerCase()}-${v.version}-$lastSegment.jar';
}
