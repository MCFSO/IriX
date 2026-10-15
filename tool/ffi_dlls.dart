// Rust FFI 动态库清单工具（纯 dart:io，无额外依赖）
//
// 背景：xmc_*.dll / libxmc_*.so / libxmc_*.dylib 的清单散落在 CMake、build_rust
// 脚本与两个 CI workflow 里，新增 crate 时漏改任何一处，发布包就会缺失该模块：
// v1.2.0 的 Windows 安装包只带了 3 个 xmc_*.dll（其余 7 个漏在复制列表外），
// 用户装完一打开市场就报 “Rust http_client library not found”。
//
// 本工具以 rust/Cargo.toml 的 workspace members 作为唯一事实来源，提供三条子命令
// （失败时以非零退出码结束，可直接当 CI 步骤用）：
//
//   dart tool/ffi_dlls.dart lists
//       校验各构建脚本 / workflow 是否覆盖全部 workspace 成员；
//   dart tool/ffi_dlls.dart bundle <目录> [--ext .dll] [--prefix xmc_]
//       校验构建产物（打包输入目录）里是否真的存在全部动态库；
//   dart tool/ffi_dlls.dart runtime <目录> [--platform windows|linux|macos]
//       校验产物的运行时必需文件（Flutter 引擎数据、AOT 快照、资源清单）。
//
// 新增 Rust crate 时：先在 rust/Cargo.toml 加 member，再运行 lists 找出所有待补的位置。

import 'dart:io';

const String _cargoToml = 'rust/Cargo.toml';

/// 需要与 workspace 成员保持一致的清单文件（相对仓库根目录）。
const List<String> _listFiles = <String>[
  'windows/runner/CMakeLists.txt',
  'linux/CMakeLists.txt',
  'build_rust.bat',
  'build_rust.sh',
  '.github/workflows/package.yml',
  '.github/workflows/build-and-test.yml',
  'macos/Runner.xcodeproj/project.pbxproj',
];

void main(List<String> args) {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stdout.writeln(
      '用法:\n'
      '  dart tool/ffi_dlls.dart lists\n'
      '  dart tool/ffi_dlls.dart bundle <目录> [--ext .dll] [--prefix xmc_]\n'
      '  dart tool/ffi_dlls.dart runtime <目录> [--platform windows|linux|macos]',
    );
    exit(args.isEmpty ? 64 : 0);
  }

  final root = _repoRoot();
  final crates = _readWorkspaceCrates(root);
  if (crates.isEmpty) {
    stderr.writeln('无法从 $root/$_cargoToml 解析 workspace members');
    exit(1);
  }

  switch (args.first) {
    case 'lists':
      exit(_checkLists(root, crates));
    case 'bundle':
      exit(_checkBundle(args.skip(1).toList()));
    case 'runtime':
      exit(_checkRuntime(args.skip(1).toList()));
    default:
      stderr.writeln('未知子命令: ${args.first}');
      exit(64);
  }
}

/// 仓库根目录 = 本脚本所在目录的上一级（不依赖调用时的 cwd）。
Directory _repoRoot() => File.fromUri(Platform.script).parent.parent;

/// 解析 `[workspace] members = [...]` 里的成员名，作为动态库清单的事实来源。
List<String> _readWorkspaceCrates(Directory root) {
  final file = File('${root.path}/$_cargoToml');
  if (!file.existsSync()) return const <String>[];
  final match = RegExp(
    r'^\s*members\s*=\s*\[(.*?)\]',
    multiLine: true,
    dotAll: true,
  ).firstMatch(file.readAsStringSync());
  if (match == null) return const <String>[];
  return RegExp(
    r'"([^"]+)"',
  ).allMatches(match.group(1)!).map((m) => m.group(1)!).toList();
}

/// 每个清单文件都必须提到每个 crate 对应的动态库名。
int _checkLists(Directory root, List<String> crates) {
  final problems = <String>[];
  for (final relative in _listFiles) {
    final file = File('${root.path}/$relative');
    if (!file.existsSync()) {
      problems.add('$relative: 文件不存在');
      continue;
    }
    final content = file.readAsStringSync();
    final missing = crates
        .where((crate) => !content.contains('xmc_$crate'))
        .map((crate) => 'xmc_$crate')
        .toList();
    if (missing.isNotEmpty) {
      problems.add('$relative: 缺少 ${missing.join(', ')}');
    }
  }

  if (problems.isEmpty) {
    stdout.writeln(
      'FFI 动态库清单一致：${crates.length} 个 crate（${crates.join(', ')}），'
      '已覆盖 ${_listFiles.length} 个清单文件。',
    );
    return 0;
  }
  stderr.writeln('FFI 动态库清单与 rust/Cargo.toml 不一致：');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  stderr.writeln(
    '请补齐上述文件（新增 crate 时容易漏），或运行 '
    '`dart tool/ffi_dlls.dart lists` 复查。',
  );
  return 1;
}

/// 校验构建产物目录里是否包含全部动态库（发布包直接取该目录）。
int _checkBundle(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'bundle 子命令需要目录参数，例如: bundle build/windows/x64/runner/Release --ext .dll',
    );
    return 64;
  }
  final directory = args.first;
  var ext = Platform.isWindows
      ? '.dll'
      : Platform.isMacOS
      ? '.dylib'
      : '.so';
  var prefix = Platform.isWindows ? 'xmc_' : 'libxmc_';
  for (var i = 1; i < args.length - 1; i++) {
    if (args[i] == '--ext') ext = args[i + 1];
    if (args[i] == '--prefix') prefix = args[i + 1];
  }

  final root = _repoRoot();
  final crates = _readWorkspaceCrates(root);
  final dir = Directory('${root.path}/$directory');
  if (!dir.existsSync()) {
    stderr.writeln('产物目录不存在: ${dir.path}');
    return 1;
  }
  final present = dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toSet();
  final missing = crates
      .map((crate) => '$prefix$crate$ext')
      .where((name) => !present.contains(name))
      .toList();

  if (missing.isEmpty) {
    stdout.writeln(
      '产物 FFI 动态库齐全：${dir.path} 含 ${crates.length} 个 $prefix*$ext。',
    );
    return 0;
  }
  stderr.writeln('产物缺少 FFI 动态库（${dir.path}）：');
  for (final name in missing) {
    stderr.writeln('  - $name');
  }
  stderr.writeln(
    '发布包由该目录打包，缺库会导致安装后对应功能报 “Rust xxx library not found”。'
    '请检查 windows/runner/CMakeLists.txt、linux/CMakeLists.txt 或 macOS 的 dylib 复制脚本，'
    '并确认已先编译 Rust 动态库。',
  );
  return 1;
}

/// 各平台上「缺了就一定打不开」的运行时文件（相对产物根目录）。
///
/// 判定依据：Flutter 引擎启动时依次需要 AOT 快照、ICU 数据（data/icudtl.dat）与
/// 资源清单（data/flutter_assets/AssetManifest.*）。缺失时 Windows 侧报
/// “Can't load AOT data ... Unable to start engine without AOT data.” /
/// “Failed to create view controller.”，双击无任何窗口出现；这类失败在构建阶段
/// 不会报错，只有真正启动才暴露。
///
/// AOT 快照位置因平台而异（均取自 Flutter 3.44 flutter_tools 源码）：
///   windows -> data/app.so
///   linux   -> lib/libapp.so（linux.dart: outputs 为 lib/libapp.so；
///              Linux 产物没有 data/app.so）
///   macOS   -> App.framework/Versions/A/App（release；kernel_blob.bin 仅 debug
///              构建生成，对 release 产物断言 kernel_blob.bin 属误报）
/// macOS 的路径以 `.app` 包根为基准（workflow 传入的是 lrix.app 本身）。
List<String> _requiredRuntimeFiles(String platform) {
  // 资源清单文件名随 Flutter 版本变化：3.44 起为 AssetManifest.bin（旧版为 .json），
  // 任一存在即可。
  const manifestCandidates = <String>[
    'data/flutter_assets/AssetManifest.bin',
    'data/flutter_assets/AssetManifest.json',
  ];
  // macOS 的引擎数据位于 Contents/Frameworks/App.framework/Resources/。
  const macManifestCandidates = <String>[
    'Contents/Frameworks/App.framework/Resources/flutter_assets/AssetManifest.bin',
    'Contents/Frameworks/App.framework/Resources/flutter_assets/AssetManifest.json',
  ];
  return switch (platform) {
    'windows' => <String>[
      'data/app.so',
      'data/icudtl.dat',
      'flutter_windows.dll',
      ...manifestCandidates,
    ],
    'linux' => <String>[
      'lib/libapp.so',
      'data/icudtl.dat',
      'lib/libflutter_linux_gtk.so',
      ...manifestCandidates,
    ],
    'macos' => <String>[
      'Contents/Frameworks/App.framework/Versions/A/App',
      ...macManifestCandidates,
    ],
    _ => throw ArgumentError('不支持的平台: $platform'),
  };
}

/// 校验产物目录里的运行时必需文件是否齐全（发布包直接取该目录）。
int _checkRuntime(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'runtime 子命令需要目录参数，例如: '
      'runtime build/windows/x64/runner/Release --platform windows',
    );
    return 64;
  }
  final directory = args.first;
  var platform = Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : 'linux';
  for (var i = 1; i < args.length - 1; i++) {
    if (args[i] == '--platform') platform = args[i + 1];
  }

  final dir = Directory('${_repoRoot().path}/$directory');
  if (!dir.existsSync()) {
    stderr.writeln('产物目录不存在: ${dir.path}');
    return 1;
  }

  final required = _requiredRuntimeFiles(platform);

  // 资源清单是一组候选项（.bin / .json，且 Windows/Linux 与 macOS 路径不同），
  // 只要组内有一个存在即算通过：用 RegExp 而非固定前缀匹配，避免漏掉 macOS。
  final manifestPattern = RegExp(r'/AssetManifest\.(bin|json)$');
  final manifestCandidates = required
      .where((p) => manifestPattern.hasMatch(p))
      .toList();
  final manifestPresent = manifestCandidates.any(
    (p) => File('${dir.path}/$p').existsSync(),
  );

  final missing = <String>[];
  for (final relative in required) {
    if (manifestPattern.hasMatch(relative)) {
      // 组内候选项只报一次，避免同一问题刷屏。
      if (!manifestPresent && relative == manifestCandidates.first) {
        missing.add(
          relative.replaceFirst(
            RegExp(r'AssetManifest\.(bin|json)$'),
            'AssetManifest.{bin,json}',
          ),
        );
      }
      continue;
    }
    if (!File('${dir.path}/$relative').existsSync()) missing.add(relative);
  }

  if (missing.isEmpty) {
    stdout.writeln('产物运行时文件齐全：${dir.path}（平台 $platform）。');
    return 0;
  }

  stderr.writeln('产物缺少运行时必需文件（${dir.path}，平台 $platform）：');
  for (final name in missing.toSet()) {
    stderr.writeln('  - $name');
  }
  stderr.writeln(
    '缺少 AOT 快照（Windows 为 data/app.so，Linux 为 lib/libapp.so，'
    'macOS 为 App.framework/Versions/A/App）或引擎数据时应用无法启动：'
    'Flutter 引擎报 "Can\'t load AOT data ... Unable to start engine without '
    'AOT data."，双击后不会出现任何窗口。该文件由 `flutter build <平台> --release` '
    '生成，上传 artifact 时务必包含整个 Release/bundle 目录，不要只挑可执行文件与动态库。',
  );
  return 1;
}
