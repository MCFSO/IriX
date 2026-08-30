// 开发者模式开关 - 全局持久化
//
// 开启后应用会把一切（运行日志流、应用操作轨迹、网络请求明细、
// 启动与崩溃堆栈）记录到程序所在目录 logs/ 下的会话日志文件，便于排障。
// 开关存于 SQLite settings 表（键 dev_mode_enabled，整数 1/0）。

import 'settings_repository.dart';

/// 开发者模式设置服务。
class DeveloperSettings {
  DeveloperSettings._();

  /// 设置键。
  static const _keyEnabled = 'dev_mode_enabled';

  /// 读取开发者模式开关；未设置时返回 false。
  static Future<bool> isEnabled() => SettingsRepository.instance.getBoolInt(
        _keyEnabled,
        defaultValue: false,
        label: 'developer mode',
      );

  /// 设置开发者模式开关。
  static Future<void> setEnabled(bool enabled) =>
      SettingsRepository.instance.setBoolInt(
        _keyEnabled,
        enabled,
        label: 'developer mode',
      );
}
