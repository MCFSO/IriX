// Hangar 项目详情页面
// 展示项目图标、描述、版本列表，支持下载到选中实例的 plugins/ 目录
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/hangar.dart';
import '../models/server_instance.dart';
import '../services/downloader.dart';
import '../services/hangar_api_service.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

/// Hangar 项目详情页面。
class HangarDetailScreen extends StatefulWidget {
  const HangarDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<HangarDetailScreen> createState() => _HangarDetailScreenState();
}

class _HangarDetailScreenState extends State<HangarDetailScreen> {
  final HangarApiService _api = HangarApiService();
  final Downloader _downloader = Downloader();

  HangarProject? _project;
  List<HangarVersion> _versions = [];
  bool _isLoading = true;
  String? _error;

  // 下载进度: "<versionName>:<platform>" -> percent
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
      final project = await _api.getProject(widget.slug);
      final versions = await _api.getVersions(widget.slug);
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

  /// 选择一个服务器实例，返回 null 表示用户取消。
  Future<ServerInstance?> _pickInstance() async {
    final state = context.read<AppState>();
    final instances = state.instances;
    if (instances.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先创建一个服务器实例')));
      }
      return null;
    }
    if (state.selected != null) return state.selected;

    if (!mounted) return null;
    return showAppDialog<ServerInstance>(context, (ctx) {
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
    });
  }

  Future<void> _downloadPlatform(
    HangarVersion version,
    HangarPlatformDownload pd,
  ) async {
    final project = _project;
    if (project == null) return;

    final threads = context.read<AppState>().downloadThreads;
    final instance = await _pickInstance();
    if (instance == null) return;

    final targetDir = p.join(instance.rootPath, 'plugins');
    final filename = '${project.slug}-${version.name}-${pd.platform}.jar';
    final targetPath = p.join(targetDir, filename);
    final progressKey = '${version.name}:${pd.platform}';

    setState(() => _downloadProgress[progressKey] = 0.0);

    try {
      await _downloader.downloadFile(pd.downloadUrl, targetPath, (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[progressKey] = progress.percent;
          });
        }
      }, threads: threads);
      if (mounted) {
        setState(() => _downloadProgress.remove(progressKey));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载到 plugins/$filename'),
            action: SnackBarAction(
              label: '查看路径',
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('目录: $targetDir')));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadProgress.remove(progressKey));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_project?.name ?? '加载中...')),
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
        Text(
          '版本列表 (${_versions.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ..._versions.map(_buildVersionTile),
      ],
    );
  }

  Widget _buildHeader(HangarProject project) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: project.avatarUrl != null && project.avatarUrl!.isNotEmpty
              ? Image.network(
                  project.avatarUrl!,
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
              Text(project.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(project.slug, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _tag(project.category),
                  ...project.platforms.take(4).map(_tag),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStats(HangarProject project) {
    return Row(
      children: [
        _statItem(Icons.download, '${_formatNumber(project.downloads)} 下载'),
        const SizedBox(width: 16),
        _statItem(Icons.star, '${_formatNumber(project.stars)} 收藏'),
      ],
    );
  }

  Widget _buildVersionTile(HangarVersion version) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(version.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '平台: ${version.downloadsPerPlatform.map((d) => d.platform).join(', ')}',
              style: const TextStyle(fontSize: 12),
            ),
            if (version.createdAt != null)
              Text(
                '发布于 ${version.createdAt!.substring(0, 10)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        children: version.downloadsPerPlatform.map((pd) {
          final progressKey = '${version.name}:${pd.platform}';
          final progress = _downloadProgress[progressKey];
          final isDownloading = progress != null;
          return ListTile(
            leading: const Icon(Icons.download, size: 20),
            title: Text('${pd.platform} · MC ${pd.gameVersions.join(', ')}'),
            subtitle: isDownloading
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: progress / 100),
                      Text(
                        '${progress.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  )
                : null,
            trailing: isDownloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: () => _downloadPlatform(version, pd),
                    child: const Text('下载'),
                  ),
          );
        }).toList(),
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
