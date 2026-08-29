// 远程实例详情
// 单个远程实例（MCSM / 本地节点）的管理界面：
// - 控制：启动 / 停止 / 重启 / 强制终止 / 删除
// - 控制台：输出日志（轮询）+ 命令下发
// - 配置：只读展示 + 编辑（名称/启动命令/停止命令/工作目录/自动重启）
// - 文件：跳转到该实例的文件管理器

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/node.dart';
import '../models/remote.dart';
import '../services/container/node_container_backend.dart';
import '../services/font_settings.dart';
import '../services/node_api_client.dart';
import '../utils/ansi_color.dart';
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

  /// 控制台 WebSocket 连接（irix-node 实时日志流）。
  ///
  /// 连接失败（旧节点 / MCSM 面板）时为 null，回退到 outputlog 轮询。
  NodeConsoleConnection? _ws;
  StreamSubscription<NodeConsoleEvent>? _wsSub;
  bool _wsFailed = false; // WS 不可用，已永久回退轮询
  int? _lastLogMs; // 最后收到的输出行时间戳（WS since 补发用）

  @override
  void initState() {
    super.initState();
    _instance = widget.initialInstance;
    _load();
    _startConsole();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _ws?.close();
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

  /// 启动控制台：优先 WebSocket 实时流，失败回退 outputlog 轮询。
  void _startConsole() {
    if (_instance.status == RemoteStatus.stopped) return;
    _connectWs();
    // 即使 WS 异步连接中，也先起一个轮询作为兜底（WS 成功后会取消）。
    if (_ws == null) {
      _startPolling();
    }
  }

  /// 建立控制台 WebSocket；升级失败则回退轮询。
  Future<void> _connectWs() async {
    if (_wsFailed) return;
    try {
      final conn = await widget.client.connectConsoleWs(
        uuid: widget.initialInstance.uuid,
        daemonId: widget.daemonId,
        since: _lastLogMs == null ? null : '$_lastLogMs',
      );
      if (!mounted) {
        conn.close();
        return;
      }
      // 连接成功：取消轮询，改用 WS 流。
      _pollTimer?.cancel();
      _pollTimer = null;
      _ws = conn;
      _wsSub = conn.events.listen(
        (event) {
          if (!mounted) return;
          if (event is NodeConsoleExit) {
            _onInstanceExited();
            return;
          }
          if (event is NodeConsoleLine) {
            _appendLog(event.line);
          }
        },
        onError: (_) => _fallbackToPolling(),
        onDone: () => _fallbackToPolling(),
      );
    } on NodeConsoleUpgradeException {
      // 旧节点 / MCSM 面板：回退轮询，且不再尝试 WS。
      _wsFailed = true;
      if (mounted && _pollTimer == null) _startPolling();
    } catch (_) {
      // 其他连接错误：本次不降级为永久失败，后续 _action 会重试连接。
      if (mounted && _ws == null && _pollTimer == null) _startPolling();
    }
  }

  /// WS 断开后回退到轮询模式。
  void _fallbackToPolling() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    if (mounted && _pollTimer == null) _startPolling();
  }

  /// 实例进程退出（WS 退出通知或状态刷新检测到停止）。
  void _onInstanceExited() {
    if (!mounted) return;
    _fallbackToPolling();
    _load();
  }

  /// 追加一行日志（保留 ANSI），并在挂载后滚动到底部。
  void _appendLog(String line) {
    if (line.isEmpty) return;
    _lastLogMs ??= DateTime.now().millisecondsSinceEpoch;
    setState(() => _log = '$_log$line\n');
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// 轮询输出日志（每 2 秒，WS 不可用时的兜底）。
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
      // 保留整段轮询结果用于 since 补发（若后续升级到 WS）。
      if (_log.isNotEmpty) {
        _lastLogMs = DateTime.now().millisecondsSinceEpoch;
      }
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
      // 启动 / 停止会改实例运行态：重建控制台连接（停止后 WS 会退出通知，
      // 启动后旧连接已失效，统一重连以便新开 WS 或回退轮询）。
      if (action == RemoteAction.start || action == RemoteAction.stop) {
        _wsSub?.cancel();
        _wsSub = null;
        _ws?.close();
        _ws = null;
        _startConsole();
      }
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
    // WS 可用时直接走文本帧（实时回显），否则回退命令接口 + 轮询刷新。
    if (_ws != null) {
      _ws!.send(command);
      return;
    }
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
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteInstance_deleteTitle(_instance.config.nickname)),
        content: Text(l.remoteInstance_deleteContent),
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _instance.config.nickname.isEmpty
              ? l.instanceDetail_title
              : _instance.config.nickname,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.instanceDetail_deleteInstance,
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
                    tabs: [
                      Tab(icon: const Icon(Icons.terminal), text: l.remoteInstance_tabConsole),
                      Tab(icon: const Icon(Icons.settings_outlined), text: l.instanceDetail_tabConfig),
                      Tab(icon: const Icon(Icons.folder), text: l.instanceDetail_tabFiles),
                      Tab(icon: const Icon(Icons.extension), text: l.instanceDetail_tabPlugins),
                      Tab(icon: const Icon(Icons.backup), text: l.instanceDetail_tabBackup),
                      Tab(icon: const Icon(Icons.inventory_2), text: l.container_tabContainers),
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
      nodeClient: widget.client,
      daemonId: widget.daemonId,
    );
  }

  /// 头部：状态 + 控制按钮。
  Widget _buildHeader(ThemeData theme) {
    final l = AppLocalizations.of(context);
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
                      ? l.nodeDetail_cwdUnknown
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
                label: l.instanceDetail_start,
                color: Colors.green,
                enabled: status == RemoteStatus.stopped && !_busy,
                onPressed: () => _action(RemoteAction.start),
              ),
              _HeaderButton(
                icon: Icons.stop,
                label: l.instanceDetail_stop,
                color: Colors.orange,
                enabled: status.isActive && !_busy,
                onPressed: () => _action(RemoteAction.stop),
              ),
              _HeaderButton(
                icon: Icons.restart_alt,
                label: l.instanceDetail_restart,
                color: Colors.blue,
                enabled: status.isActive && !_busy,
                onPressed: () => _action(RemoteAction.restart),
              ),
              _HeaderButton(
                icon: Icons.power_settings_new,
                label: l.instanceDetail_forceStop,
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
    final l = AppLocalizations.of(context);
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
              child: SelectableText.rich(
                TextSpan(
                  children: _log.isEmpty
                      ? [TextSpan(text: l.remoteInstance_noLogOutput)]
                      : ansiSpans(
                          _log,
                          TextStyle(
                            fontFamily: FontSettings.instance.terminalFamily,
                            fontSize: 12,
                            color: Colors.greenAccent,
                          ),
                        ),
                ),
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
                    hintText: l.remoteInstance_commandInputHint,
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
                tooltip: l.remoteInstance_sendCommand,
                onPressed: _sendCommand,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.jailDetail_refreshLog,
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
    final l = AppLocalizations.of(context);
    final cfg = _instance.config;
    final rows = <(String, String)>[
      (l.remoteInstance_fInstanceId, _instance.uuid),
      (l.remoteInstance_fName, cfg.nickname),
      (l.remoteInstance_fStartCommand, cfg.startCommand.isEmpty ? '—' : cfg.startCommand),
      (l.remoteInstance_fStopCommand, cfg.stopCommand.isEmpty ? '—' : cfg.stopCommand),
      (l.remoteInstance_fWorkdir, cfg.cwd.isEmpty ? '—' : cfg.cwd),
      (l.remoteInstance_fType, cfg.type),
      (l.remoteInstance_fProcessType, cfg.processType),
      (l.remoteInstance_fFileEncoding, cfg.fileCode),
      (l.remoteInstance_fInputEncoding, cfg.ie),
      (l.remoteInstance_fOutputEncoding, cfg.oe),
      (l.remoteInstance_fAutoStart, cfg.autoStart ? l.common_enabled : l.common_disabled),
      (l.remoteInstance_fAutoRestart, cfg.autoRestart ? l.common_enabled : l.common_disabled),
      (l.remoteInstance_fStartCount, '${_instance.started}'),
      (l.remoteInstance_fPid, _instance.pid > 0 ? '${_instance.pid}' : '—'),
    ];
    if (cfg.processType == 'docker') {
      rows.addAll([
        (
          l.remoteInstance_fContainerName,
          cfg.docker.containerName.isEmpty ? '—' : cfg.docker.containerName,
        ),
        (l.remoteInstance_fImage, cfg.docker.image.isEmpty ? '—' : cfg.docker.image),
        (l.remoteInstance_fMemoryLimit, '${cfg.docker.memory} MB'),
        (l.remoteInstance_fPortMapping, cfg.docker.ports.isEmpty ? '—' : cfg.docker.ports.join(', ')),
        (
          l.remoteInstance_fExtraVolumes,
          cfg.docker.extraVolumes.isEmpty
              ? '—'
              : cfg.docker.extraVolumes.join(', '),
        ),
        (l.remoteInstance_fNetworkMode, cfg.docker.networkMode),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l.remoteInstance_editConfig),
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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.remoteInstance_editConfigDialog),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nickname,
                decoration: InputDecoration(
                  labelText: l.remoteInstance_fName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _startCommand,
                decoration: InputDecoration(
                  labelText: l.remoteInstance_fStartCommand,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stopCommand,
                decoration: InputDecoration(
                  labelText: l.remoteInstance_fStopCommand,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cwd,
                decoration: InputDecoration(
                  labelText: l.remoteInstance_fWorkdir,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l.remoteInstance_autoRestartToggle),
                value: _autoRestart,
                onChanged: (v) => setState(() => _autoRestart = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (widget.showDocker) ...[
                const Divider(),
                DropdownButtonFormField<String>(
                  initialValue: _processType,
                  decoration: InputDecoration(
                    labelText: l.remoteInstance_fProcessType,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'universal',
                      child: Text(l.remoteInstance_processUniversal),
                    ),
                    DropdownMenuItem(
                      value: 'docker',
                      child: Text(l.remoteInstance_processDocker),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _processType = v ?? 'universal'),
                ),
                if (_processType == 'docker') ..._buildDockerFields(theme, l),
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
          child: Text(l.common_save),
        ),
      ],
    );
  }

  /// Docker 配置字段（进程类型为 docker 时显示）。
  List<Widget> _buildDockerFields(ThemeData theme, AppLocalizations l) {
    return [
      const SizedBox(height: 12),
      TextField(
        controller: _dockerImage,
        decoration: InputDecoration(
          labelText: l.remoteInstance_dockerImage,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _dockerMemory,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.remoteInstance_memoryLimitMb,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _networkMode,
              decoration: InputDecoration(
                labelText: l.remoteInstance_fNetworkMode,
                border: const OutlineInputBorder(),
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
        decoration: InputDecoration(
          labelText: l.remoteInstance_portsMapping,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerVolumes,
        decoration: InputDecoration(
          labelText: l.remoteInstance_extraVolumes,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dockerContainerName,
        decoration: InputDecoration(
          labelText: l.remoteInstance_containerNameAuto,
          border: const OutlineInputBorder(),
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
