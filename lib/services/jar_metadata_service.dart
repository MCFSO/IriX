// JAR 元数据读取服务
// 从插件 / Mod 的 .jar（ZIP）中解析名称、描述与图标，
// 兼容 Fabric (fabric.mod.json)、Forge/NeoForge (META-INF/mods.toml)、
// Bukkit/Paper (plugin.yml / paper-plugin.yml)。

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'rust_lib.dart';

/// JAR 元数据。
class JarMetadata {
  const JarMetadata({
    this.name,
    this.description,
    this.iconBytes,
    this.kind = JarKind.unknown,
  });

  /// 展示名称（取自元数据，无法读取时为 null）。
  final String? name;

  /// 简短描述。
  final String? description;

  /// 图标 PNG 字节（无法读取时为 null）。
  final Uint8List? iconBytes;

  /// JAR 类型（插件 / Fabric / Forge / 未知）。
  final JarKind kind;

  /// 从 Rust 返回的 JSON 构造（字段名与 `rust/file_ops/src/jar_meta.rs` 对齐）。
  factory JarMetadata.fromJson(Map<String, dynamic> json) {
    final icon = json['icon_base64'] as String?;
    return JarMetadata(
      name: json['name'] as String?,
      description: json['description'] as String?,
      iconBytes: icon == null || icon.isEmpty ? null : base64Decode(icon),
      kind: switch (json['kind'] as String?) {
        'fabric' => JarKind.fabric,
        'forge' => JarKind.forge,
        'plugin' => JarKind.plugin,
        _ => JarKind.unknown,
      },
    );
  }
}

/// JAR 类型。
enum JarKind {
  /// Bukkit/Spigot/Paper 插件。
  plugin,

  /// Fabric Mod。
  fabric,

  /// Forge / NeoForge Mod。
  forge,

  /// 未知（无法识别）。
  unknown,
}

/// 读取 JAR 元数据的服务。
///
/// 通过解压 .jar（ZIP）文件读取其中的描述文件，
/// 提取名称、描述与图标。所有方法均不抛出异常，
/// 解析失败时返回尽可能完整的结果。
class JarMetadataService {
  JarMetadataService._();

  /// 读取指定 jar 文件的元数据。
  static Future<JarMetadata> read(String jarPath) async {
    try {
      final bytes = await File(jarPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      return _parse(archive);
    } catch (_) {
      return const JarMetadata();
    }
  }

  /// 同步读取（用于已知已读入内存的场景）。
  static JarMetadata readSync(String jarPath) {
    try {
      final bytes = File(jarPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      return _parse(archive);
    } catch (_) {
      return const JarMetadata();
    }
  }

  /// 批量解析（Rust 实现，跑在后台 isolate）。
  ///
  /// 解压 jar 与解析描述文件都是 CPU 密集操作：Dart 的 `ZipDecoder` 是同步的，
  /// 在 UI isolate 上处理上百个 jar 会直接卡住帧。现在由 Rust
  /// （`rust/file_ops/src/jar_meta.rs` 的 `scan_jar_meta`）完成，Dart 只在
  /// 后台 isolate 里发起一次 FFI 调用，UI 线程全程不被占用。
  ///
  /// 返回顺序与 [jarPaths] 一一对应；Rust 不可用时回退到 Dart 解析
  /// （同样在后台 isolate，只是慢一些）。
  static Future<List<JarMetadata>> readAllInBackground(
    List<String> jarPaths,
  ) async {
    if (jarPaths.isEmpty) return const <JarMetadata>[];
    try {
      return await Isolate.run(() => _readAllViaRust(jarPaths));
    } catch (_) {
      try {
        return await Isolate.run(
          () => <JarMetadata>[for (final path in jarPaths) readSync(path)],
        );
      } catch (_) {
        return <JarMetadata>[for (final _ in jarPaths) const JarMetadata()];
      }
    }
  }

  /// 在后台 isolate 内调用 Rust 批量扫描。
  static List<JarMetadata> _readAllViaRust(List<String> jarPaths) {
    final lib = openRustLibrary('file_ops');
    final scan = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('scan_jar_meta');

    final input = jsonEncode(jarPaths).toNativeUtf8();
    Pointer<Utf8> output = nullptr;
    try {
      output = scan(input);
      if (output == nullptr) {
        throw StateError('scan_jar_meta 返回空指针');
      }
      final decoded = jsonDecode(output.toDartString()) as List<dynamic>;
      return [
        for (final item in decoded)
          JarMetadata.fromJson(item as Map<String, dynamic>),
      ];
    } finally {
      if (output != nullptr) freeRustString(lib, output);
      calloc.free(input);
    }
  }

  static JarMetadata _parse(Archive archive) {
    // Fabric：fabric.mod.json
    final fabricFile = archive.findFile('fabric.mod.json');
    if (fabricFile != null) {
      return _parseFabric(archive, fabricFile);
    }
    // Forge/NeoForge：META-INF/mods.toml
    final tomlFile = archive.findFile('META-INF/mods.toml');
    if (tomlFile != null) {
      return _parseForge(archive, tomlFile);
    }
    // Paper：paper-plugin.yml（优先）
    final paperFile = archive.findFile('paper-plugin.yml');
    if (paperFile != null) {
      return _parsePluginYaml(paperFile);
    }
    // Bukkit/Spigot：plugin.yml
    final pluginFile = archive.findFile('plugin.yml');
    if (pluginFile != null) {
      return _parsePluginYaml(pluginFile);
    }
    return const JarMetadata();
  }

  /// 解析 fabric.mod.json。
  static JarMetadata _parseFabric(Archive archive, ArchiveFile file) {
    try {
      final json = jsonDecode(_readAsString(file)) as Map<String, dynamic>;
      final name = json['name'] as String?;
      final description = json['description'] as String?;
      // icon 可能是字符串或 {size: path} 映射
      final iconEntry = json['icon'];
      String? iconPath;
      if (iconEntry is String) {
        iconPath = iconEntry;
      } else if (iconEntry is Map) {
        // 取最大尺寸的图标
        final sizes =
            iconEntry.keys.map((k) => int.tryParse(k.toString()) ?? 0).toList()
              ..sort();
        if (sizes.isNotEmpty) {
          iconPath = iconEntry[sizes.last.toString()] as String?;
        }
      }
      final iconBytes = iconPath != null ? _readIcon(archive, iconPath) : null;
      return JarMetadata(
        name: name,
        description: description,
        iconBytes: iconBytes,
        kind: JarKind.fabric,
      );
    } catch (_) {
      return const JarMetadata(kind: JarKind.fabric);
    }
  }

  /// 解析 META-INF/mods.toml（简易解析，不依赖 toml 包）。
  static JarMetadata _parseForge(Archive archive, ArchiveFile file) {
    try {
      final content = _readAsString(file);
      // mods.toml 为 TOML 格式，这里用正则提取关键字段。
      // [[mods]] 块中含 name=、description=、logoFile=。
      String? name = _tomlValue(content, 'name');
      String? description = _tomlValue(content, 'description');
      String? logoFile = _tomlValue(content, 'logoFile');
      // logoFile 路径相对于 jar 根目录（可能带前导 ./）。
      final iconPath = logoFile?.replaceAll(RegExp(r'^\./'), '');
      final iconBytes = iconPath != null ? _readIcon(archive, iconPath) : null;
      return JarMetadata(
        name: name,
        description: description,
        iconBytes: iconBytes,
        kind: JarKind.forge,
      );
    } catch (_) {
      return const JarMetadata(kind: JarKind.forge);
    }
  }

  /// 解析 plugin.yml / paper-plugin.yml。
  static JarMetadata _parsePluginYaml(ArchiveFile file) {
    try {
      final doc = loadYaml(_readAsString(file));
      if (doc is! Map) {
        return JarMetadata(kind: JarKind.plugin);
      }
      final name = doc['name']?.toString();
      final description = doc['description']?.toString();
      // 插件一般无图标，paper-plugin.yml 可能有 website 等，但不作图标。
      return JarMetadata(
        name: name,
        description: description,
        kind: JarKind.plugin,
      );
    } catch (_) {
      return const JarMetadata(kind: JarKind.plugin);
    }
  }

  /// 从 TOML 文本中提取简单 `key = "value"` 的值。
  static String? _tomlValue(String content, String key) {
    final regex = RegExp(
      r'^\s*' + RegExp.escape(key) + r'\s*=\s*"(.*)"\s*$',
      multiLine: true,
    );
    final match = regex.firstMatch(content);
    return match?.group(1);
  }

  /// 读取归档中的图标文件字节。
  static Uint8List? _readIcon(Archive archive, String path) {
    // 尝试精确匹配，再尝试大小写不敏感匹配。
    var file = archive.findFile(path);
    if (file == null) {
      final lower = path.toLowerCase();
      for (final f in archive) {
        if (f.name.toLowerCase() == lower) {
          file = f;
          break;
        }
      }
    }
    if (file == null) return null;
    return file.content;
  }

  /// 将归档文件内容转为字符串。
  static String _readAsString(ArchiveFile file) {
    return utf8.decode(file.content, allowMalformed: true);
  }

  /// 判断路径是否为 jar 文件。
  static bool isJar(String path) => p.extension(path).toLowerCase() == '.jar';
}
