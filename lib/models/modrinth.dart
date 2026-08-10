// Modrinth API v2 数据模型
// 文档: https://docs.modrinth.com

/// 项目类型
enum ModrinthProjectType {
  mod,
  plugin,
  unknown;

  static ModrinthProjectType fromString(String? type) {
    return switch (type) {
      'mod' => ModrinthProjectType.mod,
      'plugin' => ModrinthProjectType.plugin,
      _ => ModrinthProjectType.unknown,
    };
  }
}

/// 搜索结果项
class ModrinthSearchHit {
  final String projectId;
  final String slug;
  final String title;
  final String description;
  final String? iconUrl;
  final int downloads;
  final int follows;
  final List<String> versions;
  final List<String> categories;
  final String projectType;

  const ModrinthSearchHit({
    required this.projectId,
    required this.slug,
    required this.title,
    required this.description,
    this.iconUrl,
    required this.downloads,
    required this.follows,
    required this.versions,
    required this.categories,
    required this.projectType,
  });

  factory ModrinthSearchHit.fromJson(Map<String, dynamic> json) {
    return ModrinthSearchHit(
      projectId: json['project_id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      follows: (json['follows'] as num?)?.toInt() ?? 0,
      versions:
          (json['versions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      categories:
          (json['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      projectType: json['project_type'] as String? ?? 'mod',
    );
  }
}

/// 搜索结果
class ModrinthSearchResult {
  final List<ModrinthSearchHit> hits;
  final int offset;
  final int limit;
  final int totalHits;

  const ModrinthSearchResult({
    required this.hits,
    required this.offset,
    required this.limit,
    required this.totalHits,
  });

  factory ModrinthSearchResult.fromJson(Map<String, dynamic> json) {
    return ModrinthSearchResult(
      hits:
          (json['hits'] as List<dynamic>?)
              ?.map(
                (e) => ModrinthSearchHit.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      totalHits: (json['total_hits'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 项目详情
class ModrinthProject {
  final String id;
  final String slug;
  final String title;
  final String description;
  final String? body;
  final String? iconUrl;
  final int downloads;
  final int followers;
  final List<String> categories;
  final List<String> loaders;
  final List<String> gameVersions;
  final String projectType;
  final String? clientSide;
  final String? serverSide;

  const ModrinthProject({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    this.body,
    this.iconUrl,
    required this.downloads,
    required this.followers,
    required this.categories,
    required this.loaders,
    required this.gameVersions,
    required this.projectType,
    this.clientSide,
    this.serverSide,
  });

  factory ModrinthProject.fromJson(Map<String, dynamic> json) {
    return ModrinthProject(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      body: json['body'] as String?,
      iconUrl: json['icon_url'] as String?,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      followers: (json['followers'] as num?)?.toInt() ?? 0,
      categories:
          (json['categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      loaders:
          (json['loaders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      gameVersions:
          (json['game_versions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      projectType: json['project_type'] as String? ?? 'mod',
      clientSide: json['client_side'] as String?,
      serverSide: json['server_side'] as String?,
    );
  }
}

/// 版本文件
class ModrinthFile {
  final String url;
  final String filename;
  final bool primary;
  final int size;
  final Map<String, String>? hashes;

  const ModrinthFile({
    required this.url,
    required this.filename,
    required this.primary,
    required this.size,
    this.hashes,
  });

  factory ModrinthFile.fromJson(Map<String, dynamic> json) {
    final hashesRaw = json['hashes'] as Map<String, dynamic>?;
    return ModrinthFile(
      url: json['url'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      primary: json['primary'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      hashes: hashesRaw?.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

/// 标签类型
enum ModrinthTagType {
  category,
  loader,
  gameVersion,
  license,
  donationPlatform,
  reportType,
  projectType;

  static ModrinthTagType fromString(String? type) {
    return switch (type) {
      'category' => ModrinthTagType.category,
      'loader' => ModrinthTagType.loader,
      'game_version' => ModrinthTagType.gameVersion,
      'license' => ModrinthTagType.license,
      _ => ModrinthTagType.category,
    };
  }
}

/// 分类/加载器标签
class ModrinthTag {
  final String icon;
  final String name;
  final ModrinthTagType type;
  final String? projectId;

  const ModrinthTag({
    required this.icon,
    required this.name,
    required this.type,
    this.projectId,
  });

  factory ModrinthTag.fromJson(
    Map<String, dynamic> json,
    ModrinthTagType type,
  ) {
    return ModrinthTag(
      icon: json['icon'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: type,
      projectId: json['project_id'] as String?,
    );
  }
}

/// 游戏版本标签
class ModrinthGameVersionTag {
  final String version;
  final String versionType;
  final String date;
  final bool major;

  const ModrinthGameVersionTag({
    required this.version,
    required this.versionType,
    required this.date,
    required this.major,
  });

  factory ModrinthGameVersionTag.fromJson(Map<String, dynamic> json) {
    return ModrinthGameVersionTag(
      version: json['version'] as String? ?? '',
      versionType: json['version_type'] as String? ?? 'release',
      date: json['date'] as String? ?? '',
      major: json['major'] as bool? ?? false,
    );
  }
}

/// 版本
class ModrinthVersion {
  final String id;
  final String projectId;
  final String name;
  final String versionNumber;
  final List<String> gameVersions;
  final List<String> loaders;
  final String versionType;
  final List<ModrinthFile> files;
  final String? datePublished;

  const ModrinthVersion({
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    required this.gameVersions,
    required this.loaders,
    required this.versionType,
    required this.files,
    this.datePublished,
  });

  factory ModrinthVersion.fromJson(Map<String, dynamic> json) {
    return ModrinthVersion(
      id: json['id'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      versionNumber: json['version_number'] as String? ?? '',
      gameVersions:
          (json['game_versions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      loaders:
          (json['loaders'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      versionType: json['version_type'] as String? ?? 'release',
      files:
          (json['files'] as List<dynamic>?)
              ?.map((e) => ModrinthFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      datePublished: json['date_published'] as String?,
    );
  }
}
