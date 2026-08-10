// 配置文件编辑服务
// 负责扫描实例根目录下的配置文件（.yml/.yaml/.properties），
// 并提供统一的读取/写入接口。YAML 使用 yaml 包解析与序列化，
// Properties 使用简单的 key=value 格式处理。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

/// 配置文件类型。
enum ConfigFileType { yaml, properties, json, toml, text }

/// 配置文件信息。
class ConfigFileInfo {
  /// 文件绝对路径。
  final String path;

  /// 相对于实例根目录的文件名。
  final String name;

  /// 文件类型。
  final ConfigFileType type;

  ConfigFileInfo({required this.path, required this.name, required this.type});
}

/// 配置文件编辑服务。
///
/// 扫描实例根目录下的配置文件，读取为结构化数据（Map），写入时序列化回文件。
class ConfigService {
  /// 扫描实例根目录下的配置文件。
  ///
  /// 默认模式：扫描根目录顶层文件 + `config/` 子目录（递归），
  /// 返回按文件名排序的列表，name 字段为相对根目录的路径（如 `config/config.yml`）。
  ///
  /// 当 [scanAll] 为 true 时，递归扫描根目录下所有文本文件（不限扩展名），
  /// 用于插件 / Mod 配置目录中格式较杂的场景，未知格式标记为 [ConfigFileType.text]，
  /// 并跳过二进制 / 媒体 / 锁文件。
  List<ConfigFileInfo> scanConfigFiles(
    String rootPath, {
    bool scanAll = false,
  }) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];

    final files = <ConfigFileInfo>[];

    if (scanAll) {
      // scanAll 模式：递归扫描根目录下所有文本文件
      _scanDirectory(dir, rootPath, files, scanAll: true);
    } else {
      // 默认模式：扫描根目录顶层 + config/ 子目录（递归），兼容旧逻辑
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          _tryAddConfig(entity, rootPath, files);
        }
      }
      final configDir = Directory(p.join(rootPath, 'config'));
      if (configDir.existsSync()) {
        _scanDirectory(configDir, rootPath, files);
      }
    }

    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  /// 递归扫描目录。
  void _scanDirectory(
    Directory dir,
    String rootPath,
    List<ConfigFileInfo> files, {
    bool scanAll = false,
  }) {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        _tryAddConfig(entity, rootPath, files, scanAll: scanAll);
      } else if (entity is Directory) {
        _scanDirectory(entity, rootPath, files, scanAll: scanAll);
      }
    }
  }

  /// 尝试将文件添加到配置列表（按扩展名过滤）。
  void _tryAddConfig(
    File file,
    String rootPath,
    List<ConfigFileInfo> files, {
    bool scanAll = false,
  }) {
    final ext = p.extension(file.path).toLowerCase();
    switch (ext) {
      case '.yml':
      case '.yaml':
        files.add(
          ConfigFileInfo(
            path: file.path,
            name: p.basename(file.path),
            type: ConfigFileType.yaml,
          ),
        );
        break;
      case '.properties':
      case '.conf':
      case '.cfg':
        files.add(
          ConfigFileInfo(
            path: file.path,
            name: p.basename(file.path),
            type: ConfigFileType.properties,
          ),
        );
        break;
      case '.json':
        files.add(
          ConfigFileInfo(
            path: file.path,
            name: p.basename(file.path),
            type: ConfigFileType.json,
          ),
        );
        break;
      case '.toml':
        files.add(
          ConfigFileInfo(
            path: file.path,
            name: p.basename(file.path),
            type: ConfigFileType.toml,
          ),
        );
        break;
      default:
        // scanAll 模式下，未知扩展名也纳入（作为纯文本处理），
        // 但跳过明显的二进制 / 媒体 / 锁文件。
        if (scanAll && !_isBinaryExt(ext) && ext != '.jar') {
          files.add(
            ConfigFileInfo(
              path: file.path,
              name: p.basename(file.path),
              type: ConfigFileType.text,
            ),
          );
        }
        break;
    }
  }

  /// 判断是否为常见二进制扩展名（应跳过）。
  bool _isBinaryExt(String ext) {
    const binary = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.bmp',
      '.ico',
      '.webp',
      '.db',
      '.sqlite',
      '.dat',
      '.bin',
      '.lock',
      '.lck',
      '.class',
      '.nbt',
      '.mca',
      '.mcr',
      '.zip',
      '.gz',
      '.tar',
    };
    return binary.contains(ext);
  }

  /// 读取配置文件为可变的 Map 结构。
  ///
  /// - YAML：解析为 `Map<String, dynamic>`，嵌套结构保留。
  /// - Properties：解析为 `Map<String, dynamic>`，值为 String。
  /// - text：返回空 Map，迫使编辑器回退到文本模式编辑。
  ///
  /// 解析失败时抛出异常，调用方应捕获并提示用户。
  Map<String, dynamic> readConfig(String path) {
    final file = File(path);
    final content = file.readAsStringSync();
    final ext = p.extension(path).toLowerCase();

    if (ext == '.json') {
      return _parseJson(content);
    }
    if (ext == '.properties' || ext == '.conf' || ext == '.cfg') {
      return _parseProperties(content);
    }
    // text 类型（未知扩展名）：返回空 Map，编辑器将回退到文本模式。
    if (!_isKnownConfigExt(ext)) {
      return {};
    }
    return _parseYaml(content);
  }

  /// 读取配置文件的原始文本。
  String readRaw(String path) {
    return File(path).readAsStringSync();
  }

  /// 将 Map 写回配置文件。
  ///
  /// - YAML：使用 yaml_writer 序列化。
  /// - Properties：以 key=value 格式写入。
  /// - text：不通过 Map 写入，调用方应使用 [writeRaw]。
  void writeConfig(String path, Map<String, dynamic> data) {
    final ext = p.extension(path).toLowerCase();
    String content;
    if (ext == '.json') {
      content = _serializeJson(data);
    } else if (ext == '.properties' || ext == '.conf' || ext == '.cfg') {
      content = _serializeProperties(data);
    } else if (!_isKnownConfigExt(ext)) {
      // text 类型：Map 写入无意义，直接序列化为 YAML 形式以免数据丢失。
      content = _serializeYaml(data);
    } else {
      content = _serializeYaml(data);
    }
    File(path).writeAsStringSync(content);
  }

  /// 判断扩展名是否为已知配置格式（yml/yaml/properties/conf/cfg/json/toml）。
  bool _isKnownConfigExt(String ext) {
    switch (ext) {
      case '.yml':
      case '.yaml':
      case '.properties':
      case '.conf':
      case '.cfg':
      case '.json':
      case '.toml':
        return true;
      default:
        return false;
    }
  }

  /// 将原始文本写回配置文件。
  void writeRaw(String path, String content) {
    File(path).writeAsStringSync(content);
  }

  /// 解析 JSON 文本为 Map。
  Map<String, dynamic> _parseJson(String content) {
    if (content.trim().isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return {};
  }

  /// 解析 YAML 文本为 Map。
  Map<String, dynamic> _parseYaml(String content) {
    if (content.trim().isEmpty) return {};
    final doc = loadYaml(content);
    if (doc == null) return {};
    if (doc is Map) {
      return _yamlToDart(doc);
    }
    return {};
  }

  /// 递归将 YamlMap/YamlList 转为普通 Dart Map/List。
  dynamic _yamlToDart(dynamic node) {
    if (node is Map) {
      return node.map((k, v) => MapEntry(k.toString(), _yamlToDart(v)));
    }
    if (node is List) {
      return node.map(_yamlToDart).toList();
    }
    return node;
  }

  /// 序列化 Map 为 JSON 文本（带缩进）。
  String _serializeJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  /// 序列化 Map 为 YAML 文本。
  String _serializeYaml(Map<String, dynamic> data) {
    final writer = YamlWriter();
    return writer.write(data);
  }

  /// 解析 Properties 文本为 Map。
  ///
  /// 支持 `key=value` 和 `key:value` 格式，忽略注释行（# 开头）和空行。
  Map<String, dynamic> _parseProperties(String content) {
    final result = <String, dynamic>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // 查找第一个 = 或 :
      int sepIndex = trimmed.indexOf('=');
      if (sepIndex < 0) sepIndex = trimmed.indexOf(':');
      if (sepIndex < 0) continue;

      final key = trimmed.substring(0, sepIndex).trim();
      final value = trimmed.substring(sepIndex + 1).trim();
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  /// 序列化 Map 为 Properties 文本。
  ///
  /// 以 `key=value` 格式逐行写入。
  String _serializeProperties(Map<String, dynamic> data) {
    final buf = StringBuffer();
    for (final entry in data.entries) {
      buf.writeln('${entry.key}=${entry.value}');
    }
    return buf.toString();
  }
}
