// 节点卡片网格（单机 / 多机模式共用）
// - 单机模式：点击卡片进入节点详情（传入 onTapNode）
// - 多机模式：不进入详情（onTapNode 传 null），仅通过 ⋮ 菜单重命名 / 删除
// 重命名与删除确认对话框也在此处复用（showRenameNodeDialog / showDeleteNodeConfirmDialog）。

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../utils/apple_widgets.dart';

/// 节点卡片网格（作为 CustomScrollView 的一个 sliver 使用）。
class NodeCardGrid extends StatelessWidget {
  const NodeCardGrid({
    super.key,
    required this.nodes,
    required this.onlineOf,
    required this.errorOf,
    this.onTapNode,
    required this.onRenameNode,
    required this.onDeleteNode,
  });

  final List<NodeInfo> nodes;
  final bool Function(String id) onlineOf;
  final String? Function(String id) errorOf;

  /// 点击卡片进入详情的回调；为 null 时卡片不可点击。
  final void Function(NodeInfo node)? onTapNode;
  final void Function(NodeInfo node) onRenameNode;
  final void Function(NodeInfo node) onDeleteNode;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.6,
        ),
        itemCount: nodes.length,
        itemBuilder: (context, index) {
          final node = nodes[index];
          return _NodeCard(
            node: node,
            online: onlineOf(node.id),
            error: errorOf(node.id),
            onTap: onTapNode == null ? null : () => onTapNode!(node),
            onRename: () => onRenameNode(node),
            onDelete: () => onDeleteNode(node),
          );
        },
      ),
    );
  }
}

/// 重命名节点对话框，返回新名称（取消返回 null）。
Future<String?> showRenameNodeDialog(BuildContext context, NodeInfo node) {
  final controller = TextEditingController(text: node.name);
  final l = AppLocalizations.of(context);
  return showAppDialog<String>(
    context,
    (_) => AlertDialog(
      title: Text(l.node_renameTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: l.node_nameHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l.common_confirm),
        ),
      ],
    ),
  );
}

/// 删除节点确认对话框，返回是否确认删除。
Future<bool?> showDeleteNodeConfirmDialog(BuildContext context, NodeInfo node) {
  final l = AppLocalizations.of(context);
  return showAppDialog<bool>(
    context,
    (_) => AlertDialog(
      title: Text(l.node_deleteConfirmTitle(node.name)),
      content: Text(l.node_deleteConfirmContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.common_delete),
        ),
      ],
    ),
  );
}

/// 节点卡片。
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.online,
    required this.error,
    this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final NodeInfo node;
  final bool online;
  final String? error;
  final VoidCallback? onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final isLocal = node.type == NodeType.node;
    return AppleCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  (online
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest)
                      .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLocal ? Icons.terminal : Icons.dns,
              color: online
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        node.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        node.type.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      online ? Icons.circle : Icons.circle_outlined,
                      size: 8,
                      color: online ? Colors.green : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        online ? l.node_online : (error ?? l.node_offline),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: online
                              ? Colors.green
                              : theme.colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: theme.colorScheme.outline,
              size: 18,
            ),
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  onRename();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(l.node_renameMenu)),
              PopupMenuItem(value: 'delete', child: Text(l.node_deleteMenu)),
            ],
          ),
        ],
      ),
    );
  }
}
