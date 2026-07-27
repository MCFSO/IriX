// 下载设置 - 全局持久化
// 使用 SharedPreferences 存储下载线程数与动画效果开关

import 'package:shared_preferences/shared_preferences.dart';

/// 下载与界面设置服务。
///
/// 持久化两项全局设置：
/// - 下载线程数 (1-32)，控制多线程分片断点续传下载的并发数；
/// - 动画效果开关，控制 Apple 风格组件的弹簧/过渡动画是否启用。
class DownloadSettings {
  /// 默认下载线程数。
  static const int defaultThreads = 8;

  /// 下载线程数上限 (Rust 端 download_file_multipart 会 clamp 到 1-32)。
  static const int maxThreads = 32;

  /// 下载线程数下限。
  static const int minThreads = 1;

  static const _keyThreads = 'download_threads';
  static const _keyAnimations = 'animations_enabled';

  /// 获取下载线程数，未设置时返回 [defaultThreads]。
  static Future<int> getThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_keyThreads);
    if (v == null) return defaultThreads;
    return v.clamp(minThreads, maxThreads);
  }

  /// 设置下载线程数，自动 clamp 到合法区间。
  static Future<void> setThreads(int threads) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThreads, threads.clamp(minThreads, maxThreads));
  }

  /// 获取动画效果是否启用，未设置时默认为 true。
  static Future<bool> getAnimationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAnimations) ?? true;
  }

  /// 设置动画效果开关。
  static Future<void> setAnimationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimations, enabled);
  }
}
