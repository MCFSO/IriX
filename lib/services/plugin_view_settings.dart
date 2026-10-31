// 插件/Mod 列表的展示设置
//
// 目前只有一项：每次加载条数（懒加载批量）。放在 SQLite settings 表，
// 遵循项目「无 SharedPreferences」约定。

import 'settings_repository.dart';

/// 插件列表展示设置。
class PluginViewSettings {
  PluginViewSettings._();

  /// 默认每次加载条数。
  static const int defaultBatchSize = 10;

  /// 每次加载条数下限。
  static const int minBatchSize = 5;

  /// 每次加载条数上限。
  ///
  /// 上限刻意不高：一次构建上百个条目会抵消懒加载的意义。
  static const int maxBatchSize = 50;

  /// 滑块步长（5 的倍数：5/10/15/.../50）。
  static const int batchSizeStep = 5;

  static const _keyBatchSize = 'plugin_batch_size';

  /// 读取每次加载条数，未设置时返回 [defaultBatchSize]。
  static Future<int> getBatchSize() =>
      SettingsRepository.instance.getIntClamped(
        _keyBatchSize,
        defaultValue: defaultBatchSize,
        min: minBatchSize,
        max: maxBatchSize,
        label: 'plugin_batch_size',
      );

  /// 写入每次加载条数，自动 clamp 并向下对齐到 [batchSizeStep]。
  static Future<void> setBatchSize(int value) {
    final aligned = (value ~/ batchSizeStep) * batchSizeStep; // 5/10/…/50
    return SettingsRepository.instance.setIntClamped(
      _keyBatchSize,
      aligned < minBatchSize ? minBatchSize : aligned,
      min: minBatchSize,
      max: maxBatchSize,
      label: 'plugin_batch_size',
    );
  }
}
