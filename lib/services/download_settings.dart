// 下载设置 - 全局持久化
// 使用 SQLite (settings 表) 存储下载线程数

import 'settings_repository.dart';

/// 下载设置服务。
///
/// 持久化下载线程数 (1-32)，控制多线程分片断点续传下载的并发数。
class DownloadSettings {
  /// 默认下载线程数。
  static const int defaultThreads = 8;

  /// 下载线程数上限 (Rust 端 download_file_multipart 会 clamp 到 1-32)。
  static const int maxThreads = 32;

  /// 下载线程数下限。
  static const int minThreads = 1;

  static const _keyThreads = 'download_threads';

  /// 获取下载线程数，未设置时返回 [defaultThreads]。
  static Future<int> getThreads() => SettingsRepository.instance.getIntClamped(
        _keyThreads,
        defaultValue: defaultThreads,
        min: minThreads,
        max: maxThreads,
        label: 'threads',
      );

  /// 设置下载线程数，自动 clamp 到合法区间。
  static Future<void> setThreads(int threads) =>
      SettingsRepository.instance.setIntClamped(
        _keyThreads,
        threads,
        min: minThreads,
        max: maxThreads,
        label: 'threads',
      );
}
