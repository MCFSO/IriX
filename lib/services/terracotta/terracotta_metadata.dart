// 陶瓦联机（Terracotta）联机核心的元数据。
//
// 依据 HMCL 的 `org.jackhuang.hmcl.terracotta.TerracottaMetadata` 与
// `assets/terracotta.json` 移植（HMCL 侧为机器生成文件），这里以 Dart 常量
// 的形式内联，避免把大段生成数据塞进 Flutter asset 打包流程。
//
// 架构说明：联机核心（Terracotta 官方发布的**未修改**二进制）由本应用下载、
// 校验、解包后以子进程方式启动，应用只通过它暴露的本地 HTTP API 交互。
// Terracotta 采用 AGPL-3.0-or-later（含 IPC 例外条款：程序通过进程间通信
// 接口与未经修改的本作品交互不会导致自身被 AGPL 覆盖），因此 UI 必须显著
// 标注其版权信息 —— 见 `instance_multiplayer_tab.dart` 的署名卡片。

import 'dart:ffi';
import 'dart:io';

/// 当前联机核心版本（对应 HMCL `terracotta.json` 的 `version_latest`）。
const String kTerracottaVersion = '0.4.2';

/// 联机核心官方仓库（版权署名与第三方下载渠道）。
const String kTerracottaHomepage = 'https://github.com/burningtnt/Terracotta';

/// 联机核心许可证。
const String kTerracottaLicense = 'AGPL-3.0-or-later';

/// 公共联机节点列表（与 HMCL `TerracottaNodeList.NODE_LIST_URL` 一致）。
const String kTerracottaNodeListUrl = 'https://terracotta.glavo.site/nodes';

/// 单个平台的联机核心包信息。
class TerracottaPackage {
  const TerracottaPackage({required this.hash, required this.files});

  /// 整包（`*-pkg.tar.gz`）的 SHA-512（十六进制小写）。
  final String hash;

  /// 包内各文件的 SHA-512（文件名 → 摘要）。
  final Map<String, String> files;
}

/// 下载渠道（标题 + 链接）。
class TerracottaLink {
  const TerracottaLink(this.title, this.url);

  final String title;
  final String url;
}

/// 平台支持情况。
enum TerracottaSupportReason {
  /// 支持。
  ok,

  /// 当前操作系统不支持（Windows 之外的未知系统等）。
  unsupportedOs,

  /// Windows 版本过低（需要 Windows 10 及以上）。
  windowsTooOld,

  /// CPU 架构不支持（32 位、非 x86_64/arm64 等）。
  unsupportedArch,

  /// Linux LoongArch64 旧世界发行版。
  loongArch64OldWorld,
}

/// 平台与包元数据。
class TerracottaMetadata {
  TerracottaMetadata._();

  /// 各平台包（classifier → 包信息）。
  static const Map<String, TerracottaPackage> packages = {
    'windows-x86_64': TerracottaPackage(
      hash:
          '6a98f524d4f00373696517306af8aa50d01d55ce4eadb27e9e4bc2f882707a0b5f20d5d4c33371d1459dcf5bf144ffed9beb414202d9ccf32b11dbbfcf19d650',
      files: {
        'VCRUNTIME140.DLL':
            '3d4b24061f72c0e957c7b04a0c4098c94c8f1afb4a7e159850b9939c7210d73398be6f27b5ab85073b4e8c999816e7804fef0f6115c39cd061f4aaeb4dcda8cf',
        'terracotta-0.4.2-windows-x86_64.exe':
            '6e98d1f2380ed22fb5a2dd4aafce6c773e9cf69100c8bb8e49e7d6983756bdb9a31f80e06bcfbe5a2742144fe806d3d687dec54d8f09d87c659341f99dd9fd80',
      },
    ),
    'windows-arm64': TerracottaPackage(
      hash:
          'fc1077247014ac0c712469498bde2ef7f6d881d5fcb7bdd5e11ebe20218fed365be19afdb8d453a79d77b729f866058522b910741767f4df947faa891434b463',
      files: {
        'VCRUNTIME140.DLL':
            '5cb5ce114614101d260f4754c09e8a0dd57e4da885ebb96b91e274326f3e1dd95ed0ade9f542f1922fad0ed025e88a1f368e791e1d01fae69718f0ec3c7b98c8',
        'terracotta-0.4.2-windows-arm64.exe':
            '30a15c5c53e5817c5a3634532172559327474741d3b2c7ef4e8a30acc6f59cdcf3570bf5f583e3cbe9e2abc8253e977c1abda1e9f36c88c4e99240da257347d0',
      },
    ),
    'macos-x86_64': TerracottaPackage(
      hash:
          'a762e4b2d6f84e899292b9e3856d009411a516d3c47f54575f843ce082f63dff2baa68ba0faa844b8b64fb12e91017386f15f5e7f975f8ee605bf8d4217cb091',
      files: {
        'terracotta-0.4.2-macos-x86_64':
            '24efb85390eff88a538ed7e503fb1488e5e622730ca30c741a0e8b4c8f4e8d4868a2f9f38da8de540aeb535af2fd1e41c7081dae9c700e8a1a03b6c540218164',
        'terracotta-0.4.2-macos-x86_64.pkg':
            '0f80437061231018ec0f860f875aba02cae9e0b36d21f2db8e99d25948806e1119f7844a4d4acca01d6124d7079718762cdebe3756b005a55632de7029fe0d24',
      },
    ),
    'macos-arm64': TerracottaPackage(
      hash:
          '09e444fea2d9fd19f3e5cb62e29055228345be163924cbd408d947646fafed1012cf48508ee6a155ede3d571e2ffaa72d09ceeb1493c8a60feb05e0699f19ba3',
      files: {
        'terracotta-0.4.2-macos-arm64':
            '8e59a9d78acd57702dc044d6f2799c6af586b075a262f7d4dbbf0876e1af8d8271e04783c24ff820b801e3b14cd0190ab8403d097f3f2d98b6d911f95ed1e972',
        'terracotta-0.4.2-macos-arm64.pkg':
            'b0b72f8883767c359f0700e958bd859dd5932c4674fbdf2a32f7de189fb9f54822d4825a754dc856416c8760338eb8ffca80b40c0a57c608fbe6ae9928888993',
      },
    ),
    'linux-x86_64': TerracottaPackage(
      hash:
          'd326ad95815d04568d485b5038e40ffc47ca54292fa0925eee6f5cea014024f901d661708aac2a743037b990882ad82b4d0b7bb03dc3b2fe720dbf0f3efe1c98',
      files: {
        'terracotta-0.4.2-linux-x86_64':
            'fac328ba8957a711b03557bb913940f22d61b76608cd203fdf51024b6f94b19f5bc91c9b8a9fa80baf6968e1e6873c1880fd4cf54a2f8e3c6cf1e6ac161f8d0c',
      },
    ),
    'linux-arm64': TerracottaPackage(
      hash:
          '57c08f48d9535e93ad547d2dfc852d267992cc164a7208b42a2da0a6cbc2f21862f610e02a746b4b67150f4dec26b86a4f96eb9bd2f58d124d5b40ba50c6d55e',
      files: {
        'terracotta-0.4.2-linux-arm64':
            'd807744c2041c98686e4b505324713badea7a0f31e8810be49ae053a63fb6dfc474ac58d678fb93eea0dd5cccff7372d9ec6135a1046f4b306cad35cd90ecacd',
      },
    ),
    'linux-loongarch64': TerracottaPackage(
      hash:
          'a19f4ad4fa1fd2f3c1c867f8743178ab0524d1634d63e122ffc080623e4f14207ecab58830fa0d888696ef28ce4cfa189e6ffbe92c6e1aa1836652617a96a801',
      files: {
        'terracotta-0.4.2-linux-loongarch64':
            '7d4896b275207def0861e544cf2afc9501c1946f1bc8bb2bad9ef4510dd915eabb63eeedff725e69565cdf5c27c146b52dd75d24115d5141909c0865f89cd7b9',
      },
    ),
    'linux-riscv64': TerracottaPackage(
      hash:
          'ef3dfcf3c64dfcaf94adc518f0184d017a32a924f67ef33ffb8128f20669cf177cd345df3be8c00225a275bd44f70657b94fb43c60afeb21238000ac7a7f1721',
      files: {
        'terracotta-0.4.2-linux-riscv64':
            'afddc55f16f5cf3103548d13f7a3238964c8899dba8eb0e1fdc9e354da65e91fa4486de4b8680a7a3d9326eacf18c1ddb6b5b1f9459908f35f77b36f769172ea',
      },
    ),
    'freebsd-x86_64': TerracottaPackage(
      hash:
          'a4d02ebbb1419f4e9265f5b24060432799151a27e0d1871690d2f3a51f40bcfd6d92c176001a15a62caa9bf31ea1b67a7b2da10e3351bfcdd36bfac1377d08d9',
      files: {
        'terracotta-0.4.2-freebsd-x86_64':
            'a50da02752cef73d21804b26eb02261568ed3053c8fef1074014d50226843810f71e6eda39a53af3bad8e173cec40826631a4c8877af460d14a307f1b0a62519',
      },
    ),
  };

  /// 下载渠道（先国内镜像，便于大陆网络；哈希校验失败会自动换下一个）。
  static const List<String> downloadUrls = [
    'https://gitee.com/burningtnt/Terracotta/releases/download/v$kTerracottaVersion/'
        'terracotta-$kTerracottaVersion-{classifier}-pkg.tar.gz',
    'https://cnb.cool/HMCL-Terracotta/Terracotta/-/releases/download/v'
        '$kTerracottaVersion/'
        'terracotta-$kTerracottaVersion-{classifier}-pkg.tar.gz',
    'https://alist.8mi.tech/d/mirror/HMCL-Terracotta/Auto/v$kTerracottaVersion/'
        'terracotta-$kTerracottaVersion-{classifier}-pkg.tar.gz',
    'https://github.com/burningtnt/Terracotta/releases/download/v'
        '$kTerracottaVersion/'
        'terracotta-$kTerracottaVersion-{classifier}-pkg.tar.gz',
  ];

  /// 手动下载渠道（用户在界面上点击打开，用于自动下载失败时兜底）。
  static const List<TerracottaLink> packageLinks = [
    TerracottaLink(
      'GitHub 发布页',
      'https://github.com/burningtnt/Terracotta/releases/tag/v$kTerracottaVersion',
    ),
    TerracottaLink(
      'Gitee 镜像',
      'https://gitee.com/burningtnt/Terracotta/releases',
    ),
  ];

  /// 当前平台的 classifier（如 `windows-x86_64`）；不支持时返回 null。
  static String? currentClassifier() {
    if (Platform.isWindows) {
      final arch = _currentArch();
      if (arch == 'x86_64') return 'windows-x86_64';
      if (arch == 'arm64') return 'windows-arm64';
      return null;
    }
    if (Platform.isMacOS) {
      final arch = _currentArch();
      if (arch == 'x86_64') return 'macos-x86_64';
      if (arch == 'arm64') return 'macos-arm64';
      return null;
    }
    if (Platform.isLinux) {
      final arch = _currentArch();
      if (arch == null) return null;
      return packages.containsKey('linux-$arch') ? 'linux-$arch' : null;
    }
    if (_isFreeBsd) {
      return _currentArch() == 'x86_64' ? 'freebsd-x86_64' : null;
    }
    return null;
  }

  /// 当前平台的支持情况（用于界面提示「为什么不支持」）。
  static TerracottaSupportReason checkSupport() {
    final osSupported =
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        _isFreeBsd;
    if (!osSupported) return TerracottaSupportReason.unsupportedOs;

    if (Platform.isWindows && !_isWindowsAtLeast10()) {
      return TerracottaSupportReason.windowsTooOld;
    }
    if (Platform.isLinux && _unameMachine() == 'loongarch64') {
      // 旧世界 ABI 的 LoongArch64 发行版跑不了官方构建。
      return TerracottaSupportReason.loongArch64OldWorld;
    }
    if (currentClassifier() == null) {
      return TerracottaSupportReason.unsupportedArch;
    }
    return TerracottaSupportReason.ok;
  }

  /// 当前平台的包信息。
  static TerracottaPackage? currentPackage() {
    final classifier = currentClassifier();
    if (classifier == null) return null;
    return packages[classifier];
  }

  /// 官方包文件名：`terracotta-<版本>-<classifier>-pkg.tar.gz`。
  static String get packageName {
    final classifier = currentClassifier();
    return 'terracotta-$kTerracottaVersion-$classifier-pkg.tar.gz';
  }

  /// 包内可执行文件名（Windows 带 `.exe`）。
  static String? get executableName {
    final classifier = currentClassifier();
    if (classifier == null) return null;
    final name = 'terracotta-$kTerracottaVersion-$classifier';
    return Platform.isWindows ? '$name.exe' : name;
  }

  /// 展开后的下载地址列表（`{classifier}` 已替换）。
  static List<String> resolveDownloadUrls() {
    final classifier = currentClassifier();
    if (classifier == null) return const [];
    return downloadUrls
        .map((u) => u.replaceAll('{classifier}', classifier))
        .toList(growable: false);
  }

  /// 由 [Abi] 推导的 CPU 架构；必要时回退到 `uname -m`。
  static String? _currentArch() {
    switch (Abi.current()) {
      case Abi.windowsX64:
      case Abi.linuxX64:
      case Abi.macosX64:
      case Abi.androidX64:
        return 'x86_64';
      case Abi.windowsArm64:
      case Abi.linuxArm64:
      case Abi.macosArm64:
      case Abi.androidArm64:
        return 'arm64';
      case Abi.linuxRiscv64:
        return 'riscv64';
      default:
        break;
    }
    // Dart 的 Abi 枚举没有 loongarch64 / 部分 Linux 架构，用 uname 兜底。
    final machine = _unameMachine();
    switch (machine) {
      case 'x86_64':
      case 'amd64':
        return 'x86_64';
      case 'aarch64':
      case 'arm64':
        return 'arm64';
      case 'loongarch64':
        return 'loongarch64';
      case 'riscv64':
        return 'riscv64';
      default:
        return null;
    }
  }

  /// 是否为 FreeBSD（dart:io 的 `Platform` 没有 isFreeBSD 便捷属性）。
  static bool get _isFreeBsd => Platform.operatingSystem == 'freebsd';

  /// `uname -m` 的输出（非 Linux 或执行失败时返回空串）。
  static String _unameMachine() {
    if (!Platform.isLinux && !_isFreeBsd) return '';
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().toLowerCase();
      }
    } catch (_) {
      // uname 不可用时忽略：上层会退回「架构不支持」。
    }
    return '';
  }

  /// Windows 是否 >= 10（解析 `Platform.operatingSystemVersion` 里的内部版本号）。
  static bool _isWindowsAtLeast10() {
    final text = Platform.operatingSystemVersion;
    // 形如 `Windows 10 Pro (10.0.19045)` 或 `Windows 11 (10.0.22631)`。
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
    if (match == null) {
      // 解析不出来时不阻断用户，交给联机核心自己判断。
      return true;
    }
    final major = int.tryParse(match.group(1)!) ?? 10;
    final build = int.tryParse(match.group(3)!) ?? 19045;
    return major >= 10 && build >= 10240;
  }
}
