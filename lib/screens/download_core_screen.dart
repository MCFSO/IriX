// 下载核心界面
// 多步骤向导：选择核心与版本 → 下载核心文件 → 编辑启动命令并创建实例。
// 通过 [AppState] 创建下载型实例，使用 path_provider 构造实例根目录。

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../data/server_cores.dart';
import '../services/downloader.dart';
import '../state/app_state.dart';

/// 下载核心向导界面。
///
/// 三步流程：
/// 1. 选择服务器核心、版本与（固定）下载源；
/// 2. 下载核心 jar 文件并展示实时进度；
/// 3. 编辑启动命令并调用 [AppState.createDownloadedInstance] 创建实例。
class DownloadCoreScreen extends StatefulWidget {
  const DownloadCoreScreen({super.key});

  @override
  State<DownloadCoreScreen> createState() => _DownloadCoreScreenState();
}

class _DownloadCoreScreenState extends State<DownloadCoreScreen> {
  /// 当前向导步骤：0=选择，1=下载中，2=编辑命令。
  int _step = 0;

  /// 当前选中的核心（null 表示未选择）。
  ServerCore? _selectedCore;

  /// 当前选中的版本（null 表示未选择）。
  CoreVersionInfo? _selectedVersion;

  /// 固定下载源（仅 FastMirror，不可更改）。
  final String _selectedSource = 'FastMirror';

  /// 下载进度（null 表示尚未开始或无进度）。
  DownloadProgress? _progress;

  /// 下载错误信息（非 null 表示下载失败）。
  String? _downloadError;

  /// 下载是否进行中。
  bool _downloading = false;

  /// 核心文件保存路径（下载成功后填充）。
  String? _coreFilePath;

  /// 实例根目录路径（下载成功后填充）。
  String? _instanceRootDir;

  /// 启动命令控制器。
  late final TextEditingController _commandController;

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  /// 格式化字节数为人类可读字符串（B / KB / MB）。
  String _formatBytes(double bytes) {
    if (bytes < 1024) {
      return '${bytes.toStringAsFixed(0)} B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// 选择核心时重置版本并刷新后续依赖状态。
  void _onCoreChanged(ServerCore? core) {
    setState(() {
      _selectedCore = core;
      _selectedVersion = null;
    });
  }

  /// 进入下载步骤：构造实例根目录与目标文件名，调用下载器。
  Future<void> _startDownload() async {
    final core = _selectedCore;
    final version = _selectedVersion;
    if (core == null || version == null) return;

    // 在任何 await 之前读取下载线程数，避免跨异步间隙使用 BuildContext。
    final threads = context.read<AppState>().downloadThreads;

    setState(() {
      _step = 1;
      _downloading = true;
      _downloadError = null;
      _progress = null;
    });

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      // 追加时间戳保证目录唯一，避免相同 core+version 下载覆盖已有实例。
      final instanceRoot = p.join(
        docsDir.path,
        'instances',
        '${core.id}-${version.version}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      );
      final fileName = buildCoreFileName(core, version);
      final targetPath = p.join(instanceRoot, fileName);

      // Downloader 内部会确保目标文件的父目录（即实例根目录）存在。
      final savedPath = await Downloader().downloadFile(
        version.downloadUrl,
        targetPath,
        (progress) {
          setState(() {
            _progress = progress;
          });
        },
        threads: threads,
      );

      _coreFilePath = savedPath;
      _instanceRootDir = instanceRoot;

      // 预填充默认启动命令。
      _commandController.text = 'java -Xmx1024M -jar $fileName nogui';

      setState(() {
        _downloading = false;
        _step = 2;
      });
    } catch (e) {
      setState(() {
        _downloading = false;
        _downloadError = e.toString();
      });
    }
  }

  /// 完成创建实例并返回主页。
  Future<void> _finishAndCreateInstance() async {
    final core = _selectedCore;
    final version = _selectedVersion;
    final coreFilePath = _coreFilePath;
    final rootPath = _instanceRootDir;
    if (core == null ||
        version == null ||
        coreFilePath == null ||
        rootPath == null) {
      return;
    }

    await context.read<AppState>().createDownloadedInstance(
          core: core,
          versionInfo: version,
          coreFilePath: coreFilePath,
          rootPath: rootPath,
          startCommand: _commandController.text.trim(),
        );

    if (mounted) {
      // 弹出至首页路由。
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载核心'),
      ),
      body: switch (_step) {
        0 => _buildSelectionStep(),
        1 => _buildDownloadStep(),
        _ => _buildCommandStep(),
      },
    );
  }

  /// 步骤标题。
  Widget _stepHeader(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  /// 带标签的字段容器。
  Widget _labelField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // ===================== STEP 1：选择 =====================

  Widget _buildSelectionStep() {
    final core = _selectedCore;
    final versions = core?.versions ?? const <CoreVersionInfo>[];
    final canProceed = core != null && _selectedVersion != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader('第一步 · 选择核心与版本'),
          const SizedBox(height: 24),
          // 服务器核心 + 适用场景（核心下拉在左，场景卡片在右）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _labelField(
                  label: '服务器核心',
                  child: DropdownButton<ServerCore>(
                    value: core,
                    hint: const Text('请选择核心'),
                    isExpanded: true,
                    items: serverCores
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: _onCoreChanged,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: _scenarioCard(core)),
            ],
          ),
          const SizedBox(height: 24),
          // 服务器版本
          _labelField(
            label: '服务器版本',
            child: DropdownButton<CoreVersionInfo>(
              value: _selectedVersion,
              hint: Text(
                core == null
                    ? '请先选择核心'
                    : versions.isEmpty
                        ? '该核心暂无可用版本'
                        : '请选择版本',
              ),
              isExpanded: true,
              items: versions
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.version),
                      ))
                  .toList(),
              onChanged: (core == null || versions.isEmpty)
                  ? null
                  : (v) {
                      setState(() {
                        _selectedVersion = v;
                      });
                    },
            ),
          ),
          const SizedBox(height: 24),
          // 核心下载源（固定为 FastMirror，禁用）
          _labelField(
            label: '核心下载源',
            child: DropdownButton<String>(
              value: _selectedSource,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'FastMirror',
                  child: Text('FastMirror'),
                ),
              ],
              onChanged: null,
            ),
          ),
          const SizedBox(height: 32),
          // 下一步
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canProceed ? _startDownload : null,
              child: const Text('下一步'),
            ),
          ),
        ],
      ),
    );
  }

  /// 适用场景卡片。
  Widget _scenarioCard(ServerCore? core) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('适用场景', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              core == null
                  ? '请先选择核心'
                  : '${core.scenario}（${core.category.displayName}）',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  // ===================== STEP 2：下载 =====================

  Widget _buildDownloadStep() {
    final error = _downloadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('下载失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _step = 0;
                    _downloadError = null;
                  });
                },
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final progress = _progress;
    final percent = progress?.percent ?? 0.0;
    final downloaded = (progress?.downloadedBytes ?? 0).toDouble();
    final total = progress?.totalBytes ?? 0;
    final speed = progress?.speedBytesPerSec ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader('第二步 · 下载核心文件'),
          const SizedBox(height: 32),
          LinearProgressIndicator(value: percent / 100.0),
          const SizedBox(height: 16),
          Text('${percent.toStringAsFixed(1)}%'),
          const SizedBox(height: 8),
          Text(
            total > 0
                ? '${_formatBytes(downloaded)} / ${_formatBytes(total.toDouble())}'
                : '已下载 ${_formatBytes(downloaded)}',
          ),
          const SizedBox(height: 8),
          Text('速度 ${_formatBytes(speed)}/s'),
          const SizedBox(height: 24),
          if (_downloading)
            const Text(
              '正在下载…请勿离开',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  // ===================== STEP 3：编辑启动命令 =====================

  Widget _buildCommandStep() {
    final core = _selectedCore;
    final version = _selectedVersion;
    final fileName =
        (core != null && version != null) ? buildCoreFileName(core, version) : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader('第三步 · 编辑启动命令'),
          const SizedBox(height: 16),
          Text('核心文件：$fileName'),
          const SizedBox(height: 24),
          _labelField(
            label: '启动命令',
            child: TextField(
              controller: _commandController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'java -Xmx1024M -jar xxx.jar nogui',
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finishAndCreateInstance,
              child: const Text('完成并创建实例'),
            ),
          ),
        ],
      ),
    );
  }
}
