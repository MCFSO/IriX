// 集群编排管理页（多机模式「编排」导航项，K8s 风格控制平面 UI）
//
// 展示 MC 服务组（Deployment）与副本（Pod）状态，提供：
// - 崩溃自动修复 / 弹性开服开关（期望状态编辑）
// - 手动扩缩容、跨物理机迁移存档、删除服务
// - 迁移任务进度与失败重试
//
// 决策全部由 Rust xmc_orchestrator 引擎完成，本页只做展示与下发。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/node.dart';
import '../models/orchestration.dart';
import '../services/orchestrator_service.dart';
import '../state/cluster_state.dart';
import '../state/node_state.dart';
import '../utils/apple_widgets.dart';

/// 集群编排管理页。
class ClusterOrchestrationScreen extends StatefulWidget {
  const ClusterOrchestrationScreen({super.key});

  @override
  State<ClusterOrchestrationScreen> createState() =>
      _ClusterOrchestrationScreenState();
}

class _ClusterOrchestrationScreenState
    extends State<ClusterOrchestrationScreen> {
  List<ServiceStatus> _statuses = [];
  List<MigrationJob> _migrations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = OrchestratorService.instance;
      service.attach(
        nodeState: context.read<NodeState>(),
        clusterState: context.read<ClusterState>(),
      );
      service.startTicking();
      _refresh();
    });
  }

  @override
  void dispose() {
    OrchestratorService.instance.stopTicking();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final statuses = await OrchestratorService.instance.status();
      final migrations = await OrchestratorService.instance.listMigrations();
      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _migrations = migrations;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ======================== 服务操作 ========================

  Future<void> _createService() async {
    final service = await showAppDialog<McService>(
      context,
      (_) => const _ServiceDialog(),
    );
    if (service == null || !mounted) return;
    try {
      await OrchestratorService.instance.upsertService(service);
      _toast('服务已创建：${service.name}');
      await _refresh();
      unawaited(OrchestratorService.instance.tick());
    } catch (e) {
      _toast('创建失败：$e');
    }
  }

  Future<void> _updateService(McService service) async {
    try {
      await OrchestratorService.instance.upsertService(service);
      await _refresh();
      unawaited(OrchestratorService.instance.tick());
    } catch (e) {
      _toast('更新失败：$e');
    }
  }

  /// 手动扩缩容（期望副本数 ±1）。
  Future<void> _scale(McService service, int delta) async {
    final desired = (service.desiredReplicas + delta).clamp(
      service.minReplicas,
      service.maxReplicas,
    );
    if (desired == service.desiredReplicas) return;
    await _updateService(_copyWith(service, desiredReplicas: desired));
  }

  Future<void> _toggleAutoscale(McService service, bool value) =>
      _updateService(_copyWith(service, autoscale: value));

  Future<void> _toggleAutoHeal(McService service, bool value) =>
      _updateService(_copyWith(service, autoHeal: value));

  Future<void> _deleteService(McService service) async {
    final ok = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除服务 ${service.name}'),
        content: const Text('将销毁该服务的全部副本（容器 / jail），确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await OrchestratorService.instance.deleteService(service.id);
      await _refresh();
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  /// 发起跨物理机迁移。
  Future<void> _migrate(ServiceStatus status) async {
    final nodes = context.read<NodeState>().nodes;
    if (nodes.length < 2) {
      _toast('迁移需要至少 2 个节点');
      return;
    }
    final replicas = status.replicas;
    if (replicas.isEmpty) return;
    final result = await showAppDialog<({McReplica replica, String target})>(
      context,
      (_) => _MigrateDialog(status: status, nodes: nodes),
    );
    if (result == null || !mounted) return;
    try {
      final job = await OrchestratorService.instance.migrateStart(
        serviceId: status.service.id,
        replicaId: result.replica.id,
        toNode: result.target,
      );
      _toast('迁移任务已创建');
      // 自动推进后续步骤（每步执行后回报）
      unawaited(_drainMigration(job));
      await _refresh();
    } catch (e) {
      _toast('迁移失败：$e');
    }
  }

  /// 逐步执行迁移任务直到完成 / 失败。
  Future<void> _drainMigration(MigrationJob job) async {
    var current = job;
    while (current.state.isActive && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        current = await OrchestratorService.instance.runMigrationStep(current);
      } catch (e) {
        debugPrint('迁移步骤失败: $e');
        break;
      }
    }
    if (mounted) await _refresh();
  }

  Future<void> _cancelMigration(MigrationJob job) async {
    await OrchestratorService.instance.migrateCancel(job.id);
    await _refresh();
  }

  McService _copyWith(
    McService service, {
    int? desiredReplicas,
    bool? autoscale,
    bool? autoHeal,
  }) {
    final json = service.toJson();
    if (desiredReplicas != null) json['desiredReplicas'] = desiredReplicas;
    if (autoscale != null) json['autoscale'] = autoscale;
    if (autoHeal != null) json['autoHeal'] = autoHeal;
    return McService.fromJson(json);
  }

  // ======================== UI ========================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = OrchestratorService.instance;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Text('编排服务', style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              // 长说明文案用 Expanded + 省略号，避免窄窗口下 RenderFlex overflow
              Expanded(
                child: Text(
                  'K8s 风格：自动修复崩溃 · 按在线人数弹性开服 · 跨物理机迁移存档',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              if (service.lastError != null)
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: '立即对账',
                onPressed: () async {
                  await service.tick();
                  await _refresh();
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refresh,
              ),
              FilledButton.icon(
                onPressed: _createService,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建服务'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _statuses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.dashboard_customize_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      const Text('还没有编排服务'),
                      const SizedBox(height: 8),
                      const Text(
                        '新建服务后，引擎将自动调度副本到 Docker / Bastille 节点',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createService,
                        icon: const Icon(Icons.add),
                        label: const Text('新建服务'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final status in _statuses)
                      _ServiceCard(
                        status: status,
                        nodeNames: {
                          for (final n in context.read<NodeState>().nodes)
                            n.id: n.name,
                        },
                        onScale: (delta) => _scale(status.service, delta),
                        onToggleAutoscale: (value) =>
                            _toggleAutoscale(status.service, value),
                        onToggleAutoHeal: (value) =>
                            _toggleAutoHeal(status.service, value),
                        onMigrate: () => _migrate(status),
                        onDelete: () => _deleteService(status.service),
                      ),
                    if (_migrations.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('迁移任务', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      for (final job in _migrations)
                        _MigrationTile(
                          job: job,
                          onContinue: job.state.isActive
                              ? () => _drainMigration(job)
                              : null,
                          onCancel: job.state.isActive
                              ? () => _cancelMigration(job)
                              : null,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// 服务卡片（Deployment 视图）。
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.status,
    required this.nodeNames,
    required this.onScale,
    required this.onToggleAutoscale,
    required this.onToggleAutoHeal,
    required this.onMigrate,
    required this.onDelete,
  });

  final ServiceStatus status;
  final Map<String, String> nodeNames;
  final void Function(int delta) onScale;
  final void Function(bool) onToggleAutoscale;
  final void Function(bool) onToggleAutoHeal;
  final VoidCallback onMigrate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = status.service;
    final isBastille = service.runtime == 'bastille';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(service.name, style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (isBastille ? Colors.redAccent : Colors.lightBlue)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isBastille ? 'Bastille' : 'Docker',
                    style: TextStyle(
                      fontSize: 11,
                      color: isBastille ? Colors.redAccent : Colors.lightBlue,
                    ),
                  ),
                ),
                if (status.migrating) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.sync, size: 14, color: Colors.amber),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: '缩容',
                  onPressed: () => onScale(-1),
                ),
                // 副本/在线统计用 Flexible + 省略号，窄窗口不溢出
                Flexible(
                  child: Text(
                    '${status.replicas.length}/${service.desiredReplicas} 副本'
                    ' · 在线 ${status.totalPlayers}（均 ${status.avgPlayers.toStringAsFixed(1)}）',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '扩容',
                  onPressed: () => onScale(1),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'migrate':
                        onMigrate();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'migrate', child: Text('迁移存档到其它节点')),
                    PopupMenuItem(value: 'delete', child: Text('删除服务')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${service.image} · ${service.ports.join(', ')}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(value: service.autoHeal, onChanged: onToggleAutoHeal),
                const Text('自动修复崩溃', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 16),
                Switch(value: service.autoscale, onChanged: onToggleAutoscale),
                const Text('弹性开服', style: TextStyle(fontSize: 13)),
                if (service.autoscale) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '目标 ${service.targetPlayers}/副本 · 阈值 ${service.scaleDownPlayers}~${service.scaleUpPlayers}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final replica in status.replicas)
                  _ReplicaChip(
                    replica: replica,
                    nodeName: nodeNames[replica.nodeId],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 副本状态块（Pod 视图）。
class _ReplicaChip extends StatelessWidget {
  const _ReplicaChip({required this.replica, this.nodeName});

  final McReplica replica;
  final String? nodeName;

  @override
  Widget build(BuildContext context) {
    final running = replica.running;
    final color = replica.crashLoop
        ? Colors.red
        : running
        ? Colors.green
        : Colors.grey;
    final pending = replica.nodeId.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pending
                ? 'r${replica.indexNo} · 待调度'
                : 'r${replica.indexNo} · ${nodeName ?? replica.nodeId}',
            style: TextStyle(fontSize: 11, color: color),
          ),
          Text(
            pending
                ? '无满足条件的节点'
                : '${replica.containerName}\n'
                      '在线 ${replica.playersOnline}'
                      '${replica.crashCount > 0 ? ' · 崩溃 ${replica.crashCount}' : ''}'
                      '${replica.crashLoop ? ' · BackOff' : ''}'
                      '${replica.hostPort != null ? ' · :${replica.hostPort}' : ''}',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

/// 迁移任务行。
class _MigrationTile extends StatelessWidget {
  const _MigrationTile({required this.job, this.onContinue, this.onCancel});

  final MigrationJob job;
  final VoidCallback? onContinue;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final done = job.state == MigrationState.done;
    final failed = job.state == MigrationState.failed;
    final color = done
        ? Colors.green
        : failed
        ? Colors.red
        : Colors.amber;
    return ListTile(
      dense: true,
      leading: Icon(Icons.swap_horiz, size: 20, color: color),
      title: Text(
        '${job.replicaId}：${job.fromNode} → ${job.toNode}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${job.state.label}'
        '${job.error != null ? ' · ${job.error}' : ''}',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onContinue != null)
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              tooltip: '继续执行',
              onPressed: onContinue,
            ),
          if (onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: '取消迁移',
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}

/// 新建服务对话框（期望状态编辑）。
class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog();

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _nameController = TextEditingController();
  final _imageController = TextEditingController();
  final _portsController = TextEditingController(text: '25565:25565');
  final _volumesController = TextEditingController();
  final _worldDirController = TextEditingController(text: '/data/world');
  final _desiredController = TextEditingController(text: '1');
  final _minController = TextEditingController(text: '0');
  final _maxController = TextEditingController(text: '4');
  final _targetController = TextEditingController(text: '20');
  final _bastilleIpController = TextEditingController(text: '192.168.1.50');
  String _runtime = 'docker';
  bool _autoscale = false;
  bool _autoHeal = true;

  @override
  void dispose() {
    _nameController.dispose();
    _imageController.dispose();
    _portsController.dispose();
    _volumesController.dispose();
    _worldDirController.dispose();
    _desiredController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _targetController.dispose();
    _bastilleIpController.dispose();
    super.dispose();
  }

  List<String> _splitList(String text) => text
      .split(RegExp(r'[\n,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _submit() {
    final name = _nameController.text.trim();
    final image = _imageController.text.trim();
    if (name.isEmpty || image.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('名称与镜像 / 发行版不能为空')));
      return;
    }
    final target = int.tryParse(_targetController.text.trim()) ?? 20;
    final service = McService(
      id: 'svc-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name,
      runtime: _runtime,
      image: image,
      ports: _splitList(_portsController.text),
      volumes: _splitList(_volumesController.text),
      worldDir: _worldDirController.text.trim().isEmpty
          ? '/data/world'
          : _worldDirController.text.trim(),
      desiredReplicas: int.tryParse(_desiredController.text.trim()) ?? 1,
      minReplicas: int.tryParse(_minController.text.trim()) ?? 0,
      maxReplicas: int.tryParse(_maxController.text.trim()) ?? 4,
      autoscale: _autoscale,
      targetPlayers: target,
      scaleUpPlayers: target,
      scaleDownPlayers: (target / 2).round().clamp(1, target),
      autoHeal: _autoHeal,
      bastilleIpBase: _runtime == 'bastille'
          ? (_bastilleIpController.text.trim().isEmpty
                ? null
                : _bastilleIpController.text.trim())
          : null,
      jailType: _runtime == 'bastille' ? 'thin' : null,
      vnetMode: _runtime == 'bastille' ? 'none' : null,
    );
    Navigator.pop(context, service);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建编排服务'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '服务名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _runtime,
                      decoration: const InputDecoration(
                        labelText: '运行时',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'docker',
                          child: Text('Docker（Linux 节点）'),
                        ),
                        DropdownMenuItem(
                          value: 'bastille',
                          child: Text('Bastille（FreeBSD 节点）'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _runtime = value ?? 'docker'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _imageController,
                      decoration: InputDecoration(
                        labelText: '镜像 / 发行版',
                        hintText: _runtime == 'bastille'
                            ? '如 14.2-RELEASE'
                            : '如 itzg/minecraft-server:latest',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portsController,
                decoration: const InputDecoration(
                  labelText: '端口映射（扩容时宿主端口按序号顺延）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _volumesController,
                decoration: const InputDecoration(
                  labelText: '数据目录挂载（宿主机:容器内）',
                  hintText: '如 /data/mc-survival:/data',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _worldDirController,
                decoration: const InputDecoration(
                  labelText: '世界存档目录（容器内，迁移对象）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_runtime == 'bastille') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _bastilleIpController,
                  decoration: const InputDecoration(
                    labelText: 'IP 基址（副本按序号顺延，如 .50 → .51）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最小副本',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _desiredController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '期望副本',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最大副本',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _autoscale,
                onChanged: (value) => setState(() => _autoscale = value),
                title: const Text(
                  '弹性开服（按在线人数扩缩容）',
                  style: TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_autoscale)
                TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每副本目标在线人数',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              SwitchListTile(
                value: _autoHeal,
                onChanged: (value) => setState(() => _autoHeal = value),
                title: const Text(
                  '自动修复崩溃（指数退避重启）',
                  style: TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: const Text('创建'),
        ),
      ],
    );
  }
}

/// 迁移对话框：选副本 + 目标节点。
class _MigrateDialog extends StatefulWidget {
  const _MigrateDialog({required this.status, required this.nodes});

  final ServiceStatus status;
  final List<NodeInfo> nodes;

  @override
  State<_MigrateDialog> createState() => _MigrateDialogState();
}

class _MigrateDialogState extends State<_MigrateDialog> {
  McReplica? _replica;
  String? _target;

  @override
  void initState() {
    super.initState();
    _replica = widget.status.replicas.firstOrNull;
    if (_replica != null) {
      _target = widget.nodes
          .where((n) => n.id != _replica!.nodeId)
          .firstOrNull
          ?.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.nodes
        .where((n) => n.id != (_replica?.nodeId ?? ''))
        .toList();
    return AlertDialog(
      title: const Text('迁移存档到其它物理机'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<McReplica>(
              initialValue: _replica,
              decoration: const InputDecoration(
                labelText: '副本',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final r in widget.status.replicas)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      'r${r.indexNo} · ${r.nodeId}'
                      '${r.running ? '（运行中）' : ''}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _replica = value;
                _target = candidates
                    .where((n) => n.id != value?.nodeId)
                    .firstOrNull
                    ?.id;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _target,
              decoration: const InputDecoration(
                labelText: '目标节点',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final n in candidates)
                  DropdownMenuItem(value: n.id, child: Text(n.name)),
              ],
              onChanged: (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 8),
            Text(
              '迁移流程：停止副本 → 压缩世界存档 → 传输 → 目标节点恢复 → 重建并启动。',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _replica == null || _target == null
              ? null
              : () => Navigator.pop(context, (
                  replica: _replica!,
                  target: _target!,
                )),
          child: const Text('开始迁移'),
        ),
      ],
    );
  }
}
