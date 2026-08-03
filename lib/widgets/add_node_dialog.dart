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
  return showAppDialog<NodeInfo>(
    context,
    (_) => const _AddNodeDialog(),
  );
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

  Future<void> _finish() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _testResult = '请填写节点地址');
      return;
    }
    final name = _nameController.text.trim();
    if (_type == NodeType.mcsm && _apiKeyController.text.trim().isEmpty) {
      setState(() => _testResult = 'MCSM 节点需要填写 API Key');
      return;
    }
    final node = await context.read<NodeState>().addNode(
          name: name,
          type: _type,
          address: address,
          apiKey: _apiKeyController.text.trim(),
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
          FilledButton(
            onPressed: _finish,
            child: const Text('完成'),
          ),
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
            Expanded(child: _TypeCard(
              icon: Icons.dns,
              title: 'MCSM',
              subtitle: '连接远程 MCSManager 面板\n需填写面板 API Key',
              selected: _type == NodeType.mcsm,
              onTap: () => setState(() {
                _type = NodeType.mcsm;
                _applyTypeDefaults();
              }),
            )),
            const SizedBox(width: 12),
            Expanded(child: _TypeCard(
              icon: Icons.terminal,
              title: 'Node',
              subtitle: 'IriX 本地 Go 语言节点\n默认无需密钥',
              selected: _type == NodeType.node,
              onTap: () => setState(() {
                _type = NodeType.node;
                _applyTypeDefaults();
              }),
            )),
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
                ? 'MCSManager 面板地址（含端口，如 23333）'
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
          obscureText: true,
          decoration: InputDecoration(
            hintText: _type == NodeType.mcsm
                ? 'MCSManager 用户 API Key'
                : '本地节点密钥（可留空）',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.visibility),
              tooltip: '显示',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: _apiKeyController.text),
              ),
            ),
            helperText: _type == NodeType.mcsm
                ? '在 MCSManager 面板「用户信息」中生成并复制'
                : 'Node 类型为 IriX 本地节点，默认无需密钥',
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
              color: selected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
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
