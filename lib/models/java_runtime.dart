// Java 运行时模型（移植自 HMCL org.jackhuang.hmcl.java.JavaInfo / JavaRuntime）
//
// 对应关系：
// - [JavaInfo]       ⇐ HMCL JavaInfo（版本、厂商、平台/架构、版本号解析）
// - [JavaRuntime]    ⇐ HMCL JavaRuntime（可执行文件、是否 JDK、是否受管、排序）
// - [JavaArchitecture] ⇐ HMCL Architecture（架构归一化与显示名）
//
// 移植要点：
// - 版本解析完全复刻 HMCL：`1.8.0_392` → 8；`17.0.9` → 17；
//   过长的数字段返回 -1（HMCL 的 catch 兜底行为）。
// - 厂商归一化复刻 HMCL JavaInfo.normalizeVendor 的映射表。
// - JavaRuntime 相等性基于可执行文件绝对路径（HMCL 亦如此），
//   因此列表刷新时会先 clear 再 addAll，避免升级后残留旧项。

import 'dart:io';

import 'package:path/path.dart' as p;

/// CPU 架构（对应 HMCL `Architecture`）。
enum JavaArchitecture {
  x86('x86', 32),
  x86_64('x86_64', 64),
  arm64('arm64', 64),
  arm32('arm32', 32),
  riscv64('riscv64', 64),
  loongarch64('loongarch64', 64),
  unknown('unknown', 0);

  const JavaArchitecture(this.checkedName, this.bits);

  /// 用于清单/缓存的稳定标识（HMCL 的 checkedName）。
  final String checkedName;

  /// 位数（HMCL `Bits`）。
  final int bits;

  /// 展示名（HMCL `getDisplayName`）。
  String get displayName => switch (this) {
    JavaArchitecture.x86 => 'x86',
    JavaArchitecture.x86_64 => 'x86_64',
    JavaArchitecture.arm64 => 'arm64',
    JavaArchitecture.arm32 => 'arm32',
    JavaArchitecture.riscv64 => 'riscv64',
    JavaArchitecture.loongarch64 => 'loongarch64',
    JavaArchitecture.unknown => '未知',
  };

  bool get isX86 =>
      this == JavaArchitecture.x86 || this == JavaArchitecture.x86_64;

  /// 解析 `os.arch` / `OS_ARCH`（对应 HMCL `Architecture.parseArchName`）。
  static JavaArchitecture parseArchName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    switch (n) {
      case 'x86':
      case 'i386':
      case 'i486':
      case 'i586':
      case 'i686':
      case 'ia32':
      case 'x86_32':
        return JavaArchitecture.x86;
      case 'amd64':
      case 'x86_64':
      case 'x86-64':
      case 'x64':
      case 'em64t':
        return JavaArchitecture.x86_64;
      case 'aarch64':
      case 'arm64':
        return JavaArchitecture.arm64;
      case 'arm':
      case 'arm32':
      case 'armv7':
      case 'armv7l':
        return JavaArchitecture.arm32;
      case 'riscv64':
        return JavaArchitecture.riscv64;
      case 'loongarch64':
        return JavaArchitecture.loongarch64;
      default:
        return JavaArchitecture.unknown;
    }
  }

  /// 当前进程架构（对应 HMCL `Architecture.CURRENT_ARCH`）。
  static JavaArchitecture get current {
    // Dart 无直接 API，按 os.arch 语义从 Platform 版本与已知常量推断。
    // 使用环境变量而非 Process，避免额外进程开销。
    final arch =
        Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        '';
    final parsed = parseArchName(arch);
    if (parsed != JavaArchitecture.unknown) return parsed;

    // 回退：非 Windows 平台用 `uname -m` 语义常量（Dart 不提供，取 64 位默认）。
    if (Platform.isWindows) return JavaArchitecture.x86_64;
    return JavaArchitecture.x86_64;
  }
}

/// Java 安装信息（对应 HMCL `JavaInfo`）。
class JavaInfo {
  const JavaInfo({
    required this.version,
    required this.architecture,
    this.vendor,
    this.osName,
  });

  /// 完整版本字符串，如 `17.0.9`、`1.8.0_392`。
  final String version;

  /// 架构。
  final JavaArchitecture architecture;

  /// 厂商原始名（未归一化），如 `Eclipse Adoptium`。
  final String? vendor;

  /// 操作系统名（清单中 `os.name`）。
  final String? osName;

  /// 大版本号（HMCL `getParsedVersion`）。
  ///
  /// `1.8.0_392` → 8；`17.0.9` → 17；无法解析 → -1。
  int get parsedVersion => parseVersion(version);

  /// 归一化厂商名（HMCL `normalizeVendor`）。
  String? get normalizedVendor => normalizeVendor(vendor);

  /// 版本号数值列表，用于比较（HMCL `VersionNumber.asVersion`）。
  List<int> get versionNumber => parseVersionNumber(version);

  /// 解析大版本号（完全复刻 HMCL `JavaInfo.parseVersion`）。
  ///
  /// `1.x` 前缀时从索引 2 起取连续数字；否则从 0 起。
  /// 无数字或数值溢出时返回 -1。
  static int parseVersion(String version) {
    final startIndex = version.startsWith('1.') ? 2 : 0;
    var endIndex = startIndex;

    while (endIndex < version.length) {
      final ch = version.codeUnitAt(endIndex);
      // '0'..'9'
      if (ch >= 0x30 && ch <= 0x39) {
        endIndex++;
      } else {
        break;
      }
    }

    if (endIndex <= startIndex) return -1;
    final value = int.tryParse(version.substring(startIndex, endIndex));
    // HMCL 在数值过大（NumberFormatException）时返回 -1。
    return value ?? -1;
  }

  /// 解析完整版本号为可比数值列表。
  ///
  /// `17.0.9+11` → [17, 0, 9, 11]；非法段跳过。
  static List<int> parseVersionNumber(String version) {
    final result = <int>[];
    for (final part in version.split(RegExp(r'[.\-_+]'))) {
      if (part.isEmpty) continue;
      final v = int.tryParse(part);
      if (v == null) break;
      result.add(v);
    }
    return result;
  }

  /// 厂商名归一化（复刻 HMCL `JavaInfo.normalizeVendor`）。
  static String? normalizeVendor(String? vendor) {
    if (vendor == null) return null;
    switch (vendor) {
      case 'N/A':
        return null;
      case 'Oracle Corporation':
        return 'Oracle';
      case 'Azul Systems, Inc.':
        return 'Azul';
      case 'IBM Corporation':
      case 'International Business Machines Corporation':
      case 'Eclipse OpenJ9':
        return 'IBM';
      case 'Eclipse Adoptium':
        return 'Adoptium';
      case 'Amazon.com Inc.':
        return 'Amazon';
      default:
        return vendor;
    }
  }

  /// 从 JDK 根目录的 `release` 文件解析（对应 HMCL `JavaInfo.fromReleaseFile`）。
  ///
  /// 返回 null 表示文件缺失或关键字段无法解析。
  static JavaInfo? fromReleaseFile(String content) {
    final props = <String, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      var key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      // 去掉可能的首尾引号。
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      props[key] = value;
    }

    final javaVersion = props['JAVA_VERSION'];
    if (javaVersion == null || javaVersion.isEmpty) return null;

    var osName = props['OS_NAME'] ?? '';
    final vendor = props['IMPLEMENTOR'];
    // HMCL：BSD 移植版 OS_NAME 为空但厂商为 OpenJDK BSD Porting Team。
    if (osName.isEmpty && vendor == 'OpenJDK BSD Porting Team') {
      osName = 'FreeBSD';
    }

    return JavaInfo(
      version: javaVersion,
      architecture: JavaArchitecture.parseArchName(props['OS_ARCH']),
      vendor: vendor,
      osName: osName.isEmpty ? null : osName,
    );
  }

  /// 从 `java -version` 输出解析厂商（HMCL 走 java-info 子进程取 `java.vendor`）。
  ///
  /// 形如：`OpenJDK 64-Bit Server VM Eclipse Adoptium-17.0.9+9 (build ...)`。
  static String? parseVendorFromVersionOutput(String output) {
    // Oracle JDK 输出 "Java(TM) SE Runtime Environment (build 1.8.0_392-b08)"。
    if (output.contains('Java(TM)')) return 'Oracle Corporation';
    // OpenJDK 输出首行为 `openjdk version "17.0.9" 2023-10-17`，
    // 第三行为 `OpenJDK 64-Bit Server VM <vendor>-<version>+<build>`。
    final vmLine = RegExp(
      r'^(OpenJDK|Java HotSpot\(TM\)).*?VM\s+(.+?)-\d',
      multiLine: true,
    ).firstMatch(output);
    if (vmLine != null) return vmLine.group(2)?.trim();
    return null;
  }

  JavaInfo copyWith({
    String? version,
    JavaArchitecture? architecture,
    String? vendor,
    String? osName,
  }) {
    return JavaInfo(
      version: version ?? this.version,
      architecture: architecture ?? this.architecture,
      vendor: vendor ?? this.vendor,
      osName: osName ?? this.osName,
    );
  }

  Map<String, dynamic> toJson() => {
    'os.name': osName,
    'os.arch': architecture.checkedName,
    'java.version': version,
    'java.vendor': vendor,
  };

  static JavaInfo fromJson(Map<String, dynamic> json) {
    return JavaInfo(
      version: (json['java.version'] ?? '').toString(),
      architecture: JavaArchitecture.parseArchName(json['os.arch']?.toString()),
      vendor: json['java.vendor']?.toString(),
      osName: json['os.name']?.toString(),
    );
  }

  @override
  String toString() =>
      '${normalizedVendor ?? '未知'} $version (${architecture.checkedName})';
}

/// Java 运行时（对应 HMCL `JavaRuntime`）。
class JavaRuntime implements Comparable<JavaRuntime> {
  JavaRuntime({
    required this.binary,
    required this.info,
    required this.isJDK,
    this.isManaged = false,
  });

  /// java 可执行文件绝对路径。
  final String binary;

  /// 安装信息。
  final JavaInfo info;

  /// 是否为 JDK（同目录存在 javac）——HMCL `JavaRuntime.of` 的判定方式。
  final bool isJDK;

  /// 是否受 IriX 管理（安装在本应用 Java 目录下）——HMCL `isManaged`。
  final bool isManaged;

  String get version => info.version;

  int get parsedVersion => info.parsedVersion;

  JavaArchitecture get architecture => info.architecture;

  String? get vendor => info.vendor;

  String? get normalizedVendor => info.normalizedVendor;

  /// 唯一标识（可执行文件路径），用于持久化禁用列表。
  String get id => binary;

  /// java home（可执行文件的上级的上级）。
  ///
  /// 按路径自身的分隔符风格解析，而非按当前运行平台：
  /// 在 Linux CI 上校验 Windows 路径（或反之）时 `p.dirname` 会因
  /// 平台风格不符而返回 `.`，故显式选用 [p.windows] / [p.posix]。
  String get javaHome {
    final ctx = binary.contains(r'\') ? p.windows : p.posix;
    return ctx.dirname(ctx.dirname(binary));
  }

  /// 列表标题：`厂商 JDK/JRE 版本`（HMCL JavaItemCell 的拼装方式）。
  String get displayTitle {
    final v = normalizedVendor ?? '未知';
    return '$v ${isJDK ? 'JDK' : 'JRE'} $version';
  }

  /// 架构兼容判定（简化版 HMCL `JavaManager.isCompatible`）。
  ///
  /// 仅要求操作系统一致；架构不同时在 UI 上以标签提示，
  /// 不直接隐藏（服务器场景可能挂载异构 JDK 目录）。
  bool get isCompatibleWithHost {
    final host = JavaArchitecture.current;
    if (info.architecture == JavaArchitecture.unknown) return true;
    if (info.architecture == host) return true;
    // Windows x64 可运行 x86；Windows/Linux x64 兼容 x86。
    if (host == JavaArchitecture.x86_64 &&
        info.architecture == JavaArchitecture.x86) {
      return true;
    }
    // macOS arm64 经 Rosetta 2 可运行 x86_64。
    if (host == JavaArchitecture.arm64 &&
        Platform.isMacOS &&
        info.architecture == JavaArchitecture.x86_64) {
      return true;
    }
    return false;
  }

  /// 排序：受管优先 → 大版本升序 → 完整版本 → 架构 → 路径（复刻 HMCL compareTo）。
  @override
  int compareTo(JavaRuntime other) {
    if (isManaged != other.isManaged) return isManaged ? -1 : 1;

    var c = parsedVersion.compareTo(other.parsedVersion);
    if (c != 0) return c;

    c = _compareVersionNumber(info.versionNumber, other.info.versionNumber);
    if (c != 0) return c;

    c = architecture.index.compareTo(other.architecture.index);
    if (c != 0) return c;

    return binary.compareTo(other.binary);
  }

  static int _compareVersionNumber(List<int> a, List<int> b) {
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      final c = x.compareTo(y);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is JavaRuntime && other.binary == binary;

  @override
  int get hashCode => binary.hashCode;

  @override
  String toString() => 'JavaRuntime($binary)';
}
