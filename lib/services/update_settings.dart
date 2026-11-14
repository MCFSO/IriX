// 更新（OTA）设置 - 全局持久化
//
// 全部存于 SQLite settings 表（key/value 字符串），经 SettingsRepository 读写，
// 无 SharedPreferences。包含：
// - 启动时是否自动检查更新；
// - 是否把预发布版本也算作更新；
// - 用户「跳过此版本」的版本号；
// - 上次检查时间与上次看到的最新版本（用于限频与设置页展示）。

import 'settings_repository.dart';

/// 更新设置服务（静态方法，无实例状态）。
class UpdateSettings {
  /// 启动自动检查更新的默认值。
  static const bool defaultAutoCheck = true;

  /// 是否包含预发布版本的默认值。
  static const bool defaultIncludePrerelease = false;

  /// 启动自动检查的最小间隔：距上次检查不足该时长时直接跳过，
  /// 避免频繁启动应用导致 GitHub API 限流（未认证 60 次/小时）。
  static const Duration autoCheckInterval = Duration(hours: 6);

  static const String _keyAutoCheck = 'update_auto_check';
  static const String _keyIncludePrerelease = 'update_include_prerelease';
  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastCheckAtMs = 'update_last_check_at_ms';
  static const String _keyLastKnownLatest = 'update_last_known_latest';
  static const String _keyFeedUrl = 'update_feed_url';

  /// 自定义更新源（Cloudflare Worker 等自建分发地址）。
  ///
  /// 空字符串表示使用构建期内置源（`--dart-define=IRIX_UPDATE_FEED`），
  /// 最终都会回退到 GitHub 官方 Releases。
  static Future<String> getFeedUrl() => SettingsRepository.instance.getString(
    _keyFeedUrl,
    defaultValue: '',
    label: 'update_feed_url',
  );

  /// 写入自定义更新源（传空字符串清除，回到默认源）。
  static Future<void> setFeedUrl(String url) =>
      SettingsRepository.instance.setString(
        _keyFeedUrl,
        url.trim(),
        label: 'update_feed_url',
      );

  /// 是否在启动时自动检查更新。
  static Future<bool> getAutoCheck() => SettingsRepository.instance
      .getBoolString(
        _keyAutoCheck,
        defaultValue: defaultAutoCheck,
        label: 'update_auto_check',
      );

  /// 写入「启动自动检查更新」开关。
  static Future<void> setAutoCheck(bool value) => SettingsRepository.instance
      .setBoolString(_keyAutoCheck, value, label: 'update_auto_check');

  /// 是否包含预发布版本。
  static Future<bool> getIncludePrerelease() => SettingsRepository.instance
      .getBoolString(
        _keyIncludePrerelease,
        defaultValue: defaultIncludePrerelease,
        label: 'update_include_prerelease',
      );

  /// 写入「包含预发布版本」开关。
  static Future<void> setIncludePrerelease(bool value) =>
      SettingsRepository.instance.setBoolString(
        _keyIncludePrerelease,
        value,
        label: 'update_include_prerelease',
      );

  /// 用户选择「跳过此版本」的版本号；空字符串表示没有跳过任何版本。
  static Future<String> getSkippedVersion() => SettingsRepository.instance
      .getString(
        _keySkippedVersion,
        defaultValue: '',
        label: 'update_skipped_version',
      );

  /// 记录被跳过的版本号（传空字符串清除）。
  static Future<void> setSkippedVersion(String version) =>
      SettingsRepository.instance.setString(
        _keySkippedVersion,
        version,
        label: 'update_skipped_version',
      );

  /// 上次检查更新的时间（Unix 毫秒，来自 TimeService）；从未检查为 0。
  static Future<int> getLastCheckAtMs() => SettingsRepository.instance
      .getIntClamped(
        _keyLastCheckAtMs,
        defaultValue: 0,
        min: 0,
        max: 8640000000000000,
        label: 'update_last_check_at_ms',
      );

  /// 写入上次检查时间（Unix 毫秒）。
  static Future<void> setLastCheckAtMs(int ms) =>
      SettingsRepository.instance.setIntClamped(
        _keyLastCheckAtMs,
        ms,
        min: 0,
        max: 8640000000000000,
        label: 'update_last_check_at_ms',
      );

  /// 上次成功检查到的最新版本号（空字符串表示未知）。
  static Future<String> getLastKnownLatest() => SettingsRepository.instance
      .getString(
        _keyLastKnownLatest,
        defaultValue: '',
        label: 'update_last_known_latest',
      );

  /// 写入上次检查到的最新版本号。
  static Future<void> setLastKnownLatest(String version) =>
      SettingsRepository.instance.setString(
        _keyLastKnownLatest,
        version,
        label: 'update_last_known_latest',
      );
}
