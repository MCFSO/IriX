// 节点设备管理对话框（irix-node v1.4.0+ 设备绑定，见 docs/device-binding.md）
//
// 功能：
// - 列出当前账户在节点上注册的设备（`GET /api/auth/devices`），标出本机设备；
// - 绑定本机设备（注册流程见 NodeDeviceService.bind）；
// - 撤销设备（需再次输入账户密码；撤销会注销该账户全部会话，协议 §4）。
//
// 仅对 irix-node（账户会话认证）有意义；MCSM 面板没有设备体系。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';import '../models/node.dart';
import '../models/node_device.dart';
import '../services/device_auth.dart';
import '../services/node_api_client.dart';
import '../services/node_device_service.dart';
import '../utils/apple_widgets.dart';

/// 打开设备管理对话框；发生绑定/撤销时返回 true。
///
/// [username] / [password] 用于覆盖节点里已保存的账户凭据（凭据对话框里
/// 用户刚输入、尚未保存的场景）。
Future<bool?> showNodeDevicesDialog(
  BuildContext context,
  NodeInfo node, {
  String? username,
  String? password,
}) {
  return showAppDialog<bool>(
    context,
    (_) => _NodeDevicesDialog(
      node: node,
      username: username,
      password: password,
    ),
  );
}

class _NodeDevicesDialog extends StatefulWidget {
  const _NodeDevicesDialog({
    required this.node,
    this.username,
    this.password,
  });

  final NodeInfo node;

  /// 覆盖节点已保存的账户用户名（可空）。
  final String? username;

  /// 覆盖节点已保存的账户密码（可空）。
  final String? password;

  @override
  State<_NodeDevicesDialog> createState() => _NodeDevicesDialogState();
}

class _NodeDevicesDialogState extends State<_NodeDevicesDialog> {
  late final String _username =
      (widget.username ?? widget.node.accountUser).trim();
  late final String _password = widget.password ?? widget.node.accountPassword;
  late final NodeApiClient _client = NodeApiClient(
    baseUrl: widget.node.address,
    nodeId: widget.node.id,
    accountUser: _username,
    accountPassword: _password,
  );
  late final NodeDeviceService _service = NodeDeviceService(
    client: _client,
    nodeId: widget.node.id,
  );

  List<NodeDevice> _devices = const [];
  NodeDeviceBinding? _binding;
  String _policy = '';
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final binding = await DeviceAuthService.instance.bindingFor(widget.node.id);
      final devices = await _service.listDevices();
      var policy = '';
      try {
        final me = await _client.accountMe();
        policy = me['devicePolicy'] as String? ?? '';
      } catch (_) {
        // 策略查询失败不影响设备列表展示。
      }
      if (!mounted) return;
      setState(() {
        _binding = binding;
        _devices = devices;
        _policy = policy;
        _loading = false;
      });
    } on DeviceAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on NodeApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = l.nodeDevices_loadFailed('$e');
        _loading = false;
      });
    }
  }

  /// 绑定本机设备：需要账户密码（注册接口要求，协议 §4）。
  Future<void> _bind() async {
    final l = AppLocalizations.of(context);
    final name = await _askDeviceName();
    if (name == null || !mounted) return;
    final password = await _askPassword(
      title: l.nodeDevices_bindTitle,
      confirmText: l.nodeDevices_bindAction,
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final binding = await _service.bind(
        username: _username,
        password: password,
        deviceName: name,
      );
      if (!mounted) return;
      setState(() {
        _binding = binding;
        _changed = true;
      });
      _snack(l.deviceBinding_bindSuccess);
      await _load();
    } on NodeApiException catch (e) {
      if (mounted) _snack(l.deviceBinding_bindFailed(e.message), error: true);
    } on DeviceAuthException catch (e) {
      if (mounted) _snack(l.deviceBinding_bindFailed(e.message), error: true);
    } catch (e) {
      if (mounted) _snack(l.deviceBinding_bindFailed('$e'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 撤销设备（协议 §4：撤销后该账户全部会话失效，本对话框随后关闭）。
  Future<void> _revoke(NodeDevice device) async {
    final l = AppLocalizations.of(context);
    final password = await _askPassword(
      title: l.nodeDevices_revokeTitle,
      message: l.nodeDevices_revokeContent(
        _shortId(device.deviceId),
      ),
      confirmText: l.nodeDevices_revoke,
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.revoke(deviceId: device.deviceId, password: password);
      if (!mounted) return;
      _changed = true;
      _snack(l.nodeDevices_revokeSuccess);
      // 撤销会注销全部会话，继续拉列表只会得到 403，直接关闭对话框。
      Navigator.of(context).pop(_changed);
    } on NodeApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(l.nodeDevices_revokeFailed(e.message), error: true);
      }
    } on DeviceAuthException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(l.nodeDevices_revokeFailed(e.message), error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack(l.nodeDevices_revokeFailed('$e'), error: true);
      }
    }
  }

  Future<String?> _askDeviceName() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: 'IriX · ${Platform.operatingSystem}',
    );
    final result = await showAppDialog<String>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.nodeDevices_bindTitle),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.nodeDevices_deviceNameLabel,
              hintText: l.nodeDevices_deviceNameHint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.nodeDevices_bindAction),
          ),
        ],
      ),
    );
    if (result == null) return null;
    return result.trim().isEmpty
        ? 'IriX · ${Platform.operatingSystem}'
        : result.trim();
  }

  Future<String?> _askPassword({
    required String title,
    String? message,
    required String confirmText,
  }) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final result = await showAppDialog<String>(
      context,
      (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message, style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.nodeDevices_passwordLabel,
                  hintText: l.nodeDevices_passwordHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.of(ctx).pop(value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
  }

  void _snack(String message, {bool error = false}) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// deviceId 展示用短形式（前 8 位）。
  String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);

  String _formatTime(int millis) {
    if (millis <= 0) return '';
    return DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(millis).toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bound = _binding?.isActive ?? false;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l.nodeDevices_title)),
          if (_policy.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _policy == 'required'
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _policy,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _policy == 'required'
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: l.nodeDevices_refresh,
            onPressed: _busy || _loading ? null : _load,
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: _buildBody(l, theme),
        ),
      ),
      actions: [
        if (!bound)
          TextButton.icon(
            onPressed: _busy || _loading ? null : _bind,
            icon: const Icon(Icons.add_card, size: 18),
            label: Text(l.deviceBinding_bind),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
          child: Text(l.common_close),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l, ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.deviceBinding_sectionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    if (_devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(l.nodeDevices_empty),
            const SizedBox(height: 6),
            Text(
              l.deviceBinding_sectionHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = _devices[index];
        final current = device.isCurrent(_binding?.deviceId);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            current ? Icons.computer : Icons.devices_other,
            color: current ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  device.name.isEmpty
                      ? _shortId(device.deviceId)
                      : device.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (current) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l.nodeDevices_current,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_shortId(device.deviceId)}… · ${device.keyType} / '
                '${device.keyProtection}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                device.lastSeen > 0
                    ? l.nodeDevices_lastSeen(_formatTime(device.lastSeen))
                    : l.nodeDevices_neverSeen,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          trailing: TextButton(
            onPressed: _busy ? null : () => _revoke(device),
            child: Text(
              l.nodeDevices_revoke,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        );
      },
    );
  }
}
