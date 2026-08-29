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

import '../l10n/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    final service = await showAppDialog<McService>(
      context,
      (_) => const _ServiceDialog(),
    );
    if (service == null || !mounted) return;
    try {
      await OrchestratorService.instance.upsertService(service);
      _toast(l.clusterOrch_serviceCreated(service.name));
      await _refresh();
      unawaited(OrchestratorService.instance.tick());
    } catch (e) {
      _toast(l.clusterOrch_createFailed(e.toString()));
    }
  }

  Future<void> _updateService(McService service) async {
    final l = AppLocalizations.of(context);
    try {
      await OrchestratorService.instance.upsertService(service);
      await _refresh();
      unawaited(OrchestratorService.instance.tick());
    } catch (e) {
      _toast(l.clusterOrch_updateFailed(e.toString()));
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
    final l = AppLocalizations.of(context);
    final ok = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.clusterOrch_deleteService(service.name)),
        content: Text(l.clusterOrch_deleteServiceConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.common_cancel),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.common_delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await OrchestratorService.instance.deleteService(service.id);
      await _refresh();
    } catch (e) {
      _toast(l.clusterOrch_deleteFailed(e.toString()));
    }
  }

  /// 发起跨物理机迁移。
  Future<void> _migrate(ServiceStatus status) async {
    final l = AppLocalizations.of(context);
    final nodes = context.read<NodeState>().nodes;
    if (nodes.length < 2) {
      _toast(l.clusterOrch_migrateNeedTwoNodes);
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
      _toast(l.clusterOrch_migrationCreated);
      // 自动推进后续步骤（每步执行后回报）
      unawaited(_drainMigration(job));
      await _refresh();
    } catch (e) {
      _toast(l.clusterOrch_migrateFailed(e.toString()));
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
    final l = AppLocalizations.of(context);
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
              Text(l.clusterOrch_title, style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              // 长说明文案用 Expanded + 省略号，避免窄窗口下 RenderFlex overflow
              Expanded(
                child: Text(
                  l.clusterOrch_subtitle,
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
                tooltip: l.clusterOrch_reconcileNow,
                onPressed: () async {
                  await service.tick();
                  await _refresh();
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
                onPressed: _refresh,
              ),
              FilledButton.icon(
                onPressed: _createService,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.clusterOrch_newService),
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
                      Text(l.clusterOrch_noServices),
                      const SizedBox(height: 8),
                      Text(
                        l.clusterOrch_noServicesHint,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _createService,
                        icon: const Icon(Icons.add),
                        label: Text(l.clusterOrch_newService),
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
                      Text(l.clusterOrch_migrationTasks, style: theme.textTheme.titleSmall),
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
    final l = AppLocalizations.of(context);
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
                    isBastille
                        ? l.clusterOrch_runtimeBastille
                        : l.clusterOrch_runtimeDocker,
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
                  tooltip: l.clusterOrch_scaleDown,
                  onPressed: () => onScale(-1),
                ),
                // 副本/在线统计用 Flexible + 省略号，窄窗口不溢出
                Flexible(
                  child: Text(
                    l.clusterOrch_replicaStat(
                      status.replicas.length,
                      service.desiredReplicas,
                      status.totalPlayers,
                      status.avgPlayers.toStringAsFixed(1),
                    ),
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
                  tooltip: l.clusterOrch_scaleUp,
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
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'migrate',
                      child: Text(l.clusterOrch_migrateArchive),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(l.clusterOrch_deleteServiceMenuItem),
                    ),
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
                Text(l.clusterOrch_autoHeal, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 16),
                Switch(value: service.autoscale, onChanged: onToggleAutoscale),
                Text(l.clusterOrch_autoscale, style: const TextStyle(fontSize: 13)),
                if (service.autoscale) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l.clusterOrch_scaleTarget(
                        service.targetPlayers,
                        service.scaleDownPlayers,
                        service.scaleUpPlayers,
                      ),
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
    final l = AppLocalizations.of(context);
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
                ? l.clusterOrch_replicaPending(replica.indexNo)
                : 'r${replica.indexNo} · ${nodeName ?? replica.nodeId}',
            style: TextStyle(fontSize: 11, color: color),
          ),
          Text(
            pending
                ? l.clusterOrch_noSchedulableNode
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
    final l = AppLocalizations.of(context);
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
              tooltip: l.clusterOrch_continueMigration,
              onPressed: onContinue,
            ),
          if (onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: l.clusterOrch_cancelMigration,
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
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final image = _imageController.text.trim();
    if (name.isEmpty || image.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.clusterOrch_nameAndImageRequired)));
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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.clusterOrch_newServiceDialog),
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
                decoration: InputDecoration(
                  labelText: l.clusterOrch_serviceName,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _runtime,
                      decoration: InputDecoration(
                        labelText: l.clusterOrch_runtime,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'docker',
                          child: Text(l.clusterOrch_runtimeDockerLinux),
                        ),
                        DropdownMenuItem(
                          value: 'bastille',
                          child: Text(l.clusterOrch_runtimeBastilleFbsd),
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
                        labelText: l.clusterOrch_imageOrRelease,
                        hintText: _runtime == 'bastille'
                            ? l.clusterOrch_imageHintRelease
                            : l.clusterOrch_imageHintDocker,
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
                decoration: InputDecoration(
                  labelText: l.clusterOrch_portsMapping,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _volumesController,
                decoration: InputDecoration(
                  labelText: l.clusterOrch_volumeMount,
                  hintText: l.clusterOrch_volumeMountHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _worldDirController,
                decoration: InputDecoration(
                  labelText: l.clusterOrch_worldDir,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_runtime == 'bastille') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _bastilleIpController,
                  decoration: InputDecoration(
                    labelText: l.clusterOrch_bastilleIpBase,
                    isDense: true,
                    border: const OutlineInputBorder(),
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
                      decoration: InputDecoration(
                        labelText: l.clusterOrch_minReplicas,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _desiredController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.clusterOrch_desiredReplicas,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.clusterOrch_maxReplicas,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _autoscale,
                onChanged: (value) => setState(() => _autoscale = value),
                title: Text(
                  l.clusterOrch_autoscaleDesc,
                  style: const TextStyle(fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_autoscale)
                TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l.clusterOrch_targetPlayersPerReplica,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              SwitchListTile(
                value: _autoHeal,
                onChanged: (value) => setState(() => _autoHeal = value),
                title: Text(
                  l.clusterOrch_autoHealDesc,
                  style: const TextStyle(fontSize: 13),
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
          child: Text(l.common_cancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: Text(l.nodeDetail_create),
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
    final l = AppLocalizations.of(context);
    final candidates = widget.nodes
        .where((n) => n.id != (_replica?.nodeId ?? ''))
        .toList();
    return AlertDialog(
      title: Text(l.clusterOrch_migrateToPhysical),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<McReplica>(
              initialValue: _replica,
              decoration: InputDecoration(
                labelText: l.clusterOrch_replica,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final r in widget.status.replicas)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      r.running
                          ? l.clusterOrch_replicaRunning(r.indexNo, r.nodeId)
                          : 'r${r.indexNo} · ${r.nodeId}',
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
              decoration: InputDecoration(
                labelText: l.clusterOrch_targetNode,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final n in candidates)
                  DropdownMenuItem(value: n.id, child: Text(n.name)),
              ],
              onChanged: (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 8),
            Text(
              l.clusterOrch_migrateFlow,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: _replica == null || _target == null
              ? null
              : () => Navigator.pop(context, (
                  replica: _replica!,
                  target: _target!,
                )),
          child: Text(l.clusterOrch_startMigration),
        ),
      ],
    );
  }
}
