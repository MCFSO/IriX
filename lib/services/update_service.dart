// 应用内更新（OTA）：从 GitHub Releases 检查新版本、下载安装包并安装
//
// 流程：
//   1. checkForUpdates()：GET api.github.com/repos/MCFSO/IriX/releases
//      （未认证 60 次/小时，启动自动检查做了 6 小时限频）；
//   2. 用 SemVersion 与当前版本（app_version.dart）比较，取最高版本；
//   3. selectAsset()：按平台/架构挑安装包（Windows .exe → .msix → .zip，
//      macOS .dmg → .zip，Linux AppImage/.deb/.rpm/.zip）；
//   4. downloadUpdate()：Rust Downloader 多线程下载到 <数据根>/updates/，
//      用 GitHub asset 的 SHA-256 digest（或发布里的 SHA256SUMS 清单）校验；
//   5. installUpdate()：按平台安装（Windows 静默跑 Inno 安装包 / Linux AppImage
//      自我替换 / macOS 挂载 DMG 引导用户覆盖），必要时由调用方退出应用。
//
// 约定：
// - 所有 HTTP 走 Rust（http_ffi / downloader），本文件不引入 package:http；
// - “现在”一律用 TimeService（限频与持久化时间戳）；
// - 落盘目录统一经 AppPaths（updatesRoot），不直接用临时目录或文档目录。

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/update_info.dart';
import 'app_paths.dart';
import 'app_version.dart';
import 'dev_log.dart';
import 'download_settings.dart';
import 'downloader.dart';
import 'http_ffi.dart';
import 'time_service.dart';
import 'update_settings.dart';

/// 更新相关操作失败时抛出。
class UpdateException implements Exception {
  const UpdateException(this.message, {this.rateLimited = false});

  /// 面向用户的中文错误描述。
  final String message;

  /// 是否为 GitHub API 限流（设置页据此提示“稍后再试”）。
  final bool rateLimited;

  @override
  String toString() => message;
}

/// 安装方式。
enum UpdateInstallMode {
  /// 安装程序已静默启动 / 已自我替换，应用应当退出以完成更新。
  automatic,

  /// 已把安装包交给系统（挂载 DMG、打开 deb/rpm），需要用户走完向导。
  assisted,

  /// 只能定位到下载的文件，由用户手动安装。
  manual,
}

/// 安装结果。
class UpdateInstallResult {
  const UpdateInstallResult({
    required this.mode,
    required this.path,
    this.message,
    this.appMustExit = false,
  });

  /// 安装方式。
  final UpdateInstallMode mode;

  /// 安装包路径。
  final String path;

  /// 附加提示（面向用户；null 表示无需额外提示）。
  final String? message;

  /// 调用方是否需要立即退出应用（文件正被占用，安装程序在等它关闭）。
  final bool appMustExit;
}

/// 下载进度（已换算为 UI 直接可用的字段）。
class UpdateProgress {
  const UpdateProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
  });

  /// 已下载字节数。
  final int downloadedBytes;

  /// 总字节数（未知为 -1）。
  final int totalBytes;

  /// 当前速度（字节/秒）。
  final double speedBytesPerSec;

  /// 进度百分比（0–100）；总大小未知时返回 null（UI 用不确定进度条）。
  double? get percent {
    if (totalBytes <= 0) return null;
    return (downloadedBytes / totalBytes * 100).clamp(0, 100);
  }
}

/// OTA 更新服务（单例）。
class UpdateService {
  UpdateService._();

  /// 单例。
  static final UpdateService instance = UpdateService._();

  /// GitHub 仓库所有者。
  static const String githubOwner = 'MCFSO';

  /// GitHub 仓库名。
  static const String githubRepo = 'IriX';

  /// Releases API（列表，按发布时间倒序）。
  static const String releasesApiUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases';

  /// 发布页（人工查看全部版本）。
  static const String releasesPageUrl =
      'https://github.com/$githubOwner/$githubRepo/releases';

  /// 最新发布页（GitHub 会 302 到最新 tag）。
  static const String latestReleasePageUrl = '$releasesPageUrl/latest';

  /// 每次检查拉取的发布条数（足够覆盖历史版本，又不会过大）。
  static const int releasesPerPage = 30;

  /// 项目自建的默认更新源（Cloudflare Worker，见 `workers/update-feed/`）。
  ///
  /// 走 Cloudflare 边缘：`*.workers.dev` 在国内经常 DNS 被污染/不可达，
  /// 所以绑了自有域名 `update.mcfso.org`。Worker 只搬运 GitHub Releases，
  /// 失败时会自动回退到 GitHub 官方 API。
  static const String defaultFeedUrl = 'https://update.mcfso.org';

  /// 构建期默认更新源（`--dart-define=IRIX_UPDATE_FEED=https://...`）。
  ///
  /// - 不传：使用 [defaultFeedUrl]（项目自建 Worker）；
  /// - 传空字符串：不内置任何自建源，只用 GitHub 官方；
  /// - 传其它地址：换成自己的 Worker / 镜像。
  /// 运行时设置里的「更新源」优先级更高（便于临时切换/排障）。
  static const String buildTimeFeedUrl = String.fromEnvironment(
    'IRIX_UPDATE_FEED',
    defaultValue: defaultFeedUrl,
  );

  /// GitHub 官方更新源（兜底）。
  static const String githubFeedUrl =
      '$releasesApiUrl?per_page=$releasesPerPage';

  /// 当前运行版本；解析失败为 null。
  SemVersion? get currentVersion => kIrixAppSemVersion;

  // ========================= 更新源 =========================

  /// 规范化用户填写的更新源地址。
  ///
  /// - 空字符串 → 返回空（表示用官方 GitHub）；
  /// - 只填根地址（`https://irix-update.example.workers.dev`）→ 补 `/api/releases`；
  /// - 已经带 `/api/releases`、`/api/latest` 或 `.json` → 原样使用。
  ///
  /// 允许填带协议或省略协议的域名（省略时补 `https://`）。
  static String normalizeFeedUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';
    // 去掉可能被粘贴进来的查询串/末尾斜杠，避免拼出双斜杠式地址。
    text = text.replaceAll(RegExp(r'[?#].*$'), '');
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    final lower = text.toLowerCase();
    if (lower.endsWith('.json') ||
        lower.contains('/api/releases') ||
        lower.contains('/api/latest') ||
        lower.contains('/releases')) {
      return text;
    }
    return '$text/api/releases';
  }

  /// 按优先级返回更新源列表：自定义 / Worker 源在前，GitHub 官方兜底在后。
  ///
  /// [configured] 为设置里填写的地址（空表示未配置），[buildTime] 为构建期默认值。
  static List<String> feedCandidates({
    String configured = '',
    String buildTime = buildTimeFeedUrl,
  }) {
    final feeds = <String>[];
    void add(String value, {bool normalize = true}) {
      final url = normalize ? normalizeFeedUrl(value) : value.trim();
      if (url.isEmpty) return;
      if (feeds.contains(url)) return;
      feeds.add(url);
    }

    add(configured);
    add(buildTime);
    // GitHub 官方地址自带 `?per_page=`，不能被 normalizeFeedUrl 去掉查询串。
    add(githubFeedUrl, normalize: false);
    return feeds;
  }


  // ========================= 检查更新 =========================

  /// 拉取发布列表并按需过滤预发布版本。
  ///
  /// 依次尝试：设置里的更新源 → 构建期内置更新源 → GitHub 官方 API。
  /// 任一源成功即返回；全部失败时抛出最后一次的错误（GitHub 限流信息最有用）。
  Future<List<UpdateRelease>> fetchReleases({
    bool includePrerelease = false,
  }) async {
    final configured = await UpdateSettings.getFeedUrl();
    final feeds = feedCandidates(configured: configured);
    UpdateException? lastError;
    for (final feed in feeds) {
      try {
        return await _fetchFromFeed(feed, includePrerelease: includePrerelease);
      } on UpdateException catch (e) {
        lastError = e;
        DevLog.instance.devWarn('update', 'SOURCE FAILED $feed: ${e.message}');
      }
    }
    throw lastError ?? const UpdateException('没有可用的更新源');
  }

  /// 从单个更新源拉取并解析发布列表。
  Future<List<UpdateRelease>> _fetchFromFeed(
    String feedUrl, {
    required bool includePrerelease,
  }) async {
    final isGithubApi = feedUrl.contains('api.github.com');
    DevLog.instance.devInfo('update', 'CHECK $feedUrl');
    final HttpFfiResponse response;
    try {
      response = await HttpFfiService.instance.get(
        feedUrl,
        headers: {
          'Accept': isGithubApi
              ? 'application/vnd.github+json'
              : 'application/json',
          if (isGithubApi) 'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'IriX/$kIrixAppVersion (+$releasesPageUrl)',
        },
        timeout: const Duration(seconds: 20),
      );
    } on HttpFfiException catch (e) {
      throw UpdateException('无法连接更新源：${e.message}');
    }

    if (response.statusCode == 403 || response.statusCode == 429) {
      final remaining = _header(response.headers, 'x-ratelimit-remaining');
      final reset = _header(response.headers, 'x-ratelimit-reset');
      throw UpdateException(
        isGithubApi
            ? 'GitHub API 请求过于频繁（未登录每小时 60 次）'
                  '${reset == null ? '' : '，将于 ${_formatResetHint(reset)} 后恢复'}，请稍后再试。'
            : '更新源请求过于频繁（HTTP ${response.statusCode}），请稍后再试。',
        rateLimited: isGithubApi && remaining == '0',
      );
    }
    if (!response.isOk) {
      throw UpdateException('更新源返回 HTTP ${response.statusCode}');
    }

    final releases = parseReleasesPayload(
      response.body,
      includePrerelease: includePrerelease,
    );
    DevLog.instance.devInfo(
      'update',
      'CHECK OK ${releases.length} releases, latest=${_latestOf(releases)?.version}',
    );
    return releases;
  }

  /// 解析更新源返回的 JSON。
  ///
  /// 兼容三种形态，便于自建 Worker 只返回必要字段：
  /// - GitHub Releases 原始数组：`[{tag_name, assets: [...]}, ...]`
  /// - 对象包装：`{"releases": [...]}` 或 `{"data": [...]}`
  /// - 单条最新版：`{"release": {...}}`
  ///
  /// 每条尽量按 GitHub Release 字段解析（`tag_name`/`name`/`body`/`published_at`/
  /// `assets[].browser_download_url`/`assets[].digest`），解析不出合法版本号的条目
  /// 直接跳过。
  static List<UpdateRelease> parseReleasesPayload(
    String body, {
    bool includePrerelease = false,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UpdateException('更新源返回的数据不是合法 JSON');
    }

    List<dynamic> rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final list = decoded['releases'] ?? decoded['data'];
      final single = decoded['release'];
      if (list is List) {
        rawList = list;
      } else if (single is Map<String, dynamic>) {
        rawList = [single];
      } else {
        throw const UpdateException('更新源响应缺少 releases 列表');
      }
    } else {
      throw const UpdateException('更新源响应格式异常');
    }

    final releases = <UpdateRelease>[];
    for (final raw in rawList) {
      if (raw is! Map<String, dynamic>) continue;
      final release = UpdateRelease.fromJson(raw);
      if (release == null) continue;
      if (!includePrerelease && release.prerelease) continue;
      releases.add(release);
    }
    return releases;
  }

  /// 检查是否有新版本；有更新时返回 [UpdateInfo]，已是最新返回 null。
  ///
  /// [includePrerelease] 为 null 时读取用户设置。
  /// [recordCheck] 为 true 时写入“上次检查时间 / 上次看到的最新版本”。
  Future<UpdateInfo?> checkForUpdates({
    bool? includePrerelease,
    bool recordCheck = true,
  }) async {
    final withPre =
        includePrerelease ?? await UpdateSettings.getIncludePrerelease();
    final releases = await fetchReleases(includePrerelease: withPre);
    final latest = _latestOf(releases);

    if (recordCheck) {
      await UpdateSettings.setLastCheckAtMs(TimeService.instance.nowUnixMs());
      if (latest != null) {
        await UpdateSettings.setLastKnownLatest(latest.version.toString());
      }
    }

    if (latest == null) return null;
    final current = currentVersion;
    if (current == null) {
      DevLog.instance.devWarn(
        'update',
        '当前版本号无法解析（$kIrixAppVersion），跳过更新提示',
      );
      return null;
    }
    if (!latest.version.isNewerThan(current)) {
      DevLog.instance.devInfo(
        'update',
        'UP TO DATE current=$current latest=${latest.version}',
      );
      return null;
    }

    final ranked = rankAssets(
      assets: latest.assets,
      platform: platformTag,
      arch: archTag,
      hasAppImage: currentAppImagePath() != null,
      isDebLike: _isDebLike,
      isRpmLike: _isRpmLike,
    );
    final info = UpdateInfo(
      release: latest,
      currentVersion: current,
      asset: ranked.isEmpty ? null : ranked.first,
      candidates: ranked,
    );
    DevLog.instance.devInfo(
      'update',
      'UPDATE AVAILABLE $current -> ${latest.version} asset=${info.asset?.name}',
    );
    return info;
  }

  /// 启动时自动检查（受“自动检查”开关与 6 小时限频、“跳过此版本”约束）。
  ///
  /// 不需要提示时返回 null；网络错误等异常一律吞掉并记日志，避免打扰启动。
  Future<UpdateInfo?> autoCheckOnStartup() async {
    try {
      if (!await UpdateSettings.getAutoCheck()) return null;
      final last = await UpdateSettings.getLastCheckAtMs();
      final now = TimeService.instance.nowUnixMs();
      // now < last 说明系统时间被回拨，按“已过期”处理，允许检查。
      if (last > 0 &&
          now >= last &&
          now - last < UpdateSettings.autoCheckInterval.inMilliseconds) {
        DevLog.instance.devInfo(
          'update',
          'auto check skipped: ${((now - last) ~/ 60000)} min since last check',
        );
        return null;
      }
      final info = await checkForUpdates();
      if (info == null) return null;
      final dismissed = await _isDismissed(info);
      return dismissed ? null : info;
    } on UpdateException catch (e) {
      DevLog.instance.devWarn('update', 'auto check failed: ${e.message}');
      return null;
    } catch (e) {
      DevLog.instance.devWarn('update', 'auto check error: $e');
      return null;
    }
  }

  /// 该更新是否被用户「跳过此版本」。
  Future<bool> _isDismissed(UpdateInfo info) async {
    final skipped = await UpdateSettings.getSkippedVersion();
    if (skipped.isEmpty) return false;
    final parsed = SemVersion.tryParse(skipped);
    if (parsed == null) return false;
    // 跳过的版本 >= 当前最新版本时不再提示（直到出现更高版本）。
    return !info.version.isNewerThan(parsed);
  }

  /// 记住「跳过此版本」。
  Future<void> skipVersion(UpdateInfo info) async {
    await UpdateSettings.setSkippedVersion(info.version.toString());
    DevLog.instance.devInfo('update', 'SKIP ${info.version}');
  }

  /// 清除「跳过此版本」记录。
  Future<void> clearSkippedVersion() => UpdateSettings.setSkippedVersion('');

  // ========================= 下载更新 =========================

  /// 下载新版本安装包，返回本地文件路径。
  ///
  /// 若磁盘上已有校验过的同一版本安装包，直接复用（附带 `<文件名>.sha256`
  /// 校验记录），避免重复下载几十 MB。下载完成后由 Rust 侧按 SHA-256 校验，
  /// 不匹配会删除文件并抛异常（供应链完整性防护）。
  Future<String> downloadUpdate(
    UpdateInfo info, {
    void Function(UpdateProgress progress)? onProgress,
    int? threads,
  }) async {
    final asset = info.asset;
    if (asset == null) {
      throw const UpdateException('该版本没有适用于当前平台的安装包，请前往发布页手动下载。');
    }

    final dir = Directory(await AppPaths.instance.updatesRoot());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final fileName = _safeFileName(asset.name);
    final targetPath = p.join(dir.path, fileName);
    final expectedSha = await _resolveExpectedSha256(info);

    if (await _isReusable(targetPath, asset, expectedSha)) {
      DevLog.instance.devInfo('update', 'DOWNLOAD REUSE $targetPath');
      return targetPath;
    }

    // 清理上次残留：Rust 多线程下载按 `<目标>.part` 断点续传，残留会污染新版本。
    await _deleteQuietly(targetPath);
    await _deleteQuietly('$targetPath.part');
    await _deleteQuietly('$targetPath.sha256');

    final useThreads = threads ?? await DownloadSettings.getThreads();
    DevLog.instance.devInfo(
      'update',
      'DOWNLOAD START ${asset.url} -> $targetPath (${asset.sizeLabel},'
      ' threads=$useThreads, sha256=${expectedSha ?? "unknown"})',
    );
    try {
      await Downloader().downloadFile(
        asset.url,
        targetPath,
        (progress) => onProgress?.call(
          UpdateProgress(
            downloadedBytes: progress.downloadedBytes,
            totalBytes: progress.totalBytes,
            speedBytesPerSec: progress.speedBytesPerSec,
          ),
        ),
        threads: useThreads,
        sha256: expectedSha,
      );
    } on Exception catch (e) {
      DevLog.instance.devError('update', 'DOWNLOAD FAILED $e');
      throw UpdateException('下载更新失败：$e');
    }

    // 记录校验结果，供下次启动复用该安装包。
    try {
      await File('$targetPath.sha256').writeAsString(expectedSha ?? '');
    } catch (_) {
      // 记录失败不影响主流程，下次会重新下载。
    }
    DevLog.instance.devInfo('update', 'DOWNLOAD DONE $targetPath');
    return targetPath;
  }

  /// 预期的 SHA-256：优先用 GitHub asset digest，其次解析发布里的校验和清单。
  Future<String?> _resolveExpectedSha256(UpdateInfo info) async {
    final asset = info.asset!;
    if (asset.sha256 != null) return asset.sha256;
    final checksum = info.release.checksumAsset;
    if (checksum == null || checksum.url == asset.url) return null;
    try {
      final response = await HttpFfiService.instance.get(
        checksum.url,
        headers: {
          'Accept': 'text/plain',
          'User-Agent': 'IriX/$kIrixAppVersion (+$releasesPageUrl)',
        },
        timeout: const Duration(seconds: 20),
      );
      if (!response.isOk) return null;
      for (final line in const LineSplitter().convert(response.body)) {
        // 兼容 `sha256sum` 与 `sha256sum -b` 两种格式。
        final match = RegExp(
          r'^([0-9a-fA-F]{64})\s+\*?(.+)$',
        ).firstMatch(line.trim());
        if (match == null) continue;
        if (p.basename(match.group(2)!.trim()) == asset.name) {
          return match.group(1)!.toLowerCase();
        }
      }
    } catch (e) {
      DevLog.instance.devWarn('update', 'checksum fetch failed: $e');
    }
    return null;
  }

  /// 判断磁盘上已有的安装包能否直接复用（大小 + 下载时的校验记录都一致）。
  Future<bool> _isReusable(
    String path,
    UpdateAsset asset,
    String? expectedSha,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      if (asset.size > 0 && await file.length() != asset.size) return false;
      final sidecar = File('$path.sha256');
      if (!await sidecar.exists()) return false;
      final recorded = (await sidecar.readAsString()).trim();
      if ((expectedSha ?? '') != recorded) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ========================= 安装更新 =========================

  /// 安装已下载的更新包。
  ///
  /// 返回结果里的 `appMustExit` 为 true 时，调用方应在提示后尽快退出应用，
  /// 让安装程序替换正在使用的可执行文件。
  Future<UpdateInstallResult> installUpdate(
    UpdateInfo info,
    String filePath,
  ) async {
    if (!await File(filePath).exists()) {
      throw UpdateException('安装包不存在：$filePath');
    }
    DevLog.instance.devInfo('update', 'INSTALL $filePath');
    if (Platform.isWindows) return _installWindows(filePath);
    if (Platform.isMacOS) return _installMacOs(filePath);
    if (Platform.isLinux) return _installLinux(filePath);
    throw const UpdateException('当前平台不支持应用内更新，请前往发布页下载。');
  }

  Future<UpdateInstallResult> _installWindows(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.exe') {
      // fastforge 的 exe 目标是 Inno Setup：静默安装，并自动关闭/重启占用文件的
      // 应用实例（/CLOSEAPPLICATIONS + /RESTARTAPPLICATIONS）。
      const args = [
        '/SILENT',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
        '/NORESTART',
        '/SP-',
      ];
      final launched = await _startWindowsInstaller(filePath, args);
      if (launched) {
        return UpdateInstallResult(
          mode: UpdateInstallMode.automatic,
          path: filePath,
          appMustExit: true,
        );
      }
      return UpdateInstallResult(
        mode: UpdateInstallMode.manual,
        path: filePath,
        message: '安装程序启动失败，已为你定位到安装包，请手动双击安装。',
      );
    }
    if (ext == '.msix') {
      // MSIX 需要受信任的签名/应用安装程序，无法在应用内静默升级。
      await revealInFolder(filePath);
      return UpdateInstallResult(
        mode: UpdateInstallMode.manual,
        path: filePath,
        message: 'MSIX 安装包需要由“应用安装程序”确认安装，已为你定位到该文件。',
      );
    }
    await revealInFolder(filePath);
    return UpdateInstallResult(
      mode: UpdateInstallMode.manual,
      path: filePath,
      message: '便携版压缩包已下载，请解压后覆盖旧目录（或改用安装版以获得自动更新）。',
    );
  }

  /// 启动 Windows 安装程序；需要提权时回退到 PowerShell `Start-Process -Verb RunAs`。
  Future<bool> _startWindowsInstaller(String path, List<String> args) async {
    try {
      await Process.start(
        path,
        args,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } on ProcessException catch (e) {
      // 740 = ERROR_ELEVATION_REQUIRED：安装包要求管理员权限，CreateProcess 无法提权。
      final requiresElevation =
          e.errorCode == 740 || e.message.contains('740');
      if (!requiresElevation) {
        DevLog.instance.devWarn('update', 'installer start failed: $e');
        return false;
      }
    }
    try {
      // 用 ShellExecute 语义启动，弹出 UAC 提权确认。
      final quotedArgs = args.map((a) => "'$a'").join(',');
      await Process.start(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Start-Process -FilePath '${path.replaceAll("'", "''")}' "
              "-ArgumentList $quotedArgs -Verb RunAs",
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } catch (e) {
      DevLog.instance.devWarn('update', 'installer elevation failed: $e');
      return false;
    }
  }

  Future<UpdateInstallResult> _installLinux(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.appimage') {
      final current = currentAppImagePath();
      if (current == null) {
        await revealInFolder(filePath);
        return UpdateInstallResult(
          mode: UpdateInstallMode.manual,
          path: filePath,
          message: '当前不是以 AppImage 方式运行，请手动替换为新版本。',
        );
      }
      final swapped = await _replaceAppImage(current, filePath);
      if (swapped) {
        return UpdateInstallResult(
          mode: UpdateInstallMode.automatic,
          path: current,
          appMustExit: true,
        );
      }
      await revealInFolder(filePath);
      return UpdateInstallResult(
        mode: UpdateInstallMode.manual,
        path: filePath,
        message: '无法自动替换当前 AppImage（目录不可写？），请手动覆盖 $current。',
      );
    }
    if (ext == '.deb' || ext == '.rpm') {
      // 用系统默认程序（软件中心 / 包管理器图形前端）打开，由用户确认安装。
      final opened = await _openWithSystem(filePath);
      return UpdateInstallResult(
        mode: opened ? UpdateInstallMode.assisted : UpdateInstallMode.manual,
        path: filePath,
        message: opened
            ? '已把安装包交给系统包管理器，请按提示完成安装。'
            : '已为你定位到安装包，请用包管理器手动安装。',
      );
    }
    await revealInFolder(filePath);
    return UpdateInstallResult(
      mode: UpdateInstallMode.manual,
      path: filePath,
      message: '压缩包已下载，请解压后覆盖旧目录。',
    );
  }

  /// 用后台 sh 脚本等待当前进程退出后替换 AppImage，并启动新版本。
  Future<bool> _replaceAppImage(String currentPath, String newPath) async {
    try {
      final targetDir = Directory(p.dirname(currentPath));
      // 目录不可写（只读挂载等）时直接放弃自动替换。
      final probe = File(p.join(targetDir.path, '.irix_update_probe'));
      await probe.writeAsString('ok');
      await probe.delete();

      final tempDir = await AppPaths.instance.createTempDir('irix_update_');
      final script = File(p.join(tempDir.path, 'apply_update.sh'));
      // 脚本内容里的 $1/$pid 等是 shell 变量，必须转义避免被 Dart 插值。
      await script.writeAsString(
        '#!/bin/sh\n'
        '# 等旧进程退出 → 原子替换 AppImage → 启动新版本\n'
        'pid="\$1"; src="\$2"; dst="\$3"\n'
        'while kill -0 "\$pid" 2>/dev/null; do sleep 0.2; done\n'
        'tmp="\$dst.irix-new"\n'
        'cp -f "\$src" "\$tmp" || exit 1\n'
        'chmod +x "\$tmp" || exit 1\n'
        'mv -f "\$tmp" "\$dst" || exit 1\n'
        'rm -f "\$src" "\$src.sha256" "\$0"\n'
        'exec "\$dst"\n',
      );
      await Process.run('chmod', ['+x', script.path]);
      await Process.start(
        '/bin/sh',
        [script.path, '$pid', newPath, currentPath],
        mode: ProcessStartMode.detached,
        workingDirectory: tempDir.path,
      );
      DevLog.instance.devInfo(
        'update',
        'APPIMAGE SWAP scheduled $currentPath <- $newPath',
      );
      return true;
    } catch (e) {
      DevLog.instance.devWarn('update', 'AppImage swap failed: $e');
      return false;
    }
  }

  Future<UpdateInstallResult> _installMacOs(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.dmg') {
      // dmg 需要用户把 .app 拖进“应用程序”，无法在应用内静默替换。
      final opened = await _openWithSystem(filePath);
      return UpdateInstallResult(
        mode: opened ? UpdateInstallMode.assisted : UpdateInstallMode.manual,
        path: filePath,
        message: opened
            ? '已挂载 DMG，请把 lrix.app 拖到“应用程序”覆盖旧版本。'
            : '已为你定位到 DMG，请手动挂载并覆盖旧版本。',
      );
    }
    await revealInFolder(filePath);
    return UpdateInstallResult(
      mode: UpdateInstallMode.manual,
      path: filePath,
      message: '压缩包已下载，请解压后覆盖“应用程序”中的旧版本。',
    );
  }

  // ========================= 打开链接 / 文件 =========================

  /// 打开 GitHub 发布页（[latest] 为 true 时打开最新版本的发布页）。
  Future<void> openReleasePage({bool latest = true, String? htmlUrl}) async {
    final url = htmlUrl ?? (latest ? latestReleasePageUrl : releasesPageUrl);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      DevLog.instance.devWarn('update', 'open release page failed: $e');
    }
  }

  /// 在系统文件管理器中定位文件（Windows 选中该文件，其余打开所在目录）。
  Future<void> revealInFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else {
        await Process.run('xdg-open', [p.dirname(path)]);
      }
    } catch (e) {
      DevLog.instance.devWarn('update', 'reveal failed: $e');
    }
  }

  /// 用系统默认程序打开文件。
  Future<bool> _openWithSystem(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', path], runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
      return true;
    } catch (e) {
      DevLog.instance.devWarn('update', 'open with system failed: $e');
      return false;
    }
  }

  // ========================= 平台 / 架构 / 资源选择 =========================

  /// 当前平台标签：`windows` / `macos` / `linux`。
  static String get platformTag {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  /// 当前架构标签：`x64` / `arm64` / `arm` / `ia32`。
  static String get archTag {
    final abi = Abi.current();
    if (abi == Abi.windowsArm64 ||
        abi == Abi.macosArm64 ||
        abi == Abi.linuxArm64) {
      return 'arm64';
    }
    if (abi == Abi.linuxArm) return 'arm';
    if (abi == Abi.windowsIA32 || abi == Abi.linuxIA32) return 'ia32';
    return 'x64';
  }

  /// 当前进程是否运行在 AppImage 内；是则返回 AppImage 文件路径。
  ///
  /// AppImage 运行时会把 `APPIMAGE` 设为自身路径（`/proc/self/exe` 指向挂载点，
  /// 不能用来判断）。
  static String? currentAppImagePath() {
    if (!Platform.isLinux) return null;
    final env = Platform.environment['APPIMAGE'];
    if (env != null && env.trim().isNotEmpty) return env.trim();
    return null;
  }

  /// 是否 Debian 系发行版（决定优先选 .deb 还是 .rpm）。
  static bool get _isDebLike =>
      File('/etc/debian_version').existsSync() ||
      File('/etc/apt').existsSync();

  /// 是否 RPM 系发行版。
  static bool get _isRpmLike =>
      File('/etc/redhat-release').existsSync() ||
      File('/etc/fedora-release').existsSync() ||
      File('/etc/SuSE-release').existsSync() ||
      File('/etc/rpm').existsSync();

  /// 从资源列表里按平台/架构选出最合适的安装包。
  ///
  /// 打分规则（高分优先；同分取先出现者）：
  /// - Windows：`.exe` 安装程序 100 > `.msix` 40 > `.zip` 10；
  /// - macOS：`.dmg` 100 > `.zip` 10；
  /// - Linux：运行在 AppImage 内 `.AppImage` 100；否则 `.deb`（Debian 系）/
  ///   `.rpm`（RPM 系）70 > `.AppImage` 60 > `.deb` 50 > `.rpm` 50 > `.zip` 10；
  /// - 名称里带当前架构（`x64`/`x86_64`/`amd64` 或 `arm64`/`aarch64`）+20，
  ///   带其它架构 -50（避免在 ARM 机器上下到 x64 包）。
  static UpdateAsset? selectAsset({
    required List<UpdateAsset> assets,
    required String platform,
    required String arch,
    bool hasAppImage = false,
    bool isDebLike = false,
    bool isRpmLike = false,
  }) {
    final ranked = rankAssets(
      assets: assets,
      platform: platform,
      arch: arch,
      hasAppImage: hasAppImage,
      isDebLike: isDebLike,
      isRpmLike: isRpmLike,
    );
    return ranked.isEmpty ? null : ranked.first;
  }

  /// 按 [selectAsset] 的打分规则排序，返回全部可用安装包（高分在前）。
  ///
  /// 供更新提醒窗让用户自选包型（例如 MSIX/商店版用户、便携版用户不想装 exe）。
  static List<UpdateAsset> rankAssets({
    required List<UpdateAsset> assets,
    required String platform,
    required String arch,
    bool hasAppImage = false,
    bool isDebLike = false,
    bool isRpmLike = false,
  }) {
    final scored = <(UpdateAsset, int)>[];
    for (final asset in assets) {
      if (asset.isChecksumFile) continue;
      var score = _extensionScore(
        asset.extension,
        platform: platform,
        hasAppImage: hasAppImage,
        isDebLike: isDebLike,
        isRpmLike: isRpmLike,
      );
      if (score <= 0) continue;
      score += _archScore(asset.name, arch);
      scored.add((asset, score));
    }
    // List.sort 不保证稳定，这里用下标兜底保证同分时保持原顺序。
    final indexed = scored.indexed.toList()
      ..sort((a, b) {
        final byScore = b.$2.$2.compareTo(a.$2.$2);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2.$1];
  }

  static int _extensionScore(
    String ext, {
    required String platform,
    required bool hasAppImage,
    required bool isDebLike,
    required bool isRpmLike,
  }) {
    switch (platform) {
      case 'windows':
        if (ext == '.exe') return 100;
        if (ext == '.msix') return 40;
        if (ext == '.zip') return 10;
        return 0;
      case 'macos':
        if (ext == '.dmg') return 100;
        if (ext == '.zip') return 10;
        return 0;
      case 'linux':
        if (ext == '.appimage') return hasAppImage ? 100 : 60;
        if (ext == '.deb') {
          if (isDebLike && !hasAppImage) return 80;
          return 50;
        }
        if (ext == '.rpm') {
          if (isRpmLike && !hasAppImage) return 80;
          return 50;
        }
        if (ext == '.zip') return 10;
        return 0;
      default:
        return 0;
    }
  }

  /// 名称里带当前架构加分，带其它架构大幅减分。
  static int _archScore(String name, String arch) {
    final lower = name.toLowerCase();
    final archPatterns = <String, List<String>>{
      'x64': ['x64', 'x86_64', 'amd64'],
      'arm64': ['arm64', 'aarch64'],
      'arm': ['armv7', 'armhf', 'arm32'],
      'ia32': ['ia32', 'x86'],
    };
    final mine = archPatterns[arch] ?? const <String>[];
    if (mine.any(lower.contains)) return 20;
    for (final entry in archPatterns.entries) {
      if (entry.key == arch) continue;
      if (entry.value.any(lower.contains)) return -50;
    }
    return 0;
  }

  /// 取版本号最高的发布（忽略版本无法比较的条目由解析阶段保证）。
  static UpdateRelease? _latestOf(List<UpdateRelease> releases) {
    UpdateRelease? latest;
    for (final release in releases) {
      if (latest == null || release.version.isNewerThan(latest.version)) {
        latest = release;
      }
    }
    return latest;
  }

  // ========================= 小工具 =========================

  /// 只保留安全的文件名字符，避免把路径分隔符写进下载目录。
  static String _safeFileName(String name) =>
      p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败（被占用）时交给后续下载覆盖/报错。
    }
  }

  /// 大小写不敏感地读取响应头。
  static String? _header(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// 把限流重置时间戳（秒）转成“约 N 分钟后”的提示文本。
  static String _formatResetHint(String resetUnixSeconds) {
    final reset = int.tryParse(resetUnixSeconds.trim());
    if (reset == null) return '稍';
    final nowSeconds = TimeService.instance.nowUnixSeconds();
    final delta = reset - nowSeconds;
    if (delta <= 0) return '片刻';
    if (delta < 60) return '不到 1 分钟';
    return '约 ${(delta / 60).ceil()} 分钟';
  }
}
