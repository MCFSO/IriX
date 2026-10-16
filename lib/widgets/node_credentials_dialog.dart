// 节点账户凭据对话框
// irix-node 自 v1.2.0 起移除了固定 apikey 通道（见 NODE_API.md §1），
// 所有 API 请求必须携带账户会话 token。此前创建、未保存账户凭据的节点
// 会持续返回 403「未认证或会话已过期」，本对话框用于补录或更正凭据。
//
// 保存前会尝试真实登录（POST /api/auth/login）以校验凭据；登录失败时
// 询问用户是否仍然保存，避免节点离线时完全无法录入。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../services/node_api_client.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _userController = TextEditingController(text: widget.node.accountUser);
    _passwordController = TextEditingController(
      text: widget.node.accountPassword,
    );
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
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

    await nodeState.updateNodeConnection(
      widget.node.id,
      address: widget.node.address,
      apiKey: widget.node.apiKey,
      accountUser: _userController.text.trim(),
      accountPassword: _passwordController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.nodeCredentials_saved)),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.nodeCredentials_title),
      content: SizedBox(
        width: 440,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        TextButton(
          onPressed: _busy ? null : _tryLogin,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.addNode_testConnection),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(l.common_save),
        ),
      ],
    );
  }
}
