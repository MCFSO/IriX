// 节点账户凭据对话框
// irix-node 自 v1.2.0 起移除了固定 apikey 通道（见 NODE_API.md §1），
// 所有 API 请求必须携带账户会话 token。此前创建、未保存账户凭据的节点
// 会持续返回 403「未认证或会话已过期」，本对话框用于补录或更正凭据。
//
// 自 irix-node v1.4.0 起支持设备绑定（docs/device-binding.md）：本对话框
// 同时提供「绑定本机设备 / 本地解绑 / 设备管理」入口，绑定后登录改用设备
// 私钥签名 + 逐请求证明（账户开 required 时未绑定设备无法登录）。
//
// 保存前会尝试真实登录（POST /api/auth/login）以校验凭据；登录失败时
// 询问用户是否仍然保存，避免节点离线时完全无法录入。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/node_device.dart';
import '../services/device_auth.dart';
import '../services/node_api_client.dart';
import '../services/node_device_service.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';
import 'node_devices_dialog.dart';

/// 打开节点账户凭据对话框；保存成功返回 true，取消返回 null/false。
Future<bool?> showNodeCredentialsDialog(BuildContext context, NodeInfo node) {
  return showAppDialog<bool>(
    context,
    (_) => _NodeCredentialsDialog(node: node),
  );
}

class _NodeCredentialsDialog extends StatefulWidget {
  const _NodeCredentialsDialog({required this.node});

  final NodeInfo node;

  @override
  State<_NodeCredentialsDialog> createState() => _NodeCredentialsDialogState();
}

class _NodeCredentialsDialogState extends State<_NodeCredentialsDialog> {
  late final TextEditingController _userController;
  late final TextEditingController _passwordController;

  bool _obscure = true;
  bool _busy = false;
  String? _result;
  bool _resultOk = false;

  /// 本机对该节点的设备绑定记录（未绑定时为 null）。
  NodeDeviceBinding? _binding;

  /// 本机设备密钥信息（用于展示私钥载体与密钥类型）。
  DeviceKeyInfo? _keyInfo;

  /// 设备绑定操作进行中（与登录校验的 [_busy] 区分开）。
  bool _deviceBusy = false;

  /// 设备绑定相关错误提示。
  String? _deviceError;

  @override
  void initState() {
    super.initState();
    _userController = TextEditingController(text: widget.node.accountUser);
    _passwordController = TextEditingController(
      text: widget.node.accountPassword,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDeviceState();
    });
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 读取本机设备绑定记录与密钥载体（不联网）。
  Future<void> _loadDeviceState() async {
    if (!widget.node.usesAccountAuth) return;
    if (!DeviceAuthService.instance.isAvailable) return;
    try {
      final binding = await DeviceAuthService.instance.bindingFor(widget.node.id);
      final key = await DeviceAuthService.instance.keyStatus();
      if (!mounted) return;
      setState(() {
        _binding = binding;
        _keyInfo = key;
        _deviceError = null;
      });
    } on DeviceAuthException catch (e) {
      if (!mounted) return;
      setState(() => _deviceError = e.message);
    }
  }

  /// 以当前输入尝试登录，成功返回会话，失败返回 null 并写入 [_result]。
  Future<NodeAccountSession?> _tryLogin() async {
    final l = AppLocalizations.of(context);
    final user = _userController.text.trim();
    final password = _passwordController.text;
    if (user.isEmpty || password.isEmpty) {
      setState(() {
        _resultOk = false;
        _result = l.addNode_accountRequired;
      });
      return null;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final client = NodeApiClient(
        baseUrl: widget.node.address,
        nodeId: widget.node.id,
        accountUser: user,
        accountPassword: password,
      );
      final session = await client.login();
      if (!mounted) return null;
      setState(() {
        _busy = false;
        _resultOk = true;
        _result = session.isAdmin
            ? l.addNode_loginSuccessAdmin
            : l.addNode_loginSuccess;
      });
      return session;
    } on NodeApiException catch (e) {
      if (!mounted) return null;
      setState(() {
        _busy = false;
        _resultOk = false;
        _result = l.addNode_loginFailed(e.message);
      });
      return null;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _busy = false;
        _resultOk = false;
        _result = l.addNode_loginFailed('$e');
      });
      return null;
    }
  }

  /// 保存凭据：先校验登录，失败时询问是否仍要保存。
  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final nodeState = context.read<NodeState>();
    final session = await _tryLogin();
    if (!mounted) return;

    if (session == null) {
      final proceed = await showAppDialog<bool>(
        context,
        (ctx) => AlertDialog(
          title: Text(l.nodeCredentials_saveAnywayTitle),
          content: Text(l.nodeCredentials_saveAnywayContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.nodeCredentials_saveAnyway),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    await _persistCredentials(nodeState);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.nodeCredentials_saved)),
    );
    Navigator.of(context).pop(true);
  }

  /// 把当前输入的用户名/密码写回节点记录并清理旧会话。
  Future<void> _persistCredentials(NodeState nodeState) async {
    await nodeState.updateNodeConnection(
      widget.node.id,
      address: widget.node.address,
      apiKey: widget.node.apiKey,
      accountUser: _userController.text.trim(),
      accountPassword: _passwordController.text,
    );
  }

  /// 绑定本机设备（协议 §4）：需要当前输入的用户名与密码。
  ///
  /// 绑定成功后顺手保存凭据 —— 否则用户取消对话框会留下「服务端已注册设备、
  /// 本地却没有账户凭据」的半完成状态。
  Future<void> _bindDevice() async {
    final l = AppLocalizations.of(context);
    final nodeState = context.read<NodeState>();
    final user = _userController.text.trim();
    final password = _passwordController.text;
    if (user.isEmpty || password.isEmpty) {
      setState(() {
        _deviceError = l.addNode_accountRequired;
        _result = null;
      });
      return;
    }
    setState(() {
      _deviceBusy = true;
      _deviceError = null;
    });
    try {
      final client = NodeApiClient(
        baseUrl: widget.node.address,
        nodeId: widget.node.id,
        accountUser: user,
        accountPassword: password,
      );
      final service = NodeDeviceService(
        client: client,
        nodeId: widget.node.id,
      );
      final binding = await service.bind(
        username: user,
        password: password,
        deviceName: 'IriX · ${Platform.operatingSystem}',
      );
      if (!mounted) return;
      await _persistCredentials(nodeState);
      await _loadDeviceState();
      if (!mounted) return;
      setState(() {
        _binding = binding;
        _deviceBusy = false;
        _resultOk = true;
        _result = l.deviceBinding_bindSuccess;
      });
    } on NodeApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceBusy = false;
        _deviceError = l.deviceBinding_bindFailed(e.message);
      });
    } on DeviceAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceBusy = false;
        _deviceError = l.deviceBinding_bindFailed(e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceBusy = false;
        _deviceError = l.deviceBinding_bindFailed('$e');
      });
    }
  }

  /// 本地解绑（只删本机记录，服务端设备保留）。
  Future<void> _unbindDevice() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.deviceBinding_unbindTitle),
        content: Text(l.deviceBinding_unbindContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.deviceBinding_unbind),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DeviceAuthService.instance.removeBinding(widget.node.id);
    NodeApiClient.forgetSession(widget.node.id);
    if (!mounted) return;
    setState(() {
      _binding = null;
      _deviceError = null;
      _resultOk = true;
      _result = l.deviceBinding_unbound;
    });
  }

  /// 打开设备管理对话框（列表 / 撤销 / 绑定）。
  Future<void> _openDevices() async {
    final changed = await showNodeDevicesDialog(
      context,
      widget.node,
      username: _userController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    await _loadDeviceState();
    if (changed == true && mounted) {
      // 设备变更（绑定 / 撤销）会影响会话，清掉缓存后下次请求重新登录。
      NodeApiClient.forgetSession(widget.node.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.nodeCredentials_title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nodeCredentials_description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _userController,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.addNode_accountUser,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.addNode_accountPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    tooltip: _obscure ? l.addNode_show : l.addNode_hide,
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.node.usesAccountAuth) ...[
                const SizedBox(height: 16),
                _buildDeviceSection(theme, l),
              ],
              if (_result != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _resultOk ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: _resultOk ? Colors.green : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _result!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _resultOk
                              ? Colors.green
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        TextButton(
          onPressed: _busy || _deviceBusy ? null : _tryLogin,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.addNode_testConnection),
        ),
        FilledButton(
          onPressed: _busy || _deviceBusy ? null : _save,
          child: Text(l.common_save),
        ),
      ],
    );
  }

  /// 设备绑定分区（协议 §2 的 deviceId、私钥载体、TLS 指纹状态 + 操作入口）。
  Widget _buildDeviceSection(ThemeData theme, AppLocalizations l) {
    final bound = _binding?.isActive ?? false;
    final available = DeviceAuthService.instance.isAvailable;
    final shortId = bound && _binding!.deviceId.length > 8
        ? _binding!.deviceId.substring(0, 8)
        : (_binding?.deviceId ?? '');
    final fingerprint = _binding?.tlsFingerprint ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.deviceBinding_sectionTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (_deviceBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!available)
            Text(
              l.deviceBinding_unavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else ...[
            Text(
              bound
                  ? l.deviceBinding_statusBound(shortId, _binding!.username)
                  : l.deviceBinding_statusUnbound,
              style: theme.textTheme.bodySmall,
            ),
            if (_keyInfo != null)
              Text(
                l.deviceBinding_keyProtection(
                  _keyInfo!.keyProtection,
                  _keyInfo!.keyType,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            if (bound)
              Text(
                fingerprint.isEmpty
                    ? l.deviceBinding_tlsUnpinned
                    : l.deviceBinding_tlsPinned(
                        fingerprint.length > 16
                            ? fingerprint.substring(0, 16)
                            : fingerprint,
                      ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fingerprint.isEmpty
                      ? theme.colorScheme.outline
                      : Colors.green,
                ),
              ),
            if (_deviceError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _deviceError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!bound)
                  TextButton.icon(
                    onPressed: _deviceBusy ? null : _bindDevice,
                    icon: const Icon(Icons.add_card, size: 16),
                    label: Text(l.deviceBinding_bind),
                  ),
                if (bound)
                  TextButton.icon(
                    onPressed: _deviceBusy ? null : _unbindDevice,
                    icon: const Icon(Icons.link_off, size: 16),
                    label: Text(l.deviceBinding_unbind),
                  ),
                TextButton.icon(
                  onPressed: _deviceBusy ? null : _openDevices,
                  icon: const Icon(Icons.devices_other, size: 16),
                  label: Text(l.deviceBinding_manage),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
