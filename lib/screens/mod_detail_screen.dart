// Mod/插件详情页面
// 展示项目图标、描述、版本列表，支持下载到选中实例的 mods/ 或 plugins/ 目录
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/modrinth.dart';
import '../models/server_instance.dart';
import '../services/downloader.dart';
import '../services/modrinth_api_service.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

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

  /// 选择一个服务器实例，返回 null 表示用户取消
  Future<ServerInstance?> _pickInstance() async {
    final state = context.read<AppState>();
    final instances = state.instances;
    if (instances.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先创建一个服务器实例')),
        );
      }
      return null;
    }
    // 若有选中的实例直接使用，否则让用户选择
    if (state.selected != null) return state.selected;

    if (!mounted) return null;
    return showAppDialog<ServerInstance>(
      context,
      (ctx) {
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
                  onTap: () => Navigator.pop(ctx, instance),
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
      },
    );
  }

  Future<void> _downloadVersion(ModrinthVersion version) async {
    final project = _project;
    if (project == null) return;

    // 在任何 await 之前读取下载线程数，避免跨异步间隙使用 BuildContext。
    final threads = context.read<AppState>().downloadThreads;

    // 选择主文件（优先 primary）
    if (version.files.isEmpty) return;
    final file = version.files.firstWhere(
        (f) => f.primary,
        orElse: () => version.files.first,
    );

    final instance = await _pickInstance();
    if (instance == null) return;

    final subdir = _targetSubdir(project.projectType);
    final targetDir = p.join(instance.rootPath, subdir);
    final targetPath = p.join(targetDir, file.filename);

    setState(() => _downloadProgress[version.id] = 0.0);

    try {
      await _downloader.downloadFile(
        file.url,
        targetPath,
        (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress[version.id] = progress.percent;
            });
          }
        },
        threads: threads,
      );
      if (mounted) {
        setState(() => _downloadProgress.remove(version.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载到 $subdir/${file.filename}'),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () => _openFolder(targetDir),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress.remove(version.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  Future<void> _openFolder(String dirPath) async {
    // 简单提示：此处不引入额外的进程打开依赖，只显示路径
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目录: $dirPath')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_project?.title ?? '加载中...'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            FilledButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }
    final project = _project;
    if (project == null) return const Center(child: Text('未找到项目'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeader(project),
        const SizedBox(height: 16),
        _buildStats(project),
        const SizedBox(height: 16),
        Text('描述', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(project.description),
        const SizedBox(height: 24),
        Text('版本列表', style: Theme.of(context).textTheme.titleMedium),
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
    return Row(
      children: [
        _statItem(Icons.download, '${_formatNumber(project.downloads)} 下载'),
        const SizedBox(width: 16),
        _statItem(Icons.star, '${_formatNumber(project.followers)} 关注'),
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
        title: Text(version.name.isNotEmpty ? version.name : version.versionNumber),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(versionInfo, style: const TextStyle(fontSize: 12)),
            if (version.datePublished != null)
              Text(
                '发布于 ${version.datePublished!.substring(0, 10)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (isDownloading) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress / 100),
              Text('${progress.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11)),
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
                label: const Text('下载'),
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
