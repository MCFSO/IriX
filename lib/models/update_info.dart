// OTA 更新数据模型
//
// 对应 GitHub Releases API（`GET /repos/{owner}/{repo}/releases`）返回的 JSON：
// - Release：tag、发布名、正文（Markdown 更新说明）、时间、预发布标记、资源列表；
// - Asset：安装包（名称 / 下载地址 / 大小 / GitHub 计算的 SHA-256 digest）。
//
// 解析失败或版本号无法识别的条目返回 null，由调用方跳过（GitHub 上存在
// `Stable` 这类不带版本号的 tag，不能让它们影响「最新版本」判定）。

import '../services/app_version.dart';

/// GitHub Release 里的一个可下载资源（安装包）。
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  /// 资源文件名，如 `irix-1.3.0-windows-x64.exe`。
  final String name;

  /// 直链下载地址（`browser_download_url`）。
  final String url;

  /// 文件大小（字节），未知为 0。
  final int size;

  /// GitHub 计算的 SHA-256（小写十六进制），未知为 null。
  final String? sha256;

  /// 是否为本仓库的校验和清单文件（`SHA256SUMS-1.3.0.txt`）。
  bool get isChecksumFile => name.toUpperCase().startsWith('SHA256SUMS');

  /// 小写扩展名（含点），如 `.exe`。
  String get extension {
    final idx = name.lastIndexOf('.');
    return idx < 0 ? '' : name.substring(idx).toLowerCase();
  }

  /// 从 GitHub API 的 asset 对象解析；缺少必要字段时返回 null。
  static UpdateAsset? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?)?.trim() ?? '';
    final url = (json['browser_download_url'] as String?)?.trim() ?? '';
    if (name.isEmpty || url.isEmpty) return null;
    final size = (json['size'] as num?)?.toInt() ?? 0;
    return UpdateAsset(
      name: name,
      url: url,
      size: size < 0 ? 0 : size,
      sha256: _parseDigest(json['digest'] as String?),
    );
  }

  /// `"sha256:e28635..."` → `e28635...`（只接受 sha256，其它算法忽略）。
  static String? _parseDigest(String? digest) {
    if (digest == null) return null;
    final text = digest.trim().toLowerCase();
    const prefix = 'sha256:';
    if (!text.startsWith(prefix)) return null;
    final hex = text.substring(prefix.length).trim();
    if (hex.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
      return null;
    }
    return hex;
  }

  /// 展示用大小文本（B/KB/MB/GB）。
  String get sizeLabel => formatBytes(size);

  @override
  String toString() => 'UpdateAsset($name, $size bytes)';
}

/// GitHub Release（一条发布记录）。
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.prerelease,
    required this.htmlUrl,
    required this.assets,
    this.publishedAt,
  });

  /// 从 tag 解析出的版本号。
  final SemVersion version;

  /// 原始 tag（如 `Stable-v1.3.0`）。
  final String tagName;

  /// 发布标题（如 `v1.3.0`）。
  final String title;

  /// 发布正文（Markdown 更新说明）。
  final String notes;

  /// 是否为预发布（GitHub 的 `prerelease` 标记或版本号自带 `-rc` 等后缀）。
  final bool prerelease;

  /// 发布页地址。
  final String htmlUrl;

  /// 资源（安装包）列表。
  final List<UpdateAsset> assets;

  /// 发布时间（UTC）；缺失时为 null。
  final DateTime? publishedAt;

  /// `v1.3.0` 形式的展示版本。
  String get versionLabel => 'v$version';

  /// 清单文件资源（`SHA256SUMS-*.txt`），用于在没有 digest 时校验。
  UpdateAsset? get checksumAsset {
    for (final asset in assets) {
      if (asset.isChecksumFile) return asset;
    }
    return null;
  }

  /// 从 GitHub API 的 release 对象解析；草稿、无有效版本号时返回 null。
  static UpdateRelease? fromJson(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final title = (json['name'] as String?)?.trim() ?? '';
    // tag 优先，其次发布标题（个别发布只有 name 带版本号）。
    final version = SemVersion.tryParse(tag) ?? SemVersion.tryParse(title);
    if (version == null) return null;

    final assets = <UpdateAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final raw in rawAssets) {
        if (raw is Map<String, dynamic>) {
          final asset = UpdateAsset.fromJson(raw);
          if (asset != null) assets.add(asset);
        }
      }
    }

    DateTime? publishedAt;
    final published = (json['published_at'] as String?)?.trim();
    if (published != null && published.isNotEmpty) {
      publishedAt = DateTime.tryParse(published)?.toUtc();
    }

    return UpdateRelease(
      version: version,
      tagName: tag,
      title: title.isEmpty ? 'v$version' : title,
      notes: (json['body'] as String?) ?? '',
      prerelease: json['prerelease'] == true || version.isPreRelease,
      htmlUrl:
          (json['html_url'] as String?)?.trim() ??
          'https://github.com/MCFSO/IriX/releases',
      assets: List<UpdateAsset>.unmodifiable(assets),
      publishedAt: publishedAt,
    );
  }

  @override
  String toString() => 'UpdateRelease($version, assets: ${assets.length})';
}

/// 一次「有新版本可用」的检查结果。
class UpdateInfo {
  const UpdateInfo({
    required this.release,
    required this.currentVersion,
    required this.asset,
    this.candidates = const <UpdateAsset>[],
  });

  /// 最新的发布记录。
  final UpdateRelease release;

  /// 当前运行的版本。
  final SemVersion currentVersion;

  /// 匹配当前平台/架构的安装包（打分最高者）；没有可用安装包时为 null。
  final UpdateAsset? asset;

  /// 当前平台全部可用安装包（高分在前），供用户自选包型。
  final List<UpdateAsset> candidates;

  /// 可选安装包列表（[candidates] 为空时退化为只有 [asset]）。
  List<UpdateAsset> get assetChoices => candidates.isNotEmpty
      ? candidates
      : (asset == null ? const <UpdateAsset>[] : <UpdateAsset>[asset!]);

  /// 替换选中的安装包（用户在提醒窗里切换包型时使用）。
  UpdateInfo withAsset(UpdateAsset? selected) => UpdateInfo(
    release: release,
    currentVersion: currentVersion,
    asset: selected,
    candidates: candidates,
  );

  /// 新版本号。
  SemVersion get version => release.version;

  /// `v1.4.0` 形式的展示版本。
  String get versionLabel => release.versionLabel;

  /// 展示用「当前版本 → 新版本」文本。
  String get transitionLabel => 'v$currentVersion → $versionLabel';

  /// 是否有可下载安装包。
  bool get hasAsset => asset != null;

  @override
  String toString() => 'UpdateInfo($transitionLabel, asset: ${asset?.name})';
}

/// 字节数 → 人类可读文本（B/KB/MB/GB）。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
