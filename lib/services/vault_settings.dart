// Vault 设置 - 全局持久化
// 使用 SQLite (settings 表) 存储客户端 Vault（加密保险库）功能开关

import 'settings_repository.dart';

/// Vault（加密保险库，docs/vault-design.md）客户端设置服务。
///
/// 控制客户端是否启用 Vault 能力（保险库状态展示、解锁 / 初始化 / TOTP /
/// 证书绑定等界面与流程）。节点侧需以 `-vault` 开启并配置 TLS
/// （vault-design.md D7：vault 开启时强制 TLS），客户端开关与其独立：
/// 即使节点启用了 vault，客户端开关关闭时也不展示相关能力。
class VaultSettings {
  /// 默认状态：关闭（Vault 为可选高级功能，默认不暴露）。
  static const bool defaultEnabled = false;

  static const _keyEnabled = 'vault_enabled';

  /// 是否启用客户端 Vault 能力。
  static Future<bool> isEnabled() => SettingsRepository.instance.getBoolString(
        _keyEnabled,
        defaultValue: defaultEnabled,
        label: 'vault enabled',
      );

  /// 设置客户端 Vault 能力开关。
  static Future<void> setEnabled(bool enabled) =>
      SettingsRepository.instance.setBoolString(
        _keyEnabled,
        enabled,
        label: 'vault enabled',
      );
}
