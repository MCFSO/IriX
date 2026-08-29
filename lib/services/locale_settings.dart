// 界面语言设置 — 全局持久化
//
// 使用 SQLite (settings 表) 存储用户选择的语言偏好，取值：
// - 'system'：跟随系统（默认）
// - 'zh'：简体中文
// - 'en'：English
//
// 通过 ChangeNotifier 暴露响应式状态；切换后整个 MaterialApp
// 经 Consumer 重建，locale 立即生效。结构与 FontSettings 保持一致。

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';

/// 支持的语言标识。
enum AppLanguage {
  /// 跟随系统（null → 由 WidgetsBinding 决定）。
  system,

  /// 简体中文。
  zh,

  /// English。
  en;

  /// 持久化存储值（'system'/'zh'/'en'）。
  String get storageValue => name;

  /// 用户可读的显示名（用于设置下拉框）。
  String displayName(String Function(String) l10n) {
    switch (this) {
      case AppLanguage.system:
        return l10n('common_languageSystem');
      case AppLanguage.zh:
        return l10n('common_languageChinese');
      case AppLanguage.en:
        return l10n('common_languageEnglish');
    }
  }
}

/// 语言设置服务（单例 ChangeNotifier）。
class LocaleSettings extends ChangeNotifier {
  LocaleSettings._();

  /// 全局单例。
  static final LocaleSettings instance = LocaleSettings._();

  static const String keyLanguage = 'language';

  /// 默认语言：跟随系统。
  static const AppLanguage defaultLanguage = AppLanguage.system;

  static const List<AppLanguage> options = AppLanguage.values;

  AppLanguage _language = defaultLanguage;

  /// 当前语言偏好。
  AppLanguage get language => _language;

  /// 解析后的实际 [Locale]，null 表示跟随系统。
  String? get localeCode {
    switch (_language) {
      case AppLanguage.system:
        return null;
      case AppLanguage.zh:
        return 'zh';
      case AppLanguage.en:
        return 'en';
    }
  }

  /// 从 settings 表加载语言偏好。
  Future<void> load() async {
    try {
      final v = await DatabaseManager.instance.getSetting(keyLanguage);
      _language = _fromStorage(v) ?? defaultLanguage;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load language setting: $e');
    }
  }

  /// 设置语言偏好并持久化。
  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    try {
      await DatabaseManager.instance.setSetting(
        keyLanguage,
        language.storageValue,
      );
    } catch (e) {
      debugPrint('Failed to save language setting: $e');
    }
  }

  /// 由存储字符串解析语言；未知值回退默认。
  static AppLanguage? _fromStorage(String? value) {
    if (value == null) return null;
    for (final l in AppLanguage.values) {
      if (l.storageValue == value) return l;
    }
    return null;
  }
}
