// 容器环境面板
// 通用的 Docker / Bastille 资源管理面板：容器、镜像、卷、网络四个 Tab。
// 实例详情页的「容器」Tab 与后续多机节点页共用本组件。
//
// [highlightName] 非空时，在「容器」Tab 顶部展示该容器的状态卡片与快捷操作
// （用于实例详情页高亮实例自身的容器）。

import 'dart:async';

import 'package:flutter/material.dart' hide ImageInfo;

import '../services/container/container_backend.dart';
import '../utils/apple_widgets.dart';

/// 容器环境面板。
class ContainerEnvironmentPanel extends StatefulWidget {
  const ContainerEnvironmentPanel({
    super.key,
    required this.backend,
    this.highlightName,
  });

  /// 容器后端（本地 Docker / 远程节点）。
  final ContainerBackend backend;

  /// 需要高亮的容器名（实例自身的容器）。
  final String? highlightName;

  @override
  State<ContainerEnvironmentPanel> createState() =>
      _ContainerEnvironmentPanelState();
}

class _ContainerEnvironmentPanelState extends State<ContainerEnvironmentPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 环境探测结果。
  ContainerEnvironmentInfo? _env;
  bool _envLoading = true;

  /// 各 Tab 数据。
  List<ContainerInfo> _containers = [];
  List<ImageInfo> _images = [];
  List<VolumeInfo> _volumes = [];
  List<NetworkInfo> _networks = [];

  /// 各 Tab 加载状态。
  bool _containersLoading = false;
  bool _imagesLoading = false;
  bool _volumesLoading = false;
  bool _networksLoading = false;

  /// 错误提示（展示在顶部）。
  String? _error;

  /// 构建进度轮询定时器。
  Timer? _buildPollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _probeEnvironment();
  }

  @override
  void dispose() {
    _buildPollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  Future<void> _probeEnvironment() async {
    setState(() => _envLoading = true);
    final env = await widget.backend.environment();
    if (!mounted) return;
    setState(() {
      _env = env;
      _envLoading = false;
      _error = env.available ? null : env.errorMessage;
    });
    if (env.available) {
      unawaited(_refreshContainers());
      unawaited(_refreshImages());
      unawaited(_refreshVolumes());
      unawaited(_refreshNetworks());
    }
  }

  Future<void> _refreshContainers() async {
    setState(() => _containersLoading = true);
    try {
      final list = await widget.backend.listContainers();
      if (!mounted) return;
      setState(() => _containers = list);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _containersLoading = false);
  }

  Future<void> _refreshImages() async {
    setState(() => _imagesLoading = true);
    try {
      final list = await widget.backend.listImages();
      if (!mounted) return;
      setState(() => _images = list);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _imagesLoading = false);
  }

  Future<void> _refreshVolumes() async {
    setState(() => _volumesLoading = true);
    try {
      final list = await widget.backend.listVolumes();
      if (!mounted) return;
      setState(() => _volumes = list);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _volumesLoading = false);
  }

  Future<void> _refreshNetworks() async {
    setState(() => _networksLoading = true);
    try {
      final list = await widget.backend.listNetworks();
      if (!mounted) return;
      setState(() => _networks = list);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _networksLoading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 执行容器操作后刷新列表。
  Future<void> _runContainerAction(
    ContainerInfo container,
    Future<void> Function() action, {
    String? confirmText,
  }) async {
    if (confirmText != null) {
      final ok = await showAppDialog<bool>(
        context,
        (_) => AlertDialog(
          title: const Text('确认操作'),
          content: Text(confirmText),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作成功：${container.name}')),
      );
      await _refreshContainers();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 构建镜像 ====================

  Future<void> _openBuildImageDialog() async {
    final backend = widget.backend;
    final result = await showAppDialog<_BuildImageInput>(
      context,
      (_) => const _BuildImageDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final job = await backend.buildImage(
        result.dockerfile,
        result.name,
        result.tag,
      );
      if (!mounted) return;
      await _watchBuild(job.jobId, result.name);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 轮询构建进度直到完成，展示日志对话框。
  Future<void> _watchBuild(String jobId, String imageName) async {
    if (!mounted) return;
    showAppDialog<void>(
      context,
      (_) => _BuildProgressDialog(
        backend: widget.backend,
        jobId: jobId,
        title: '构建 $imageName',
      ),
    );
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    if (_envLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_env == null || !_env!.available) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '${widget.backend.displayName} 不可用',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _probeEnvironment,
              icon: const Icon(Icons.refresh),
              label: const Text('重新检测'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (widget.backend.isRemote || _env!.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _env!.errorMessage ?? '${widget.backend.displayName} 环境',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
                if (_env!.version != null)
                  Text(
                    'v${_env!.version}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
              ],
            ),
          ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: '容器'),
            Tab(icon: Icon(Icons.image), text: '镜像'),
            Tab(icon: Icon(Icons.storage), text: '卷'),
            Tab(icon: Icon(Icons.hub), text: '网络'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildContainersTab(),
              _buildImagesTab(),
              _buildVolumesTab(),
              _buildNetworksTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 容器 Tab ====================

  Widget _buildContainersTab() {
    final highlight = widget.highlightName;
    final highlightInfo = highlight == null
        ? null
        : _containers.where((c) => c.name == highlight).firstOrNull;
    return Column(
      children: [
        if (highlight != null && highlightInfo != null)
          _HighlightContainerCard(
            container: highlightInfo,
            onStart: () => _runContainerAction(
              highlightInfo,
              () => widget.backend.startContainer(highlightInfo.name),
            ),
            onStop: () => _runContainerAction(
              highlightInfo,
              () => widget.backend.stopContainer(highlightInfo.name),
            ),
            onRestart: () => _runContainerAction(
              highlightInfo,
              () => widget.backend.restartContainer(highlightInfo.name),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('容器列表', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshContainers,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _containersLoading
              ? const Center(child: CircularProgressIndicator())
              : _containers.isEmpty
                  ? const Center(child: Text('暂无容器'))
                  : ListView.builder(
                      itemCount: _containers.length,
                      itemBuilder: (context, index) {
                        final c = _containers[index];
                        return _ContainerTile(
                          container: c,
                          onStart: () => _runContainerAction(
                            c,
                            () => widget.backend.startContainer(c.name),
                          ),
                          onStop: () => _runContainerAction(
                            c,
                            () => widget.backend.stopContainer(c.name),
                          ),
                          onRestart: () => _runContainerAction(
                            c,
                            () => widget.backend.restartContainer(c.name),
                          ),
                          onRemove: () => _runContainerAction(
                            c,
                            () =>
                                widget.backend.removeContainer(c.name, force: true),
                            confirmText: '确定删除容器 ${c.name} 吗？',
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ==================== 镜像 Tab ====================

  Widget _buildImagesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('镜像列表', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshImages,
              ),
              FilledButton.tonalIcon(
                onPressed: _openPullImageDialog,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('拉取'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openBuildImageDialog,
                icon: const Icon(Icons.build_circle_outlined, size: 18),
                label: const Text('构建'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _imagesLoading
              ? const Center(child: CircularProgressIndicator())
              : _images.isEmpty
                  ? const Center(child: Text('暂无镜像'))
                  : ListView.builder(
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final image = _images[index];
                        return ListTile(
                          leading: const Icon(Icons.image),
                          title: Text(image.displayTag),
                          subtitle: Text(
                            '${_formatBytes(image.sizeBytes)}'
                            '${image.createdAt != null ? ' · ${image.createdAt!.toLocal().toString().split('.').first}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除镜像',
                            onPressed: () async {
                              final ok = await showAppDialog<bool>(
                                context,
                                (_) => AlertDialog(
                                  title: const Text('删除镜像'),
                                  content: Text('确定删除镜像 ${image.displayTag} 吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        foregroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true || !mounted) return;
                              try {
                                await widget.backend.removeImage(image.displayTag);
                                await _refreshImages();
                              } on ContainerBackendException catch (e) {
                                _showError(e.message);
                              }
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _openPullImageDialog() async {
    final name = await showAppDialog<String>(
      context,
      (_) => const _TextInputDialog(
        title: '拉取镜像',
        label: '镜像名称',
        hint: '如 itzg/minecraft-server:latest',
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await widget.backend.pullImage(name.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('镜像拉取完成：${name.trim()}')));
      await _refreshImages();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 卷 / 网络 Tab ====================

  Widget _buildVolumesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('卷列表', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshVolumes,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _volumesLoading
              ? const Center(child: CircularProgressIndicator())
              : _volumes.isEmpty
                  ? const Center(child: Text('暂无卷'))
                  : ListView.builder(
                      itemCount: _volumes.length,
                      itemBuilder: (context, index) {
                        final volume = _volumes[index];
                        return ListTile(
                          leading: const Icon(Icons.storage),
                          title: Text(volume.name),
                          subtitle: Text(
                            volume.mountpoint ?? volume.driver ?? '',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除卷',
                            onPressed: () async {
                              final ok = await showAppDialog<bool>(
                                context,
                                (_) => AlertDialog(
                                  title: const Text('删除卷'),
                                  content: Text('确定删除卷 ${volume.name} 吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        foregroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true || !mounted) return;
                              try {
                                await widget.backend.removeVolume(volume.name);
                                await _refreshVolumes();
                              } on ContainerBackendException catch (e) {
                                _showError(e.message);
                              }
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildNetworksTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text('网络列表', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshNetworks,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _networksLoading
              ? const Center(child: CircularProgressIndicator())
              : _networks.isEmpty
                  ? const Center(child: Text('暂无网络'))
                  : ListView.builder(
                      itemCount: _networks.length,
                      itemBuilder: (context, index) {
                        final network = _networks[index];
                        return ListTile(
                          leading: const Icon(Icons.hub),
                          title: Text(network.name),
                          subtitle: Text(
                            [network.driver, network.subnet]
                                .whereType<String>()
                                .join(' · '),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ==================== 工具 ====================

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 容器行。
class _ContainerTile extends StatelessWidget {
  const _ContainerTile({
    required this.container,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onRemove,
  });

  final ContainerInfo container;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = container.isRunning;
    return ListTile(
      leading: Icon(Icons.inventory_2, color: running ? Colors.green : Colors.grey),
      title: Text(container.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(container.image),
          if (container.ports.isNotEmpty)
            Text(
              container.ports.join(', '),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: '启动',
            onPressed: running ? null : onStart,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: '停止',
            onPressed: running ? onStop : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重启',
            onPressed: onRestart,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: onRemove,
          ),
        ],
      ),
      onTap: () => showAppDialog<void>(
        context,
        (_) => AlertDialog(
          title: Text(container.name),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kv('状态', container.status),
                _kv('镜像', container.image),
                if (container.ports.isNotEmpty)
                  _kv('端口', container.ports.join('\n')),
                if (container.createdAt != null)
                  _kv(
                    '创建时间',
                    container.createdAt!
                        .toLocal()
                        .toString()
                        .split('.')
                        .first,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              key,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 高亮容器卡片（实例自身的容器）。
class _HighlightContainerCard extends StatelessWidget {
  const _HighlightContainerCard({
    required this.container,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final ContainerInfo container;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = container.isRunning;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: running ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    container.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (running ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    container.status,
                    style: TextStyle(
                      fontSize: 12,
                      color: running ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              container.image,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
            ),
            if (container.ports.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                container.ports.join(', '),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: running ? null : onStart,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('启动'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: running ? onStop : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重启'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 构建镜像输入结果。
class _BuildImageInput {
  const _BuildImageInput({
    required this.dockerfile,
    required this.name,
    required this.tag,
  });

  final String dockerfile;
  final String name;
  final String tag;
}

/// 构建镜像对话框（Dockerfile 文本 + 名称 + 标签）。
class _BuildImageDialog extends StatefulWidget {
  const _BuildImageDialog();

  @override
  State<_BuildImageDialog> createState() => _BuildImageDialogState();
}

class _BuildImageDialogState extends State<_BuildImageDialog> {
  final _dockerfileController = TextEditingController(
    text: 'FROM eclipse-temurin:21-jre\n'
        'WORKDIR /data\n'
        'CMD ["java", "-Xmx2G", "-jar", "server.jar", "nogui"]',
  );
  final _nameController = TextEditingController(text: 'mc-server');
  final _tagController = TextEditingController(text: 'latest');

  @override
  void dispose() {
    _dockerfileController.dispose();
    _nameController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('构建镜像'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '镜像名称',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(
                      labelText: '标签',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dockerfileController,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: 'Dockerfile',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '构建上下文为 stdin（与 MCSM dockerFile 一致）；需要 COPY 本地文件时请把文件放进镜像基础层。',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            final name = _nameController.text.trim();
            final tag = _tagController.text.trim();
            final dockerfile = _dockerfileController.text;
            if (name.isEmpty || dockerfile.trim().isEmpty) return;
            Navigator.pop(
              context,
              _BuildImageInput(
                dockerfile: dockerfile,
                name: name,
                tag: tag.isEmpty ? 'latest' : tag,
              ),
            );
          },
          icon: const Icon(Icons.build_circle_outlined),
          label: const Text('开始构建'),
        ),
      ],
    );
  }
}

/// 构建进度对话框（轮询后端直到完成）。
class _BuildProgressDialog extends StatefulWidget {
  const _BuildProgressDialog({
    required this.backend,
    required this.jobId,
    required this.title,
  });

  final ContainerBackend backend;
  final String jobId;
  final String title;

  @override
  State<_BuildProgressDialog> createState() => _BuildProgressDialogState();
}

class _BuildProgressDialogState extends State<_BuildProgressDialog> {
  String _status = 'building';
  final List<String> _log = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  void _poll() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    unawaited(_tick());
  }

  Future<void> _tick() async {
    try {
      final progress = await widget.backend.buildProgress(widget.jobId);
      if (!mounted) return;
      setState(() {
        _status = progress.status;
        if (progress.log.isNotEmpty) {
          _log.clear();
          _log.addAll(progress.log);
        }
      });
      if (progress.isDone) {
        _timer?.cancel();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _status == 'done';
    final failed = _status == 'failed';
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!done && !failed)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    done ? Icons.check_circle : Icons.error,
                    color: done ? Colors.green : Colors.red,
                    size: 18,
                  ),
                const SizedBox(width: 8),
                Text(
                  done
                      ? '构建完成'
                      : failed
                          ? '构建失败'
                          : '构建中...',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _log.isEmpty
                    ? const Text(
                        '等待构建输出...',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Text(
                          _log[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!done && !failed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('后台构建'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 单行文本输入对话框。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.hint,
  });

  final String title;
  final String label;
  final String hint;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            Navigator.pop(context, value.trim());
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
