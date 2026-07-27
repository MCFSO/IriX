// 配置注释导入服务
// 支持 CSV 导入中文注释，覆盖/扩充硬编码的 config_descriptions.dart
// 导入后持久化为 JSON 文件 (config_annotations.json)，启动时加载

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

import '../data/config_descriptions.dart';

/// 配置注释导入服务 (单例)
///
/// CSV 格式 (2 列):
/// ```
/// key,description
/// server.properties.max-players,最大玩家数
/// bukkit.yml.settings.update-folder,插件更新文件夹
/// ```
/// 第一行若为表头 (含 "key" 字样) 则跳过。
class ConfigAnnotationService {
  ConfigAnnotationService._();
  static final ConfigAnnotationService instance = ConfigAnnotationService._();

  Map<String, String> _imported = {};
  bool _initialized = false;

  /// 初始化 — 加载持久化的导入注释
  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/config_annotations.json');
      if (await file.exists()) {
        final json = await file.readAsString();
        final map = jsonDecode(json) as Map<String, dynamic>;
        _imported = map.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {
      // 加载失败时使用空 map，不影响硬编码注释
    }
    _initialized = true;
  }

  /// 查找注释 — 先查导入的，再回退硬编码
  String? get(String fileName, String keyPath) {
    final key = '$fileName.$keyPath';
    return _imported[key] ?? getConfigDescriptionHardcoded(fileName, keyPath);
  }

  /// 从 CSV 内容导入注释
  ///
  /// 返回导入的条目数。已有的导入注释会被新值覆盖。
  Future<int> importCsv(String csvContent) async {
    final rows = const CsvToListConverter().convert(
      csvContent,
      shouldParseNumbers: false,
    );

    var count = 0;
    for (final row in rows) {
      if (row.length < 2) continue;
      final key = row[0].toString().trim();
      final desc = row[1].toString().trim();
      if (key.isEmpty || desc.isEmpty) continue;
      // 跳过表头
      if (key.toLowerCase() == 'key') continue;
      _imported[key] = desc;
      count++;
    }

    if (count > 0) {
      await _persist();
    }
    return count;
  }

  /// 持久化到 JSON 文件
  Future<void> _persist() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/config_annotations.json');
    await file.writeAsString(jsonEncode(_imported));
  }
}
