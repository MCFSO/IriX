// 安装目标选择器（本地实例 / 节点实例）
// 供市场（Modrinth / Hangar）安装 Mod / 插件时选择安装位置：
// - 本地实例：AppState 中的本地实例列表
// - 节点实例：节点 → 守护进程 → 远程实例列表（MCSM 面板 / IriX 节点通用）

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../models/server_instance.dart';
import '../services/node_api_client.dart';
import '../state/app_state.dart';
import '../state/node_state.dart';
import 'apple_widgets.dart';

/// 节点端长耗时操作（上传）使用的超时。
const Duration _installLongTimeout = Duration(minutes: 10);

/// 安装目标：本地实例或节点（远程）实例。
class InstallTarget {
  /// 本地实例目标（非空表示安装到本地）。
  final ServerInstance? localInstance;

  /// 节点目标（四个字段同时非空表示安装到节点实例）。
  final NodeInfo? node;
  final NodeApiClient? client;
  final String? daemonId;
  final RemoteInstance? remoteInstance;

  const InstallTarget._({
    this.localInstance,
    this.node,
    this.client,
    this.daemonId,
    this.remoteInstance,
  });

  factory InstallTarget.local(ServerInstance instance) =>
      InstallTarget._(localInstance: instance);

  factory InstallTarget.remote({
    required NodeInfo node,
    required NodeApiClient client,
    required String daemonId,
    required RemoteInstance instance,
  }) =>
      InstallTarget._(
        node: node,
        client: client,
        daemonId: daemonId,
        remoteInstance: instance,
      );

  /// 是否安装到节点实例。
  bool get isRemote =>
      node != null && client != null && daemonId != null && remoteInstance != null;

  /// 目标显示名。
  String get displayName => isRemote
      ? '${node!.name} / ${remoteInstance!.config.nickname.isEmpty ? remoteInstance!.uuid : remoteInstance!.config.nickname}'
      : localInstance?.name ?? '?';
}

/// 弹出安装目标选择对话框，返回 null 表示取消。
///
/// 本地与节点都可用时让用户选择模式；只有一种可用时直接进入该模式。
Future<InstallTarget?> pickInstallTarget(BuildContext context) async {
  final app = context.read<AppState>();
  final nodeState = context.read<NodeState>();
  final hasLocal = app.instances.isNotEmpty;
  final hasNodes = nodeState.nodes.isNotEmpty;

  if (!hasLocal && !hasNodes) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先创建本地实例或添加节点')));
    }
    return null;
  }

  // 两种目标都可用 → 先选模式；否则直接进入。
  InstallTarget? target;
  if (hasLocal && hasNodes) {
    final mode = await showAppDialog<String>(
      context,
      (ctx) => AlertDialog(
        title: const Text('选择安装位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('本地实例'),
              subtitle: const Text('安装到本机实例目录'),
              onTap: () => Navigator.pop(ctx, 'local'),
            ),
            ListTile(
              leading: const Icon(Icons.lan),
              title: const Text('节点实例'),
              subtitle: const Text('上传到节点（MCSM / IriX 节点）上的实例'),
              onTap: () => Navigator.pop(ctx, 'node'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mode == null) return null;
    if (!context.mounted) return null;
    target = mode == 'local'
        ? await _pickLocal(context)
        : await _pickRemote(context);
  } else if (hasLocal) {
    target = await _pickLocal(context);
  } else {
    target = await _pickRemote(context);
  }
  return target;
}

/// 选择本地实例。
Future<InstallTarget?> _pickLocal(BuildContext context) async {
  final state = context.read<AppState>();
  final instances = state.instances;
  // 若有选中的实例直接使用。
  if (state.selected != null) return InstallTarget.local(state.selected!);
  if (!context.mounted) return null;
  return showAppDialog<InstallTarget>(context, (ctx) {
    return AlertDialog(
      title: const Text('选择目标实例'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: instances.length,
          itemBuilder: (context, index) {
            final instance = instances[index];
            return ListTile(
              leading: const Icon(Icons.storage),
              title: Text(instance.name),
              subtitle: Text(instance.rootPath),
              onTap: () => Navigator.pop(ctx, InstallTarget.local(instance)),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ],
    );
  });
}

/// 选择节点实例：节点 → 守护进程 → 实例。
Future<InstallTarget?> _pickRemote(BuildContext context) async {
  final nodeState = context.read<NodeState>();
  if (nodeState.nodes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在「节点」中添加节点')));
    }
    return null;
  }
  if (!context.mounted) return null;
  return showAppDialog<InstallTarget>(context, (ctx) {
    return _NodeTargetPicker(nodeState: nodeState);
  });
}

/// 节点目标选择对话框（内部分步：节点 → 守护进程 → 实例）。
class _NodeTargetPicker extends StatefulWidget {
  const _NodeTargetPicker({required this.nodeState});

  final NodeState nodeState;

  @override
  State<_NodeTargetPicker> createState() => _NodeTargetPickerState();
}

class _NodeTargetPickerState extends State<_NodeTargetPicker> {
  NodeInfo? _node;
  NodeApiClient? _client;

  /// 守护进程列表（overview.remote）。
  List<DaemonInfo>? _daemons;

  /// 远程实例列表。
  List<RemoteInstance>? _instances;

  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (_node == null) {
      // 步骤 1：选择节点
      body = SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.nodeState.nodes.length,
          itemBuilder: (context, index) {
            final node = widget.nodeState.nodes[index];
            final online = widget.nodeState.isOnline(node.id);
            return ListTile(
              leading: Icon(
                node.type == NodeType.mcsm ? Icons.dns : Icons.lan,
              ),
              title: Text(node.name),
              subtitle: Text(
                '${node.type.label} · ${node.address}${online ? '' : '（离线？仍可尝试）'}',
              ),
              onTap: () => _selectNode(node),
            );
          },
        ),
      );
    } else if (_daemons == null) {
      body = _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : _errorBody(theme, '获取节点信息失败');
    } else if (_instances == null) {
      body = SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _daemons!.length,
          itemBuilder: (context, index) {
            final daemon = _daemons![index];
            return ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(daemon.displayName),
              subtitle: Text(
                '${daemon.available ? '在线' : '离线'} · 运行 ${daemon.runningInstances}/${daemon.totalInstances}',
              ),
              onTap: () => _selectDaemon(daemon.uuid),
            );
          },
        ),
      );
    } else {
      // 步骤 3：选择实例
      body = _instances!.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '该守护进程下没有实例，请先在节点详情中创建实例。',
                style: theme.textTheme.bodySmall,
              ),
            )
          : SizedBox(
              width: 420,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _instances!.length,
                itemBuilder: (context, index) {
                  final instance = _instances![index];
                  return ListTile(
                    leading: const Icon(Icons.storage),
                    title: Text(
                      instance.config.nickname.isEmpty
                          ? instance.uuid
                          : instance.config.nickname,
                    ),
                    subtitle: Text(instance.config.cwd),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(InstallTarget.remote(
                      node: _node!,
                      client: _client!,
                      daemonId: _daemonId!,
                      instance: instance,
                    )),
                  );
                },
              ),
            );
    }

    return AlertDialog(
      title: Text(_title()),
      content: body,
      actions: [
        if (_node != null)
          TextButton(
            onPressed: () => setState(() {
              _node = null;
              _client = null;
              _daemons = null;
              _instances = null;
              _error = null;
            }),
            child: const Text('上一步'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  String? _daemonId;

  String _title() {
    if (_node == null) return '选择节点';
    if (_daemons == null) return '连接节点…';
    if (_instances == null) return '选择守护进程';
    return '选择节点实例';
  }

  Widget _errorBody(ThemeData theme, String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$_error\n$message',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _selectNode(_node!),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectNode(NodeInfo node) async {
    setState(() {
      _node = node;
      _client = NodeApiClient.of(node);
      _daemons = null;
      _instances = null;
      _loading = true;
      _error = null;
    });
    try {
      final overview = await _client!.overview();
      if (!mounted) return;
      setState(() {
        _daemons = overview.remote;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectDaemon(String daemonId) async {
    setState(() {
      _daemonId = daemonId;
      _instances = null;
      _loading = true;
      _error = null;
    });
    try {
      final instances = await _client!.listInstances(daemonId: daemonId);
      if (!mounted) return;
      setState(() {
        _instances = instances;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
}

/// 将本地文件上传安装到节点实例的目标目录（mods/ 或 plugins/）。
///
/// 上传完成后若文件名以 .zip 结尾，会在节点端解压到实例根目录。
Future<void> installFileToRemote({
  required InstallTarget target,
  required String localPath,
  required String subdir,
}) async {
  assert(target.isRemote);
  final client = target.client!;
  final daemonId = target.daemonId!;
  final uuid = target.remoteInstance!.uuid;
  final ticket = await client.uploadTicket(
    daemonId: daemonId,
    uuid: uuid,
    uploadDir: '/$subdir',
    timeout: _installLongTimeout,
  );
  await client.directUpload(
    ticket: ticket,
    localPath: localPath,
    timeout: _installLongTimeout,
  );
  final name = p.basename(localPath);
  if (name.toLowerCase().endsWith('.zip')) {
    // 压缩包上传在子目录内，解压到同一子目录并清理压缩包。
    await client.unzip(
      daemonId: daemonId,
      uuid: uuid,
      source: '/$subdir/$name',
      dest: '/$subdir',
      timeout: _installLongTimeout,
    );
    try {
      await client.deleteFiles(
        daemonId: daemonId,
        uuid: uuid,
        targets: ['/$subdir/$name'],
      );
    } catch (_) {
      // 清理失败不影响安装结果。
    }
  }
}
