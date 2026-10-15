// 受管 Java 仓库（移植自 HMCL HMCLJavaRepository + JavaManifest）
//
// HMCL 的受管仓库布局：<root>/<platform>/<name>/ 与 <name>.json 清单并列，
// 清单记录 os.name / os.arch / java.version / java.vendor 及文件清单，
// 卸载时按清单精确清理。
//
// IriX 沿用同样的思路但保持与既有 JdkInstaller 兼容的目录形式：
//   <dataRoot>/java/jdk-<feature>/         ← JDK 安装根（bin/java 在此）
//   <dataRoot>/java/jdk-<feature>.json     ← 对应清单
// 这样既满足 `AppPaths._remapJdkSettings` 的既有约定，也保留了 HMCL
// 「有 .json 即视为受管安装」的语义。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/java_runtime.dart';
import '../app_paths.dart';

/// 受管 JDK 清单（对应 HMCL `JavaManifest`）。
class JavaManifest {
  const JavaManifest({required this.info, this.name, this.update, this.files});

  /// Java 安装信息（os.name / os.arch / java.version / java.vendor）。
  final JavaInfo info;

  /// 安装名（目录名，如 `jdk-17`）。
  final String? name;

  /// 更新元数据（provider / component 等）。
  final Map<String, dynamic>? update;

  /// 文件清单（相对路径 → 描述），HMCL 用于精确卸载。
  final Map<String, dynamic>? files;

  Map<String, dynamic> toJson() => {
    'name': name,
    'os.name': info.osName,
    'os.arch': info.architecture.checkedName,
    'java.version': info.version,
    'java.vendor': info.vendor,
    if (update != null) 'update': update,
    if (files != null) 'files': files,
  };

  /// 解析清单；关键字段缺失返回 null（对应 HMCL 反序列化抛 JsonParseException）。
  static JavaManifest? fromJson(Map<String, dynamic> json) {
    final version = json['java.version']?.toString();
    if (version == null || version.isEmpty) return null;
    final archName = json['os.arch']?.toString();
    if (archName == null || archName.isEmpty) return null;

    return JavaManifest(
      info: JavaInfo.fromJson(json),
      name: json['name']?.toString(),
      update: json['update'] is Map
          ? Map<String, dynamic>.from(json['update'] as Map)
          : null,
      files: json['files'] is Map
          ? Map<String, dynamic>.from(json['files'] as Map)
          : null,
    );
  }

  static JavaManifest? tryParse(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('Failed to parse java manifest: $e');
      return null;
    }
  }
}

/// 受管 Java 仓库。
class JavaRepository {
  JavaRepository._();

  static final JavaRepository instance = JavaRepository._();

  /// 仓库根目录（`<dataRoot>/java`）。
  Future<String> root() => AppPaths.instance.javaRoot();

  /// 安装名 → 安装目录。
  Future<String> javaDir(String name) async => p.join(await root(), name);

  /// 安装名 → 清单文件路径。
  Future<String> manifestFile(String name) async =>
      p.join(await root(), '$name.json');

  /// 是否已安装（存在清单文件即视为受管安装，对齐 HMCL isInstalled）。
  Future<bool> isInstalled(String name) async =>
      File(await manifestFile(name)).existsSync();

  /// java 可执行文件路径（未安装返回 null）。
  Future<String?> javaExecutable(String name) async {
    final exe = p.join(
      await javaDir(name),
      'bin',
      Platform.isWindows ? 'java.exe' : 'java',
    );
    return File(exe).existsSync() ? exe : null;
  }

  /// 列出仓库内全部受管安装（目录 + 清单成对存在）。
  Future<List<({String name, String executable, JavaManifest? manifest})>>
  listInstalled() async {
    final result =
        <({String name, String executable, JavaManifest? manifest})>[];
    try {
      final dir = Directory(await root());
      if (!dir.existsSync()) return result;

      for (final entity in dir.listSync()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;

        final exe = p.join(
          entity.path,
          'bin',
          Platform.isWindows ? 'java.exe' : 'java',
        );
        if (!File(exe).existsSync()) continue;

        JavaManifest? manifest;
        final mf = File(p.join(dir.path, '$name.json'));
        if (mf.existsSync()) {
          try {
            manifest = JavaManifest.tryParse(mf.readAsStringSync());
          } catch (e) {
            debugPrint('Failed to read java manifest ${mf.path}: $e');
          }
        }

        result.add((name: name, executable: exe, manifest: manifest));
      }
    } catch (e) {
      debugPrint('Failed to list java repository: $e');
    }
    return result;
  }

  /// 写清单（对齐 HMCL `JsonUtils.writeToJsonFile`）。
  Future<void> writeManifest(String name, JavaManifest manifest) async {
    final file = File(await manifestFile(name));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
  }

  /// 卸载受管安装：先删清单再删目录（对齐 HMCL getUninstallJavaTask）。
  Future<void> uninstall(String name) async {
    final mf = File(await manifestFile(name));
    if (mf.existsSync()) {
      try {
        mf.deleteSync();
      } catch (e) {
        debugPrint('Failed to delete java manifest ${mf.path}: $e');
      }
    }

    final dir = Directory(await javaDir(name));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
