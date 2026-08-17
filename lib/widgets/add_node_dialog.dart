// 添加节点三步向导
// 步骤 1：选择节点类型（MCSM / Node）
// 步骤 2：填写节点名称与 API 地址
// 步骤 3：填写节点 Key / API Key（本地节点可留空），并测试连接

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _testResult = '请先填写地址');
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
      _testResult = ok ? '连接成功' : '连接失败，请检查地址与 API Key';
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
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _testResult = '请填写节点地址');
      return;
    }
    final name = _nameController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (_type == NodeType.mcsm && apiKey.isEmpty) {
      setState(() => _testResult = 'MCSM 节点需要填写 API Key');
      return;
    }
    // H-6：远程 IriX 节点必须配置密钥，否则守护进程端口暴露即形成
    // 未认证的远程文件读写 + 命令执行面；仅本机回环允许留空。
    if (_type == NodeType.node && apiKey.isEmpty && !_isLoopback(address)) {
      setState(() => _testResult = '远程 Node 节点必须填写密钥（仅本机回环地址可留空）');
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
          title: const Text('明文连接警告'),
          content: const Text(
            '该节点地址使用明文 HTTP（非 https），API 密钥与全部控制流量'
            '（含文件读写、命令执行）可被同网段窃听或篡改。\n\n'
            '建议：节点启用 HTTPS 后再连接；确属可信内网环境可继续。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('仍然继续'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        setState(() => _testResult = '已取消：请为节点启用 HTTPS');
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
    return AlertDialog(
      title: Text('添加节点'),
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
          child: Text(_step > 0 ? '上一步' : '取消'),
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
            child: const Text('下一步'),
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
                : const Text('测试连接'),
          ),
          FilledButton(onPressed: _finish, child: const Text('完成')),
        ],
      ],
    );
  }

  /// 步骤指示器。
  Widget _buildStepper(ThemeData theme) {
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
                ['类型', '名称', 'Key'][i],
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
    return Column(
      key: const ValueKey('step-type'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择节点类型', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TypeCard(
                icon: Icons.dns,
                title: 'MCSM',
                subtitle: '连接远程 MCSManager 面板\n需填写面板 API Key',
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
                subtitle: 'IriX 本地 Go 语言节点\n本机回环可免密钥，远程必须配置密钥',
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
    return Column(
      key: const ValueKey('step-name'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('节点名称', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            hintText: '例如：我的面板 / 本地节点',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('节点地址', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _addressController,
          decoration: InputDecoration(
            hintText: _type == NodeType.mcsm
                ? 'http://192.168.1.5:23333'
                : 'http://127.0.0.1:12346',
            border: const OutlineInputBorder(),
            helperText: _type == NodeType.mcsm
                ? 'MCSManager 面板地址（含端口，如 23333）；远程建议使用 https'
                : '本地节点守护进程地址（默认 12346 端口）',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  /// 步骤 3：API Key。
  Widget _buildKeyStep(ThemeData theme) {
    return Column(
      key: const ValueKey('step-key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('节点 Key / API Key', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          obscureText: _obscureKey,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: _type == NodeType.mcsm
                ? 'MCSManager 用户 API Key'
                : '本地节点密钥（本机回环可留空）',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _apiKeyController.text),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 API Key')),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  tooltip: _obscureKey ? '显示' : '隐藏',
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ],
            ),
            helperText: _type == NodeType.mcsm
                ? '在 MCSManager 面板「用户信息」中生成并复制'
                : '远程节点必须填写密钥；仅 127.0.0.1 本机回环可留空',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _testResult!.contains('成功')
                    ? Icons.check_circle
                    : Icons.error_outline,
                size: 18,
                color: _testResult!.contains('成功')
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _testResult!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _testResult!.contains('成功')
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
