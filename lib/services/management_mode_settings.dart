// 管理模式设置 - 全局持久化
// 使用 SQLite (settings 表) 存储单机 / 多机管理模式与多机模式的监控节点

import 'package:flutter/foundation.dart';

import '../services/database_manager.dart';

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
    try {
      final v = await DatabaseManager.instance.getSetting(_keyMode);
      return ManagementMode.fromId(v);
    } catch (e) {
      debugPrint('Failed to get management mode: $e');
      return ManagementMode.single;
    }
  }

  /// 设置当前管理模式。
  static Future<void> setMode(ManagementMode mode) async {
    try {
      await DatabaseManager.instance.setSetting(_keyMode, mode.id);
    } catch (e) {
      debugPrint('Failed to set management mode: $e');
    }
  }

  /// 获取多机模式的监控节点 id（可空）。
  static Future<String?> getMonitorNodeId() async {
    try {
      final v = await DatabaseManager.instance.getSetting(_keyMonitorNode);
      return (v == null || v.isEmpty) ? null : v;
    } catch (e) {
      debugPrint('Failed to get monitor node id: $e');
      return null;
    }
  }

  /// 设置多机模式的监控节点 id（传 null 清除）。
  static Future<void> setMonitorNodeId(String? nodeId) async {
    try {
      if (nodeId == null || nodeId.isEmpty) {
        await DatabaseManager.instance.setSetting(_keyMonitorNode, '');
      } else {
        await DatabaseManager.instance.setSetting(_keyMonitorNode, nodeId);
      }
    } catch (e) {
      debugPrint('Failed to set monitor node id: $e');
    }
  }
}
