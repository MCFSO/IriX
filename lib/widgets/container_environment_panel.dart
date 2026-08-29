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
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../screens/bastille_jail_detail_screen.dart';
import '../services/container/container_backend.dart';
import '../services/font_settings.dart';
import '../services/node_api_client.dart';
import '../utils/apple_widgets.dart';

/// 容器环境面板。
class ContainerEnvironmentPanel extends StatefulWidget {
  const ContainerEnvironmentPanel({
    super.key,
    required this.backend,
    this.highlightName,
    this.nodeClient,
    this.daemonId,
  });

  /// 容器后端（本地 Docker / 远程节点）。
  final ContainerBackend backend;

  /// 需要高亮的容器名（实例自身的容器）。
  final String? highlightName;

  /// 节点 API 客户端（Bastille Jail 详情页的实例选择用）。
  final NodeApiClient? nodeClient;

  /// 守护进程 id（配合 [nodeClient] 使用）。
  final String? daemonId;

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
    final l = AppLocalizations.of(context);
    if (confirmText != null) {
      final ok = await showAppDialog<bool>(
        context,
        (_) => AlertDialog(
          title: Text(l.container_confirmOperation),
          content: Text(confirmText),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.common_cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.common_confirm),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await action();
      _showSuccess(l.container_operationSuccess(container.name));
      await _refreshContainers();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 打开 Jail 详情页（Bastille 深度管理：运行/控制台/软件包/挂载/设置）。
  Future<void> _openJailDetail(ContainerInfo container) async {
    await pushPage<void>(
      context,
      (_) => JailDetailScreen(
        backend: widget.backend,
        jailName: container.name,
        nodeClient: widget.nodeClient,
        daemonId: widget.daemonId,
        initialContainer: container,
      ),
    );
    await _refreshContainers();
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
      final l = AppLocalizations.of(context);
      final info = await widget.backend.createContainer(result.toRequest());
      _showSuccess(l.container_created(info.name));
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
      final l = AppLocalizations.of(context);
      final info = await widget.backend.cloneContainer(
        container.name,
        newName: result.newName,
        ip: result.ip,
      );
      _showSuccess(l.container_cloned(info.name));
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
      final l = AppLocalizations.of(context);
      await widget.backend.updateContainerLimits(
        container.name,
        memoryLimitMb: result.memoryLimitMb,
        cpus: result.cpus,
        diskLimitMb: result.diskLimitMb,
      );
      _showSuccess(l.container_limitsUpdated(container.name));
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  /// 导出 jail 为归档（Bastille）。
  Future<void> _exportContainer(ContainerInfo container) async {
    try {
      final l = AppLocalizations.of(context);
      final path = await widget.backend.exportContainer(container.name);
      if (!mounted) return;
      await showAppDialog<void>(
        context,
        (_) => AlertDialog(
          title: Text(l.container_exportDone(container.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.container_exportSavedPath),
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
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.common_close),
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
      final l = AppLocalizations.of(context);
      final info = await widget.backend.importContainer(
        result.file,
        release: result.release,
        force: result.force,
      );
      _showSuccess(l.container_importDone(info.name));
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
    final l = AppLocalizations.of(context);
    showAppDialog<void>(
      context,
      (_) => _BuildProgressDialog(
        backend: widget.backend,
        jobId: jobId,
        title: l.container_buildTitle(imageName),
      ),
    );
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              l.container_envUnavailable(widget.backend.displayName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                isBastille
                    ? l.container_envUnavailableBastille
                    : l.container_envUnavailableDocker,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _probeEnvironment,
              icon: const Icon(Icons.refresh),
              label: Text(l.container_redetect),
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
                    _env!.errorMessage ?? l.container_envLabel(widget.backend.displayName),
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
              ? [
                  Tab(icon: const Icon(Icons.inventory_2), text: l.container_tabContainers),
                  Tab(icon: const Icon(Icons.image), text: l.container_tabRelease),
                  Tab(icon: const Icon(Icons.swap_horiz), text: l.container_tabForward),
                  Tab(icon: const Icon(Icons.settings), text: l.container_tabSettings),
                ]
              : [
                  Tab(icon: const Icon(Icons.inventory_2), text: l.container_tabContainers),
                  Tab(icon: const Icon(Icons.image), text: l.container_tabImages),
                  Tab(icon: const Icon(Icons.storage), text: l.container_tabVolumes),
                  Tab(icon: const Icon(Icons.hub), text: l.container_tabNetworks),
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
    final l = AppLocalizations.of(context);
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
                _isBastille ? l.container_jailList : l.container_containerList,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
                onPressed: _refreshContainers,
              ),
              if (_isBastille)
                FilledButton.tonalIcon(
                  onPressed: _openImportDialog,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(l.container_import),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(_isBastille ? l.container_createJail : l.container_createContainer),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _containersLoading
              ? const Center(child: CircularProgressIndicator())
              : _containers.isEmpty
              ? Center(child: Text(_isBastille ? l.container_noJails : l.container_noContainers))
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
                      onManage: _isBastille ? () => _openJailDetail(c) : null,
                      onExport: _isBastille ? () => _exportContainer(c) : null,
                      onRemove: () => _runContainerAction(
                        c,
                        () =>
                            widget.backend.removeContainer(c.name, force: true),
                        confirmText: _isBastille
                            ? l.container_deleteConfirmJail(c.name)
                            : l.container_deleteConfirmContainer(c.name),
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
    final l = AppLocalizations.of(context);
    final isBastille = _isBastille;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                isBastille ? l.container_bootstrappedReleases : l.container_imageList,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
                onPressed: _refreshImages,
              ),
              FilledButton.tonalIcon(
                onPressed: _openPullImageDialog,
                icon: const Icon(Icons.download, size: 18),
                label: Text(isBastille ? l.container_bootstrap : l.container_pull),
              ),
              if (!isBastille) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _openBuildImageDialog,
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: Text(l.container_build),
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
                        ? l.container_noReleases
                        : l.container_noImages,
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
                              tooltip: l.container_deleteImage,
                              onPressed: () async {
                                final ok = await showAppDialog<bool>(
                                  context,
                                  (_) => AlertDialog(
                                    title: Text(l.container_deleteImage),
                                    content: Text(
                                      l.container_deleteImageConfirm(
                                        image.displayTag,
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(l.common_cancel),
                                      ),
                                      FilledButton.tonal(
                                        style: FilledButton.styleFrom(
                                          foregroundColor: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(l.common_delete),
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
    final l = AppLocalizations.of(context);
    final isBastille = _isBastille;
    final name = await showAppDialog<String>(
      context,
      (_) => _TextInputDialog(
        title: isBastille ? l.container_bootstrapRelease : l.container_pullImage,
        label: isBastille ? l.container_releaseName : l.container_imageName,
        hint: isBastille ? l.container_releaseNameHint : l.container_imageNameHint,
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await widget.backend.pullImage(name.trim());
      _showSuccess(
        isBastille
            ? l.container_bootstrapSubmitted(name.trim())
            : l.container_pullDone(name.trim()),
      );
      await _refreshImages();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 转发（rdr）Tab ====================

  Widget _buildRdrTab() {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                l.container_rdrRules,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
                onPressed: _refreshRdr,
              ),
              FilledButton.icon(
                onPressed: _openRdrDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.container_addForward),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rdrLoading
              ? const Center(child: CircularProgressIndicator())
              : _rdrMappings.isEmpty
              ? Center(child: Text(l.container_noRdrRules))
              : ListView.builder(
                  itemCount: _rdrMappings.length,
                  itemBuilder: (context, index) {
                    final mapping = _rdrMappings[index];
                    return ListTile(
                      leading: const Icon(Icons.swap_horiz, color: Colors.grey),
                      title: Text(mapping.container),
                      subtitle: Text(
                        l.container_rdrSubtitle(
                          mapping.proto,
                          mapping.hostPort,
                          mapping.containerPort,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l.container_deleteForward,
                        onPressed: () async {
                          final ok = await showAppDialog<bool>(
                            context,
                            (_) => AlertDialog(
                              title: Text(l.container_deleteForward),
                              content: Text(
                                l.container_deleteForwardConfirm(
                                  mapping.container,
                                  mapping.proto,
                                  mapping.hostPort,
                                  mapping.containerPort,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l.common_cancel),
                                ),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l.common_delete),
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
                            _showSuccess(l.container_forwardDeleted);
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
      final l = AppLocalizations.of(context);
      await widget.backend.addPortMapping(
        PortMappingRequest(
          container: result.jail,
          proto: result.proto,
          hostPort: result.hostPort,
          containerPort: result.containerPort,
        ),
      );
      _showSuccess(l.container_forwardAdded);
      await _refreshRdr();
    } on ContainerBackendException catch (e) {
      _showError(e.message);
    }
  }

  // ==================== 设置（bastille setup）Tab ====================

  Widget _buildSetupTab() {
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SetupCard(
          backend: widget.backend,
          mode: 'default',
          icon: Icons.auto_awesome_outlined,
          title: l.container_setupDefaultTitle,
          description: l.container_setupDefaultDesc,
          fields: const [],
          runLabel: l.container_setupDefaultRun,
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'firewall',
          icon: Icons.shield_outlined,
          title: l.container_setupFirewallTitle,
          description: l.container_setupFirewallDesc,
          fields: [
            ('extIf', l.container_setupFieldExtIf, l.container_setupFieldExtIfHint, ''),
          ],
          runLabel: l.container_setupFirewallRun,
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'vnet',
          icon: Icons.lan_outlined,
          title: l.container_setupVnetTitle,
          description: l.container_setupVnetDesc,
          fields: [
            ('extIf', l.container_setupFieldExtIf, l.container_setupFieldExtIfHint, ''),
            ('tunIf', l.container_setupFieldTunIf, l.container_setupFieldTunIfHint, 'bastille0'),
            ('addr', l.container_setupFieldAddr, l.container_setupFieldAddrHint, '10.99.0.0/24'),
          ],
          runLabel: l.container_setupVnetRun,
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'bridge',
          icon: Icons.hub_outlined,
          title: l.container_setupBridgeTitle,
          description: l.container_setupBridgeDesc,
          fields: const [],
          runLabel: l.container_setupBridgeRun,
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'shared',
          icon: Icons.cell_tower,
          title: l.container_setupSharedTitle,
          description: l.container_setupSharedDesc,
          fields: [
            ('extIf', l.container_setupFieldNic, l.container_setupFieldExtIfHint, ''),
          ],
          runLabel: l.container_setupSharedRun,
        ),
        const SizedBox(height: 12),
        _SetupCard(
          backend: widget.backend,
          mode: 'linux',
          icon: Icons.terminal,
          title: l.container_setupLinuxTitle,
          description: l.container_setupLinuxDesc,
          fields: const [],
          runLabel: l.container_setupLinuxRun,
        ),
      ],
    );
  }

  // ==================== 卷 / 网络 Tab（Docker）====================

  Widget _buildVolumesTab() {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(l.container_volumeList, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
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
              ? Center(child: Text(l.container_noVolumes))
              : ListView.builder(
                  itemCount: _volumes.length,
                  itemBuilder: (context, index) {
                    final volume = _volumes[index];
                    return ListTile(
                      leading: const Icon(Icons.storage),
                      title: Text(volume.name),
                      subtitle: Text(volume.mountpoint ?? volume.driver ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l.container_deleteVolume,
                        onPressed: () async {
                          final ok = await showAppDialog<bool>(
                            context,
                            (_) => AlertDialog(
                              title: Text(l.container_deleteVolume),
                              content: Text(l.container_deleteVolumeConfirm(volume.name)),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l.common_cancel),
                                ),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                  ),
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l.common_delete),
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
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(l.container_networkList, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.common_refresh,
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
              ? Center(child: Text(l.container_noNetworks))
              : ListView.builder(
                  itemCount: _networks.length,
                  itemBuilder: (context, index) {
                    final network = _networks[index];
                    return ListTile(
                      leading: const Icon(Icons.hub),
                      title: Text(network.name),
                      subtitle: Text(
                        [
                          network.driver,
                          network.subnet,
                        ].whereType<String>().join(' · '),
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
    this.onManage,
    this.onExport,
  });

  final ContainerInfo container;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onClone;
  final VoidCallback onLimits;
  final VoidCallback onRemove;

  /// Bastille：打开 Jail 详情页（运行/控制台/软件包/挂载/设置）。
  final VoidCallback? onManage;

  /// Bastille：导出为归档。
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final running = container.isRunning;
    return ListTile(
      leading: Icon(
        Icons.inventory_2,
        color: running ? Colors.green : Colors.grey,
      ),
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
            tooltip: l.container_start,
            onPressed: running ? null : onStart,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: l.container_stop,
            onPressed: running ? onStop : null,
          ),
          if (onManage != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: l.container_manageDetail,
              onPressed: onManage,
            ),
          PopupMenuButton<String>(
            tooltip: l.container_moreActions,
            onSelected: (value) {
              switch (value) {
                case 'restart':
                  onRestart();
                case 'clone':
                  onClone();
                case 'limits':
                  onLimits();
                case 'manage':
                  onManage?.call();
                case 'export':
                  onExport?.call();
                case 'remove':
                  onRemove();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'restart', child: Text(l.container_restart)),
              PopupMenuItem(value: 'clone', child: Text(l.container_clone)),
              PopupMenuItem(value: 'limits', child: Text(l.container_resourceLimit)),
              if (onManage != null)
                PopupMenuItem(value: 'manage', child: Text(l.container_manageDetail)),
              if (onExport != null)
                PopupMenuItem(value: 'export', child: Text(l.container_exportArchive)),
              PopupMenuItem(value: 'remove', child: Text(l.common_delete)),
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
                _kv(l.container_status, container.status),
                _kv(l.container_image, container.image),
                if (container.ports.isNotEmpty)
                  _kv(l.container_ports, container.ports.join('\n')),
                if (container.createdAt != null)
                  _kv(
                    l.container_createdAt,
                    container.createdAt!.toLocal().toString().split('.').first,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.common_close),
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
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
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
    final l = AppLocalizations.of(context);
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
                    color: (running ? Colors.green : Colors.grey).withValues(
                      alpha: 0.15,
                    ),
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
                  label: Text(l.container_start),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: running ? onStop : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(l.container_stop),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.container_restart),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l.container_clone,
                  onPressed: onClone,
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: l.container_resourceLimit,
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
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final image = _imageController.text.trim();
    // empty 类型仅需 NAME（bastille create -E NAME）。
    final isEmptyJail = widget.isBastille && _jailType == 'empty';
    if (name.isEmpty || (!isEmptyJail && image.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEmptyJail ? l.container_enterJailName : l.container_nameAndImageRequired),
        ),
      );
      return;
    }
    if (widget.isBastille) {
      // Bastille 的 jail 名不允许含点号与斜杠等字符，且不能为纯数字
      // （纯数字会被 jail(8) 当作 jid 解析）。
      if (!RegExp(r'^(?=.*[a-zA-Z])[a-zA-Z0-9_-]+$').hasMatch(name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.container_jailNameRule)),
        );
        return;
      }
      // Bastille 的 NAME / RELEASE / IP 需显式声明（empty 仅 NAME；VNET 另有 --no-ip）。
      if (!isEmptyJail && _ipController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.container_jailIpRequired)),
        );
        return;
      }
      // Linux Jail 与任何 VNET 模式互斥。
      if (_jailType == 'linux' && _vnetMode != 'none') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.container_linuxVnetConflict)),
        );
        return;
      }
      if (_vnetMode != 'none') {
        // VNET 需要网卡参数（-V 物理网卡 / -B 桥接网卡），且 IP 须含子网掩码。
        if (_interfaceController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_vnetMode == 'bridge' ? l.container_enterBridgeNic : l.container_enterPhysicalNic),
            ),
          );
          return;
        }
        if (!_ipController.text.contains('/')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.container_vnetIpMustContainMask),
            ),
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
        ).showSnackBar(SnackBar(content: Text(l.container_portFormatError(port))));
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
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isBastille = widget.isBastille;
    return AlertDialog(
      title: Text(isBastille ? l.container_createJail : l.container_createContainer),
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
                inputFormatters: isBastille
                    ? [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_-]'),
                        ),
                      ]
                    : null,
                decoration: InputDecoration(
                  labelText: l.common_name,
                  helperText: isBastille ? l.container_nameHelperBastille : null,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imageController,
                decoration: InputDecoration(
                  labelText: isBastille ? l.container_release : l.container_image,
                  helperText: isBastille
                      ? l.container_releaseHelper
                      : l.container_imageHelper,
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
                        label: Text(tag, style: const TextStyle(fontSize: 11)),
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
                        decoration: InputDecoration(
                          labelText: l.container_ipAddress,
                          helperText: l.container_ipHelper,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _jailType,
                        decoration: InputDecoration(
                          labelText: l.container_jailType,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'thin',
                            child: Text(l.container_jailTypeThin),
                          ),
                          DropdownMenuItem(
                            value: 'thick',
                            child: Text(l.container_jailTypeThick),
                          ),
                          DropdownMenuItem(
                            value: 'clone',
                            child: Text(l.container_jailTypeClone),
                          ),
                          DropdownMenuItem(
                            value: 'empty',
                            child: Text(l.container_jailTypeEmpty),
                          ),
                          DropdownMenuItem(
                            value: 'linux',
                            child: Text(l.container_jailTypeLinux),
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
                        decoration: InputDecoration(
                          labelText: l.container_vnetMode,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text(l.container_vnetModeNone),
                          ),
                          DropdownMenuItem(
                            value: 'vnet',
                            child: Text(l.container_vnetModeVnet),
                          ),
                          DropdownMenuItem(
                            value: 'bridge',
                            enabled: _jailType != 'linux',
                            child: Text(l.container_vnetModeBridge),
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
                            labelText: _vnetMode == 'bridge'
                                ? l.container_bridgeNic
                                : l.container_physicalNic,
                            hintText: _vnetMode == 'bridge'
                                ? l.container_bridgeNicHint
                                : l.container_physicalNicHint,
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
                  labelText: l.container_portMapping,
                  helperText: isBastille
                      ? l.container_portMappingHelperBastille
                      : l.container_portMappingHelper,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _volumesController,
                decoration: InputDecoration(
                  labelText: isBastille ? l.container_dataMount : l.container_volumeMount,
                  helperText: isBastille
                      ? l.container_dataMountHelper
                      : l.container_volumeMountHelper,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!isBastille) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _envController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l.container_envVars,
                    helperText: l.container_envVarsHelper,
                    alignLabelWithHint: true,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _restartPolicy,
                  decoration: InputDecoration(
                    labelText: l.container_restartPolicy,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'no', child: Text(l.container_restartNo)),
                    DropdownMenuItem(
                      value: 'unless-stopped',
                      child: Text(l.container_restartUnlessStopped),
                    ),
                    DropdownMenuItem(
                      value: 'always',
                      child: Text(l.container_restartAlways),
                    ),
                    DropdownMenuItem(
                      value: 'on-failure',
                      child: Text(l.container_restartOnFailure),
                    ),
                  ],
                  onChanged: (value) => setState(() => _restartPolicy = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _commandController,
                  decoration: InputDecoration(
                    labelText: l.container_startCommand,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _workdirController,
                decoration: InputDecoration(
                  labelText: l.container_workdir,
                  helperText: l.container_workdirHelper,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memoryController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.container_memoryLimit,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cpusController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.container_cpuCores,
                        isDense: true,
                        border: const OutlineInputBorder(),
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
                  labelText: l.container_diskLimit,
                  helperText: isBastille
                      ? l.container_diskLimitHelperBastille
                      : l.container_diskLimitHelper,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (isBastille)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.container_createHintBastille,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add),
          label: Text(isBastille ? l.container_createJail : l.container_createContainer),
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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.container_cloneTitle(widget.source)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              inputFormatters: widget.isBastille
                  ? [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_-]'),
                      ),
                    ]
                  : null,
              decoration: InputDecoration(
                labelText: l.container_newName,
                helperText: widget.isBastille ? l.container_notPureNumber : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.isBastille) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: l.container_newIp,
                  hintText: l.container_newIpHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            if (widget.isBastille &&
                !RegExp(r'^(?=.*[a-zA-Z])[a-zA-Z0-9_-]+$').hasMatch(name)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.container_jailNameRule)),
              );
              return;
            }
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
          child: Text(l.container_clone),
        ),
      ],
    );
  }
}

// ==================== 资源限制对话框 ====================

class _LimitsInput {
  const _LimitsInput({this.memoryLimitMb, this.cpus, this.diskLimitMb});

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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.container_resourceLimits),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _memoryController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.container_memoryLimitKeep,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cpusController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.container_cpuCoresKeep,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diskController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.container_diskLimitKeep,
                helperText: l.container_diskLimitKeepHelper,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
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
          child: Text(l.common_apply),
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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.container_addForward),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _jail,
              decoration: InputDecoration(
                labelText: l.container_jail,
                isDense: true,
                border: const OutlineInputBorder(),
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
              decoration: InputDecoration(
                labelText: l.container_protocol,
                isDense: true,
                border: const OutlineInputBorder(),
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
                    decoration: InputDecoration(
                      labelText: l.container_hostPort,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _jailPortController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.container_jailPort,
                      isDense: true,
                      border: const OutlineInputBorder(),
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
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: () {
            final jail = _jail;
            final hostPort = int.tryParse(_hostPortController.text.trim());
            final jailPort = int.tryParse(_jailPortController.text.trim());
            if (jail == null ||
                jail.isEmpty ||
                hostPort == null ||
                jailPort == null) {
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
          child: Text(l.common_add),
        ),
      ],
    );
  }
}

// ==================== 导入对话框 ====================

class _ImportInput {
  const _ImportInput({required this.file, this.release, this.force = false});

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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.container_importJail),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fileController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.container_archivePath,
                hintText: l.container_archivePathHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _releaseController,
              decoration: InputDecoration(
                labelText: l.container_specifyRelease,
                hintText: l.container_specifyReleaseHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              value: _force,
              onChanged: (value) => setState(() => _force = value ?? false),
              title: Text(l.container_skipChecksum),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
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
          child: Text(l.container_import),
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
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.container_enterNicName)));
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
      final l = AppLocalizations.of(context);
      setState(() {
        _resultOk = result.ok;
        _result = result.detail ?? (result.ok ? l.container_initDone : l.container_initFailed);
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
                  color: (_resultOk ? Colors.green : Colors.red).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  _result!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: FontSettings.instance.terminalFamily,
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
    text:
        'FROM eclipse-temurin:21-jre\n'
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
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.container_buildImage),
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
                    decoration: InputDecoration(
                      labelText: l.container_imageName,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      labelText: l.container_tag,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dockerfileController,
              maxLines: 12,
              style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 12),
              decoration: InputDecoration(
                labelText: l.container_dockerfile,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.container_buildContextNote,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_cancel),
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
          label: Text(l.container_startBuild),
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
    final l = AppLocalizations.of(context);
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
                      ? l.container_buildDone
                      : failed
                      ? l.container_buildFailed
                      : l.container_building,
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
                    ? Text(
                        l.container_waitingBuildOutput,
                        style: TextStyle(
                          fontFamily: FontSettings.instance.terminalFamily,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Text(
                          _log[index],
                          style: TextStyle(
                            fontFamily: FontSettings.instance.terminalFamily,
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
            child: Text(l.container_buildInBackground),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.common_close),
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
    final l = AppLocalizations.of(context);
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
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.pop(context, value);
            }
          },
          child: Text(l.common_confirm),
        ),
      ],
    );
  }
}
