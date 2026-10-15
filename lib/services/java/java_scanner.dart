// Java 候选路径扫描（移植自 HMCL JavaManager.Searcher）
//
// HMCL 的搜索来源（逐一对应实现）：
//   1. IriX 受管仓库（AppPaths.javaRoot()）        ⇐ REPOSITORY / LOCAL_REPOSITORY
//   2. Windows 注册表 JavaSoft\JDK|JRE              ⇐ queryJavaInRegistryKey
//   3. Program Files 下的已知厂商目录                ⇐ searchJavaInProgramFiles
//         Java / BellSoft / AdoptOpenJDK / Zulu / Microsoft /
//         Eclipse Foundation / Semeru
//   4. Linux /usr/lib/jvm、/usr/java、SDKMAN!        ⇐ searchAllJavaInDirectory
//   5. macOS /Library/Java/JavaVirtualMachines 等    ⇐ searchJavaInMacJavaVirtualMachines
//   6. Mojang 官方启动器的 runtime 目录              ⇐ searchAllOfficialJava
//   7. 环境变量 PATH                                  ⇐ tryAddJavaExecutable
//   8. HMCL_JRES 环境变量（IriX 沿用同名变量）        ⇐ getenv("HMCL_JRES")
//   9. 用户主目录 ~/.jdks                            ⇐ searchAllJavaInDirectory
//  10. settings 中用户手动添加的路径                  ⇐ userSettings().getUserJava()
//
// 与 HMCL 一致，被「禁用」的路径会被跳过（存于 JavaSettings）。

import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';

/// 一个待探测的候选 java 可执行文件。
typedef JavaCandidate = ({String path, bool isManaged});

/// Java 候选可执行文件扫描器。
class JavaScanner {
  JavaScanner._();

  static final JavaScanner instance = JavaScanner._();

  /// Windows 下 Program Files 中的已知厂商目录（HMCL KNOWN_VENDOR_DIRECTORIES）。
  static const _knownVendorDirectories = [
    'Java',
    'BellSoft',
    'AdoptOpenJDK',
    'Zulu',
    'Microsoft',
    'Eclipse Foundation',
    'Semeru',
    'Eclipse Adoptium',
    'Amazon Corretto',
  ];

  /// Java 可执行文件名。
  String get _javaExe => Platform.isWindows ? 'java.exe' : 'java';

  /// 扫描全部候选可执行文件（去重，不探测）。
  ///
  /// [extraPaths] 为 settings 中用户手动添加的路径（可能是 java 可执行文件、
  /// java home 目录或 JDK 根目录）；[disabled] 为需要跳过的可执行文件路径。
  Future<List<JavaCandidate>> scan({
    Iterable<String> extraPaths = const [],
    Set<String> disabled = const {},
  }) async {
    final Map<String, bool> found = {}; // path → isManaged

    void add(String? path, {bool isManaged = false}) {
      if (path == null || path.isEmpty) return;
      final norm = p.normalize(p.absolute(path));
      if (disabled.contains(norm)) return;
      // 受管标记一旦为 true 不再被覆盖。
      if (found[norm] == true) return;
      found[norm] = isManaged;
    }

    // 1. IriX 受管仓库：<dataRoot>/java/jdk-<feature>/bin/java
    await _scanManagedRepository(add);

    // 2-5. 平台特定的系统安装位置。
    if (Platform.isWindows) {
      await _scanWindowsRegistry(add);
      _scanWindowsProgramFiles(add);
      _scanMojangRuntimeWindows(add);
    } else if (Platform.isLinux) {
      for (final dir in const [
        '/usr/java',
        '/usr/lib/jvm',
        '/usr/lib32/jvm',
        '/usr/lib64/jvm',
      ]) {
        _scanJavaHomeChildren(dir, add);
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        _scanJavaHomeChildren(
          p.join(home, '.sdkman', 'candidates', 'java'),
          add,
        );
      }
      final home2 = Platform.environment['HOME'];
      if (home2 != null && home2.isNotEmpty) {
        _scanMojangRuntimeUnix(p.join(home2, '.minecraft', 'runtime'), add);
      }
    } else if (Platform.isMacOS) {
      for (final dir in const [
        '/Library/Java/JavaVirtualMachines',
        '/System/Library/Java/JavaVirtualMachines',
      ]) {
        _scanMacVirtualMachines(dir, add);
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        _scanMacVirtualMachines(
          p.join(home, 'Library', 'Java', 'JavaVirtualMachines'),
          add,
        );
        _scanMojangRuntimeUnix(
          p.join(
            home,
            'Library',
            'Application Support',
            'minecraft',
            'runtime',
          ),
          add,
        );
      }
      // Homebrew
      add('/opt/homebrew/opt/java/bin/java');
      _scanJavaHomeChildren('/opt/homebrew/Cellar/openjdk', add);
    }

    // 7. PATH 中的 java（跳过 Windows 上 Oracle 的 Common Files 占位目录）。
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      if (Platform.isWindows &&
          dir.toLowerCase().contains(r'\common files\oracle\java\')) {
        continue;
      }
      add(p.join(dir, _javaExe));
    }

    // 8. HMCL_JRES / IRIX_JRES 环境变量（多个 java home，用路径分隔符分隔）。
    for (final varName in const ['HMCL_JRES', 'IRIX_JRES']) {
      final value = Platform.environment[varName];
      if (value == null || value.isEmpty) continue;
      for (final home in value.split(Platform.isWindows ? ';' : ':')) {
        if (home.trim().isEmpty) continue;
        add(_executableOf(home.trim()));
      }
    }

    // 9. ~/.jdks
    final userHome =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userHome != null && userHome.isNotEmpty) {
      _scanJavaHomeChildren(p.join(userHome, '.jdks'), add);
    }

    // 10. 用户手动添加的路径。
    for (final raw in extraPaths) {
      if (raw.trim().isEmpty) continue;
      add(_executableOf(raw.trim()));
    }

    final candidates = found.entries
        .map((e) => (path: e.key, isManaged: e.value))
        .toList();
    return candidates;
  }

  /// 把用户给出的路径归一化为 java 可执行文件路径。
  ///
  /// 支持三种输入：java 可执行文件本身、JDK 根目录（含 bin/）、bin 目录。
  String _executableOf(String path) {
    final norm = p.normalize(p.absolute(path));
    if (p.basename(norm).toLowerCase() == _javaExe.toLowerCase()) return norm;
    if (p.basename(norm).toLowerCase() == 'bin') {
      return p.join(norm, _javaExe);
    }
    return p.join(norm, 'bin', _javaExe);
  }

  /// 扫描 IriX 受管 Java 仓库（`<dataRoot>/java/*/bin/java`）。
  Future<void> _scanManagedRepository(
    void Function(String?, {bool isManaged}) add,
  ) async {
    try {
      final root = await AppPaths.instance.javaRoot();
      final dir = Directory(root);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        add(p.join(entity.path, 'bin', _javaExe), isManaged: true);
      }
    } catch (_) {
      // 数据目录尚未初始化等场景直接跳过。
    }
  }

  /// 扫描某目录下的每个子目录并视为 java home。
  void _scanJavaHomeChildren(
    String dirPath,
    void Function(String?, {bool isManaged}) add,
  ) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        add(p.join(entity.path, 'bin', _javaExe));
      }
    } catch (_) {}
  }

  /// macOS：`<dir>/<name>/Contents/Home/bin/java`。
  void _scanMacVirtualMachines(
    String dirPath,
    void Function(String?, {bool isManaged}) add,
  ) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        final home = p.join(entity.path, 'Contents', 'Home');
        if (Directory(home).existsSync()) {
          add(p.join(home, 'bin', _javaExe));
        }
      }
    } catch (_) {}
  }

  /// Windows Program Files 下的厂商目录。
  void _scanWindowsProgramFiles(void Function(String?, {bool isManaged}) add) {
    final env = Platform.environment;
    final roots = <String>{
      if ((env['ProgramFiles'] ?? '').isNotEmpty) env['ProgramFiles']!,
      if ((env['ProgramFiles(x86)'] ?? '').isNotEmpty)
        env['ProgramFiles(x86)']!,
      r'C:\Program Files',
      r'C:\Program Files (x86)',
    };
    for (final root in roots) {
      for (final vendor in _knownVendorDirectories) {
        _scanJavaHomeChildren(p.join(root, vendor), add);
        // 部分厂商路径为 <vendor>/jdk-<ver>/bin/java，多下探一层。
        _scanNestedJavaHomes(p.join(root, vendor), add);
      }
      // 部分安装器直接装在 Program Files\Java\jdk-17 一级。
      _scanJavaHomeChildren(p.join(root, 'Java'), add);
    }
  }

  /// 对 `<base>/<sub>/<jdk>/bin/java` 形式再下探一层。
  void _scanNestedJavaHomes(
    String basePath,
    void Function(String?, {bool isManaged}) add,
  ) {
    final dir = Directory(basePath);
    if (!dir.existsSync()) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        // 该子目录本身是 java home 时已由 _scanJavaHomeChildren 覆盖。
        if (Directory(p.join(entity.path, 'bin')).existsSync()) continue;
        _scanJavaHomeChildren(entity.path, add);
      }
    } catch (_) {}
  }

  /// Windows 注册表查询（HMCL queryJavaInRegistryKey）。
  ///
  /// Dart 无原生注册表 API，用 `reg query` 代替。
  Future<void> _scanWindowsRegistry(
    void Function(String?, {bool isManaged}) add,
  ) async {
    const keys = [
      r'HKLM\SOFTWARE\JavaSoft\Java Runtime Environment',
      r'HKLM\SOFTWARE\JavaSoft\Java Development Kit',
      r'HKLM\SOFTWARE\JavaSoft\JRE',
      r'HKLM\SOFTWARE\JavaSoft\JDK',
    ];

    for (final key in keys) {
      try {
        final result = await Process.run('reg', [
          'query',
          key,
        ]).timeout(const Duration(seconds: 8));
        if (result.exitCode != 0) continue;
        final output = result.stdout.toString();

        // 枚举子键（形如 HKLM\SOFTWARE\JavaSoft\JDK\17.0.9），
        // 再取该子键的 JavaHome 值。
        final subKeyRegex = RegExp(
          '^(${RegExp.escape(key)}[^\\r\\n]*)\$',
          multiLine: true,
        );
        for (final m in subKeyRegex.allMatches(output)) {
          final subKey = m.group(1)?.trim();
          if (subKey == null || subKey == key) continue;
          final home = await _queryRegistryValue(subKey, 'JavaHome');
          if (home != null) add(_executableOf(home));
        }
      } catch (_) {
        // reg.exe 不可用（非 Windows 或权限受限）时跳过。
      }
    }
  }

  /// 读取注册表某个字符串值。
  Future<String?> _queryRegistryValue(String key, String name) async {
    try {
      final result = await Process.run('reg', [
        'query',
        key,
        '/v',
        name,
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      // 输出：`    JavaHome    REG_SZ    C:\Program Files\Java\jdk-17`
      final m = RegExp(
        '$name\\s+REG_SZ\\s+(.+)',
      ).firstMatch(result.stdout.toString());
      final value = m?.group(1)?.trim();
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  /// Windows：Mojang 官方启动器 runtime 目录。
  void _scanMojangRuntimeWindows(void Function(String?, {bool isManaged}) add) {
    final localAppData = Platform.environment['localappdata'];
    if (localAppData != null && localAppData.isNotEmpty) {
      _scanMojangRuntimeUnix(
        p.join(
          localAppData,
          'Packages',
          'Microsoft.4297127D64EC6_8wekyb3d8bbwe',
          'LocalCache',
          'Local',
          'runtime',
        ),
        add,
      );
    }
    final pf86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    _scanMojangRuntimeUnix(p.join(pf86, 'Minecraft Launcher', 'runtime'), add);
  }

  /// Mojang runtime 目录形如：
  /// `<dir>/<component>/<platform>/<component>/bin/java`
  /// （macOS 为 `<component>/<platform>/<component>/jre.bundle/Contents/Home`）。
  void _scanMojangRuntimeUnix(
    String dirPath,
    void Function(String?, {bool isManaged}) add,
  ) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    final platformKey = _mojangPlatform();
    try {
      for (final component in dir.listSync()) {
        if (component is! Directory) continue;
        final componentName = p.basename(component.path);

        final platformDirs = <String>[
          if (platformKey != null) p.join(component.path, platformKey),
          // 平台键不匹配时仍尝试枚举实际子目录。
          ..._subDirs(component.path),
        ];

        for (final platformDir in platformDirs) {
          final jdkRoot = p.join(platformDir, componentName);
          if (!Directory(jdkRoot).existsSync()) continue;

          if (Platform.isMacOS) {
            final macHome = p.join(jdkRoot, 'jre.bundle', 'Contents', 'Home');
            add(
              Directory(macHome).existsSync()
                  ? p.join(macHome, 'bin', _javaExe)
                  : null,
            );
          } else {
            add(p.join(jdkRoot, 'bin', _javaExe));
          }
        }
      }
    } catch (_) {}
  }

  List<String> _subDirs(String path) {
    try {
      return Directory(
        path,
      ).listSync().whereType<Directory>().map((d) => d.path).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Mojang 平台键（HMCL getMojangJavaPlatform）。
  String? _mojangPlatform() {
    final arch = JavaArchitectureShim.current;
    if (Platform.isWindows) {
      return switch (arch) {
        'x86' => 'windows-x86',
        'x86_64' => 'windows-x64',
        'arm64' => 'windows-arm64',
        _ => null,
      };
    }
    if (Platform.isLinux) {
      return switch (arch) {
        'x86' => 'linux-i386',
        'x86_64' => 'linux',
        _ => null,
      };
    }
    if (Platform.isMacOS) {
      return switch (arch) {
        'x86_64' => 'mac-os',
        'arm64' => 'mac-os-arm64',
        _ => null,
      };
    }
    return null;
  }
}

/// 轻量架构判断（避免 models 与 services 循环依赖的额外导入开销）。
class JavaArchitectureShim {
  JavaArchitectureShim._();

  static String get current {
    final arch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
        .toLowerCase();
    if (arch.contains('arm64') || arch.contains('aarch64')) return 'arm64';
    if (arch.contains('x86') && !arch.contains('64')) return 'x86';
    if (arch.isNotEmpty) return 'x86_64';
    return Platform.isWindows ? 'x86_64' : 'x86_64';
  }
}
