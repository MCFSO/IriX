// 下载核心界面
// 多步骤向导：选择核心与版本 → 下载核心文件 → 编辑启动命令并创建实例。
// 通过 [AppState] 创建下载型实例，实例文件夹放在 APP 根目录的 instances/ 下。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../data/server_cores.dart';
import '../services/downloader.dart';
import '../services/msl_api_service.dart';
import '../state/app_state.dart';

/// 下载核心向导界面。
///
/// 三步流程：
/// 1. 选择下载源、服务器核心与版本；
/// 2. 下载核心 jar 文件并展示实时进度；
/// 3. 编辑启动命令并调用 [AppState.createDownloadedInstance] 创建实例。
class DownloadCoreScreen extends StatefulWidget {
  const DownloadCoreScreen({super.key});

  @override
  State<DownloadCoreScreen> createState() => _DownloadCoreScreenState();
}

class _DownloadCoreScreenState extends State<DownloadCoreScreen> {
  int _step = 0;
  String _downloadSource = 'FastMirror';

  ServerCore? _selectedCore;
  CoreVersionInfo? _selectedVersion;

  /// MSL 源：API 返回的核心标识符列表（如 paper、purpur）。
  List<String>? _mslCores;

  /// MSL 源：当前选中核心的版本列表。
  List<String>? _mslVersions;

  /// MSL 源：当前选中核心的描述。
  String? _mslDescription;

  /// MSL 源：选中的核心标识符。
  String? _selectedMslCore;

  /// MSL 源：选中的版本。
  String? _selectedMslVersion;

  /// MSL 加载中。
  bool _mslLoading = false;
  String? _mslError;

  DownloadProgress? _progress;
  String? _downloadError;
  bool _downloading = false;
  String? _coreFilePath;
  String? _instanceRootDir;

  /// MSL 源期望的 SHA-256（用于下载后完整性校验，H-1）。
  String? _expectedSha256;

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

  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _onDownloadSourceChanged(String? source) {
    if (source == null || source == _downloadSource) return;
    setState(() {
      _downloadSource = source;
      _selectedCore = null;
      _selectedVersion = null;
      _selectedMslCore = null;
      _selectedMslVersion = null;
      _mslVersions = null;
      _mslDescription = null;
      _mslError = null;
      _expectedSha256 = null;
    });
    if (source == 'MSL') {
      _fetchMslCores();
    }
  }

  Future<void> _fetchMslCores() async {
    setState(() {
      _mslLoading = true;
      _mslError = null;
      _mslCores = null;
    });
    try {
      final list = await MslApiService.instance.getMirrorsFlat();
      if (!mounted) return;
      setState(() {
        _mslCores = list;
        _mslLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mslError = e.toString();
        _mslLoading = false;
      });
    }
  }

  Future<void> _onMslCoreChanged(String? core) async {
    if (core == null) return;
    setState(() {
      _selectedMslCore = core;
      _selectedMslVersion = null;
      _mslVersions = null;
      _mslDescription = null;
      _mslLoading = true;
    });
    try {
      final info = await MslApiService.instance.getServerInfo(core);
      if (!mounted) return;
      setState(() {
        _mslVersions = info.versions;
        _mslDescription = info.description;
        _mslLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mslError = e.toString();
        _mslLoading = false;
      });
    }
  }

  void _onCoreChanged(ServerCore? core) {
    setState(() {
      _selectedCore = core;
      _selectedVersion = null;
    });
  }

  Future<void> _startDownload() async {
    final threads = context.read<AppState>().downloadThreads;

    String downloadUrl;
    String fileName;

    if (_downloadSource == 'MSL') {
      final core = _selectedMslCore;
      final version = _selectedMslVersion;
      if (core == null || version == null) return;

      setState(() {
        _step = 1;
        _downloading = true;
        _downloadError = null;
        _progress = null;
      });

      try {
        final info = await MslApiService.instance.getDownloadUrl(core, version);

        downloadUrl = info.url;
        fileName = '$core-$version.jar';
        // 记录 MSL 返回的 sha256，下载完成后校验（H-1 完整性校验）。
        _expectedSha256 = info.sha256;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _downloadError = e.toString();
        });
        return;
      }
    } else {
      final core = _selectedCore;
      final version = _selectedVersion;
      if (core == null || version == null) return;

      downloadUrl = version.downloadUrl;
      fileName = buildCoreFileName(core, version);

      setState(() {
        _step = 1;
        _downloading = true;
        _downloadError = null;
        _progress = null;
      });
    }

    try {
      // 实例文件夹放在 APP 根目录（exe 所在目录）下的 instances/。
      final appRoot = p.dirname(Platform.resolvedExecutable);
      final instanceRoot = p.join(
        appRoot,
        'instances',
        '${_downloadSource.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      );
      final targetPath = p.join(instanceRoot, fileName);

      final savedPath = await Downloader().downloadFile(
        downloadUrl,
        targetPath,
        (progress) {
          // 下载线程可能在页面销毁后仍在回调，需确认挂载再刷新 UI。
          if (!mounted) return;
          setState(() => _progress = progress);
        },
        threads: threads,
        sha256: _expectedSha256,
      );

      if (!mounted) return;
      _coreFilePath = savedPath;
      _instanceRootDir = instanceRoot;
      _commandController.text = 'java -Xmx1024M -jar $fileName nogui';

      setState(() {
        _downloading = false;
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = e.toString();
      });
    }
  }

  Future<void> _finishAndCreateInstance() async {
    final coreFilePath = _coreFilePath;
    final rootPath = _instanceRootDir;
    if (coreFilePath == null || rootPath == null) return;

    final coreType = _downloadSource == 'MSL'
        ? (_selectedMslCore ?? 'unknown')
        : _selectedCore?.id ?? 'unknown';
    final coreName = _downloadSource == 'MSL'
        ? (_selectedMslCore ?? 'Unknown')
        : _selectedCore?.name ?? 'Unknown';
    final category = _downloadSource == 'MSL'
        ? CoreCategory.vanilla
        : _selectedCore?.category ?? CoreCategory.vanilla;

    final dummyCore = ServerCore(
      id: coreType,
      name: coreName,
      category: category,
      scenarioZh: _mslDescription ?? '',
      scenarioEn: _mslDescription ?? '',
      versions: const [],
    );
    final dummyVersion = CoreVersionInfo(
      _downloadSource == 'MSL'
          ? (_selectedMslVersion ?? '')
          : _selectedVersion?.version ?? '',
      '',
    );

    await context.read<AppState>().createDownloadedInstance(
      core: dummyCore,
      versionInfo: dummyVersion,
      coreFilePath: coreFilePath,
      rootPath: rootPath,
      startCommand: _commandController.text.trim(),
    );

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.download_title)),
      body: switch (_step) {
        0 => _buildSelectionStep(),
        1 => _buildDownloadStep(),
        _ => _buildCommandStep(),
      },
    );
  }

  Widget _stepHeader(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

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

  // ===================== STEP 1 =====================

  Widget _buildSelectionStep() {
    final l = AppLocalizations.of(context);
    final isMsl = _downloadSource == 'MSL';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(l.download_step1),
          const SizedBox(height: 16),

          // 下载源选择
          _labelField(
            label: l.download_source,
            child: DropdownButton<String>(
              value: _downloadSource,
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                  value: 'FastMirror',
                  child: Text('FastMirror'),
                ),
                DropdownMenuItem(value: 'MSL', child: Text(l.download_mslSource)),
              ],
              onChanged: _onDownloadSourceChanged,
            ),
          ),

          // MSL 归属声明
          if (isMsl)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _mslAttribution(),
            ),

          const SizedBox(height: 24),

          if (isMsl) _buildMslSelection() else _buildFastMirrorSelection(),
        ],
      ),
    );
  }

  Widget _mslAttribution() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Image.network(
              'https://mslmc.cn/favicon.ico',
              width: 14,
              height: 14,
              errorBuilder: (_, _, _) => const Icon(Icons.cloud, size: 14),
            ),
            const SizedBox(width: 6),
            Text(
              l.download_mslAttribution,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- FastMirror ----

  Widget _buildFastMirrorSelection() {
    final l = AppLocalizations.of(context);
    final core = _selectedCore;
    final versions = core?.versions ?? const <CoreVersionInfo>[];
    final canProceed = core != null && _selectedVersion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _labelField(
                label: l.download_serverCore,
                child: DropdownButton<ServerCore>(
                  value: core,
                  hint: Text(l.download_selectCore),
                  isExpanded: true,
                  items: serverCores
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      )
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
        _labelField(
          label: l.download_serverVersion,
          child: DropdownButton<CoreVersionInfo>(
            value: _selectedVersion,
            hint: Text(
              core == null
                  ? l.download_selectCoreFirst
                  : versions.isEmpty
                  ? l.download_noVersionsForCore
                  : l.download_selectVersion,
            ),
            isExpanded: true,
            items: versions
                .map((v) => DropdownMenuItem(value: v, child: Text(v.version)))
                .toList(),
            onChanged: (core == null || versions.isEmpty)
                ? null
                : (v) => setState(() => _selectedVersion = v),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canProceed ? _startDownload : null,
            child: Text(l.download_nextStep),
          ),
        ),
      ],
    );
  }

  Widget _scenarioCard(ServerCore? core) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.download_scenario, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              core == null
                  ? l.download_selectCoreFirst
                  : l.download_scenarioWithCategory(
                      core.scenario, core.category.displayName),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  // ---- MSL ----

  Widget _buildMslSelection() {
    final l = AppLocalizations.of(context);
    final error = _mslError;
    if (_mslLoading && _mslCores == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (error != null && _mslCores == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            Text(l.download_loadFailed, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetchMslCores,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l.common_retry),
            ),
          ],
        ),
      );
    }

    final cores = _mslCores ?? [];
    final canProceed = _selectedMslCore != null && _selectedMslVersion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _labelField(
                label: l.download_serverCore,
                child: DropdownButton<String>(
                  value: _selectedMslCore,
                  hint: Text(l.download_selectCore),
                  isExpanded: true,
                  items: cores
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(_mslCoreDisplayName(c)),
                        ),
                      )
                      .toList(),
                  onChanged: _onMslCoreChanged,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: _mslDescription != null
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l.download_description,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _mslDescription!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _labelField(
          label: l.download_serverVersion,
          child: _mslLoading && _selectedMslCore != null && _mslVersions == null
              ? const SizedBox(
                  height: 40,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : DropdownButton<String>(
                  value: _selectedMslVersion,
                  hint: Text(
                    _selectedMslCore == null
                        ? l.download_selectCoreFirst
                        : (_mslVersions?.isEmpty ?? true)
                        ? l.download_noVersionsForCore
                        : l.download_selectVersion,
                  ),
                  isExpanded: true,
                  items: (_mslVersions ?? [])
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged:
                      _selectedMslCore != null &&
                          (_mslVersions?.isNotEmpty ?? false)
                      ? (v) => setState(() => _selectedMslVersion = v)
                      : null,
                ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canProceed ? _startDownload : null,
            child: Text(l.download_nextStep),
          ),
        ),
      ],
    );
  }

  String _mslCoreDisplayName(String id) {
    const displayNames = {
      'paper': 'Paper',
      'purpur': 'Purpur',
      'leaf': 'Leaf',
      'leaves': 'Leaves',
      'spigot': 'Spigot',
      'bukkit': 'CraftBukkit',
      'folia': 'Folia',
      'pufferfish': 'Pufferfish',
      'pufferfish_purpur': 'Pufferfish+Purpur',
      'spongevanilla': 'SpongeVanilla',
      'arclight-forge': 'Arclight (Forge)',
      'arclight-neoforge': 'Arclight (NeoForge)',
      'arclight-fabric': 'Arclight (Fabric)',
      'youer': 'Youer',
      'mohist': 'Mohist',
      'catserver': 'CatServer',
      'banner': 'Banner',
      'spongeforge': 'SpongeForge',
      'neoforge': 'NeoForge',
      'forge': 'Forge',
      'fabric': 'Fabric',
      'quilt': 'Quilt',
      'vanilla': 'Vanilla',
      'vanilla-snapshot': 'Vanilla Snapshot',
      'bedrock-server': 'Bedrock Server',
      'nukkitx': 'NukkitX',
      'velocity': 'Velocity',
      'bungeecord': 'BungeeCord',
      'lightfall': 'LightFall',
      'travertine': 'Travertine',
    };
    return displayNames[id] ?? id;
  }

  // ===================== STEP 2 =====================

  Widget _buildDownloadStep() {
    final l = AppLocalizations.of(context);
    final error = _downloadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(l.download_downloadFailed, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() {
                  _step = 0;
                  _downloadError = null;
                }),
                child: Text(l.common_back),
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
          _stepHeader(l.download_step2),
          const SizedBox(height: 32),
          LinearProgressIndicator(value: percent / 100.0),
          const SizedBox(height: 16),
          Text('${percent.toStringAsFixed(1)}%'),
          const SizedBox(height: 8),
          Text(
            total > 0
                ? '${_formatBytes(downloaded)} / ${_formatBytes(total.toDouble())}'
                : l.download_downloaded(_formatBytes(downloaded)),
          ),
          const SizedBox(height: 8),
          Text(l.download_speed(_formatBytes(speed))),
          const SizedBox(height: 24),
          if (_downloading)
            Text(
              l.download_downloadingHint,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }

  // ===================== STEP 3 =====================

  Widget _buildCommandStep() {
    final l = AppLocalizations.of(context);
    String fileName;
    if (_downloadSource == 'MSL') {
      fileName =
          '${_selectedMslCore ?? 'core'}-${_selectedMslVersion ?? 'unknown'}.jar';
    } else {
      fileName = (_selectedCore != null && _selectedVersion != null)
          ? buildCoreFileName(_selectedCore!, _selectedVersion!)
          : '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepHeader(l.download_step3),
          const SizedBox(height: 16),
          Text(l.download_coreFile(fileName)),
          const SizedBox(height: 24),
          _labelField(
            label: l.download_command,
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
              child: Text(l.download_finishCreate),
            ),
          ),
        ],
      ),
    );
  }
}
