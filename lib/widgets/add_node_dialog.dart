// 添加节点三步向导
// 步骤 1：选择节点类型（MCSM / Node）
// 步骤 2：填写节点名称与 API 地址
// 步骤 3：填写节点 Key / API Key（本地节点可留空），并测试连接

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../services/node_api_client.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';

/// 打开添加节点向导；返回创建的节点，取消返回 null。
Future<NodeInfo?> showAddNodeDialog(BuildContext context) {
  return showAppDialog<NodeInfo>(context, (_) => const _AddNodeDialog());
}

class _AddNodeDialog extends StatefulWidget {
  const _AddNodeDialog();

  @override
  State<_AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<_AddNodeDialog> {
  int _step = 0;
  NodeType _type = NodeType.mcsm;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _testing = false;
  String? _testResult;

  /// 最近一次测试连接是否成功（用于结果图标/着色，与语言无关）。
  bool _testOk = false;

  /// API Key 是否隐藏（默认隐藏，眼睛按钮切换显示）。
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = '本地';
    _addressController.text = 'http://127.0.0.1:12346';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 切换节点类型时更新默认地址。
  void _applyTypeDefaults() {
    final defaultAddress = _type == NodeType.node
        ? 'http://127.0.0.1:12346'
        : 'http://127.0.0.1:23333';
    // 仅在地址为空或仍为上一个默认值时覆盖
    final current = _addressController.text.trim();
    if (current.isEmpty ||
        current == 'http://127.0.0.1:12346' ||
        current == 'http://127.0.0.1:23333') {
      _addressController.text = defaultAddress;
    }
  }

  Future<void> _testConnection() async {
    final l = AppLocalizations.of(context);
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _testResult = l.addNode_fillAddressFirst);
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = NodeApiClient(
      baseUrl: address,
      apiKey: _apiKeyController.text.trim(),
    );
    final ok = await client.ping();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok ? l.addNode_connectSuccess : l.addNode_connectFailed;
    });
  }

  /// 判断地址是否为本地回环（127.0.0.1 / localhost / ::1）。
  static bool _isLoopback(String address) {
    final uri = Uri.tryParse(address);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  Future<void> _finish() async {
    final l = AppLocalizations.of(context);
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _testResult = l.addNode_fillNodeAddress);
      return;
    }
    final name = _nameController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (_type == NodeType.mcsm && apiKey.isEmpty) {
      setState(() => _testResult = l.addNode_mcsmApiKeyRequired);
      return;
    }
    // H-6：远程 IriX 节点必须配置密钥，否则守护进程端口暴露即形成
    // 未认证的远程文件读写 + 命令执行面；仅本机回环允许留空。
    if (_type == NodeType.node && apiKey.isEmpty && !_isLoopback(address)) {
      setState(() => _testResult = l.addNode_remoteNodeKeyRequired);
      return;
    }
    // H-6：远程明文 HTTP 警告（凭证与全部控制流量可被窃听篡改）。
    final nodeState = context.read<NodeState>();
    final uri = Uri.tryParse(address);
    if (uri != null &&
        uri.scheme != 'https' &&
        !_isLoopback(address) &&
        uri.host != '') {
      final proceed = await showAppDialog<bool>(
        context,
        (ctx) => AlertDialog(
          title: Text(l.addNode_plaintextWarningTitle),
          content: Text(l.addNode_plaintextWarningContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.addNode_continueAnyway),
            ),
          ],
        ),
      );
      if (proceed != true) {
        setState(() => _testResult = l.addNode_cancelledEnableHttps);
        return;
      }
    }
    final node = await nodeState.addNode(
      name: name,
      type: _type,
      address: address,
      apiKey: apiKey,
    );
    if (!mounted) return;
    Navigator.of(context).pop(node);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addNode_title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepper(theme),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: switch (_step) {
                0 => _buildTypeStep(theme),
                1 => _buildNameStep(theme),
                _ => _buildKeyStep(theme),
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _step > 0
              ? () => setState(() {
                  _step--;
                  _testResult = null;
                })
              : () => Navigator.of(context).pop(),
          child: Text(_step > 0 ? l.addNode_prevStep : l.common_cancel),
        ),
        if (_step < 2)
          FilledButton(
            onPressed: () => setState(() {
              if (_step == 0) {
                _applyTypeDefaults();
              }
              _step++;
              _testResult = null;
            }),
            child: Text(l.addNode_nextStep),
          )
        else ...[
          TextButton(
            onPressed: _testing ? null : _testConnection,
            child: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.addNode_testConnection),
          ),
          FilledButton(onPressed: _finish, child: Text(l.addNode_finish)),
        ],
      ],
    );
  }

  /// 步骤指示器。
  Widget _buildStepper(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Row(
      children: List.generate(3, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: done || active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  done ? '✓' : '${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: done || active
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                [
                  l.addNode_stepType,
                  l.addNode_stepName,
                  l.addNode_stepKey,
                ][i],
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: done
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  /// 步骤 1：节点类型。
  Widget _buildTypeStep(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-type'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.addNode_selectType, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TypeCard(
                icon: Icons.dns,
                title: 'MCSM',
                subtitle: l.addNode_mcsmSubtitle,
                selected: _type == NodeType.mcsm,
                onTap: () => setState(() {
                  _type = NodeType.mcsm;
                  _applyTypeDefaults();
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TypeCard(
                icon: Icons.terminal,
                title: 'Node',
                subtitle: l.addNode_nodeSubtitle,
                selected: _type == NodeType.node,
                onTap: () => setState(() {
                  _type = NodeType.node;
                  _applyTypeDefaults();
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 步骤 2：名称与地址。
  Widget _buildNameStep(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-name'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.common_name, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: l.addNode_nameHint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(l.addNode_address, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _addressController,
          decoration: InputDecoration(
            hintText: _type == NodeType.mcsm
                ? 'http://192.168.1.5:23333'
                : 'http://127.0.0.1:12346',
            border: const OutlineInputBorder(),
            helperText: _type == NodeType.mcsm
                ? l.addNode_mcsmAddressHelper
                : l.addNode_nodeAddressHelper,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  /// 步骤 3：API Key。
  Widget _buildKeyStep(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.addNode_keyTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          obscureText: _obscureKey,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: _type == NodeType.mcsm
                ? l.addNode_mcsmKeyHint
                : l.addNode_nodeKeyHint,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: l.common_copy,
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _apiKeyController.text),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.addNode_copiedApiKey)),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  tooltip: _obscureKey ? l.addNode_show : l.addNode_hide,
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ],
            ),
            helperText: _type == NodeType.mcsm
                ? l.addNode_mcsmKeyHelper
                : l.addNode_nodeKeyHelper,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _testOk ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: _testOk
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _testResult!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _testOk
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 类型选择卡片。
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: 2,
              color: selected ? theme.colorScheme.primary : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 32,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
