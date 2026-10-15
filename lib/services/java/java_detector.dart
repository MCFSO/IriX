// Java 运行时探测（移植自 HMCL JavaInfoUtils / JavaRuntime.of）
//
// HMCL 通过启动一个 Java 子进程运行 `org.glavo.info.Main` 读取
// `java.version` / `java.vendor` / `os.arch`。
// Dart 侧等价做法：执行 `java -XshowSettings:properties -version`，
// 从 stderr 解析 `java.version` 等系统属性（该命令在任何 JRE/JDK 上可用，
// 无需额外 jar 与 classpath）。
//
// 探测结果按可执行文件路径 + 文件大小/修改时间缓存（复刻 HMCL 的
// javaCache.json，key 含 size/lastModified/release 哈希）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/java_runtime.dart';

/// 单个 Java 可执行文件的探测结果缓存。
class _CacheEntry {
  const _CacheEntry(this.key, this.info, this.isJDK);

  final String key;
  final JavaInfo info;
  final bool isJDK;
}

/// Java 运行时探测服务。
class JavaDetector {
  JavaDetector._();

  static final JavaDetector instance = JavaDetector._();

  final Map<String, _CacheEntry> _cache = {};

  /// Java 可执行文件名（HMCL `OperatingSystem.getJavaExecutable`）。
  static String get javaExecutableName =>
      Platform.isWindows ? 'java.exe' : 'java';

  /// javac 可执行文件名（用于 JDK / JRE 判定）。
  static String get javacExecutableName =>
      Platform.isWindows ? 'javac.exe' : 'javac';

  /// 探测指定 java 可执行文件。
  ///
  /// [isManaged] 标记是否由 IriX 安装管理。
  /// 失败（文件不存在 / 执行超时 / 无法解析版本）返回 null。
  Future<JavaRuntime?> detect(
    String executable, {
    bool isManaged = false,
  }) async {
    final file = File(executable);
    if (!file.existsSync()) return null;

    String realPath;
    try {
      realPath = await file.resolveSymbolicLinks();
    } catch (_) {
      realPath = p.normalize(p.absolute(executable));
    }

    final stat = file.statSync();
    final cacheKey = _cacheKey(realPath, stat);
    final cached = _cache[realPath];
    if (cached != null && cacheKey != null && cached.key == cacheKey) {
      // 缓存命中：复用 info，但受管状态可能变化（安装/接管），需重建运行时。
      return JavaRuntime(
        binary: realPath,
        info: cached.info,
        isJDK: cached.isJDK,
        isManaged: isManaged,
      );
    }

    final info = await _probe(realPath);
    if (info == null) return null;

    final isJDK = File(
      p.join(p.dirname(realPath), javacExecutableName),
    ).existsSync();

    if (cacheKey != null) {
      _cache[realPath] = _CacheEntry(
        cacheKey,
        info.copyWith(osName: _osName),
        isJDK,
      );
    }

    return JavaRuntime(
      binary: realPath,
      info: info.copyWith(osName: _osName),
      isJDK: isJDK,
      isManaged: isManaged,
    );
  }

  /// 批量探测（并发上限 4，避免一次性拉起过多子进程）。
  Future<List<JavaRuntime>> detectAll(
    Iterable<({String path, bool isManaged})> candidates,
  ) async {
    final result = <JavaRuntime>[];
    final queue = candidates.toList();
    const concurrency = 4;

    for (var i = 0; i < queue.length; i += concurrency) {
      final batch = queue.skip(i).take(concurrency);
      final done = await Future.wait(
        batch.map((c) => detect(c.path, isManaged: c.isManaged)),
      );
      result.addAll(done.whereType<JavaRuntime>());
    }

    result.sort();
    return result;
  }

  /// 清空探测缓存（「刷新」按钮调用）。
  void clearCache() => _cache.clear();

  /// 缓存键：文件大小 + 修改时间 + release 文件哈希（复刻 HMCL createCacheKey）。
  String? _cacheKey(String realPath, FileStat stat) {
    final binDir = p.dirname(realPath);
    if (p.basename(binDir) != 'bin') return null;

    final javaHome = p.dirname(binDir);
    if (!Directory(p.join(javaHome, 'lib')).existsSync()) return null;

    final parts = <String>[
      'sz:${stat.size}',
      'lm:${stat.modified.millisecondsSinceEpoch}',
    ];

    // release 文件内容指纹（HMCL 取 SHA-1；此处用长度 + 首行足够区分升级）。
    final release = File(p.join(javaHome, 'release'));
    if (release.existsSync()) {
      try {
        final text = release.readAsStringSync();
        parts.add('rel:${text.length}:${text.hashCode}');
      } catch (_) {}
    }

    return parts.join(',');
  }

  /// 实际执行 `java -XshowSettings:properties -version` 并解析系统属性。
  Future<JavaInfo?> _probe(String executable) async {
    try {
      final process = await Process.start(executable, [
        '-XshowSettings:properties',
        '-version',
      ], runInShell: false);

      // 该命令的输出全部写到 stderr。
      final buffer = StringBuffer();
      final done = process.stderr
          .transform(utf8.decoder)
          .listen(buffer.write)
          .asFuture<void>();
      // 同时消费 stdout，避免管道阻塞。
      process.stdout.drain<void>();

      await Future.wait([done]).timeout(const Duration(seconds: 15));

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      final output = buffer.toString();
      if (output.trim().isEmpty && exitCode != 0) return null;

      final info = _parseProperties(output);

      // 属性缺失时回退到 `release` 文件（受管 JDK 一定有该文件）。
      if (info == null) {
        final releaseFile = File(
          p.join(p.dirname(p.dirname(executable)), 'release'),
        );
        if (releaseFile.existsSync()) {
          try {
            return JavaInfo.fromReleaseFile(releaseFile.readAsStringSync());
          } catch (_) {}
        }
      }
      return info;
    } catch (_) {
      return null;
    }
  }

  /// 解析 `-XshowSettings:properties` 的 `key = value` 行。
  JavaInfo? _parseProperties(String output) {
    final props = <String, String>{};

    // 形状形如：
    //     java.version = 17.0.9
    //     java.vendor = Eclipse Adoptium
    //     os.arch = amd64
    final regex = RegExp(
      r'^\s{4}([a-z][a-zA-Z0-9._]*)\s*=\s*(.*)$',
      multiLine: true,
    );
    for (final m in regex.allMatches(output)) {
      props[m.group(1)!] = m.group(2)!.trim();
    }

    var version = props['java.version'];
    var arch = props['os.arch'];
    var vendor = props['java.vendor'];

    // -XshowSettings 在某些旧 JRE 上不可用，退化为解析 `-version` 文本。
    if (version == null || version.isEmpty) {
      final fallback = _parseVersionText(output);
      version = fallback.version;
      arch = fallback.architecture.checkedName;
      vendor ??= fallback.vendor;
    }

    if (version.isEmpty) return null;

    return JavaInfo(
      version: version,
      architecture: JavaArchitecture.parseArchName(arch),
      vendor: vendor,
      osName: _osName,
    );
  }

  /// 从 `java -version` 的文本输出解析（老版本回退路径）。
  static JavaInfo _parseVersionText(String output) {
    // openjdk version "17.0.9" 2023-10-17
    // java version "1.8.0_392"
    final m = RegExp(r'version\s+"([^"]+)"').firstMatch(output);
    final version = m?.group(1) ?? '';

    // OpenJDK 64-Bit Server VM (build ...) → 位宽推断架构。
    JavaArchitecture arch = JavaArchitecture.unknown;
    if (output.contains('64-Bit') || output.contains('64-bit')) {
      arch = JavaArchitecture.current == JavaArchitecture.arm64
          ? JavaArchitecture.arm64
          : JavaArchitecture.x86_64;
    } else if (output.contains('32-Bit') || output.contains('32-bit')) {
      arch = JavaArchitecture.x86;
    }

    return JavaInfo(
      version: version,
      architecture: arch,
      vendor: JavaInfo.parseVendorFromVersionOutput(output),
      osName: _osName,
    );
  }

  static String get _osName {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'Mac OS X';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    return Platform.operatingSystem;
  }
}
