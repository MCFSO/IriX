// 字体设置 - 全局持久化
// 使用 SQLite (settings 表) 存储 UI 字体与终端字体，两者分开管理：
// - UI 字体：默认 MiSans（内置字体资产，见 pubspec.yaml fonts）
// - 终端字体：默认 JetBrains Mono（内置字体资产）
// 通过 ChangeNotifier 暴露响应式状态，切换后整个应用立即重建生效。

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';
import 'locale_settings.dart';

/// 字体设置服务（单例 ChangeNotifier）。
///
/// 两个独立维度：
/// - [uiFamily]：全局 UI 字体。空字符串表示跟随系统默认字体。
/// - [terminalFamily]：终端 / 日志 / 代码等等宽文本字体。
///   `'inherit'` 表示跟随 UI 字体。
class FontSettings extends ChangeNotifier {
  FontSettings._();

  /// 全局单例。
  static final FontSettings instance = FontSettings._();

  static const String keyUiFamily = 'font_ui_family';
  static const String keyTerminalFamily = 'font_terminal_family';

  /// 内置字体族名称（与 pubspec.yaml `fonts` 声明对应）。
  static const String bundledMiSans = 'MiSans';

  /// 内置点阵字体族名称（Fusion Pixel 12px 中文等宽）。
  static const String bundledPixel = 'FusionPixel';

  /// 内置 JetBrains Mono 字体族名称（终端默认）。
  static const String bundledJetBrainsMono = 'JetBrainsMono';

  /// 默认 UI 字体：MiSans（内置）。
  static const String defaultUiFamily = bundledMiSans;

  /// 默认终端字体：JetBrains Mono（内置）。
  static const String defaultTerminalFamily = bundledJetBrainsMono;

  /// 终端字体「跟随 UI 字体」的特殊值。
  static const String inheritTerminal = 'inherit';

  String _uiFamily = defaultUiFamily;
  String _terminalFamily = defaultTerminalFamily;

  /// 全局 UI 字体族；空字符串表示跟随系统默认字体。
  String get uiFamily => _uiFamily;

  /// 终端字体设置值；`'inherit'` 表示跟随 UI 字体。
  String get terminalFamily => _terminalFamily;

  /// 供 ThemeData 使用的 UI 字体（空 → null，即系统默认）。
  String? get uiFontFamily => _uiFamily.isEmpty ? null : _uiFamily;

  /// 实际生效的终端字体族（已解析 `'inherit'`）。
  String get effectiveTerminalFamily {
    if (_terminalFamily == inheritTerminal) {
      return _uiFamily.isEmpty ? 'monospace' : _uiFamily;
    }
    return _terminalFamily;
  }

  /// 从 settings 表加载字体设置。
  Future<void> load() async {
    try {
      _uiFamily =
          (await DatabaseManager.instance.getSetting(keyUiFamily)) ??
          defaultUiFamily;
      _terminalFamily =
          (await DatabaseManager.instance.getSetting(keyTerminalFamily)) ??
          defaultTerminalFamily;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load font settings: $e');
    }
  }

  /// 设置 UI 字体并持久化。
  Future<void> setUiFamily(String family) async {
    if (_uiFamily == family) return;
    _uiFamily = family;
    notifyListeners();
    try {
      await DatabaseManager.instance.setSetting(keyUiFamily, family);
    } catch (e) {
      debugPrint('Failed to save ui font: $e');
    }
  }

  /// 设置终端字体并持久化。
  Future<void> setTerminalFamily(String family) async {
    if (_terminalFamily == family) return;
    _terminalFamily = family;
    notifyListeners();
    try {
      await DatabaseManager.instance.setSetting(keyTerminalFamily, family);
    } catch (e) {
      debugPrint('Failed to save terminal font: $e');
    }
  }

  /// 可用 UI 字体选项：(存储值, 显示名)。
  ///
  /// 内置 MiSans 与系统常见中文字体；未安装的系统字体由 Flutter
  /// 自动回退到默认字体，不会报错。
  ///
  /// 显示名随语言设置切换（无 BuildContext，读取 LocaleSettings）。
  static List<(String, String)> get uiOptions {
    final en = LocaleSettings.instance.localeCode == 'en';
    return [
      (bundledMiSans, en ? 'MiSans (built-in, recommended)' : 'MiSans（内置，推荐）'),
      ('', en ? 'System default font' : '系统默认字体'),
      ('Microsoft YaHei', en ? 'Microsoft YaHei' : '微软雅黑'),
      ('PingFang SC', en ? 'PingFang SC' : '苹方 PingFang SC'),
      ('Noto Sans SC', en ? 'Noto Sans SC' : '思源黑体 Noto Sans SC'),
    ];
  }

  /// 可用终端字体选项：(存储值, 显示名)。
  ///
  /// 显示名随语言设置切换（无 BuildContext，读取 LocaleSettings）。
  static List<(String, String)> get terminalOptions {
    final en = LocaleSettings.instance.localeCode == 'en';
    return [
      (
        bundledJetBrainsMono,
        en ? 'JetBrains Mono (built-in, recommended)' : 'JetBrains Mono（内置，推荐）'
      ),
      (bundledPixel, en ? 'Pixel font Fusion Pixel (built-in)' : '点阵字体 Fusion Pixel（内置）'),
      ('monospace', en ? 'System monospace font' : '系统等宽字体'),
      (inheritTerminal, en ? 'Inherit UI font' : '跟随 UI 字体'),
      ('Consolas', 'Consolas'),
      ('Cascadia Mono', 'Cascadia Mono'),
    ];
  }
}
