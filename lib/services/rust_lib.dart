// Rust FFI 动态库通用加载器
//
// 集中存放各 *_ffi.dart 中重复的：
// - 跨平台动态库名拼接（Platform.isWindows ? *.dll : macos *.dylib : linux *.so）
// - 多路径搜索（cwd / lib / 平台 runner 目录 / 从 exe 目录向上逐级查找）
// - FreeString / GetLastError 的 typedef 与统一释放辅助
//
// 仅依赖 dart:ffi / dart:io / package:ffi / package:path，无任何项目业务耦合，
// 可原样搬到任意 Flutter + Rust FFI 项目复用。

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Rust 侧统一导出的 `free_string` 用于释放 Rust 分配并返回给 Dart 的 `*mut c_char`。
typedef FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Rust 侧统一导出的 `get_last_error` 返回最近一次错误的文本（Rust 分配）。
typedef GetLastErrorC = Pointer<Utf8> Function();
typedef GetLastErrorDart = Pointer<Utf8> Function();

/// 根据平台返回 Rust 动态库文件名。
///
/// [baseName] 为不带前缀/后缀的核心名，例如 `http_client` 对应
/// `xmc_http_client.dll` / `libxmc_http_client.dylib` / `libxmc_http_client.so`。
String rustLibraryName(String baseName) => Platform.isWindows
    ? 'xmc_$baseName.dll'
    : Platform.isMacOS
        ? 'libxmc_$baseName.dylib'
        : 'libxmc_$baseName.so';

/// 打开指定 Rust 动态库，依次尝试多个常见路径。
///
/// [baseName] 见 [rustLibraryName]。[notFoundHint] 用于丰富加载失败时的提示
/// （例如告知用户先编译并复制动态库）。抛 [UnsupportedError] 时附带所有尝试过的路径。
DynamicLibrary openRustLibrary(String baseName, {String? notFoundHint}) {
  final libName = rustLibraryName(baseName);
  final attempts = <String>[];

  for (final libPath in _possibleLibraryPaths(libName)) {
    try {
      final file = File(libPath);
      if (file.existsSync()) {
        return DynamicLibrary.open(libPath);
      }
      attempts.add('$libPath (文件不存在)');
    } catch (e) {
      attempts.add('$libPath (加载失败: $e)');
    }
  }

  try {
    return DynamicLibrary.open(libName);
  } catch (e) {
    attempts.add('系统搜索路径 "$libName" (加载失败: $e)');
  }

  final hint = notFoundHint == null ? '' : '$notFoundHint\n';
  throw UnsupportedError(
    'Rust $baseName library not found.\n'
    '$hint'
    'cwd: ${Directory.current.path}\n'
    'exe: ${Platform.resolvedExecutable}\n'
    '尝试的路径:\n${attempts.map((a) => '  - $a').join('\n')}',
  );
}

/// 计算可能的动态库路径列表：cwd / cwd/lib / 平台 runner 目录，
/// 以及从 exe 目录向上逐级查找（含 lib 与平台 runner / Frameworks 子目录）。
List<String> _possibleLibraryPaths(String libName) {
  final paths = <String>[];

  final cwd = Directory.current.path;
  paths.add(p.join(cwd, libName));
  paths.add(p.join(cwd, 'lib', libName));
  if (Platform.isWindows) {
    paths.add(p.join(cwd, 'windows', 'runner', libName));
  } else if (Platform.isMacOS) {
    paths.add(p.join(cwd, 'macos', libName));
  } else {
    paths.add(p.join(cwd, 'linux', libName));
  }

  // flutter run 时 exe 位于 build/.../runner/Debug 等子目录，需向上找项目根。
  try {
    final exePath = Platform.resolvedExecutable;
    var dir = p.dirname(exePath);
    for (var i = 0; i < 10; i++) {
      paths.add(p.join(dir, libName));
      paths.add(p.join(dir, 'lib', libName));
      if (Platform.isWindows) {
        paths.add(p.join(dir, 'windows', 'runner', libName));
      } else if (Platform.isMacOS) {
        paths.add(p.join(dir, 'macos', libName));
        paths.add(p.join(dir, '..', 'Frameworks', libName));
      } else {
        paths.add(p.join(dir, 'linux', libName));
      }
      final parent = p.dirname(dir);
      if (parent == dir) break; // 到达文件系统根
      dir = parent;
    }
  } catch (_) {
    // 忽略
  }

  return paths;
}

/// 在 [lib] 中查找 Rust 的字符串释放函数并释放 [ptr]（由 Rust 分配的内存）。
///
/// 多数 crate 导出 `free_string`；orchestrator 等少数 crate 用独立命名
/// （如 `orchestrator_free_string`），可通过 [symbolName] 指定。
/// [ptr] 为 nullptr 时静默跳过；[lib] 句柄获取失败时忽略（指针泄漏可接受）。
void freeRustString(
  DynamicLibrary lib,
  Pointer<Utf8> ptr, {
  String symbolName = 'free_string',
}) {
  if (ptr == nullptr) return;
  try {
    final freeString = lib.lookupFunction<FreeStringC, FreeStringDart>(
      symbolName,
    );
    freeString(ptr);
  } catch (_) {
    // 库句柄无法再次打开时忽略（调试场景可接受）
  }
}

/// 在 [lib] 中查找 Rust 的 `get_last_error` 并读取最近错误文本，随后释放该指针。
///
/// 无错误（空指针）时返回 null；[lib] 句柄获取失败时返回 null。
String? readLastError(DynamicLibrary lib) {
  try {
    final getLastError = lib.lookupFunction<GetLastErrorC, GetLastErrorDart>(
      'get_last_error',
    );
    final ptr = getLastError();
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      freeRustString(lib, ptr);
    }
  } catch (_) {
    return null;
  }
}
