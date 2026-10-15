// Java 管理持久化（对应 HMCL UserSettings 中的 getUserJava / getDisabledJava）
//
// 存储于 SQLite settings 表（遵循 IriX 约定，无 SharedPreferences）：
//   java_user_added   —— 用户手动添加的 java 路径（JSON 数组）
//   java_disabled     —— 被禁用的 java 可执行文件路径（JSON 数组）
//   java_selected     —— 当前默认/选中 Java（可执行文件路径）
//   java_cache        —— 探测结果缓存（JSON 对象，对齐 HMCL javaCache.json 的角色）

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database_manager.dart';

/// Java 管理设置仓库。
class JavaSettings {
  JavaSettings._();

  static final JavaSettings instance = JavaSettings._();

  static const _keyUserAdded = 'java_user_added';
  static const _keyDisabled = 'java_disabled';
  static const _keySelected = 'java_selected';

  /// 用户手动添加的 java 路径（持久化）。
  Future<List<String>> getUserAdded() => _readList(_keyUserAdded);

  /// 覆盖写入用户手动添加列表。
  Future<void> setUserAdded(List<String> paths) =>
      _writeList(_keyUserAdded, paths);

  /// 追加一个手动添加路径（已存在则忽略）。
  Future<void> addUserAdded(String path) async {
    final list = await getUserAdded();
    if (list.contains(path)) return;
    list.add(path);
    await setUserAdded(list);
  }

  /// 从手动添加列表中移除。
  Future<void> removeUserAdded(String path) async {
    final list = await getUserAdded();
    if (!list.remove(path)) return;
    await setUserAdded(list);
  }

  /// 被禁用的 java 可执行文件路径（对应 HMCL `disabledJava`）。
  Future<Set<String>> getDisabled() async =>
      (await _readList(_keyDisabled)).toSet();

  /// 覆盖写入禁用列表。
  Future<void> setDisabled(Iterable<String> paths) =>
      _writeList(_keyDisabled, paths.toList());

  /// 禁用某个 java（同时从用户添加列表与选中项移除）。
  Future<void> disable(String binary) async {
    final disabled = await getDisabled();
    disabled.add(binary);
    await setDisabled(disabled);

    await removeUserAdded(binary);
    if (await getSelected() == binary) await setSelected(null);
  }

  /// 解除禁用（HMCL「已禁用管理」页面里恢复）。
  Future<void> enable(String binary) async {
    final disabled = await getDisabled();
    if (!disabled.remove(binary)) return;
    await setDisabled(disabled);
  }

  /// 当前选中的 Java 可执行文件路径（对应 HMCL 实例级 java 选择器的全局默认）。
  Future<String?> getSelected() async {
    try {
      final value = await DatabaseManager.instance.getSetting(_keySelected);
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (e) {
      debugPrint('Failed to get java_selected: $e');
      return null;
    }
  }

  /// 设置选中的 Java；传 null 表示清除。
  Future<void> setSelected(String? binary) async {
    try {
      await DatabaseManager.instance.setSetting(_keySelected, binary ?? '');
    } catch (e) {
      debugPrint('Failed to set java_selected: $e');
    }
  }

  /// 读取 JSON 字符串数组。
  Future<List<String>> _readList(String key) async {
    try {
      final raw = await DatabaseManager.instance.getSetting(key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Failed to read java setting $key: $e');
      return [];
    }
  }

  /// 写入 JSON 字符串数组。
  Future<void> _writeList(String key, List<String> values) async {
    try {
      await DatabaseManager.instance.setSetting(key, jsonEncode(values));
    } catch (e) {
      debugPrint('Failed to write java setting $key: $e');
    }
  }
}
