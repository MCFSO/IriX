// 设置持久化通用基类
//
// 抽取 download_settings / vault_settings / backup_settings /
// management_mode_settings / ai_settings 中重复的 KV 读写样板：
// try { 读写 settings 表 → 解码 → clamp → 返回 } catch { debugPrint → 返回默认值 }。
//
// 全部基于 [DatabaseManager] 的 settings 表（key/value 字符串），
// 子类或静态调用方只需传入 key、默认值与边界即可。

import 'package:flutter/foundation.dart';

import 'database_manager.dart';

/// 设置持久化仓库：封装 settings 表的带兜底读写。
///
/// 提供字符串、整数（含 clamp）、布尔（字符串/整数两种编码）、
/// JSON 序列化值的读写辅助；统一 try/catch + debugPrint 兜底，
/// 调用方无需再手写错误处理样板。
class SettingsRepository {
  SettingsRepository._();
  static final instance = SettingsRepository._();

  // === 字符串 ===

  /// 读取字符串值；未设置或异常时返回 [defaultValue]。
  Future<String> getString(
    String key, {
    required String defaultValue,
    String? label,
  }) async {
    try {
      final v = await DatabaseManager.instance.getSetting(key);
      return v ?? defaultValue;
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return defaultValue;
    }
  }

  /// 读取可空字符串值；未设置返回 null，异常返回 null。
  Future<String?> getStringOrNull(String key, {String? label}) async {
    try {
      return await DatabaseManager.instance.getSetting(key);
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return null;
    }
  }

  /// 写入字符串值；异常时仅 debugPrint。
  Future<void> setString(String key, String value, {String? label}) async {
    try {
      await DatabaseManager.instance.setSetting(key, value);
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }

  // === 整数（含 clamp）===

  /// 读取整数值，自动 clamp 到 [min]–[max]；未设置或异常时返回 [defaultValue]。
  Future<int> getIntClamped(
    String key, {
    required int defaultValue,
    required int min,
    required int max,
    String? label,
  }) async {
    try {
      final v = await DatabaseManager.instance.getIntSetting(key);
      if (v == null) return defaultValue;
      return v.clamp(min, max);
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return defaultValue;
    }
  }

  /// 写入整数值，自动 clamp 到 [min]–[max]；异常时仅 debugPrint。
  Future<void> setIntClamped(
    String key,
    int value, {
    required int min,
    required int max,
    String? label,
  }) async {
    try {
      await DatabaseManager.instance.setIntSetting(key, value.clamp(min, max));
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }

  /// 读取可空整数值；未设置返回 null，异常返回 null。
  Future<int?> getIntOrNull(String key, {String? label}) async {
    try {
      return await DatabaseManager.instance.getIntSetting(key);
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return null;
    }
  }

  /// 写入整数值（不做 clamp）；异常时仅 debugPrint。
  Future<void> setInt(String key, int value, {String? label}) async {
    try {
      await DatabaseManager.instance.setIntSetting(key, value);
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }

  // === 布尔（字符串编码 '1'/'0'，兼容 'true'）===

  /// 读取布尔值（存储为字符串 '1'/'0'，兼容 'true'）；
  /// 未设置或异常时返回 [defaultValue]。
  Future<bool> getBoolString(
    String key, {
    required bool defaultValue,
    String? label,
  }) async {
    try {
      final v = await DatabaseManager.instance.getSetting(key);
      if (v == null) return defaultValue;
      return v == '1' || v == 'true';
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return defaultValue;
    }
  }

  /// 写入布尔值（存储为字符串 '1'/'0'）；异常时仅 debugPrint。
  Future<void> setBoolString(String key, bool value, {String? label}) async {
    try {
      await DatabaseManager.instance.setSetting(key, value ? '1' : '0');
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }

  // === 布尔（整数编码 1/0）===

  /// 读取布尔值（存储为整数 1/0）；未设置或异常时返回 [defaultValue]。
  Future<bool> getBoolInt(
    String key, {
    required bool defaultValue,
    String? label,
  }) async {
    try {
      return await DatabaseManager.instance.getIntSetting(key) == 1;
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return defaultValue;
    }
  }

  /// 写入布尔值（存储为整数 1/0）；异常时仅 debugPrint。
  Future<void> setBoolInt(String key, bool value, {String? label}) async {
    try {
      await DatabaseManager.instance.setIntSetting(key, value ? 1 : 0);
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }

  // === JSON 序列化值 ===

  /// 读取 JSON 编码的字符串；未设置或异常时返回 null。
  /// 调用方负责 jsonDecode 与类型转换。
  Future<String?> getJson(String key, {String? label}) async {
    try {
      final v = await DatabaseManager.instance.getSetting(key);
      if (v == null || v.trim().isEmpty) return null;
      return v;
    } catch (e) {
      debugPrint('Failed to get ${label ?? key}: $e');
      return null;
    }
  }

  /// 写入 JSON 编码的字符串；异常时仅 debugPrint。
  Future<void> setJson(String key, String encoded, {String? label}) async {
    try {
      await DatabaseManager.instance.setSetting(key, encoded);
    } catch (e) {
      debugPrint('Failed to set ${label ?? key}: $e');
    }
  }
}
