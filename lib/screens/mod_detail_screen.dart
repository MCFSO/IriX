// Mod/插件详情页面
// 展示项目图标、描述、版本列表，支持安装到本地实例或节点实例的
// mods/ 或 plugins/ 目录
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/modrinth.dart';
import '../models/server_instance.dart';
import '../services/downloader.dart';
import '../services/modrinth_api_service.dart';
import '../state/app_state.dart';
import '../utils/install_target_picker.dart';

/// Mod 详情页面
class ModDetailScreen extends StatefulWidget {
  const ModDetailScreen({
    super.key,
    required this.projectId,
    required this.projectSlug,
  });

  final String projectId;
  final String projectSlug;

  @override
  State<ModDetailScreen> createState() => _ModDetailScreenState();
}

class _ModDetailScreenState extends State<ModDetailScreen> {
  final ModrinthApiService _api = ModrinthApiService();
  final Downloader _downloader = Downloader();

  ModrinthProject? _project;
  List<ModrinthVersion> _versions = [];
  bool _isLoading = true;
  String? _error;

  // 下载进度: versionId -> percent
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final project = await _api.getProject(widget.projectSlug);
      final versions = await _api.getProjectVersions(widget.projectSlug);
      if (mounted) {
        setState(() {
          _project = project;
          _versions = versions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// 根据项目类型决定下载到 mods/ 还是 plugins/ 目录
  String _targetSubdir(String projectType) {
    return switch (projectType) {
      'plugin' => 'plugins',
      'mod' => 'mods',
      _ => 'mods',
    };
  }

  /// 选择一个安装目标（本地实例 / 节点实例），返回 null 表示用户取消。
  Future<InstallTarget?> _pickTarget() => pickInstallTarget(context);

  Future<void> _downloadVersion(ModrinthVersion version) async {
    final project = _project;
    if (project == null) return;

    // 在任何 await 之前读取下载线程数，避免跨异步间隙使用 BuildContext。
    final l = AppLocalizations.of(context);
    final threads = context.read<AppState>().downloadThreads;

    // 选择主文件（优先 primary）
    if (version.files.isEmpty) return;
    final file = version.files.firstWhere(
      (f) => f.primary,
      orElse: () => version.files.first,
    );

    final target = await _pickTarget();
    if (target == null) return;

    final subdir = _targetSubdir(project.projectType);
    // M-2：文件名来自远端 API（Modrinth），落盘前净化——只取 basename，
    // 拒绝含路径分隔符/../ 的文件名，防止越出实例目录写任意路径。
    final safeName = p.basename(file.filename);
    if (safeName.isEmpty ||
        safeName.contains('..') ||
        safeName.contains('/') ||
        safeName.contains(r'\')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.mod_downloadRejected)),
        );
      }
      return;
    }

    setState(() => _downloadProgress[version.id] = 0.0);

    try {
      if (target.isRemote) {
        await _downloadToRemote(
          target: target,
          url: file.url,
          safeName: safeName,
          subdir: subdir,
          threads: threads,
          sha512: file.hashes?['sha512'],
          progressKey: version.id,
        );
      } else {
        await _downloadToLocal(
          instance: target.localInstance!,
          url: file.url,
          safeName: safeName,
          subdir: subdir,
          threads: threads,
          sha512: file.hashes?['sha512'],
          progressKey: version.id,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress.remove(version.id));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.mod_downloadFailed(e.toString()))));
      }
    }
  }

  /// 下载到本地实例目录（校验哈希后落盘）。
  Future<void> _downloadToLocal({
    required ServerInstance instance,
    required String url,
    required String safeName,
    required String subdir,
    required int threads,
    String? sha512,
    required String progressKey,
  }) async {
    final l = AppLocalizations.of(context);
    final targetDir = p.join(instance.rootPath, subdir);
    final targetPath = p.join(targetDir, safeName);
    await _downloader.downloadFile(
      url,
      targetPath,
      (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[progressKey] = progress.percent;
          });
        }
      },
      threads: threads,
      // H-1：Modrinth 提供 sha1/sha512 哈希，下载后校验完整性。
      sha512: sha512,
    );
    if (mounted) {
      setState(() => _downloadProgress.remove(progressKey));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.mod_downloadedTo('$subdir/$safeName')),
          action: SnackBarAction(
            label: l.mod_openDirectory,
            onPressed: () => _openFolder(targetDir),
          ),
        ),
      );
    }
  }

  /// 下载到临时目录后上传到节点实例（校验哈希后上传）。
  Future<void> _downloadToRemote({
    required InstallTarget target,
    required String url,
    required String safeName,
    required String subdir,
    required int threads,
    String? sha512,
    required String progressKey,
  }) async {
    final l = AppLocalizations.of(context);
    // 下载到系统临时目录，安装完成后清理。
    final tempDir = await Directory.systemTemp.createTemp('irix_install_');
    final tempPath = p.join(tempDir.path, safeName);
    try {
      await _downloader.downloadFile(
        url,
        tempPath,
        (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress[progressKey] = progress.percent;
            });
          }
        },
        threads: threads,
        // H-1：Modrinth 提供 sha1/sha512 哈希，下载后校验完整性。
        sha512: sha512,
      );
      await installFileToRemote(
        target: target,
        localPath: tempPath,
        subdir: subdir,
      );
      if (mounted) {
        setState(() => _downloadProgress.remove(progressKey));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.mod_installedToNode(target.displayName, subdir))),
        );
      }
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // 忽略临时目录清理失败。
      }
    }
  }

  Future<void> _openFolder(String dirPath) async {
    // 简单提示：此处不引入额外的进程打开依赖，只显示路径
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.mod_directory(dirPath))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_project?.title ?? l.common_loading)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l = AppLocalizations.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadData, child: Text(l.common_retry)),
          ],
        ),
      );
    }
    final project = _project;
    if (project == null) return Center(child: Text(l.mod_notFound));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeader(project),
        const SizedBox(height: 16),
        _buildStats(project),
        const SizedBox(height: 16),
        Text(l.mod_description, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(project.description),
        const SizedBox(height: 24),
        Text(l.mod_versionList, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._versions.map(_buildVersionTile),
      ],
    );
  }

  Widget _buildHeader(ModrinthProject project) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: project.iconUrl != null && project.iconUrl!.isNotEmpty
              ? Image.network(
                  project.iconUrl!,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholderIcon(theme),
                )
              : _placeholderIcon(theme),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(project.slug, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _tag(project.projectType),
                  ...project.loaders.take(3).map(_tag),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStats(ModrinthProject project) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        _statItem(Icons.download, '${_formatNumber(project.downloads)} ${l.mod_downloads}'),
        const SizedBox(width: 16),
        _statItem(Icons.star, '${_formatNumber(project.followers)} ${l.mod_follows}'),
      ],
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildVersionTile(ModrinthVersion version) {
    final l = AppLocalizations.of(context);
    final progress = _downloadProgress[version.id];
    final isDownloading = progress != null;

    String versionInfo;
    if (version.gameVersions.isNotEmpty) {
      versionInfo =
          'MC ${version.gameVersions.join(', ')} · ${version.loaders.join(', ')}';
    } else {
      versionInfo = version.versionNumber;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          version.name.isNotEmpty ? version.name : version.versionNumber,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(versionInfo, style: const TextStyle(fontSize: 12)),
            if (version.datePublished != null)
              Text(
                l.mod_publishedOn(version.datePublished!.substring(0, 10)),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (isDownloading) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress / 100),
              Text(
                '${progress.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ],
        ),
        trailing: isDownloading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.icon(
                onPressed: () => _downloadVersion(version),
                icon: const Icon(Icons.download, size: 18),
                label: Text(l.common_download),
              ),
        isThreeLine: true,
      ),
    );
  }

  Widget _placeholderIcon(ThemeData theme) {
    return Container(
      width: 96,
      height: 96,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.extension, color: theme.colorScheme.outline, size: 40),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 11,
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
