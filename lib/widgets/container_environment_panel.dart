// 容器环境面板
// 通用的 Docker / Bastille 资源管理面板，按运行时裁切 Tab：
// - Docker：容器、镜像、卷、网络
// - Bastille：容器（jail）、发行版（bootstrap）、转发（rdr）、设置（bastille setup）
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

  /// 是否 Bastille 后端（决定 Tab 布局）。
  bool get _isBastille => widget.backend.runtime == ContainerRuntime.bastille;

  /// 环境探测结果。
  ContainerEnvironmentInfo? _env;
  bool _envLoading = true;

  /// 各 Tab 数据。
  List<ContainerInfo> _containers = [];
  List<ImageInfo> _images = [];
  List<VolumeInfo> _volumes = [];
  List<NetworkInfo> _networks = [];
  List<PortMappingInfo> _rdrMappings = [];

  /// 各 Tab 加载状态。
  bool _containersLoading = false;
  bool _imagesLoading = false;
  bool _volumesLoading = false;
  bool _networksLoading = false;
  bool _rdrLoading = false;

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
      if (_isBastille) {
        unawaited(_refreshRdr());
      } else {
        unawaited(_refreshVolumes());
        unawaited(_refreshNetworks());
      }
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

  Future<void> _refreshRdr() async {
    setState(() => _rdrLoading = true);
    try {
      final list = await widget.backend.listPortMappings();
      if (!mounted) return;
      setState(() => _rdrMappings = list);
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _rdrLoading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      _showSuccess('操作成功：${container.name}');
      await _refreshContainers();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 创建容器 / jail ====================

  Future<void> _openCreateDialog() async {
    final result = await showAppDialog<_CreateInput>(
      context,
      (_) => _CreateContainerDialog(
        isBastille: _isBastille,
        images: _images.map((e) => e.displayTag).toList(),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final info = await widget.backend.createContainer(result.toRequest());
      _showSuccess('已创建：${info.name}');
      await _refreshContainers();
      if (_isBastille) unawaited(_refreshRdr());
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 克隆容器 / jail。
  Future<void> _openCloneDialog(ContainerInfo container) async {
    final result = await showAppDialog<_CloneInput>(
      context,
      (_) => _CloneDialog(source: container.name, isBastille: _isBastille),
    );
    if (result == null || !mounted) return;
    try {
      final info = await widget.backend.cloneContainer(
        container.name,
        newName: result.newName,
        ip: result.ip,
      );
      _showSuccess('已克隆为：${info.name}');
      await _refreshContainers();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 资源限制（内存 / CPU / 磁盘）。
  Future<void> _openLimitsDialog(ContainerInfo container) async {
    final result = await showAppDialog<_LimitsInput>(
      context,
      (_) => const _LimitsDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await widget.backend.updateContainerLimits(
        container.name,
        memoryLimitMb: result.memoryLimitMb,
        cpus: result.cpus,
        diskLimitMb: result.diskLimitMb,
      );
      _showSuccess('资源限制已更新：${container.name}');
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 导出 jail 为归档（Bastille）。
  Future<void> _exportContainer(ContainerInfo container) async {
    try {
      final path = await widget.backend.exportContainer(container.name);
      if (!mounted) return;
      await showAppDialog<void>(
        context,
        (_) => AlertDialog(
          title: Text('导出完成：${container.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('归档已保存到节点上的路径：'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  path,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 从归档导入 jail（Bastille）。
  Future<void> _openImportDialog() async {
    final result = await showAppDialog<_ImportInput>(
      context,
      (_) => const _ImportDialog(),
    );
    if (result == null || !mounted) return;
    try {
      final info = await widget.backend.importContainer(
        result.file,
        release: result.release,
        force: result.force,
      );
      _showSuccess('导入完成：${info.name}');
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
      final isBastille = _isBastille;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBastille ? Icons.deck_outlined : Icons.inventory_2,
              size: 48,
              color: Colors.grey,
            ),
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
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isBastille
                    ? 'Bastille 运行在 FreeBSD 节点上：请在「节点管理」中添加在线 '
                        'FreeBSD 节点（irix-node）后，从节点详情页的「容器」Tab 管理 jail。'
                    : '本机使用 Docker 环境：安装并启动 Docker Desktop（或安装 docker '
                        'CLI）后点击「重新检测」即可使用全部容器功能。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
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
          tabs: _isBastille
              ? const [
                  Tab(icon: Icon(Icons.inventory_2), text: '容器'),
                  Tab(icon: Icon(Icons.image), text: '发行'),
                  Tab(icon: Icon(Icons.swap_horiz), text: '转发'),
                  Tab(icon: Icon(Icons.settings), text: '设置'),
                ]
              : const [
                  Tab(icon: Icon(Icons.inventory_2), text: '容器'),
                  Tab(icon: Icon(Icons.image), text: '镜像'),
                  Tab(icon: Icon(Icons.storage), text: '卷'),
                  Tab(icon: Icon(Icons.hub), text: '网络'),
                ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _isBastille
                ? [
                    _buildContainersTab(),
                    _buildImagesTab(),
                    _buildRdrTab(),
                    _buildSetupTab(),
                  ]
                : [
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
            onClone: () => _openCloneDialog(highlightInfo),
            onLimits: () => _openLimitsDialog(highlightInfo),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                _isBastille ? 'Jail 列表' : '容器列表',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshContainers,
              ),
              if (_isBastille)
                FilledButton.tonalIcon(
                  onPressed: _openImportDialog,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导入'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(_isBastille ? '创建 Jail' : '创建容器'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _containersLoading
              ? const Center(child: CircularProgressIndicator())
              : _containers.isEmpty
                  ? Center(child: Text(_isBastille ? '暂无 Jail' : '暂无容器'))
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
                          onClone: () => _openCloneDialog(c),
                          onLimits: () => _openLimitsDialog(c),
                          onExport: _isBastille ? () => _exportContainer(c) : null,
                          onRemove: () => _runContainerAction(
                            c,
                            () => widget.backend.removeContainer(
                              c.name,
                              force: true,
                            ),
                            confirmText:
                                '确定删除${_isBastille ? ' Jail' : '容器'} ${c.name} 吗？'
                                '${_isBastille ? '\n（运行中的 Jail 将以 -a 强制摧毁）' : ''}',
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ==================== 镜像 / 发行版 Tab ====================

  Widget _buildImagesTab() {
    final isBastille = _isBastille;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                isBastille ? '已 Bootstrap 的发行版' : '镜像列表',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshImages,
              ),
              FilledButton.tonalIcon(
                onPressed: _openPullImageDialog,
                icon: const Icon(Icons.download, size: 18),
                label: Text(isBastille ? 'Bootstrap' : '拉取'),
              ),
              if (!isBastille) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openBuildImageDialog,
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: const Text('构建'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _imagesLoading
              ? const Center(child: CircularProgressIndicator())
              : _images.isEmpty
                  ? Center(
                      child: Text(
                        isBastille
                            ? '暂无发行版，点击 Bootstrap 拉取（如 14.2-RELEASE）'
                            : '暂无镜像',
                      ),
                    )
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
                          trailing: isBastille
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除镜像',
                                  onPressed: () async {
                                    final ok = await showAppDialog<bool>(
                                      context,
                                      (_) => AlertDialog(
                                        title: const Text('删除镜像'),
                                        content: Text(
                                          '确定删除镜像 ${image.displayTag} 吗？',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton.tonal(
                                            style: FilledButton.styleFrom(
                                              foregroundColor: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('删除'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true || !mounted) return;
                                    try {
                                      await widget.backend.removeImage(
                                        image.displayTag,
                                      );
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
    final isBastille = _isBastille;
    final name = await showAppDialog<String>(
      context,
      (_) => _TextInputDialog(
        title: isBastille ? 'Bootstrap 发行版' : '拉取镜像',
        label: isBastille ? '发行版名称' : '镜像名称',
        hint: isBastille ? '如 14.2-RELEASE' : '如 itzg/minecraft-server:latest',
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await widget.backend.pullImage(name.trim());
      _showSuccess(
        isBastille
            ? 'Bootstrap 任务已提交：${name.trim()}（后台进行，稍后刷新列表）'
            : '镜像拉取完成：${name.trim()}',
      );
      await _refreshImages();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 转发（rdr）Tab ====================

  Widget _buildRdrTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                '端口转发规则（bastille rdr）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _refreshRdr,
              ),
              FilledButton.icon(
                onPressed: _openRdrDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加转发'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rdrLoading
              ? const Center(child: CircularProgressIndicator())
              : _rdrMappings.isEmpty
                  ? const Center(child: Text('暂无转发规则'))
                  : ListView.builder(
                      itemCount: _rdrMappings.length,
                      itemBuilder: (context, index) {
                        final mapping = _rdrMappings[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.swap_horiz,
                            color: Colors.grey,
                          ),
                          title: Text(mapping.container),
                          subtitle: Text(
                            '${mapping.proto}  宿主机 ${mapping.hostPort} → jail ${mapping.containerPort}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除转发',
                            onPressed: () async {
                              final ok = await showAppDialog<bool>(
                                context,
                                (_) => AlertDialog(
                                  title: const Text('删除转发'),
                                  content: Text(
                                    '确定删除 ${mapping.container} 的 '
                                    '${mapping.proto} ${mapping.hostPort}→${mapping.containerPort} 吗？',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true || !mounted) return;
                              try {
                                await widget.backend.removePortMapping(
                                  PortMappingRequest(
                                    container: mapping.container,
                                    proto: mapping.proto,
                                    hostPort: mapping.hostPort,
                                    containerPort: mapping.containerPort,
                                  ),
                                );
                                _showSuccess('转发规则已删除');
                                await _refreshRdr();
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

  Future<void> _openRdrDialog() async {
    final result = await showAppDialog<_RdrInput>(
      context,
      (_) => _RdrDialog(jails: _containers.map((c) => c.name).toList()),
    );
    if (result == null || !mounted) return;
    try {
      await widget.backend.addPortMapping(
        PortMappingRequest(
          container: result.jail,
          proto: result.proto,
          hostPort: result.hostPort,
          containerPort: result.containerPort,
        ),
      );
      _showSuccess('转发规则已添加');
      await _refreshRdr();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 设置（bastille setup）Tab ====================

  Widget _buildSetupTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SetupCard(
          backend: widget.backend,
          mode: 'default',
          icon: Icons.auto_awesome_outlined,
          title: '一键默认初始化',
          description: '不带选项执行 bastille setup：自动配置 loopback（bastille0）、'
              'firewall 与 storage。多数场景足够使用。',
          fields: const [],
          runLabel: '执行 bastille setup',
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'firewall',
          icon: Icons.shield_outlined,
          title: '防火墙（firewall）',
          description: '配置 PF 防火墙：启用服务并生成默认 pf.conf —— '
              '端口转发（bastille rdr）的前提。',
          fields: const [
            ('extIf', '外网网卡', '如 em0', ''),
          ],
          runLabel: '执行 bastille setup firewall',
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'vnet',
          icon: Icons.lan_outlined,
          title: 'VNET 网络（vnet）',
          description: '为 VNET jail（-V）配置宿主网络。'
              '参数为可选项（部分版本为交互式，由服务端注入）。',
          fields: const [
            ('extIf', '外网网卡', '如 em0', ''),
            ('tunIf', '桥接网卡', '默认 bastille0', 'bastille0'),
            ('addr', '网段', '如 10.99.0.0/24', '10.99.0.0/24'),
          ],
          runLabel: '执行 bastille setup vnet',
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'bridge',
          icon: Icons.hub_outlined,
          title: '桥接网络（bridge）',
          description: '配置桥接网卡 —— 桥接 VNET jail（-B）的前提。'
              '需先在系统上创建 bridge 接口（如 ifconfig bridge create）。',
          fields: const [],
          runLabel: '执行 bastille setup bridge',
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'shared',
          icon: Icons.cell_tower,
          title: '共享网卡（shared）',
          description: '将指定网卡设为共享接口：create 未指定 INTERFACE 时默认使用。'
              '与 loopback 互斥（配置其一将禁用另一项）。',
          fields: const [
            ('extIf', '网卡', '如 em0', ''),
          ],
          runLabel: '执行 bastille setup shared',
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'linux',
          icon: Icons.terminal,
          title: 'Linux Jail（linux）',
          description: '初始化 Linuxulator —— 创建 Linux jail（-L）的前提：'
              '加载所需内核模块并安装 debootstrap 包。',
          fields: const [],
          runLabel: '执行 bastille setup linux',
        ),
      ],
    );
  }

  // ==================== 卷 / 网络 Tab（Docker）====================

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
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(context, true),
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
    required this.onClone,
    required this.onLimits,
    required this.onRemove,
    this.onExport,
  });

  final ContainerInfo container;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onClone;
  final VoidCallback onLimits;
  final VoidCallback onRemove;

  /// Bastille：导出为归档。
  final VoidCallback? onExport;

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
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'restart':
                  onRestart();
                case 'clone':
                  onClone();
                case 'limits':
                  onLimits();
                case 'export':
                  onExport?.call();
                case 'remove':
                  onRemove();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'restart', child: Text('重启')),
              const PopupMenuItem(value: 'clone', child: Text('克隆')),
              const PopupMenuItem(value: 'limits', child: Text('资源限制')),
              if (onExport != null)
                const PopupMenuItem(value: 'export', child: Text('导出归档')),
              const PopupMenuItem(value: 'remove', child: Text('删除')),
            ],
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
    required this.onClone,
    required this.onLimits,
  });

  final ContainerInfo container;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onClone;
  final VoidCallback onLimits;

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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '克隆',
                  onPressed: onClone,
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: '资源限制',
                  onPressed: onLimits,
                  icon: const Icon(Icons.speed_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 创建容器 / jail 对话框 ====================

/// 创建输入结果。
class _CreateInput {
  const _CreateInput({
    required this.name,
    required this.image,
    required this.isBastille,
    this.ip,
    this.jailType,
    this.vnetMode,
    this.vnetInterface,
    this.ports = const [],
    this.volumes = const [],
    this.env = const {},
    this.restartPolicy,
    this.memoryLimitMb,
    this.cpus,
    this.diskLimitMb,
    this.workdir,
    this.command,
  });

  final String name;
  final String image;
  final bool isBastille;
  final String? ip;
  final String? jailType;

  /// none | vnet | bridge（Bastille 的 -V / -B）。
  final String? vnetMode;

  /// INTERFACE 位置参数（-V 物理网卡 / -B 桥接网卡）。
  final String? vnetInterface;

  final List<String> ports;
  final List<String> volumes;
  final Map<String, String> env;
  final String? restartPolicy;
  final int? memoryLimitMb;
  final int? cpus;
  final int? diskLimitMb;
  final String? workdir;
  final String? command;

  CreateContainerRequest toRequest() => CreateContainerRequest(
        name: name,
        image: image,
        command: command,
        ports: ports,
        volumes: volumes,
        env: env,
        restartPolicy: isBastille ? null : restartPolicy,
        memoryLimitMb: memoryLimitMb,
        cpus: cpus,
        diskLimitMb: diskLimitMb,
        workdir: workdir,
        ip: ip,
        jailType: isBastille ? jailType : null,
        vnetMode: isBastille ? vnetMode : null,
        vnetInterface: isBastille ? vnetInterface : null,
      );
}

/// 创建容器 / jail 对话框（按运行时裁切字段）。
class _CreateContainerDialog extends StatefulWidget {
  const _CreateContainerDialog({
    required this.isBastille,
    required this.images,
  });

  final bool isBastille;

  /// 已有镜像 / 发行版（可点击快速填入）。
  final List<String> images;

  @override
  State<_CreateContainerDialog> createState() => _CreateContainerDialogState();
}

class _CreateContainerDialogState extends State<_CreateContainerDialog> {
  final _nameController = TextEditingController();
  final _imageController = TextEditingController();
  final _ipController = TextEditingController(text: '192.168.1.50/24');
  final _interfaceController = TextEditingController(text: 'em0');
  final _portsController = TextEditingController(text: '25565:25565');
  final _volumesController = TextEditingController();
  final _envController = TextEditingController();
  final _commandController = TextEditingController();
  final _memoryController = TextEditingController();
  final _cpusController = TextEditingController();
  final _diskController = TextEditingController();
  final _workdirController = TextEditingController();

  String _jailType = 'thin';
  String _vnetMode = 'none';
  String? _restartPolicy = 'unless-stopped';

  @override
  void dispose() {
    _nameController.dispose();
    _imageController.dispose();
    _ipController.dispose();
    _interfaceController.dispose();
    _portsController.dispose();
    _volumesController.dispose();
    _envController.dispose();
    _commandController.dispose();
    _memoryController.dispose();
    _cpusController.dispose();
    _diskController.dispose();
    _workdirController.dispose();
    super.dispose();
  }

  List<String> _splitList(String text) => text
      .split(RegExp(r'[\n,;]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

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

  void _submit() {
    final name = _nameController.text.trim();
    final image = _imageController.text.trim();
    // empty 类型仅需 NAME（bastille create -E NAME）。
    final isEmptyJail = widget.isBastille && _jailType == 'empty';
    if (name.isEmpty || (!isEmptyJail && image.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(isEmptyJail
              ? '请填写 Jail 名称'
              : '名称与镜像 / 发行版不能为空'),
        ),
      );
      return;
    }
    if (widget.isBastille) {
      // Bastille 的 jail 名不允许含点号与斜杠等字符。
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Jail 名仅允许字母、数字、- 和 _')),
        );
        return;
      }
      // Bastille 的 NAME / RELEASE / IP 需显式声明（empty 仅 NAME；VNET 另有 --no-ip）。
      if (!isEmptyJail && _ipController.text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Bastille 创建 Jail 必须显式声明 IP 地址')),
        );
        return;
      }
      // Linux Jail 与任何 VNET 模式互斥。
      if (_jailType == 'linux' && _vnetMode != 'none') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('Linux Jail（-L）不能与 VNET（-V/-B）同时使用')),
        );
        return;
      }
      if (_vnetMode != 'none') {
        // VNET 需要网卡参数（-V 物理网卡 / -B 桥接网卡），且 IP 须含子网掩码。
        if (_interfaceController.text.trim().isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _vnetMode == 'bridge' ? '请填写桥接网卡名称' : '请填写物理网卡名称',
              ),
            ),
          );
          return;
        }
        if (!_ipController.text.contains('/')) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(content: Text('VNET Jail 的 IP 必须含子网掩码，如 192.168.1.50/24')),
          );
          return;
        }
      }
    }
    final ports = _splitList(_portsController.text);
    for (final port in ports) {
      if (!RegExp(r'^\d+:\d+$').hasMatch(port)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text('端口格式错误：$port（应为 宿主机:容器端口）')),
        );
        return;
      }
    }
    Navigator.pop(
      context,
      _CreateInput(
        name: name,
        image: image,
        isBastille: widget.isBastille,
        ip: widget.isBastille
            ? (_ipController.text.trim().isEmpty
                  ? null
                  : _ipController.text.trim())
            : null,
        jailType: _jailType,
        vnetMode: widget.isBastille ? _vnetMode : null,
        vnetInterface: widget.isBastille && _vnetMode != 'none'
            ? (_interfaceController.text.trim().isEmpty
                  ? null
                  : _interfaceController.text.trim())
            : null,
        ports: ports,
        volumes: _splitList(_volumesController.text),
        env: _parseEnv(_envController.text),
        restartPolicy: _restartPolicy,
        memoryLimitMb: int.tryParse(_memoryController.text.trim()),
        cpus: int.tryParse(_cpusController.text.trim()),
        diskLimitMb: int.tryParse(_diskController.text.trim()),
        workdir: _workdirController.text.trim().isEmpty
            ? null
            : _workdirController.text.trim(),
        command: _commandController.text.trim().isEmpty
            ? null
            : _commandController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBastille = widget.isBastille;
    return AlertDialog(
      title: Text(isBastille ? '创建 Jail' : '创建容器'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageController,
                decoration: InputDecoration(
                  labelText: isBastille ? '发行版' : '镜像',
                  helperText: isBastille
                      ? '如 14.2-RELEASE（需先 Bootstrap）'
                      : '如 itzg/minecraft-server:latest',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.images.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in widget.images)
                      ActionChip(
                        label: Text(
                          tag,
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _imageController.text = tag),
                      ),
                  ],
                ),
              ],
              if (isBastille) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP 地址',
                          helperText: '含前缀，如 192.168.1.50/24',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _jailType,
                        decoration: const InputDecoration(
                          labelText: 'Jail 类型',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'thin',
                            child: Text('thin — 符号链接样板（默认）'),
                          ),
                          DropdownMenuItem(
                            value: 'thick',
                            child: Text('thick — 厚容器（-T 解压样板）'),
                          ),
                          DropdownMenuItem(
                            value: 'clone',
                            child: Text('clone — 克隆现有发行版'),
                          ),
                          DropdownMenuItem(
                            value: 'empty',
                            child: Text('empty — 空容器（-E，仅需名称）'),
                          ),
                          DropdownMenuItem(
                            value: 'linux',
                            child: Text('linux — Linux Jail（-L）'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _jailType = value ?? 'thin';
                          // Linux Jail 与 VNET 互斥：切到 linux 时关闭 VNET。
                          if (_jailType == 'linux') _vnetMode = 'none';
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _vnetMode,
                        decoration: const InputDecoration(
                          labelText: 'VNET 模式',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'none',
                            child: Text('不使用 VNET（共享宿主网络）'),
                          ),
                          const DropdownMenuItem(
                            value: 'vnet',
                            child: Text('VNET（-V，网卡须为物理网卡）'),
                          ),
                          DropdownMenuItem(
                            value: 'bridge',
                            enabled: _jailType != 'linux',
                            child: const Text('桥接 VNET（-B，网卡须为桥接网卡）'),
                          ),
                        ],
                        onChanged: _jailType == 'linux'
                            ? null
                            : (value) =>
                                  setState(() => _vnetMode = value ?? 'none'),
                      ),
                    ),
                    if (_vnetMode != 'none') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _interfaceController,
                          decoration: InputDecoration(
                            labelText: _vnetMode == 'bridge' ? '桥接网卡' : '物理网卡',
                            hintText: _vnetMode == 'bridge' ? '如 bridge0' : '如 em0',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _portsController,
                decoration: InputDecoration(
                  labelText: '端口映射',
                  helperText: isBastille
                      ? '宿主机端口:jail 端口，多个用逗号分隔；创建后经 rdr 自动应用'
                      : '宿主机端口:容器端口，多个用逗号分隔',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _volumesController,
                decoration: InputDecoration(
                  labelText: isBastille ? '数据目录挂载（nullfs）' : '卷挂载',
                  helperText: isBastille
                      ? '宿主机路径:jail 内路径，多个用逗号分隔'
                      : '宿主机路径:容器路径，多个用逗号分隔',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!isBastille) ...[
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
                      child: Text('unless-stopped — 退出自动重启'),
                    ),
                    DropdownMenuItem(
                      value: 'always',
                      child: Text('always — 总是重启'),
                    ),
                    DropdownMenuItem(
                      value: 'on-failure',
                      child: Text('on-failure — 异常退出时重启'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _restartPolicy = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    labelText: '启动命令（留空用镜像默认）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _workdirController,
                decoration: const InputDecoration(
                  labelText: '工作目录（留空默认）',
                  helperText: '如 /data —— 强制在挂载的数据目录内启动',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _diskController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '磁盘上限（MB，留空不限）',
                  helperText: isBastille
                      ? 'ZFS 数据集配额'
                      : '依赖存储驱动支持 size 配额',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (isBastille)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '提示：thin（默认）/ thick（-T）/ clone（-C）/ empty（-E，仅需名称）/ linux（-L）'
                    '为互斥的创建方式；Linux Jail 不能与 VNET（-V/-B）同时使用；'
                    'VNET 需先完成「设置」页的网络初始化，IP 必须含子网掩码。',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: Text(isBastille ? '创建 Jail' : '创建容器'),
        ),
      ],
    );
  }
}

// ==================== 克隆对话框 ====================

class _CloneInput {
  const _CloneInput({required this.newName, this.ip});

  final String newName;
  final String? ip;
}

/// 克隆容器 / jail 对话框。
class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.source, required this.isBastille});

  final String source;
  final bool isBastille;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  late final TextEditingController _nameController;
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '${widget.source}-clone');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('克隆 ${widget.source}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新名称',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.isBastille) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: '新 IP 地址（留空沿用源，需含前缀）',
                  hintText: '如 192.168.1.51/24',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _CloneInput(
                newName: name,
                ip: widget.isBastille
                    ? (_ipController.text.trim().isEmpty
                          ? null
                          : _ipController.text.trim())
                    : null,
              ),
            );
          },
          child: const Text('克隆'),
        ),
      ],
    );
  }
}

// ==================== 资源限制对话框 ====================

class _LimitsInput {
  const _LimitsInput({
    this.memoryLimitMb,
    this.cpus,
    this.diskLimitMb,
  });

  final int? memoryLimitMb;
  final int? cpus;
  final int? diskLimitMb;
}

/// 资源限制对话框（内存 / CPU / 磁盘）。
class _LimitsDialog extends StatefulWidget {
  const _LimitsDialog();

  @override
  State<_LimitsDialog> createState() => _LimitsDialogState();
}

class _LimitsDialogState extends State<_LimitsDialog> {
  final _memoryController = TextEditingController();
  final _cpusController = TextEditingController();
  final _diskController = TextEditingController();

  @override
  void dispose() {
    _memoryController.dispose();
    _cpusController.dispose();
    _diskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('资源限制'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _memoryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '内存上限（MB，留空不变）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cpusController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CPU 核数（留空不变）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diskController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '磁盘上限（MB，留空不变）',
                helperText: 'Docker 不支持热更新磁盘上限',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LimitsInput(
              memoryLimitMb: int.tryParse(_memoryController.text.trim()),
              cpus: int.tryParse(_cpusController.text.trim()),
              diskLimitMb: int.tryParse(_diskController.text.trim()),
            ),
          ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

// ==================== 转发（rdr）对话框 ====================

class _RdrInput {
  const _RdrInput({
    required this.jail,
    required this.proto,
    required this.hostPort,
    required this.containerPort,
  });

  final String jail;
  final String proto;
  final int hostPort;
  final int containerPort;
}

/// 添加端口转发对话框（Bastille rdr）。
class _RdrDialog extends StatefulWidget {
  const _RdrDialog({required this.jails});

  /// 现有 jail 名列表。
  final List<String> jails;

  @override
  State<_RdrDialog> createState() => _RdrDialogState();
}

class _RdrDialogState extends State<_RdrDialog> {
  String? _jail;
  String _proto = 'tcp';
  final _hostPortController = TextEditingController();
  final _jailPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _jail = widget.jails.firstOrNull;
  }

  @override
  void dispose() {
    _hostPortController.dispose();
    _jailPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加端口转发'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _jail,
              decoration: const InputDecoration(
                labelText: 'Jail',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final name in widget.jails)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) => setState(() => _jail = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _proto,
              decoration: const InputDecoration(
                labelText: '协议',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'tcp', child: Text('tcp')),
                DropdownMenuItem(value: 'udp', child: Text('udp')),
              ],
              onChanged: (value) => setState(() => _proto = value ?? 'tcp'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '宿主机端口',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _jailPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Jail 内端口',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final jail = _jail;
            final hostPort = int.tryParse(_hostPortController.text.trim());
            final jailPort = int.tryParse(_jailPortController.text.trim());
            if (jail == null || jail.isEmpty || hostPort == null || jailPort == null) {
              return;
            }
            Navigator.pop(
              context,
              _RdrInput(
                jail: jail,
                proto: _proto,
                hostPort: hostPort,
                containerPort: jailPort,
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

// ==================== 导入对话框 ====================

class _ImportInput {
  const _ImportInput({
    required this.file,
    this.release,
    this.force = false,
  });

  final String file;

  /// 指定导入到哪个发行版（`bastille import FILE [RELEASE]`，可选）。
  final String? release;

  /// 跳过校验和验证（-f）。
  final bool force;
}

/// 从归档导入 jail 对话框（Bastille）。
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _fileController = TextEditingController();
  final _releaseController = TextEditingController();
  bool _force = false;

  @override
  void dispose() {
    _fileController.dispose();
    _releaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入 Jail'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fileController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '归档路径（节点上的归档文件）',
                hintText: '如 /usr/local/bastille/backups/xxx.txz',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _releaseController,
              decoration: const InputDecoration(
                labelText: '指定发行版（留空按归档内名称）',
                hintText: '如 14.2-RELEASE',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: _force,
              onChanged: (value) => setState(() => _force = value ?? false),
              title: const Text('跳过校验和验证（-f / --force）'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final file = _fileController.text.trim();
            if (file.isEmpty) return;
            Navigator.pop(
              context,
              _ImportInput(
                file: file,
                release: _releaseController.text.trim().isEmpty
                    ? null
                    : _releaseController.text.trim(),
                force: _force,
              ),
            );
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}

// ==================== bastille setup 设置卡片 ====================

/// 单条 setup 动作卡片（pf / vnet / linux）。
class _SetupCard extends StatefulWidget {
  const _SetupCard({
    required this.backend,
    required this.mode,
    required this.icon,
    required this.title,
    required this.description,
    required this.fields,
    required this.runLabel,
  });

  final ContainerBackend backend;
  final String mode;
  final IconData icon;
  final String title;
  final String description;

  /// 输入字段：(键, 标签, 提示, 初始值)。
  final List<(String, String, String, String)> fields;

  final String runLabel;

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  final Map<String, TextEditingController> _controllers = {};
  bool _busy = false;
  String? _result;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    for (final (key, _, _, initial) in widget.fields) {
      _controllers[key] = TextEditingController(text: initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final mode = widget.mode;
    final extIf = _controllers['extIf']?.text.trim() ?? '';
    // firewall / vnet / shared 需要网卡参数；default / bridge / linux 无需。
    final needsExtIf = mode == 'firewall' || mode == 'vnet' || mode == 'shared';
    if (needsExtIf && extIf.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写网卡名称')));
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await widget.backend.setupEnvironment(
        BastilleSetupRequest(
          mode: mode,
          extIf: _controllers['extIf']?.text.trim().isEmpty ?? true
              ? null
              : _controllers['extIf']!.text.trim(),
          tunIf: _controllers['tunIf']?.text.trim().isEmpty ?? true
              ? null
              : _controllers['tunIf']!.text.trim(),
          addr: _controllers['addr']?.text.trim().isEmpty ?? true
              ? null
              : _controllers['addr']!.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _resultOk = result.ok;
        _result = result.detail ?? (result.ok ? '初始化完成' : '初始化失败');
      });
    } on ContainerBackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _resultOk = false;
        _result = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(widget.title, style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.description,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            if (widget.fields.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (key, label, hint, _) in widget.fields) ...[
                    Expanded(
                      child: TextField(
                        controller: _controllers[key],
                        decoration: InputDecoration(
                          labelText: label,
                          hintText: hint,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_resultOk ? Colors.green : Colors.red)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _result!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: _resultOk ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _run,
                icon: const Icon(Icons.terminal, size: 16),
                label: Text(widget.runLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 构建镜像 ====================

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
