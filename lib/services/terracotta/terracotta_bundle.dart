// 陶瓦联机（Terracotta）联机核心的下载 / 安装 / 完整性校验。
//
// 对应 HMCL `TerracottaBundle`：
// - 官方发布包是 `terracotta-<版本>-<平台>-pkg.tar.gz`（内含未修改的联机核心
//   可执行文件与所需运行库），整包与包内每个文件都有 SHA-512 摘要；
// - 安装目录为 `<数据根>/terracotta/<版本>/`，安装完成后逐个复核摘要，
//   摘要不符即整体删除（防止半装状态被当成「已安装」）；
// - 联机核心本体不参与本仓库的构建，也不做任何修改/重链接，只被当作外部
//   程序运行（Terracotta 的 AGPL 例外条款允许这种 IPC 方式使用）。

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../dev_log.dart';
import '../downloader.dart';
import 'terracotta_metadata.dart';

/// 本地联机核心状态（对应 HMCL `AbstractTerracottaProvider.Status`）。
enum TerracottaBundleStatus {
  /// 未安装。
  notExist,

  /// 存在旧版本目录，需要更新。
  legacyVersion,

  /// 已就绪（文件齐全且摘要正确）。
  ready,
}

/// 下载失败（网络/镜像全部失效或摘要不符）。
class TerracottaDownloadException implements Exception {
  TerracottaDownloadException(this.message);

  final String message;

  @override
  String toString() => 'TerracottaDownloadException: $message';
}

/// 安装失败（包结构异常、摘要不符、解包失败）。
class TerracottaInstallException implements Exception {
  TerracottaInstallException(this.message);

  final String message;

  @override
  String toString() => 'TerracottaInstallException: $message';
}

/// 单个文件的校验结果。
class TerracottaVerifyResult {
  const TerracottaVerifyResult({required this.ok, this.badFiles = const []});

  final bool ok;

  /// 校验不通过的文件名（用于日志与界面提示）。
  final List<String> badFiles;
}

/// 一个平台的联机核心包：负责下载、校验、安装与路径解析。
class TerracottaBundle {
  TerracottaBundle({
    required this.version,
    required this.classifier,
    required this.rootPath,
    required this.package,
  });

  /// 按当前平台解析（不支持时返回 null，由调用方转成 Fatal(os)）。
  static TerracottaBundle? forCurrentPlatform(String terracottaRoot) {
    final classifier = TerracottaMetadata.currentClassifier();
    final package = TerracottaMetadata.currentPackage();
    if (classifier == null || package == null) return null;
    return TerracottaBundle(
      version: kTerracottaVersion,
      classifier: classifier,
      rootPath: p.join(terracottaRoot, kTerracottaVersion),
      package: package,
    );
  }

  /// 联机核心版本号。
  final String version;

  /// 平台标识（如 `windows-x86_64`）。
  final String classifier;

  /// 安装目录（`<数据根>/terracotta/<版本>`）。
  final String rootPath;

  /// 包元数据（整包摘要 + 包内文件摘要）。
  final TerracottaPackage package;

  /// 官方包文件名。
  String get packageName => 'terracotta-$version-$classifier-pkg.tar.gz';

  /// 可执行文件名（Windows 带 `.exe`）。
  String get executableName {
    final base = 'terracotta-$version-$classifier';
    return Platform.isWindows ? '$base.exe' : base;
  }

  /// 可执行文件绝对路径。
  String get executablePath => p.join(rootPath, executableName);

  /// 校验通过的文件清单（用于「已安装」判定）。
  Iterable<String> get expectedFiles => package.files.keys;

  /// 目录内是否已有解包结果（不代表校验通过）。
  bool get directoryExists => Directory(rootPath).existsSync();

  /// 判定本地状态：文件齐全且摘要一致才算就绪。
  Future<TerracottaBundleStatus> status() async {
    if (directoryExists) {
      final result = await verifyInstalled();
      if (result.ok) return TerracottaBundleStatus.ready;
    }
    if (await hasLegacyVersions()) return TerracottaBundleStatus.legacyVersion;
    return TerracottaBundleStatus.notExist;
  }

  /// 逐个复核已安装文件的 SHA-512（在独立 isolate 中读取，避免卡 UI）。
  Future<TerracottaVerifyResult> verifyInstalled() async {
    if (!directoryExists) {
      return const TerracottaVerifyResult(ok: false, badFiles: ['(目录不存在)']);
    }
    final files = Map<String, String>.from(package.files);
    final root = rootPath;
    try {
      final bad = await Isolate.run(() => _verifyFilesSync(root, files));
      return TerracottaVerifyResult(ok: bad.isEmpty, badFiles: bad);
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '校验已安装文件失败: $e');
      return TerracottaVerifyResult(ok: false, badFiles: ['(校验异常: $e)']);
    }
  }

  /// 下载官方包（自动按顺序尝试镜像），返回本地 tar.gz 路径。
  ///
  /// [onProgress] 汇报 0..1 的进度（总进度 = 单文件进度，包只有一个文件）。
  Future<String> download({
    void Function(double? progress)? onProgress,
    Future<void> Function()? isCancelled,
  }) async {
    final urls = TerracottaMetadata.resolveDownloadUrls();
    if (urls.isEmpty) {
      throw TerracottaDownloadException('当前平台没有可用的下载渠道');
    }

    final tempDir = await AppPaths.instance.createTempDir('irix-terracotta-');
    final target = p.join(tempDir.path, packageName);
    Object? lastError;

    for (final url in urls) {
      if (isCancelled != null) await isCancelled();
      DevLog.instance.devInfo('terracotta', '下载联机核心: $url');
      try {
        await Downloader().downloadFile(
          url,
          target,
          (progress) {
            final total = progress.totalBytes;
            if (total > 0) {
              onProgress?.call(
                (progress.downloadedBytes / total).clamp(0.0, 1.0),
              );
            } else {
              onProgress?.call(null);
            }
          },
          // 整包 SHA-512 由 Rust Downloader 校验，杜绝镜像投毒。
          sha512: package.hash,
        );
        onProgress?.call(1);
        return target;
      } catch (e) {
        lastError = e;
        DevLog.instance.devWarn('terracotta', '下载失败，尝试下一个渠道: $e');
        final file = File(target);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      }
    }

    throw TerracottaDownloadException('所有下载渠道均失败：${lastError ?? '未知错误'}');
  }

  /// 安装本地 tar.gz（[pkgPath] 为已下载或用户手动选择的包）。
  ///
  /// 完成后删除旧目录、写入新文件并复核摘要；失败时清理半成品目录。
  Future<void> install(String pkgPath) async {
    final file = File(pkgPath);
    if (!file.existsSync()) {
      throw TerracottaInstallException('安装包不存在: $pkgPath');
    }
    final bytes = await file.readAsBytes();
    final root = rootPath;
    final files = Map<String, String>.from(package.files);
    final executable = executableName;

    List<String> written;
    try {
      written = await Isolate.run(
        () => _extractBundleSync(bytes, root, files, executable),
      );
    } catch (e) {
      await _deleteDirectory(root);
      throw TerracottaInstallException('解包失败: $e');
    }

    if (written.isNotEmpty) {
      await _deleteDirectory(root);
      throw TerracottaInstallException('安装包内容校验失败: ${written.join(', ')}');
    }
    DevLog.instance.devInfo('terracotta', '联机核心已安装: $root');
  }

  /// 用户手动选择的本地包是否合法（只看文件名，与 HMCL 行为一致）。
  bool isInvalidLocalBundle(String path) =>
      p.basename(path).toLowerCase() != packageName.toLowerCase();

  /// 移除半成品/旧安装目录。
  Future<void> _deleteDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        DevLog.instance.devWarn('terracotta', '删除目录失败 $path: $e');
      }
    }
  }

  /// 是否存在旧版本目录（`<root>/<版本号>`，版本号 <= 当前版本且不等于当前版本）。
  Future<bool> hasLegacyVersions() async =>
      (await legacyVersionDirs()).isNotEmpty;

  /// 旧版本目录列表。
  Future<List<String>> legacyVersionDirs() async {
    final parent = Directory(p.dirname(rootPath));
    if (!await parent.exists()) return const [];
    final current = _parseVersion(version);
    if (current == null) return const [];
    final result = <String>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      final parsed = _parseVersion(name);
      if (parsed == null) continue;
      if (_compareVersion(parsed, current) <= 0 && name != version) {
        result.add(entity.path);
      }
    }
    return result;
  }

  /// 删除旧版本目录（升级完成后调用，与 HMCL `removeLegacyVersionFiles` 一致）。
  Future<void> removeLegacyVersions() async {
    for (final dir in await legacyVersionDirs()) {
      await _deleteDirectory(dir);
    }
  }
}

/// 解析 `0.4.2` 这类版本号；非法返回 null。
List<int>? _parseVersion(String text) {
  final match = RegExp(r'^v?(\d+(?:\.\d+)*)$').firstMatch(text.trim());
  if (match == null) return null;
  return match.group(1)!.split('.').map(int.parse).toList(growable: false);
}

/// 逐段比较版本号（缺失段按 0 处理）。
int _compareVersion(List<int> a, List<int> b) {
  final max = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < max; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

/// isolate 内：校验已安装文件的摘要，返回不通过的文件名。
List<String> _verifyFilesSync(String root, Map<String, String> files) {
  final bad = <String>[];
  var total = 0;
  for (final entry in files.entries) {
    final file = File(p.join(root, entry.key));
    if (!file.existsSync()) {
      bad.add(entry.key);
      continue;
    }
    final bytes = file.readAsBytesSync();
    total += bytes.length;
    // 与 HMCL 相同的 50MB 上限：正常包远小于该值，超过即视为异常。
    if (total >= 50 * 1024 * 1024) {
      bad.add(entry.key);
      continue;
    }
    if (crypto.sha512.convert(bytes).toString().toLowerCase() !=
        entry.value.toLowerCase()) {
      bad.add(entry.key);
    }
  }
  return bad;
}

/// isolate 内：解包并写入 `root`，返回摘要不符（因而被拒绝）的文件名。
List<String> _extractBundleSync(
  Uint8List archiveBytes,
  String root,
  Map<String, String> files,
  String executableName,
) {
  final Archive archive = TarDecoder().decodeBytes(
    GZipDecoder().decodeBytes(archiveBytes),
  );

  // 包内条目名可能带 `./` 或 `/` 前缀，统一按「末段文件名」匹配。
  final entries = <String, ArchiveFile>{};
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    final name = p.basename(entry.name.replaceAll('\\', '/'));
    entries[name] = entry;
  }

  for (final name in files.keys) {
    if (!entries.containsKey(name)) {
      throw StateError('安装包缺少文件: $name');
    }
  }

  final dir = Directory(root);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final rootNorm = p.normalize(p.absolute(root));
  final bad = <String>[];

  for (final entry in files.entries) {
    final name = entry.key;
    final file = entries[name]!;
    final outPath = p.normalize(p.join(rootNorm, name));
    // tar 条目不允许逃逸安装目录。
    if (!p.isWithin(rootNorm, outPath)) {
      throw StateError('安装包条目越界: ${file.name}');
    }
    final content = file.content;
    final outFile = File(outPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsBytesSync(content, flush: true);

    if (crypto.sha512.convert(content).toString().toLowerCase() !=
        entry.value.toLowerCase()) {
      bad.add(name);
    }
  }

  // POSIX 平台补上可执行权限（Windows 无需处理）。
  if (!Platform.isWindows) {
    final target = p.join(rootNorm, executableName);
    if (File(target).existsSync()) {
      Process.runSync('chmod', ['755', target]);
    }
  }
  return bad;
}
