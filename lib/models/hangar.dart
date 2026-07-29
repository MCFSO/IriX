// Hangar (PaperMC) API v1 数据模型
// 文档: https://docs.papermc.io/hangar/
//
// Hangar 是 PaperMC 团队运营的插件 / 软件发布平台，主要面向
// Paper / Velocity / Waterfall / Folia 等基于 Bukkit 生态的服务端软件。

/// 市场来源枚举 — 用于在 UI 层切换 Modrinth / Hangar。
enum MarketplaceSource {
  modrinth,
  hangar;

  String get label => switch (this) {
        MarketplaceSource.modrinth => 'Modrinth',
        MarketplaceSource.hangar => 'Hangar',
      };
}

/// Hangar 平台标识（用于版本下载与筛选）。
enum HangarPlatform {
  paper('Paper'),
  velocity('Velocity'),
  waterfalls('Waterfall'),
  folia('Folia'),
  sponge('Sponge');

  final String label;
  const HangarPlatform(this.label);

  /// Hangar API 使用的全小写平台名。
  String get apiValue => name;
}

/// Hangar 项目搜索结果项。
class HangarProjectHit {
  final String slug;
  final String name;
  final String description;
  final String? namespace;
  final String category;
  final int downloads;
  final int stars;
  final String? avatarUrl;
  final List<String> platforms;

  const HangarProjectHit({
    required this.slug,
    required this.name,
    required this.description,
    this.namespace,
    required this.category,
    required this.downloads,
    required this.stars,
    this.avatarUrl,
    required this.platforms,
  });

  factory HangarProjectHit.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    return HangarProjectHit(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      namespace: (json['namespace'] as Map<String, dynamic>?)?['owner'] as String?,
      category: json['category'] as String? ?? '',
      downloads: (stats['downloads'] as num?)?.toInt() ?? 0,
      stars: (stats['stars'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatar_url'] as String?,
      platforms: ((json['platforms'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Hangar 项目详情。
class HangarProject {
  final String slug;
  final String name;
  final String description;
  final String? namespace;
  final String category;
  final int downloads;
  final int stars;
  final String? avatarUrl;
  final List<String> platforms;
  final String? homepage;
  final String? repo;

  const HangarProject({
    required this.slug,
    required this.name,
    required this.description,
    this.namespace,
    required this.category,
    required this.downloads,
    required this.stars,
    this.avatarUrl,
    required this.platforms,
    this.homepage,
    this.repo,
  });

  factory HangarProject.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final links = json['links'] as Map<String, dynamic>? ?? const {};
    return HangarProject(
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      namespace: (json['namespace'] as Map<String, dynamic>?)?['owner'] as String?,
      category: json['category'] as String? ?? '',
      downloads: (stats['downloads'] as num?)?.toInt() ?? 0,
      stars: (stats['stars'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatar_url'] as String?,
      platforms: ((json['platforms'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      homepage: links['homepage'] as String?,
      repo: links['issues'] as String?,
    );
  }
}

/// Hangar 版本中的单个平台下载项。
class HangarPlatformDownload {
  /// 平台名 (paper / velocity / waterfall / folia / sponge)。
  final String platform;
  /// 该平台支持的 MC 版本列表。
  final List<String> gameVersions;
  /// 下载 URL（由 API 直接给出或按规则拼接）。
  final String downloadUrl;

  const HangarPlatformDownload({
    required this.platform,
    required this.gameVersions,
    required this.downloadUrl,
  });

  factory HangarPlatformDownload.fromJson(
    Map<String, dynamic> json,
    String projectSlug,
    String versionName,
  ) {
    final platform = json['platform'] as String? ?? 'paper';
    final versions = (json['versions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    return HangarPlatformDownload(
      platform: platform,
      gameVersions: versions,
      downloadUrl:
          'https://hangar.papermc.io/api/v1/projects/$projectSlug/versions/$versionName/$platform/download',
    );
  }
}

/// Hangar 版本。
class HangarVersion {
  final String name;
  final String? createdAt;
  final int downloads;
  final String? description;
  final List<HangarPlatformDownload> downloadsPerPlatform;

  const HangarVersion({
    required this.name,
    this.createdAt,
    required this.downloads,
    this.description,
    required this.downloadsPerPlatform,
  });

  factory HangarVersion.fromJson(
    Map<String, dynamic> json,
    String projectSlug,
  ) {
    final downloads = json['downloads'] as Map<String, dynamic>? ?? const {};
    final platformEntries = downloads['platforms'] as List<dynamic>? ?? const [];
    final stats = json['stats'] as Map<String, dynamic>?;
    return HangarVersion(
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as String?,
      downloads: (downloads['total'] as num?)?.toInt() ??
          (stats?['downloads'] as num?)?.toInt() ??
          0,
      description: json['description'] as String?,
      downloadsPerPlatform: platformEntries
          .map((e) => HangarPlatformDownload.fromJson(
                e as Map<String, dynamic>,
                projectSlug,
                json['name'] as String? ?? '',
              ))
          .toList(),
    );
  }
}
