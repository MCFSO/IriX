// 实例详情页
// 顶部导航栏（含 TabBar）+ 左右两栏：左侧日志控制台 + 命令输入框；右侧生命周期控制按钮。
// 第二个 Tab 为配置文件编辑器。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/server_instance.dart';
import '../services/ai_assistant_service.dart';
import '../services/backup_ffi.dart';
import '../services/backup_settings.dart';
import '../services/background_tasks.dart';
import '../services/font_settings.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';
import '../widgets/container_environment_panel.dart';
import 'ai_screen.dart';
import 'config_editor_screen.dart';
import 'file_manager_screen.dart';
import 'plugins_tab.dart';

/// 实例详情页。
///
/// 布局：顶部导航栏 + 左右两栏。
/// - 左侧：终端风格日志窗口（实时滚动、带时间戳）+ 单行命令输入框（回车发送到 stdin）。
/// - 右侧：启动 / 重启 / 停止·强制停止 按钮，按状态动态启用/禁用与切换样式。
///
/// 停止按钮点击后立即变为「强制停止」，在关闭流程期间及已关闭后均可点击，
/// 下次启动前恢复为「停止」。
class InstanceDetailScreen extends StatefulWidget {
  const InstanceDetailScreen({super.key, required this.instanceId});

  /// 所查看实例的唯一标识。
  final String instanceId;

  @override
  State<InstanceDetailScreen> createState() => _InstanceDetailScreenState();
}

class _InstanceDetailScreenState extends State<InstanceDetailScreen> {
  /// 日志滚动控制器，用于自动滚动到底部。
  final ScrollController _scrollController = ScrollController();

  /// 命令输入框控制器。
  final TextEditingController _commandController = TextEditingController();

  /// 焦点节点，用于输入后重新聚焦。
  final FocusNode _focusNode = FocusNode();

  /// 日志行缓存。
  final List<String> _logs = [];

  /// 日志流订阅。
  StreamSubscription<String>? _logSub;

  /// 是否已点击停止（用于切换「强制停止」按钮样式）。
  ///
  /// 点击「停止」或「重启」触发 stop 指令后置为 true，
  /// 进程下次启动时（状态变为 starting/running）重置为 false。
  bool _stopClicked = false;

  /// 后台文件任务管理器。
  final BackgroundTaskManager _taskManager = BackgroundTaskManager();

  /// 右侧 AI 侧栏是否展开。
  bool _showAi = false;

  /// AI 侧栏的会话状态（页面打开期间保持，收起再展开不丢失）。
  late final AiChatController _aiController;

  /// 本机 Docker 是否可用（决定「设置」Tab 中「Docker 容器」运行方式是否可选；
  /// 「容器」Tab 始终展示，不可用时面板呈现原因与重新检测按钮）。
  bool _dockerAvailable = false;

  /// 是否正在探测 Docker 环境。
  bool _dockerProbing = true;

  @override
  void initState() {
    super.initState();
    _aiController = AiChatController(
      conversation: AiAssistantService.instance.createConversation(),
    );
    _subscribeLogs();
    context.read<AppState>().addListener(_onAppStateChanged);
    _probeDocker();
  }

  /// 探测本机 Docker 可用性（AppState 缓存了探测结果）。
  Future<void> _probeDocker() async {
    final env = await context.read<AppState>().dockerEnvironment();
    if (!mounted) return;
    setState(() {
      _dockerAvailable = env.available;
      _dockerProbing = false;
    });
  }

  @override
  void didUpdateWidget(InstanceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 若实例 id 变化则重新订阅日志。
    if (oldWidget.instanceId != widget.instanceId) {
      _logSub?.cancel();
      _logs.clear();
      _subscribeLogs();
    }
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_onAppStateChanged);
    _aiController.dispose();
    _logSub?.cancel();
    _scrollController.dispose();
    _commandController.dispose();
    _focusNode.dispose();
    _taskManager.dispose();
    super.dispose();
  }

  /// 订阅当前实例的日志流。
  void _subscribeLogs() {
    final state = context.read<AppState>();
    final stream = state.logsFor(widget.instanceId);
    if (stream == null) return;
    // 避免重复订阅：若已有活跃订阅则不重复建立。
    if (_logSub != null) return;
    _logSub = stream.listen((line) {
      if (!mounted) return;
      setState(() {
        _logs.add(line);
        // 限制日志缓存长度，避免内存无限增长。
        if (_logs.length > 2000) {
          _logs.removeRange(0, _logs.length - 2000);
        }
      });
      // 自动滚动到底部。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final state = context.read<AppState>();
    final instance = state.instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    if (instance == null) return;
    final status = instance.status;

    if (status == InstanceStatus.starting || status == InstanceStatus.stopped) {
      _stopClicked = false;
    }

    if (status.isActive && _logSub == null) {
      _subscribeLogs();
    }

    if (status == InstanceStatus.stopped && _logSub != null) {
      _logSub!.cancel();
      _logSub = null;
    }
  }

  /// 发送命令到服务器进程。
  void _sendCommand() {
    final text = _commandController.text.trim();
    if (text.isEmpty) return;
    context.read<AppState>().sendCommand(widget.instanceId, text);
    _commandController.clear();
    _focusNode.requestFocus();
  }

  /// 启动实例，失败时通过 SnackBar 提示错误。
  Future<void> _startInstance() async {
    try {
      await context.read<AppState>().startInstance(widget.instanceId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('启动失败：$e')));
    }
  }

  /// 重启实例，失败时通过 SnackBar 提示错误。
  Future<void> _restartInstance() async {
    try {
      await context.read<AppState>().restartInstance(widget.instanceId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重启失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final instance = state.instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    if (instance == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('实例详情')),
        body: const Center(child: Text('实例不存在')),
      );
    }

    // 「容器」Tab 始终展示：本机无 Docker 时面板呈现不可用状态与检测按钮，
    // 避免用户完全看不到容器管理入口。
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text(instance.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.smart_toy_outlined),
              isSelected: _showAi,
              tooltip: _showAi ? '关闭 AI 助手' : '打开 AI 助手',
              onPressed: () => setState(() => _showAi = !_showAi),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: '总览'),
              Tab(icon: Icon(Icons.description), text: '配置'),
              Tab(icon: Icon(Icons.extension), text: '插件/Mod'),
              Tab(icon: Icon(Icons.folder), text: '文件'),
              Tab(icon: Icon(Icons.backup), text: '备份'),
              Tab(icon: Icon(Icons.settings), text: '设置'),
              Tab(icon: Icon(Icons.inventory_2), text: '容器'),
            ],
          ),
        ),
        body: Row(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: 总览 — 日志控制台 + 生命周期控制
                  Selector<AppState, InstanceStatus>(
                    selector: (_, s) => s.instances
                        .firstWhere(
                          (e) => e.id == widget.instanceId,
                          orElse: () => instance,
                        )
                        .status,
                    builder: (context, status, _) {
                      return Row(
                        children: [
                          // 左侧：日志 + 命令输入
                          Expanded(flex: 3, child: _buildLogPanel()),
                          const VerticalDivider(width: 1),
                          // 右侧：生命周期控制
                          Expanded(flex: 1, child: _buildControlPanel(status)),
                        ],
                      );
                    },
                  ),
                  // Tab 2: 配置 — 配置文件编辑器
                  ConfigEditorScreen(rootPath: instance.rootPath),
                  // Tab 3: 插件/Mod — 卡片网格
                  PluginsTab(rootPath: instance.rootPath),
                  // Tab 4: 文件管理
                  FileManagerScreen(rootPath: instance.rootPath),
                  // Tab 5: 备份 — 文件选择与压缩
                  _BackupTab(
                    rootPath: instance.rootPath,
                    instanceId: widget.instanceId,
                  ),
                  // Tab 6: 设置 — 实例名称 + 启动命令
                  _SettingsTab(
                    instanceId: widget.instanceId,
                    dockerAvailable: _dockerAvailable,
                    dockerProbing: _dockerProbing,
                  ),
                  // Tab 7: 容器 — 本机 Docker 全功能管理（不可用时展示原因与重新检测）
                  ContainerEnvironmentPanel(
                    backend: state.dockerCli,
                    highlightName: instance.runMode == RunMode.docker
                        ? state.containerNameFor(instance)
                        : null,
                  ),
                ],
              ),
            ),
            // 右侧 AI 助手侧栏（可手动收起）
            if (_showAi) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: 380,
                child: AiChatPanel(
                  controller: _aiController,
                  rootPath: instance.rootPath,
                  instanceName: instance.name,
                  onClose: () => setState(() => _showAi = false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 左侧日志面板：终端风格日志窗口 + 命令输入框。
  Widget _buildLogPanel() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Container(
            // 半透明背景，符合 Apple 材质设计
            color: Colors.black.withValues(alpha: 0.4),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return Text(
                  _logs[index],
                  style: TextStyle(
                    fontFamily: FontSettings.instance.terminalFamily,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commandController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: '输入服务器指令（无需 /）后按回车',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    // 半透明背景
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    filled: true,
                  ),
                  onSubmitted: (_) => _sendCommand(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: _sendCommand,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 右侧生命周期控制面板。
  Widget _buildControlPanel(InstanceStatus status) {
    final theme = Theme.of(context);
    final isActive = status.isActive;
    final isStopped = status == InstanceStatus.stopped;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('控制', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          // 启动按钮：仅在「已关闭」可用
          FilledButton.icon(
            onPressed: isStopped ? _startInstance : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动'),
          ),
          const SizedBox(height: 12),
          // 重启按钮：仅在「启动中」可用
          FilledButton.tonalIcon(
            onPressed: isActive ? _restartInstance : null,
            icon: const Icon(Icons.refresh),
            label: const Text('重启'),
          ),
          const SizedBox(height: 12),
          // 停止 / 强制停止 按钮
          if (!_stopClicked)
            FilledButton.icon(
              onPressed: isActive
                  ? () {
                      context.read<AppState>().stopInstance(widget.instanceId);
                      setState(() => _stopClicked = true);
                    }
                  : null,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              // 在关闭流程期间及已关闭后均可点击，以备随时强制终止。
              onPressed: () =>
                  context.read<AppState>().forceStopInstance(widget.instanceId),
              icon: const Icon(Icons.dangerous),
              label: const Text('强制停止'),
            ),
          const SizedBox(height: 24),
          // 状态信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前状态', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(status.label, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 备份 Tab：文件列表 + 全选 + 备份按钮。
class _BackupTab extends StatefulWidget {
  const _BackupTab({required this.rootPath, required this.instanceId});

  final String rootPath;
  final String instanceId;

  @override
  State<_BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends State<_BackupTab> {
  /// 根目录下的文件和文件夹列表。
  List<FileSystemEntity> _files = [];

  /// 已选择的文件/文件夹索引集合。
  final Set<int> _selectedIndices = {};

  /// 是否正在扫描文件。
  bool _loading = true;

  /// 备份进度（0.0 ~ 1.0）。
  double? _backupProgress;

  /// 备份是否正在进行中。
  bool _backupInProgress = false;

  @override
  void initState() {
    super.initState();
    _scanFiles();
  }

  /// 扫描根目录下的文件和文件夹。
  void _scanFiles() {
    final dir = Directory(widget.rootPath);
    if (!dir.existsSync()) {
      setState(() {
        _files = [];
        _loading = false;
      });
      return;
    }
    final entities = dir.listSync(recursive: false);
    setState(() {
      _files = entities;
      _loading = false;
    });
  }

  /// 全选 / 取消全选。
  void _toggleSelectAll(bool? value) {
    if (value == true) {
      setState(() {
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(_files.length, (i) => i));
      });
    } else {
      setState(() {
        _selectedIndices.clear();
      });
    }
  }

  /// 切换单个文件的选择状态。
  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// 开始备份。
  ///
  /// 弹出进度对话框，调用 FFI 压缩函数，支持取消。
  Future<void> _startBackup() async {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个文件或文件夹')));
      return;
    }

    final selectedNames = _selectedIndices
        .map((i) => p.basename(_files[i].path))
        .toList();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final outputPath = p.join(
      p.dirname(widget.rootPath),
      '${p.basename(widget.rootPath)}_backup_$timestamp.zip',
    );

    setState(() {
      _backupInProgress = true;
      _backupProgress = 0.0;
    });

    // 尝试调用 Rust FFI (在后台 isolate 执行，不阻塞 UI)
    try {
      final backupService = BackupService.instance;
      final compressionLevel = await BackupSettings.getLevel(widget.instanceId);

      final result = await backupService.backup(
        widget.rootPath,
        outputPath,
        selectedNames,
        compressionLevel: compressionLevel,
        onProgress: (progress) {
          // 进度消息在主 isolate 事件循环触发，可直接更新 UI
          if (mounted && _backupInProgress) {
            setState(() {
              _backupProgress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      if (result.isSuccess) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('备份已保存到 $outputPath')));
      } else if (result.isCancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份已取消')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份失败: ${result.error ?? '错误码 ${result.code}'}'),
          ),
        );
      }
    } catch (e) {
      // isolate 启动失败等异常
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('备份失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _backupInProgress = false;
          _backupProgress = null;
        });
      }
    }
  }

  /// 取消备份。
  void _cancelBackup() {
    try {
      BackupService.instance.cancel();
    } catch (_) {
      // FFI 未初始化，忽略
    }
    setState(() {
      _backupInProgress = false;
      _backupProgress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_backupInProgress) {
      return _buildProgressDialog();
    }

    return Column(
      children: [
        // 全选复选框
        CheckboxListTile(
          value: _selectedIndices.length == _files.length && _files.isNotEmpty,
          tristate: true,
          onChanged: _toggleSelectAll,
          title: const Text('全选'),
          subtitle: Text('已选择 ${_selectedIndices.length} / ${_files.length} 项'),
        ),
        const Divider(),
        // 文件列表
        Expanded(
          child: _files.isEmpty
              ? const Center(child: Text('根目录为空'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final entity = _files[index];
                    final name = p.basename(entity.path);
                    final isDir = entity is Directory;
                    final isSelected = _selectedIndices.contains(index);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(index),
                      secondary: Icon(
                        isDir ? Icons.folder : Icons.insert_drive_file,
                      ),
                      title: Text(name),
                      subtitle: Text(isDir ? '文件夹' : '文件'),
                    );
                  },
                ),
        ),
        // 底部备份按钮
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: FilledButton.icon(
              onPressed: _startBackup,
              icon: const Icon(Icons.archive),
              label: const Text('开始备份'),
            ),
          ),
        ),
      ],
    );
  }

  /// 备份进度对话框。
  Widget _buildProgressDialog() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('正在备份...', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: _backupProgress),
              const SizedBox(height: 12),
              Text(
                '${((_backupProgress ?? 0) * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: _cancelBackup, child: const Text('取消')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动命令编辑卡片。
class _StartCommandCard extends StatefulWidget {
  const _StartCommandCard({required this.instanceId});

  final String instanceId;

  @override
  State<_StartCommandCard> createState() => _StartCommandCardState();
}

class _StartCommandCardState extends State<_StartCommandCard> {
  late final TextEditingController _controller;
  bool _dirty = false;

  /// 正则匹配 -Xmx 值（如 -Xmx2G、-Xmx0.5G、-Xmx2048M）。
  static final _xmxRegex = RegExp(r'-Xmx(\d+(?:\.\d+)?)([gGmM]?)');

  @override
  void initState() {
    super.initState();
    final instance = context
        .read<AppState>()
        .instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    _controller = TextEditingController(text: instance?.startCommand ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 从启动命令中解析 -Xmx 的内存值，返回以 GB 为单位的值。
  /// 无匹配时返回 null（表示未设置 -Xmx）。
  double? _parseXmxGb() {
    final match = _xmxRegex.firstMatch(_controller.text);
    if (match == null) return null;
    final num = double.tryParse(match.group(1)!) ?? 2048;
    final unit = match.group(2)?.toLowerCase();
    if (unit == 'g') return num;
    if (unit == 'm') return num / 1024;
    // 无单位按 MB 处理
    return num / 1024;
  }

  /// 拖动滑块时，更新启动命令中的 -Xmx 值。
  void _onMemoryChanged(double gb) {
    final xmxArg =
        '-Xmx${gb == gb.truncateToDouble() ? gb.toInt().toString() : gb.toStringAsFixed(1)}G';
    final text = _controller.text;
    String newText;
    if (_xmxRegex.hasMatch(text)) {
      newText = text.replaceAll(_xmxRegex, xmxArg);
    } else {
      // 无 -Xmx，插入到 java 之后
      if (text.startsWith('java')) {
        newText = text.replaceFirst('java', 'java $xmxArg');
      } else {
        newText = '$xmxArg $text';
      }
    }
    _controller.text = newText;
    setState(() => _dirty = true);
  }

  void _save() {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;
    context.read<AppState>().updateStartCommand(widget.instanceId, cmd);
    setState(() => _dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('启动命令已更新')));
  }

  @override
  Widget build(BuildContext context) {
    final memGb = _parseXmxGb();
    final hasXmx = memGb != null;
    final displayGb = hasXmx ? memGb.clamp(0.5, 32).toDouble() : 2.0;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 内存调节滑块
            Row(
              children: [
                const Icon(Icons.memory),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '最大内存',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text(
                            hasXmx
                                ? (displayGb == displayGb.truncateToDouble()
                                      ? '${displayGb.toInt()} GB'
                                      : '${displayGb.toStringAsFixed(1)} GB')
                                : '未设置',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: hasXmx
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: displayGb,
                        min: 0.5,
                        max: 32,
                        divisions: 63,
                        label: displayGb == displayGb.truncateToDouble()
                            ? '${displayGb.toInt()}GB'
                            : '${displayGb.toStringAsFixed(1)}GB',
                        onChanged: (gb) => _onMemoryChanged(gb),
                      ),
                      if (!hasXmx)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '当前启动命令未指定 -Xmx，拖动滑块以设置内存',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 启动命令文本框
            Row(
              children: [
                const Icon(Icons.terminal),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: '启动命令',
                      helperText: '如：java -Xmx2G -jar paper.jar nogui',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    onSubmitted: (_) => _dirty ? _save() : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _dirty ? _save : null,
                  icon: const Icon(Icons.check),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置 Tab：实例名称 + 启动命令 + 运行方式 + 删除实例。
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.instanceId,
    this.dockerAvailable = false,
    this.dockerProbing = false,
  });

  final String instanceId;

  /// 本机 Docker 是否可用（决定容器化选项是否可选）。
  final bool dockerAvailable;

  /// 是否仍在探测 Docker 环境。
  final bool dockerProbing;

  /// 确认删除实例并返回上级。
  ///
  /// 弹窗中提供勾选框，用户可选择是否同时删除服务器根目录下的所有文件。
  Future<void> _confirmDelete(BuildContext context) async {
    final result = await showAppDialog<_DeleteConfirmation>(
      context,
      (_) => const _DeleteConfirmationDialog(),
    );
    if (result == null || !result.confirmed) return;
    if (!context.mounted) return;
    await context.read<AppState>().removeInstance(
      instanceId,
      deleteFiles: result.deleteFiles,
    );
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _InstanceNameCard(instanceId: instanceId),
        _StartCommandCard(instanceId: instanceId),
        _RunModeCard(
          instanceId: instanceId,
          dockerAvailable: dockerAvailable,
          dockerProbing: dockerProbing,
        ),
        _EulaCard(instanceId: instanceId),
        _CompressionSettingsCard(instanceId: instanceId),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除实例'),
          ),
        ),
      ],
    );
  }
}

/// 运行方式卡片：原生进程 / Docker 容器。
class _RunModeCard extends StatefulWidget {
  const _RunModeCard({
    required this.instanceId,
    required this.dockerAvailable,
    required this.dockerProbing,
  });

  final String instanceId;
  final bool dockerAvailable;
  final bool dockerProbing;

  @override
  State<_RunModeCard> createState() => _RunModeCardState();
}

class _RunModeCardState extends State<_RunModeCard> {
  /// 切换运行方式。
  Future<void> _switchMode(RunMode mode) async {
    if (mode == RunMode.docker && !widget.dockerAvailable) return;
    final state = context.read<AppState>();
    final instance = state.instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    if (instance == null) return;
    if (instance.status.isActive) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先停止服务器再切换运行方式')));
      return;
    }
    await state.updateRunMode(widget.instanceId, mode, instance.container);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已切换为「${mode.label}」运行')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instance = context
        .watch<AppState>()
        .instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    final runMode = instance?.runMode ?? RunMode.native;
    final isDocker = runMode == RunMode.docker;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Text('运行方式', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RadioGroup<RunMode>(
              groupValue: runMode,
              onChanged: (mode) {
                if (mode != null) _switchMode(mode);
              },
              child: Column(
                children: [
                  RadioListTile<RunMode>(
                    value: RunMode.native,
                    title: const Text('原生进程'),
                    subtitle: const Text('直接以 java 进程运行（默认）'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<RunMode>(
                    value: RunMode.docker,
                    enabled: !widget.dockerProbing && widget.dockerAvailable,
                    title: Row(
                      children: [
                        const Text('Docker 容器'),
                        if (widget.dockerProbing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                        if (!widget.dockerProbing &&
                            !widget.dockerAvailable) ...[
                          const SizedBox(width: 8),
                          Text(
                            '不可用',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      !widget.dockerProbing && !widget.dockerAvailable
                          ? '未检测到 Docker CLI，请先安装并启动 Docker Desktop'
                          : '服务器运行在 Docker 容器中，启停/控制台/文件走容器',
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (isDocker) ...[
              const Divider(height: 24),
              _ContainerConfigCard(instanceId: widget.instanceId),
            ],
          ],
        ),
      ),
    );
  }
}

/// 容器配置卡片（Docker 运行方式下的镜像 / 端口 / 卷 / 环境变量等）。
class _ContainerConfigCard extends StatefulWidget {
  const _ContainerConfigCard({required this.instanceId});

  final String instanceId;

  @override
  State<_ContainerConfigCard> createState() => _ContainerConfigCardState();
}

class _ContainerConfigCardState extends State<_ContainerConfigCard> {
  late final TextEditingController _imageController;
  late final TextEditingController _nameController;
  late final TextEditingController _portsController;
  late final TextEditingController _volumesController;
  late final TextEditingController _envController;
  late final TextEditingController _memoryController;
  late final TextEditingController _cpusController;
  late final TextEditingController _diskController;
  late final TextEditingController _workdirController;
  String? _restartPolicy;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final config = _currentConfig();
    _imageController = TextEditingController(text: config.image);
    _nameController = TextEditingController(text: config.containerName ?? '');
    _portsController = TextEditingController(text: config.ports.join(', '));
    _volumesController = TextEditingController(text: config.volumes.join(', '));
    _envController = TextEditingController(
      text: config.env.entries.map((e) => '${e.key}=${e.value}').join('\n'),
    );
    _memoryController = TextEditingController(
      text: config.memoryLimitMb?.toString() ?? '',
    );
    _cpusController = TextEditingController(
      text: config.cpus?.toString() ?? '',
    );
    _diskController = TextEditingController(
      text: config.diskLimitMb?.toString() ?? '',
    );
    _workdirController = TextEditingController(text: config.workdir ?? '');
    _restartPolicy = config.restartPolicy;
  }

  @override
  void dispose() {
    _imageController.dispose();
    _nameController.dispose();
    _portsController.dispose();
    _volumesController.dispose();
    _envController.dispose();
    _memoryController.dispose();
    _cpusController.dispose();
    _diskController.dispose();
    _workdirController.dispose();
    super.dispose();
  }

  ContainerConfig _currentConfig() {
    return context
            .read<AppState>()
            .instances
            .where((e) => e.id == widget.instanceId)
            .firstOrNull
            ?.container ??
        const ContainerConfig();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// 保存容器配置。
  Future<void> _save() async {
    final config = ContainerConfig(
      image: _imageController.text.trim(),
      containerName: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      ports: _splitList(_portsController.text),
      volumes: _splitList(_volumesController.text),
      env: _parseEnv(_envController.text),
      restartPolicy: _restartPolicy,
      memoryLimitMb: int.tryParse(_memoryController.text.trim()),
      cpus: int.tryParse(_cpusController.text.trim()),
      diskLimitMb: int.tryParse(_diskController.text.trim()),
      workdir: _workdirController.text.trim().isEmpty
          ? null
          : _workdirController.text.trim(),
    );
    final error = config.validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await context.read<AppState>().updateRunMode(
      widget.instanceId,
      RunMode.docker,
      config,
    );
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('容器配置已保存')));
  }

  List<String> _splitList(String text) {
    return text
        .split(RegExp(r'[\n,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Map<String, String> _parseEnv(String text) {
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      map[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune),
            const SizedBox(width: 16),
            Expanded(child: Text('容器配置', style: theme.textTheme.titleSmall)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _imageController,
          decoration: const InputDecoration(
            labelText: '镜像',
            helperText: '如 itzg/minecraft-server:latest',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '容器名称（留空自动生成）',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portsController,
          decoration: const InputDecoration(
            labelText: '端口映射',
            helperText: '宿主机端口:容器端口，多个用逗号分隔，如 25565:25565, 8123:8123',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _volumesController,
          decoration: const InputDecoration(
            labelText: '卷挂载',
            helperText: '宿主机路径:容器路径；留空默认挂载实例目录到 /data',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _envController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '环境变量',
            helperText: '每行一个 KEY=VALUE，如 MEMORY=2G、EULA=TRUE',
            alignLabelWithHint: true,
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _restartPolicy,
          decoration: const InputDecoration(
            labelText: '重启策略',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'no', child: Text('no — 不自动重启')),
            DropdownMenuItem(
              value: 'unless-stopped',
              child: Text('unless-stopped — 容器退出自动重启'),
            ),
            DropdownMenuItem(value: 'always', child: Text('always — 总是重启')),
            DropdownMenuItem(
              value: 'on-failure',
              child: Text('on-failure — 异常退出时重启'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _restartPolicy = value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _memoryController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '内存上限（MB，留空不限）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _cpusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'CPU 核数（留空不限）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _diskController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '磁盘上限（MB，留空不限）',
                  helperText: '需存储驱动支持 size 配额',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _workdirController,
                decoration: const InputDecoration(
                  labelText: '工作目录（留空默认）',
                  helperText: '如 /data，强制在数据目录启动',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '容器由实例名派生，如 xmc-<名称>-<id后缀>',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 删除确认结果。
class _DeleteConfirmation {
  const _DeleteConfirmation({
    required this.confirmed,
    required this.deleteFiles,
  });

  final bool confirmed;
  final bool deleteFiles;
}

/// 删除确认对话框。
///
/// 提供勾选框，用户可选择是否同时删除服务器根目录下的所有文件。
class _DeleteConfirmationDialog extends StatefulWidget {
  const _DeleteConfirmationDialog();

  @override
  State<_DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState extends State<_DeleteConfirmationDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('删除实例'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('确定要删除此实例吗？'),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _deleteFiles,
            onChanged: (v) => setState(() => _deleteFiles = v ?? false),
            title: const Text('同时删除服务器文件'),
            subtitle: const Text('勾选后将删除服务器根目录下的所有文件，包括世界、配置和核心。此操作不可撤销。'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _DeleteConfirmation(confirmed: false, deleteFiles: _deleteFiles),
          ),
          child: const Text('取消'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(
            context,
            _DeleteConfirmation(confirmed: true, deleteFiles: _deleteFiles),
          ),
          child: const Text('删除'),
        ),
      ],
    );
  }
}

/// 实例名称编辑卡片。
class _InstanceNameCard extends StatefulWidget {
  const _InstanceNameCard({required this.instanceId});

  final String instanceId;

  @override
  State<_InstanceNameCard> createState() => _InstanceNameCardState();
}

class _InstanceNameCardState extends State<_InstanceNameCard> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final instance = context
        .read<AppState>()
        .instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    _controller = TextEditingController(text: instance?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    context.read<AppState>().renameInstance(widget.instanceId, name);
    setState(() => _dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('实例名称已更新')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.label),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: '实例名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                onSubmitted: (_) => _dirty ? _save() : null,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.check),
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 压缩设置卡片 — 调节备份压缩比率/速度 (每实例独立)。
class _CompressionSettingsCard extends StatefulWidget {
  const _CompressionSettingsCard({required this.instanceId});

  final String instanceId;

  @override
  State<_CompressionSettingsCard> createState() =>
      _CompressionSettingsCardState();
}

class _CompressionSettingsCardState extends State<_CompressionSettingsCard> {
  int _level = 6;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLevel();
  }

  Future<void> _loadLevel() async {
    final level = await BackupSettings.getLevel(widget.instanceId);
    if (mounted) {
      setState(() {
        _level = level;
        _loading = false;
      });
    }
  }

  Future<void> _onChanged(double value) async {
    final newLevel = value.round();
    setState(() => _level = newLevel);
    await BackupSettings.setLevel(widget.instanceId, newLevel);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        margin: EdgeInsets.all(8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compress),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '备份压缩级别',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  compressionLevelLabel(_level),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _level.toDouble(),
              min: 0,
              max: 9,
              divisions: 9,
              label: '$_level',
              onChanged: _onChanged,
            ),
            const SizedBox(height: 4),
            Text(
              '级别越低压缩越快但文件更大，级别越高压缩比越好但更慢。0=不压缩(仅存储)，6=标准，9=最佳压缩比。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// EULA 同意卡片。
///
/// 读取实例根目录下的 `eula.txt`，解析 `eula=` 的值并展示当前状态。
/// 通过开关将 `eula=` 改为 `true` 以同意 Mojang EULA，便于启动服务器。
class _EulaCard extends StatefulWidget {
  const _EulaCard({required this.instanceId});

  final String instanceId;

  @override
  State<_EulaCard> createState() => _EulaCardState();
}

class _EulaCardState extends State<_EulaCard> {
  static final _eulaRegex = RegExp(
    r'^\s*eula\s*=\s*(true|false)\s*$',
    caseSensitive: false,
  );

  bool _accepted = false;
  bool _fileExists = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEula();
  }

  /// 获取当前实例的 eula.txt 路径。
  String _eulaPath() {
    final instance = context
        .read<AppState>()
        .instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    return p.join(instance?.rootPath ?? '', 'eula.txt');
  }

  /// 读取 eula.txt 并解析当前状态。
  void _loadEula() {
    bool accepted = false;
    bool exists = true;
    try {
      final file = File(_eulaPath());
      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          final match = _eulaRegex.firstMatch(line);
          if (match != null) {
            accepted = match.group(1)!.toLowerCase() == 'true';
            break;
          }
        }
      } else {
        exists = false;
      }
    } catch (_) {
      exists = false;
    }
    if (!mounted) return;
    setState(() {
      _accepted = accepted;
      _fileExists = exists;
      _loading = false;
    });
  }

  /// 将 eula.txt 中的 `eula=` 设为指定值，保留其余注释内容。
  /// 若文件不存在则创建一个标准的 eula.txt。
  Future<void> _setEula(bool value) async {
    final path = _eulaPath();
    final file = File(path);
    String content;
    if (file.existsSync()) {
      final lines = file.readAsLinesSync();
      var replaced = false;
      for (var i = 0; i < lines.length; i++) {
        if (_eulaRegex.hasMatch(lines[i])) {
          lines[i] = 'eula=$value';
          replaced = true;
          break;
        }
      }
      if (!replaced) lines.add('eula=$value');
      content = lines.join('\n');
    } else {
      content =
          '#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).\neula=$value';
    }
    try {
      file.writeAsStringSync(content);
      if (!mounted) return;
      setState(() {
        _accepted = value;
        _fileExists = true;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? '已同意 EULA' : '已撤销 EULA 同意')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('写入 eula.txt 失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        margin: EdgeInsets.all(8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gavel),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'EULA 最终用户许可协议',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_fileExists)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '未找到 eula.txt，将在同意后自动创建。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            SwitchListTile(
              value: _accepted,
              onChanged: (v) => _setEula(v),
              title: const Text('同意 Mojang EULA'),
              subtitle: Text(_accepted ? '已同意，服务器可正常启动' : '未同意，服务器启动后将自动退出'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 4),
            Text(
              '同意后将写入 eula=true 到 eula.txt。详见 Mojang EULA。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
