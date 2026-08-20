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
    final supportedPlatforms =
        json['supportedPlatforms'] as Map<String, dynamic>? ?? const {};
    return HangarProjectHit(
      slug: json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      namespace:
          (json['namespace'] as Map<String, dynamic>?)?['owner'] as String?,
      category: json['category'] as String? ?? '',
      downloads: (stats['downloads'] as num?)?.toInt() ?? 0,
      stars: (stats['stars'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatarUrl'] as String?,
      platforms: supportedPlatforms.keys.toList(),
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
    final supportedPlatforms =
        json['supportedPlatforms'] as Map<String, dynamic>? ?? const {};
    return HangarProject(
      slug: json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      namespace:
          (json['namespace'] as Map<String, dynamic>?)?['owner'] as String?,
      category: json['category'] as String? ?? '',
      downloads: (stats['downloads'] as num?)?.toInt() ?? 0,
      stars: (stats['stars'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatarUrl'] as String?,
      platforms: supportedPlatforms.keys.toList(),
      homepage: _findJsonLink(json, 'homepage'),
      repo: _findJsonLink(json, 'source'),
    );
  }
}

String? _findJsonLink(Map<String, dynamic> json, String linkName) {
  final settings = json['settings'] as Map<String, dynamic>?;
  if (settings == null) return null;
  final links = settings['links'] as List<dynamic>?;
  if (links == null) return null;
  for (final group in links) {
    final g = group as Map<String, dynamic>?;
    if (g == null) continue;
    for (final link in (g['links'] as List<dynamic>? ?? const [])) {
      final l = link as Map<String, dynamic>?;
      if (l == null) continue;
      final name = l['name'] as String? ?? '';
      if (name.toLowerCase() == linkName.toLowerCase()) {
        return l['url'] as String?;
      }
    }
  }
  return null;
}

/// Hangar 版本中的单个平台下载项。
class HangarPlatformDownload {
  final String platform;
  final List<String> gameVersions;
  final String downloadUrl;

  /// 官方发布资产的 SHA-256（来自 fileInfo.sha256Hash），用于下载后完整性校验（H-1）。
  final String? sha256;

  const HangarPlatformDownload({
    required this.platform,
    required this.gameVersions,
    required this.downloadUrl,
    this.sha256,
  });

  /// 从 `downloads[PLATFORM]` 条目解析。
  ///
  /// [platformKey] 为平台大写名（如 `PAPER`）；[gameVersions] 取自版本级
  /// `platformDependencies[platformKey]`；[sha256] 取自 `fileInfo.sha256Hash`。
  factory HangarPlatformDownload.fromJson(
    Map<String, dynamic> json,
    String platformKey,
    List<String> gameVersions,
  ) {
    final fileInfo = json['fileInfo'] as Map<String, dynamic>? ?? const {};
    return HangarPlatformDownload(
      platform: platformKey.toLowerCase(),
      gameVersions: gameVersions,
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: fileInfo['sha256Hash'] as String?,
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
    // downloads 是按平台大写名（PAPER/VELOCITY/...）索引的 map，
    // 每项含 fileInfo.sha256Hash 与 downloadUrl（H-1 完整性校验所需）。
    final downloads = json['downloads'] as Map<String, dynamic>? ?? const {};
    // 平台对应的游戏版本取自版本级 platformDependencies（按平台大写名索引）。
    final platformDeps =
        json['platformDependencies'] as Map<String, dynamic>? ?? const {};
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final platformDownloads = <HangarPlatformDownload>[];
    for (final entry in downloads.entries) {
      final platformKey = entry.key; // 如 "PAPER"
      final platformJson = entry.value as Map<String, dynamic>? ?? const {};
      final gameVersions =
          (platformDeps[platformKey] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      platformDownloads.add(
        HangarPlatformDownload.fromJson(platformJson, platformKey, gameVersions),
      );
    }
    return HangarVersion(
      name: json['name'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      downloads: (stats['totalDownloads'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
      downloadsPerPlatform: platformDownloads,
    );
  }
}
