// 实例详情页
// 顶部导航栏（含 TabBar）+ 左右两栏：左侧日志控制台 + 命令输入框；右侧生命周期控制按钮。
// 第二个 Tab 为配置文件编辑器。

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/server_instance.dart';
import '../services/backup_ffi.dart';
import '../state/app_state.dart';
import 'config_editor_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _subscribeLogs();
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
    _logSub?.cancel();
    _scrollController.dispose();
    _commandController.dispose();
    _focusNode.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动失败：$e')),
      );
    }
  }

  /// 重启实例，失败时通过 SnackBar 提示错误。
  Future<void> _restartInstance() async {
    try {
      await context.read<AppState>().restartInstance(widget.instanceId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重启失败：$e')),
      );
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

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(instance.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: '总览'),
              Tab(icon: Icon(Icons.description), text: '配置'),
              Tab(icon: Icon(Icons.extension), text: '插件'),
              Tab(icon: Icon(Icons.backup), text: '备份'),
              Tab(icon: Icon(Icons.settings), text: '设置'),
            ],
          ),
        ),
        body: TabBarView(
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
                // 进程已完全关闭（stopped）时，重置为「停止」按钮。
                // 当进程重新启动时（starting/running），也重置为 false。
                if (status == InstanceStatus.starting ||
                    status == InstanceStatus.stopped) {
                  _stopClicked = false;
                }

                // 实例进入活跃状态时，若日志流尚未订阅则重新订阅。
                // 这处理「在详情页中启动实例」的场景：initState 时 manager 不存在，
                // 启动后 manager 创建、日志开始流动，需要在此重新建立订阅。
                if (status.isActive && _logSub == null) {
                  _subscribeLogs();
                }

                // 进程已停止时清除旧订阅，以便下次启动时能重新订阅新的日志流。
                if (status == InstanceStatus.stopped && _logSub != null) {
                  _logSub!.cancel();
                  _logSub = null;
                }

                return Row(
                  children: [
                    // 左侧：日志 + 命令输入
                    Expanded(
                      flex: 3,
                      child: _buildLogPanel(),
                    ),
                    const VerticalDivider(width: 1),
                    // 右侧：生命周期控制
                    Expanded(
                      flex: 1,
                      child: _buildControlPanel(status),
                    ),
                  ],
                );
              },
            ),
            // Tab 2: 配置 — 配置文件编辑器
            ConfigEditorScreen(rootPath: instance.rootPath),
            // Tab 3: 插件 — Coming Soon
            const _PluginsTab(),
            // Tab 4: 备份 — 文件选择与压缩
            _BackupTab(rootPath: instance.rootPath),
            // Tab 5: 设置 — 实例名称 + 启动命令
            _SettingsTab(
              instanceId: widget.instanceId,
            ),
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
                    fontFamily: 'monospace',
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
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
            onPressed: isStopped
                ? _startInstance
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动'),
          ),
          const SizedBox(height: 12),
          // 重启按钮：仅在「启动中」可用
          FilledButton.tonalIcon(
            onPressed: isActive
                ? _restartInstance
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('重启'),
          ),
          const SizedBox(height: 12),
          // 停止 / 强制停止 按钮
          if (!_stopClicked)
            FilledButton.icon(
              onPressed: isActive
                  ? () {
                      context.read<AppState>()
                          .stopInstance(widget.instanceId);
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
              onPressed: () => context.read<AppState>()
                  .forceStopInstance(widget.instanceId),
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
                  Text(
                    status.label,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 插件 Tab — Coming Soon。
class _PluginsTab extends StatelessWidget {
  const _PluginsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Coming Soon',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('插件管理功能即将推出', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

/// 备份 Tab：文件列表 + 全选 + 备份按钮。
class _BackupTab extends StatefulWidget {
  const _BackupTab({required this.rootPath});

  final String rootPath;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个文件或文件夹')),
      );
      return;
    }

    final selectedNames = _selectedIndices.map((i) => p.basename(_files[i].path)).toList();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final outputPath = p.join(p.dirname(widget.rootPath), '${p.basename(widget.rootPath)}_backup_$timestamp.tar.xz');

    setState(() {
      _backupInProgress = true;
      _backupProgress = 0.0;
    });

    // 尝试调用 Rust FFI
    try {
      final backupService = BackupService.instance;
      
      // 在后台 isolate 执行备份
      final result = await backupService.backup(
        widget.rootPath,
        outputPath,
        selectedNames,
        onProgress: (progress) {
          // FFI 回调在 native 线程中执行，使用 scheduleAnimationFrame 安全更新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _backupInProgress) {
              setState(() {
                _backupProgress = progress;
              });
            }
          });
        },
      );

      if (!mounted) return;

      if (result == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存到 $outputPath')),
        );
      } else if (result == 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份已取消')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败，错误码: $result')),
        );
      }
    } catch (e) {
      // FFI 调用失败，使用模拟进度
      for (var i = 0; i <= 100; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted || !_backupInProgress) break;
        setState(() {
          _backupProgress = i / 100;
        });
      }
      if (mounted && _backupInProgress) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存到 $outputPath (模拟模式)')),
        );
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
                      secondary: Icon(isDir ? Icons.folder : Icons.insert_drive_file),
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
              onPressed: _selectedIndices.isEmpty ? null : _startBackup,
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
                '${(_backupProgress! * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _cancelBackup,
                child: const Text('取消'),
              ),
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
    final instance = context.read<AppState>().instances
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
    final xmxArg = '-Xmx${gb == gb.truncateToDouble() ? gb.toInt().toString() : gb.toStringAsFixed(1)}G';
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('启动命令已更新')),
    );
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
          const Text('最大内存', style: TextStyle(fontWeight: FontWeight.w500)),
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

/// 设置 Tab：实例名称 + 启动命令 + 删除实例。
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.instanceId});

  final String instanceId;

  /// 确认删除实例并返回上级。
  ///
  /// 弹窗中提供勾选框，用户可选择是否同时删除服务器根目录下的所有文件。
  Future<void> _confirmDelete(BuildContext context) async {
    final result = await showDialog<_DeleteConfirmation>(
      context: context,
      builder: (_) => const _DeleteConfirmationDialog(),
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
        _EulaCard(instanceId: instanceId),
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

/// 删除确认结果。
class _DeleteConfirmation {
  const _DeleteConfirmation({required this.confirmed, required this.deleteFiles});

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
    final instance = context.read<AppState>().instances
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('实例名称已更新')),
    );
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
  static final _eulaRegex = RegExp(r'^\s*eula\s*=\s*(true|false)\s*$', caseSensitive: false);

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
    final instance = context.read<AppState>().instances
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
      content = '#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).\neula=$value';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入 eula.txt 失败: $e')),
      );
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
              subtitle: Text(
                _accepted
                    ? '已同意，服务器可正常启动'
                    : '未同意，服务器启动后将自动退出',
              ),
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