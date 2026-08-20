// 远程实例详情
// 单个远程实例（MCSM / 本地节点）的管理界面：
// - 控制：启动 / 停止 / 重启 / 强制终止 / 删除
// - 控制台：输出日志（轮询）+ 命令下发
// - 配置：只读展示 + 编辑（名称/启动命令/停止命令/工作目录/自动重启）
// - 文件：跳转到该实例的文件管理器

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/node.dart';
import '../models/remote.dart';
import '../services/container/node_container_backend.dart';
import '../services/node_api_client.dart';
import '../services/font_settings.dart';
import '../utils/apple_widgets.dart';
import '../utils/docker_visibility.dart';
import '../widgets/container_environment_panel.dart';
import 'node_detail_screen.dart' show remoteStatusChip;
import 'remote_file_manager_screen.dart';
import 'remote_plugins_backup_tabs.dart';

/// 远程实例详情页。
class RemoteInstanceDetailScreen extends StatefulWidget {
  const RemoteInstanceDetailScreen({
    super.key,
    required this.node,
    required this.client,
    required this.daemonId,
    required this.initialInstance,
    this.nodePlatform,
  });

  final NodeInfo node;
  final NodeApiClient client;
  final String daemonId;
  final RemoteInstance initialInstance;

  /// 节点平台（概览 system.platform），用于决定是否显示 Docker 设置。
  final String? nodePlatform;

  @override
  State<RemoteInstanceDetailScreen> createState() =>
      _RemoteInstanceDetailScreenState();
}

class _RemoteInstanceDetailScreenState
    extends State<RemoteInstanceDetailScreen> {
  late RemoteInstance _instance;
  String _log = '';
  bool _busy = false;
  String? _error;
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _instance = widget.initialInstance;
    _load();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final instance = await widget.client.getInstance(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
      );
      if (!mounted) return;
      setState(() {
        _instance = instance;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  /// 轮询输出日志（每 2 秒）。
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _instance.status == RemoteStatus.stopped) return;
      _fetchLog();
    });
  }

  Future<void> _fetchLog() async {
    try {
      final log = await widget.client.outputLog(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
        size: 512,
      );
      if (!mounted) return;
      setState(() => _log = log);
      // 保持滚动到底部
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    } catch (_) {
      // 轮询失败静默处理
    }
  }

  Future<void> _action(RemoteAction action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.instanceAction(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
        action: action,
      );
      await _load();
      await _fetchLog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) return;
    _commandController.clear();
    try {
      await widget.client.sendCommand(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
        command: command,
      );
      await _fetchLog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _editConfig() async {
    final cfg = _instance.config;
    final showDocker = shouldShowDockerSettings(
      nodePlatform: widget.nodePlatform,
    );
    final result = await showAppDialog<_ConfigEditResult?>(
      context,
      (_) => _ConfigEditDialog(cfg: cfg, showDocker: showDocker),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.updateInstance(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
        config: InstanceConfig(
          nickname: result.nickname,
          startCommand: result.startCommand,
          stopCommand: result.stopCommand,
          cwd: result.cwd,
          autoRestart: result.autoRestart,
          type: cfg.type,
          processType: result.processType,
          fileCode: cfg.fileCode,
          ie: cfg.ie,
          oe: cfg.oe,
          tag: cfg.tag,
          docker: result.docker,
          createDatetime: cfg.createDatetime,
        ).toJson(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text('删除实例「${_instance.config.nickname}」？'),
        content: const Text('同时删除实例文件需要面板 API 权限支持。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteInstances(
        uuids: [widget.initialInstance.uuid],
        daemonId: widget.daemonId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _instance.config.nickname.isEmpty
              ? '实例详情'
              : _instance.config.nickname,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除实例',
            onPressed: _busy ? null : _delete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(theme),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: 6,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(icon: Icon(Icons.terminal), text: '控制台'),
                      Tab(icon: Icon(Icons.settings_outlined), text: '配置'),
                      Tab(icon: Icon(Icons.folder), text: '文件'),
                      Tab(icon: Icon(Icons.extension), text: '插件/Mod'),
                      Tab(icon: Icon(Icons.backup), text: '备份'),
                      Tab(icon: Icon(Icons.inventory_2), text: '容器'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildConsole(theme),
                        _buildConfig(theme),
                        RemoteFileManagerScreen(
                          client: widget.client,
                          daemonId: widget.daemonId,
                          initialUuid: widget.initialInstance.uuid,
                          embedded: true,
                        ),
                        RemotePluginsTab(
                          client: widget.client,
                          daemonId: widget.daemonId,
                          uuid: widget.initialInstance.uuid,
                        ),
                        RemoteBackupTab(
                          client: widget.client,
                          daemonId: widget.daemonId,
                          uuid: widget.initialInstance.uuid,
                          nickname: _instance.config.nickname,
                        ),
                        _buildContainerTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 容器 Tab：该节点容器环境的全功能管理（Docker / Bastille 按节点平台）。
  Widget _buildContainerTab() {
    final backend = nodeContainerBackend(
      client: widget.client,
      daemonId: widget.daemonId,
      platformHint: widget.nodePlatform,
    );
    // 实例以 Docker 方式运行时高亮其容器。
    final docker = _instance.config.docker;
    final highlightName =
        _instance.config.processType == 'docker' &&
            docker.containerName.isNotEmpty
        ? docker.containerName
        : null;
    return ContainerEnvironmentPanel(
      backend: backend,
      highlightName: highlightName,
    );
  }

  /// 头部：状态 + 控制按钮。
  Widget _buildHeader(ThemeData theme) {
    final status = _instance.status;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              remoteStatusChip(context, status),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _instance.config.cwd.isEmpty
                      ? '工作目录未知'
                      : _instance.config.cwd,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _HeaderButton(
                icon: Icons.play_arrow,
                label: '启动',
                color: Colors.green,
                enabled: status == RemoteStatus.stopped && !_busy,
                onPressed: () => _action(RemoteAction.start),
              ),
              _HeaderButton(
                icon: Icons.stop,
                label: '停止',
                color: Colors.orange,
                enabled: status.isActive && !_busy,
                onPressed: () => _action(RemoteAction.stop),
              ),
              _HeaderButton(
                icon: Icons.restart_alt,
                label: '重启',
                color: Colors.blue,
                enabled: status.isActive && !_busy,
                onPressed: () => _action(RemoteAction.restart),
              ),
              _HeaderButton(
                icon: Icons.power_settings_new,
                label: '强制终止',
                color: Colors.red,
                enabled: status.isActive && !_busy,
                onPressed: () => _action(RemoteAction.kill),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 控制台。
  Widget _buildConsole(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SelectableText(
                _log.isEmpty ? '（暂无日志输出）' : _log,
                style: TextStyle(
                  fontFamily: FontSettings.instance.terminalFamily,
                  fontSize: 12,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    hintText: '输入命令（如 say hello），回车发送',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendCommand(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                tooltip: '发送命令',
                onPressed: _sendCommand,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新日志',
                onPressed: _fetchLog,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 配置信息。
  Widget _buildConfig(ThemeData theme) {
    final cfg = _instance.config;
    final rows = <(String, String)>[
      ('实例 ID', _instance.uuid),
      ('名称', cfg.nickname),
      ('启动命令', cfg.startCommand.isEmpty ? '—' : cfg.startCommand),
      ('停止命令', cfg.stopCommand.isEmpty ? '—' : cfg.stopCommand),
      ('工作目录', cfg.cwd.isEmpty ? '—' : cfg.cwd),
      ('类型', cfg.type),
      ('进程类型', cfg.processType),
      ('文件编码', cfg.fileCode),
      ('输入编码', cfg.ie),
      ('输出编码', cfg.oe),
      ('自动启动', cfg.autoStart ? '是' : '否'),
      ('自动重启', cfg.autoRestart ? '是' : '否'),
      ('启动次数', '${_instance.started}'),
      ('进程 PID', _instance.pid > 0 ? '${_instance.pid}' : '—'),
    ];
    if (cfg.processType == 'docker') {
      rows.addAll([
        (
          '容器名称',
          cfg.docker.containerName.isEmpty ? '—' : cfg.docker.containerName,
        ),
        ('镜像', cfg.docker.image.isEmpty ? '—' : cfg.docker.image),
        ('内存限制', '${cfg.docker.memory} MB'),
        ('端口映射', cfg.docker.ports.isEmpty ? '—' : cfg.docker.ports.join(', ')),
        (
          '额外挂载卷',
          cfg.docker.extraVolumes.isEmpty
              ? '—'
              : cfg.docker.extraVolumes.join(', '),
        ),
        ('网络模式', cfg.docker.networkMode),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑配置'),
            onPressed: _busy ? null : _editConfig,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final (key, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            key,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(value, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 头部操作按钮。
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        foregroundColor: enabled ? color : null,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}

/// 配置编辑结果。
class _ConfigEditResult {
  final String nickname;
  final String startCommand;
  final String stopCommand;
  final String cwd;
  final bool autoRestart;
  final String processType;
  final InstanceDockerConfig docker;

  const _ConfigEditResult({
    required this.nickname,
    required this.startCommand,
    required this.stopCommand,
    required this.cwd,
    required this.autoRestart,
    required this.processType,
    required this.docker,
  });
}

/// 配置编辑对话框。
///
/// [showDocker] 为 false 时不显示进程类型与 Docker 配置
/// （客户端 Windows + 节点 Windows 的情况，见 shouldShowDockerSettings）。
class _ConfigEditDialog extends StatefulWidget {
  const _ConfigEditDialog({required this.cfg, required this.showDocker});

  final InstanceConfig cfg;
  final bool showDocker;

  @override
  State<_ConfigEditDialog> createState() => _ConfigEditDialogState();
}

class _ConfigEditDialogState extends State<_ConfigEditDialog> {
  late final TextEditingController _nickname;
  late final TextEditingController _startCommand;
  late final TextEditingController _stopCommand;
  late final TextEditingController _cwd;
  late bool _autoRestart;

  // Docker 配置
  late String _processType;
  late final TextEditingController _dockerImage;
  late final TextEditingController _dockerMemory;
  late final TextEditingController _dockerPorts;
  late final TextEditingController _dockerVolumes;
  late final TextEditingController _dockerContainerName;
  late String _networkMode;

  @override
  void initState() {
    super.initState();
    final docker = widget.cfg.docker;
    _nickname = TextEditingController(text: widget.cfg.nickname);
    _startCommand = TextEditingController(text: widget.cfg.startCommand);
    _stopCommand = TextEditingController(text: widget.cfg.stopCommand);
    _cwd = TextEditingController(text: widget.cfg.cwd);
    _autoRestart = widget.cfg.autoRestart;
    _processType = widget.cfg.processType;
    _dockerImage = TextEditingController(text: docker.image);
    _dockerMemory = TextEditingController(text: '${docker.memory}');
    _dockerPorts = TextEditingController(text: docker.ports.join(', '));
    _dockerVolumes = TextEditingController(
      text: docker.extraVolumes.join(', '),
    );
    _dockerContainerName = TextEditingController(text: docker.containerName);
    _networkMode = docker.networkMode;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _startCommand.dispose();
    _stopCommand.dispose();
    _cwd.dispose();
    _dockerImage.dispose();
    _dockerMemory.dispose();
    _dockerPorts.dispose();
    _dockerVolumes.dispose();
    _dockerContainerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('编辑实例配置'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nickname,
                decoration: const InputDecoration(
                  labelText: '实例名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _startCommand,
                decoration: const InputDecoration(
                  labelText: '启动命令',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stopCommand,
                decoration: const InputDecoration(
                  labelText: '停止命令',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cwd,
                decoration: const InputDecoration(
                  labelText: '工作目录',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('崩溃后自动重启'),
                value: _autoRestart,
                onChanged: (v) => setState(() => _autoRestart = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.showDocker) ...[
                const Divider(),
                DropdownButtonFormField<String>(
                  initialValue: _processType,
                  decoration: const InputDecoration(
                    labelText: '进程类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'universal',
                      child: Text('通用（直接运行进程）'),
                    ),
                    DropdownMenuItem(
                      value: 'docker',
                      child: Text('Docker（容器内运行）'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _processType = v ?? 'universal'),
                ),
                if (_processType == 'docker') ..._buildDockerFields(theme),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _ConfigEditResult(
                nickname: _nickname.text.trim(),
                startCommand: _startCommand.text.trim(),
                stopCommand: _stopCommand.text.trim(),
                cwd: _cwd.text.trim(),
                autoRestart: _autoRestart,
                processType: _processType,
                docker: _buildDockerConfig(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// Docker 配置字段（进程类型为 docker 时显示）。
  List<Widget> _buildDockerFields(ThemeData theme) {
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _dockerImage,
        decoration: const InputDecoration(
          labelText: 'Docker 镜像（如 mcsm-ubuntu:22.04）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _dockerMemory,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '内存限制（MB）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _networkMode,
              decoration: const InputDecoration(
                labelText: '网络模式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'bridge', child: Text('bridge')),
                DropdownMenuItem(value: 'host', child: Text('host')),
                DropdownMenuItem(value: 'none', child: Text('none')),
              ],
              onChanged: (v) => setState(() => _networkMode = v ?? 'bridge'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerPorts,
        decoration: const InputDecoration(
          labelText: '端口映射（逗号分隔，如 25565:25565/tcp）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerVolumes,
        decoration: const InputDecoration(
          labelText: '额外挂载卷（逗号分隔，如 /data:/data）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerContainerName,
        decoration: const InputDecoration(
          labelText: '容器名称（可留空自动生成）',
          border: OutlineInputBorder(),
        ),
      ),
    ];
  }

  InstanceDockerConfig _buildDockerConfig() {
    List<String> split(String value) => value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return InstanceDockerConfig(
      containerName: _dockerContainerName.text.trim(),
      image: _dockerImage.text.trim().isEmpty
          ? 'mcsm-ubuntu:22.04'
          : _dockerImage.text.trim(),
      memory: int.tryParse(_dockerMemory.text.trim()) ?? 1024,
      ports: split(_dockerPorts.text),
      extraVolumes: split(_dockerVolumes.text),
      networkMode: _networkMode,
    );
  }
}

extension on RemoteStatus {
  bool get isActive =>
      this == RemoteStatus.running ||
      this == RemoteStatus.starting ||
      this == RemoteStatus.stopping;
}
