// 管理模式设置 - 全局持久化
// 使用 SQLite (settings 表) 存储单机 / 多机管理模式与多机模式的监控节点

import 'settings_repository.dart';

/// 管理模式。
enum ManagementMode {
  /// 单机模式：本地实例直接在本机运行（默认）。
  single('single', '单机模式'),

  /// 多机模式：实例分布到多个节点，由协调器负责资源分配、崩溃迁移与数据同步。
  multi('multi', '多机模式');

  const ManagementMode(this.id, this.label);

  /// 持久化标识。
  final String id;

  /// 中文显示名。
  final String label;

  /// 从持久化标识反序列化，未知值回退 [single]。
  static ManagementMode fromId(String? value) {
    for (final m in ManagementMode.values) {
      if (m.id == value) return m;
    }
    return ManagementMode.single;
  }
}

/// 管理模式设置服务。
///
/// 持久化管理模式（默认单机）与多机模式的监控节点 id。
class ManagementModeSettings {
  static const _keyMode = 'management_mode';
  static const _keyMonitorNode = 'cluster_monitor_node_id';

  /// 获取当前管理模式，未设置时返回 [ManagementMode.single]。
  static Future<ManagementMode> getMode() async {
    final v = await SettingsRepository.instance.getStringOrNull(
      _keyMode,
      label: 'management mode',
    );
    return ManagementMode.fromId(v);
  }

  /// 设置当前管理模式。
  static Future<void> setMode(ManagementMode mode) =>
      SettingsRepository.instance.setString(
        _keyMode,
        mode.id,
        label: 'management mode',
      );

  /// 获取多机模式的监控节点 id（可空）。
  static Future<String?> getMonitorNodeId() async {
    final v = await SettingsRepository.instance.getStringOrNull(
      _keyMonitorNode,
      label: 'monitor node id',
    );
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 设置多机模式的监控节点 id（传 null 清除）。
  static Future<void> setMonitorNodeId(String? nodeId) =>
      SettingsRepository.instance.setString(
        _keyMonitorNode,
        (nodeId == null || nodeId.isEmpty) ? '' : nodeId,
        label: 'monitor node id',
      );
}
