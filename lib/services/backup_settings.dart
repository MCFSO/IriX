// 备份压缩设置 - 每实例独立存储
// 使用 SQLite (settings 表) 持久化 Deflate 压缩级别 (0-9)

import 'settings_repository.dart';

/// 备份压缩级别标签
const _compressionLabels = <int, String>{
  0: '仅存储',
  1: '最快',
  3: '快速',
  6: '标准',
  9: '最佳',
};

/// 获取压缩级别的中文说明
String compressionLevelLabel(int level) {
  return _compressionLabels[level] ?? '级别 $level';
}

/// 备份设置服务 - 每实例独立压缩级别
class BackupSettings {
  static const _defaultLevel = 6;

  /// 获取实例的压缩级别
  static Future<int> getLevel(String instanceId) async {
    final v = await SettingsRepository.instance.getIntOrNull(
      'backup_compression_level_$instanceId',
      label: 'backup compression level',
    );
    return v ?? _defaultLevel;
  }

  /// 设置实例的压缩级别
  static Future<void> setLevel(String instanceId, int level) =>
      SettingsRepository.instance.setInt(
        'backup_compression_level_$instanceId',
        level,
        label: 'backup compression level',
      );
}
