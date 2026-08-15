// JDK 安装服务（首次引导用）
//
// 从 Adoptium（Eclipse Temurin）API 查询并下载指定大版本的 JDK，
// 解压到应用数据目录，供首次引导「安装 JDK 8 / 17 / 21 / 25」步骤调用。
// - 元数据查询走 Rust http_client（HttpFfiService）
// - 二进制下载走 Rust Downloader（流式写盘，进度回调）
// - 解压用 package:archive（zip / tar.gz 按链接扩展名判断），
//   在后台 isolate 执行（大文件避免阻塞 UI），并剥离顶层目录
// - 已安装位置持久化到 settings（jdk_home_<feature>）

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_manager.dart';
import 'downloader.dart';
import 'http_ffi.dart';

/// JDK 安装服务。
class JdkInstaller {
  JdkInstaller._();

  static final JdkInstaller instance = JdkInstaller._();

  /// 首次引导默认安装的大版本序列。
  static const defaultVersions = ['8', '17', '21', '25'];

  /// 安装根目录（应用文档目录 / irix / java）。
  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'irix', 'java'));
  }

  /// 版本对应的安装目录。
  Future<Directory> _versionDir(String featureVersion) async {
    return Directory(p.join((await _rootDir()).path, 'jdk-$featureVersion'));
  }

  /// 是否已安装（目录存在且含 java 可执行文件）。
  Future<bool> isInstalled(String featureVersion) async {
    final dir = await _versionDir(featureVersion);
    final java = p.join(
      dir.path,
      'bin',
      Platform.isWindows ? 'java.exe' : 'java',
    );
    return File(java).existsSync();
  }

  /// 已安装 JDK 的根路径（未安装返回 null）。
  Future<String?> javaHome(String featureVersion) async {
    if (!await isInstalled(featureVersion)) return null;
    return (await _versionDir(featureVersion)).path;
  }

  /// 查询 Adoptium 获取该版本当前平台的下载链接。
  Future<String> _resolveDownloadUrl(String featureVersion) async {
    final os = switch (Platform.operatingSystem) {
      'windows' => 'windows',
      'macos' => 'mac',
      'linux' => 'linux',
      final other => throw Exception('不支持的平台: $other'),
    };
    final url = Uri.parse(
      'https://api.adoptium.net/v3/assets/latest/$featureVersion/hotspot'
      '?architecture=x64&image_type=jdk&os=$os&vendor=eclipse',
    );
    final resp = await HttpFfiService.instance.get(
      url.toString(),
      timeout: const Duration(seconds: 20),
    );
    if (resp.statusCode >= 400) {
      throw Exception('Adoptium API 返回 HTTP ${resp.statusCode}');
    }
    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final binary = item['binary'];
      if (binary is! Map<String, dynamic>) continue;
      final package = binary['package'];
      if (package is! Map<String, dynamic>) continue;
      final link = package['link'];
      if (link is String && link.isNotEmpty) return link;
    }
    throw Exception('未找到 JDK $featureVersion 的下载链接');
  }

  /// 安装指定大版本 JDK。
  ///
  /// [onProgress] 为下载进度（0~1）；已安装时立即返回。
  /// 返回安装后的根路径。
  Future<String> install(
    String featureVersion, {
    void Function(double progress)? onProgress,
  }) async {
    final existing = await javaHome(featureVersion);
    if (existing != null) return existing;

    final url = await _resolveDownloadUrl(featureVersion);
    final tmpDir = await Directory.systemTemp.createTemp('irix-jdk-');
    final archivePath = p.join(tmpDir.path, 'jdk-archive');
    try {
      await Downloader().downloadFile(url, archivePath, (progress) {
        final total = progress.totalBytes;
        final ratio = total > 0 ? progress.downloadedBytes / total : 0.0;
        onProgress?.call(ratio.clamp(0.0, 1.0));
      });
      final target = await _versionDir(featureVersion);
      if (target.existsSync()) target.deleteSync(recursive: true);
      target.createSync(recursive: true);
      await Isolate.run(() => _extract(archivePath, target.path, url));
      final home = target.path;
      await DatabaseManager.instance.setSetting(
        'jdk_home_$featureVersion',
        home,
      );
      return home;
    } finally {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 解压归档到目标目录（后台 isolate 内同步执行），剥离顶层目录。
  static void _extract(String archivePath, String targetPath, String url) {
    final bytes = File(archivePath).readAsBytesSync();
    final archive = (url.endsWith('.tar.gz') || url.endsWith('.tgz'))
        ? TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes))
        : ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      // 剥离顶层目录（如 jdk-17.0.13+11/...）
      var name = file.name;
      final slash = name.indexOf('/');
      if (slash > 0) name = name.substring(slash + 1);
      if (name.isEmpty) continue;
      final outPath = p.join(targetPath, name);
      final outDir = Directory(p.dirname(outPath));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      File(outPath).writeAsBytesSync(file.content as List<int>);
    }
  }
}
