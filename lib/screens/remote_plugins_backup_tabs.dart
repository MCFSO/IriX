// 远程实例「插件 / Mod」与「备份」标签页
//
// - 插件/Mod：列出实例 plugins/ 与 mods/ 目录下的 .jar（mods 递归子目录），
//   支持上传（本地 .jar → 直连上传）、下载与删除。
// - 备份：节点端压缩实例根目录（输出压缩包位于实例内，故压缩目标为
//   顶层条目而非根目录本身，避免自包含）→ 流式下载到本地；恢复：
//   选择本地 .zip → 上传到实例根目录 → 节点端解压。
// 两种节点类型（MCSM 面板 / IriX 本地节点）共用实例级文件 API。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/node_ops.dart';
import '../models/remote.dart';
import '../services/node_api_client.dart';
import '../utils/apple_widgets.dart';

/// 节点端长耗时操作（压缩 / 解压 / 票据）使用的超时。
const Duration _longTimeout = Duration(minutes: 10);

/// 远程实例「插件 / Mod」标签页。
class RemotePluginsTab extends StatefulWidget {
  const RemotePluginsTab({
    super.key,
    required this.client,
    required this.daemonId,
    required this.uuid,
  });

  final NodeApiClient client;
  final String daemonId;
  final String uuid;

  @override
  State<RemotePluginsTab> createState() => _RemotePluginsTabState();
}

/// 远程 .jar 条目（带实例内绝对路径）。
class _JarItem {
  final String path;
  final String name;
  final int size;

  const _JarItem({required this.path, required this.name, required this.size});
}

class _RemotePluginsTabState extends State<RemotePluginsTab> {
  List<_JarItem> _plugins = [];
  List<_JarItem> _mods = [];

  /// 元数据检测结果（GET /api/instance/plugins，irix-node §4.4）。
  List<RemotePluginMeta> _metas = [];

  /// 是否在使用元数据展示（false = 节点不支持，回退文件列表）。
  bool _usingMeta = false;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 优先元数据检测（名称 / 描述 / 版本 / 图标）；节点不支持时
      // （MCSM / 旧版本）自动回退到文件列表。
      try {
        final metas = await widget.client.instancePlugins(
          uuid: widget.uuid,
          daemonId: widget.daemonId,
        );
        if (!mounted) return;
        setState(() {
          _metas = metas;
          _usingMeta = true;
          _loading = false;
        });
        return;
      } catch (_) {
        // 回退：文件列表
      }
      final plugins = await _listJars('/plugins', recursive: false);
      final mods = await _listJars('/mods', recursive: true);
      if (!mounted) return;
      setState(() {
        _plugins = plugins;
        _mods = mods;
        _usingMeta = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 递归列出目录下的 .jar 文件（最多 3 层，防止深层目录爆炸）。
  Future<List<_JarItem>> _listJars(
    String dir, {
    required bool recursive,
    int depth = 0,
  }) async {
    final result = <_JarItem>[];
    if (depth > 3) return result;
    final data = await widget.client.listFiles(
      daemonId: widget.daemonId,
      uuid: widget.uuid,
      target: dir,
      pageSize: 1000,
    );
    for (final entry in data.items) {
      final path = '$dir/${entry.name}';
      if (entry.isDirectory) {
        if (recursive) {
          result.addAll(
            await _listJars(path, recursive: true, depth: depth + 1),
          );
        }
      } else if (entry.name.toLowerCase().endsWith('.jar')) {
        result.add(_JarItem(path: path, name: entry.name, size: entry.size));
      }
    }
    return result;
  }

  /// 上传 .jar 到指定目录。
  Future<void> _upload(String uploadDir) async {
    final l = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l.remoteTab_selectJarToUpload,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jar'],
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ticket = await widget.client.uploadTicket(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        uploadDir: uploadDir,
        timeout: _longTimeout,
      );
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        await widget.client.directUpload(
          ticket: ticket,
          localPath: path,
          timeout: _longTimeout,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 下载 .jar 到本地（保存对话框）。
  Future<void> _download(_JarItem item) =>
      _downloadJar(item.path, item.name, item.size);

  /// 下载元数据条目（RemotePluginMeta）。
  Future<void> _downloadMeta(RemotePluginMeta meta) =>
      _downloadJar(meta.path, meta.fileName, meta.size);

  Future<void> _downloadJar(String path, String name, int size) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ticket = await widget.client.downloadTicket(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        fileName: path,
        timeout: _longTimeout,
      );
      final bytes = await widget.client.directDownload(ticket);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l.remoteTab_saveFile,
        fileName: name,
      );
      if (savePath != null) {
        await File(savePath).writeAsBytes(bytes, flush: true);
        if (mounted) _showSnack(l.remoteTab_downloadedTo(savePath));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 删除远程 .jar。
  Future<void> _delete(_JarItem item) => _deleteJar(item.path, item.name);

  /// 删除元数据条目。
  Future<void> _deleteMeta(RemotePluginMeta meta) =>
      _deleteJar(meta.path, meta.fileName);

  Future<void> _deleteJar(String path, String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteTab_deleteJar(name)),
        content: Text(l.remoteTab_deleteFileHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteFiles(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        targets: [path],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(l.common_retry),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_usingMeta) ...[
          _buildMetaSection(
            theme,
            l,
            title: l.remoteTab_plugins,
            icon: Icons.extension,
            items: _metas.where((m) => m.isPlugin).toList(),
            uploadDir: '/plugins',
          ),
          const SizedBox(height: 16),
          _buildMetaSection(
            theme,
            l,
            title: l.remoteTab_mods,
            icon: Icons.category_outlined,
            items: _metas.where((m) => !m.isPlugin).toList(),
            uploadDir: '/mods',
          ),
          const SizedBox(height: 8),
          Text(
            l.remoteTab_metaDetectionHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          _buildSection(
            theme,
            l,
            title: l.remoteTab_plugins,
            icon: Icons.extension,
            items: _plugins,
            uploadDir: '/plugins',
          ),
          const SizedBox(height: 16),
          _buildSection(
            theme,
            l,
            title: l.remoteTab_mods,
            icon: Icons.category_outlined,
            items: _mods,
            uploadDir: '/mods',
          ),
          const SizedBox(height: 8),
          Text(
            l.remoteTab_fileListHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// 元数据展示分区（名称 / 版本 / 描述 / 图标）。
  Widget _buildMetaSection(
    ThemeData theme,
    AppLocalizations l, {
    required String title,
    required IconData icon,
    required List<RemotePluginMeta> items,
    required String uploadDir,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                IconButton(
                  icon: const Icon(Icons.upload_file, size: 20),
                  tooltip: l.remoteTab_uploadJar,
                  onPressed: _busy ? null : () => _upload(uploadDir),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.remoteTab_emptyNoDetection,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final meta in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _metaIcon(theme, meta),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    meta.name.isNotEmpty
                                        ? meta.name
                                        : meta.fileName,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (meta.version != null &&
                                    meta.version!.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      meta.version!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (meta.description != null &&
                                meta.description!.isNotEmpty)
                              Text(
                                meta.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatSize(meta.size),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download, size: 18),
                        tooltip: l.remoteTab_download,
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _downloadMeta(meta),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: l.remoteTab_delete,
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _deleteMeta(meta),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// 元数据图标（base64 解码失败 / 无图标时用类型默认图标）。
  Widget _metaIcon(ThemeData theme, RemotePluginMeta meta) {
    final bytes = meta.iconBytes;
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          Uint8List.fromList(bytes),
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _defaultMetaIcon(theme, meta),
        ),
      );
    }
    return _defaultMetaIcon(theme, meta);
  }

  Widget _defaultMetaIcon(ThemeData theme, RemotePluginMeta meta) {
    return Icon(
      meta.isPlugin ? Icons.extension : Icons.widgets,
      size: 30,
      color: meta.isPlugin
          ? Colors.blue.withValues(alpha: 0.8)
          : Colors.deepPurple.withValues(alpha: 0.8),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    AppLocalizations l, {
    required String title,
    required IconData icon,
    required List<_JarItem> items,
    required String uploadDir,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                IconButton(
                  icon: const Icon(Icons.upload_file, size: 20),
                  tooltip: l.remoteTab_uploadJar,
                  onPressed: _busy ? null : () => _upload(uploadDir),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.remoteTab_empty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        _formatSize(item.size),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download, size: 18),
                        tooltip: l.remoteTab_download,
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _download(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: l.remoteTab_delete,
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : () => _delete(item),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(1)} ${units[i]}';
  }
}

/// 远程实例「备份」标签页。
///
/// 备份 = 节点端压缩实例根目录 → 流式下载到本地；恢复 = 本地 .zip
/// 上传到实例根目录 → 节点端解压。两种节点类型通用。
class RemoteBackupTab extends StatefulWidget {
  const RemoteBackupTab({
    super.key,
    required this.client,
    required this.daemonId,
    required this.uuid,
    required this.nickname,
  });

  final NodeApiClient client;
  final String daemonId;
  final String uuid;
  final String nickname;

  @override
  State<RemoteBackupTab> createState() => _RemoteBackupTabState();
}

class _RemoteBackupTabState extends State<RemoteBackupTab> {
  /// 实例根目录下已有的 .zip 备份（含用户自己打包的文件）。
  List<RemoteFileEntry> _zips = [];

  bool _loading = true;
  bool _busy = false;

  /// 备份下载进度（0.0 ~ 1.0，null = 未在下载）。
  double? _progress;

  /// 当前操作描述（如「节点端压缩中…」「下载中…」）。
  String? _status;

  String? _error;

  // ---- 节点端快照（irix-node §4.5，仅 irix-node 支持）----
  /// 是否支持节点端快照（首次探测；MCSM 节点为 false，隐藏整个区块）。
  bool? _snapshotSupported;
  List<BackupItem> _snapshots = [];
  bool _snapshotBusy = false;
  String? _snapshotStatus;
  double? _snapshotProgress; // 快照 / 恢复进度（0~1）
  String? _snapshotError;
  Timer? _snapshotPoll; // snapshot-progress 轮询

  @override
  void initState() {
    super.initState();
    _load();
    _loadSnapshots();
  }

  @override
  void dispose() {
    _cancelSnapshotPoll();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client.listFiles(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        target: '/',
        pageSize: 1000,
      );
      final zips =
          data.items
              .where(
                (e) => !e.isDirectory && e.name.toLowerCase().endsWith('.zip'),
              )
              .toList()
            ..sort((a, b) => b.name.compareTo(a.name));
      if (!mounted) return;
      setState(() {
        _zips = zips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 开始备份：节点端压缩根目录 → 流式下载到本地。
  Future<void> _startBackup() async {
    final l = AppLocalizations.of(context);
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = l.remoteTab_statusListRoot;
    });
    try {
      // 1. 根目录顶层条目（压缩目标排除压缩包自身，避免自包含）。
      final root = await widget.client.listFiles(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        target: '/',
        pageSize: 1000,
      );
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final zipName = 'backup_$timestamp.zip';
      final targets = [for (final e in root.items) '/${e.name}'];

      // 2. 节点端压缩（压缩目标不含压缩包本身）。
      if (!mounted) return;
      setState(() => _status = l.remoteTab_statusCompressing);
      await widget.client.compress(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        source: '/$zipName',
        targets: targets,
        timeout: _longTimeout,
      );

      // 3. 选择保存位置。
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l.remoteTab_saveBackup,
        fileName: zipName,
      );
      if (savePath == null) {
        await _cleanupZip(zipName);
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }

      // 4. 流式下载（Rust 下载器写盘，不占内存）。
      if (!mounted) return;
      setState(() {
        _status = l.remoteTab_statusDownloading;
        _progress = 0;
      });
      final ticket = await widget.client.downloadTicket(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        fileName: '/$zipName',
        timeout: _longTimeout,
      );
      await widget.client.directDownloadToFile(ticket, savePath, (done, total) {
        if (!mounted) return;
        setState(() {
          _progress = total > 0 ? done / total : 0;
        });
      });

      // 5. 清理节点端压缩包并刷新列表。
      await _cleanupZip(zipName);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _status = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.remoteTab_backupSaved(savePath))));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _status = null;
        _error = e.toString();
      });
    }
  }

  /// 恢复备份：本地 .zip → 上传到实例根目录 → 节点端解压。
  Future<void> _restore() async {
    final l = AppLocalizations.of(context);
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l.remoteTab_selectRestoreZip,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final localPath = result?.files.single.path;
    if (localPath == null || !mounted) return;
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteTab_restoreBackupTitle),
        content: Text(l.remoteTab_restoreBackupContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.remoteTab_restore),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = l.remoteTab_uploadingBackup;
    });
    try {
      final fileName = p.basename(localPath);
      final ticket = await widget.client.uploadTicket(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        uploadDir: '/',
        timeout: _longTimeout,
      );
      await widget.client.directUpload(
        ticket: ticket,
        localPath: localPath,
        timeout: _longTimeout,
      );
      if (!mounted) return;
      setState(() => _status = l.remoteTab_unzippingOnNode);
      await widget.client.unzip(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        source: '/$fileName',
        dest: '/',
        timeout: _longTimeout,
      );
      // 解压完成后删除上传的压缩包。
      try {
        await widget.client.deleteFiles(
          daemonId: widget.daemonId,
          uuid: widget.uuid,
          targets: ['/$fileName'],
        );
      } catch (_) {
        // 清理失败不影响恢复结果。
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.remoteTab_backupRestored)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = e.toString();
      });
    }
  }

  /// 下载节点上的备份压缩包到本地。
  Future<void> _download(RemoteFileEntry entry) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _status = l.remoteTab_statusDownloadingEntry(entry.name);
    });
    try {
      final ticket = await widget.client.downloadTicket(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        fileName: '/${entry.name}',
        timeout: _longTimeout,
      );
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l.remoteTab_saveFile,
        fileName: entry.name,
      );
      if (savePath != null) {
        await widget.client.directDownloadToFile(ticket, savePath, (
          done,
          total,
        ) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? done / total : 0;
          });
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.remoteTab_downloadedTo(savePath))));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _status = null;
        });
      }
    }
  }

  /// 删除节点上的备份压缩包。
  Future<void> _delete(RemoteFileEntry entry) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteTab_deleteZip(entry.name)),
        content: Text(l.remoteTab_deleteZipHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.deleteFiles(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        targets: ['/${entry.name}'],
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 清理节点端临时压缩包（失败静默）。
  Future<void> _cleanupZip(String zipName) async {
    try {
      await widget.client.deleteFiles(
        daemonId: widget.daemonId,
        uuid: widget.uuid,
        targets: ['/$zipName'],
      );
    } catch (_) {
      // 忽略清理失败。
    }
  }

  // ==================== 节点端快照（irix-node §4.5）====================

  /// 探测节点是否支持快照，并加载快照列表。
  Future<void> _loadSnapshots() async {
    if (_snapshotSupported == false) return; // MCSM 节点已确认不支持
    try {
      final list = await widget.client.listBackups(
        uuid: widget.uuid,
        daemonId: widget.daemonId,
      );
      if (!mounted) return;
      setState(() {
        _snapshotSupported = true;
        _snapshots = list;
        _snapshotError = null;
      });
    } catch (e) {
      if (!mounted) return;
      // 节点不支持（MCSM / 旧版本）：隐藏整个快照区块。
      setState(() => _snapshotSupported = false);
    }
  }

  /// 创建快照：发起任务并轮询进度（snapshot-progress）。
  Future<void> _createSnapshot() async {
    final l = AppLocalizations.of(context);
    if (_snapshotBusy) return;
    _cancelSnapshotPoll();
    setState(() {
      _snapshotBusy = true;
      _snapshotProgress = 0;
      _snapshotStatus = l.remoteTab_statusCreatingSnapshot;
      _snapshotError = null;
    });
    try {
      final jobId = await widget.client.instanceSnapshot(
        uuid: widget.uuid,
        daemonId: widget.daemonId,
      );
      _snapshotPoll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
        try {
          final p = await widget.client.snapshotProgress(jobId);
          if (!mounted) return;
          setState(() {
            _snapshotProgress = p.percent;
            _snapshotStatus = p.message.isEmpty ? p.status : p.message;
          });
          if (p.isDone) {
            _cancelSnapshotPoll();
            if (!mounted) return;
            setState(() {
              _snapshotBusy = false;
              _snapshotProgress = null;
              _snapshotStatus = null;
            });
            await _loadSnapshots();
          } else if (p.isFailed) {
            _cancelSnapshotPoll();
            if (!mounted) return;
            setState(() {
              _snapshotBusy = false;
              _snapshotProgress = null;
              _snapshotStatus = null;
              _snapshotError = l.remoteTab_snapshotFailed;
            });
          }
        } catch (e) {
          _cancelSnapshotPoll();
          if (!mounted) return;
          setState(() {
            _snapshotBusy = false;
            _snapshotProgress = null;
            _snapshotStatus = null;
            _snapshotError = e.toString();
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshotBusy = false;
        _snapshotProgress = null;
        _snapshotStatus = null;
        _snapshotError = e.toString();
      });
    }
  }

  /// 恢复快照：先确认，再发起任务并轮询进度。
  Future<void> _restoreSnapshot(BackupItem item) async {
    final l = AppLocalizations.of(context);
    if (_snapshotBusy) return;
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteTab_restoreSnapshotTitle),
        content: Text(
          l.remoteTab_restoreSnapshotContent(item.fileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.remoteTab_restore),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _cancelSnapshotPoll();
    setState(() {
      _snapshotBusy = true;
      _snapshotProgress = 0;
      _snapshotStatus = l.remoteTab_statusRestoringSnapshot;
      _snapshotError = null;
    });
    try {
      final jobId = await widget.client.instanceRestore(
        uuid: widget.uuid,
        daemonId: widget.daemonId,
        archivePath: item.path,
      );
      _snapshotPoll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
        try {
          final p = await widget.client.snapshotProgress(jobId);
          if (!mounted) return;
          setState(() {
            _snapshotProgress = p.percent;
            _snapshotStatus = p.message.isEmpty ? p.status : p.message;
          });
          if (p.isDone) {
            _cancelSnapshotPoll();
            if (!mounted) return;
            setState(() {
              _snapshotBusy = false;
              _snapshotProgress = null;
              _snapshotStatus = null;
            });
            await _loadSnapshots();
          } else if (p.isFailed) {
            _cancelSnapshotPoll();
            if (!mounted) return;
            setState(() {
              _snapshotBusy = false;
              _snapshotProgress = null;
              _snapshotStatus = null;
              _snapshotError = l.remoteTab_restoreFailed;
            });
          }
        } catch (e) {
          _cancelSnapshotPoll();
          if (!mounted) return;
          setState(() {
            _snapshotBusy = false;
            _snapshotProgress = null;
            _snapshotStatus = null;
            _snapshotError = e.toString();
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshotBusy = false;
        _snapshotProgress = null;
        _snapshotStatus = null;
        _snapshotError = e.toString();
      });
    }
  }

  /// 下载快照到本地（直连票据下载）。
  Future<void> _downloadSnapshot(BackupItem item) async {
    final l = AppLocalizations.of(context);
    if (_snapshotBusy) return;
    setState(() => _snapshotError = null);
    try {
      final ticket = await widget.client.backupDownloadTicket(
        uuid: widget.uuid,
        path: item.path,
        timeout: _longTimeout,
      );
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: l.remoteTab_saveSnapshot,
        fileName: item.fileName,
      );
      if (savePath == null || !mounted) return;
      await widget.client.directDownloadToFile(ticket, savePath, (done, total) {
        if (!mounted) return;
        setState(() {
          _snapshotProgress = total > 0 ? done / total : 0;
          _snapshotStatus = l.remoteTab_statusDownloadingSnapshot;
        });
      });
      if (!mounted) return;
      setState(() {
        _snapshotProgress = null;
        _snapshotStatus = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.remoteTab_downloadedTo(savePath))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshotProgress = null;
        _snapshotStatus = null;
        _snapshotError = e.toString();
      });
    }
  }

  /// 删除快照（节点侧备份区删除，不可恢复）。
  Future<void> _deleteSnapshot(BackupItem item) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.remoteTab_deleteSnapshot(item.fileName)),
        content: Text(l.remoteTab_deleteSnapshotHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.client.deleteBackups(
        uuid: widget.uuid,
        daemonId: widget.daemonId,
        paths: [item.path],
      );
      await _loadSnapshots();
    } catch (e) {
      if (!mounted) return;
      setState(() => _snapshotError = e.toString());
    }
  }

  void _cancelSnapshotPoll() {
    _snapshotPoll?.cancel();
    _snapshotPoll = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.remoteTab_instanceBackup, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  l.remoteTab_instanceBackupDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.backup, size: 18),
                      label: Text(l.remoteTab_startBackup),
                      onPressed: _busy ? null : _startBackup,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: Text(l.remoteTab_restoreBackup),
                      onPressed: _busy ? null : _restore,
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status ?? l.remoteTab_statusProcessing,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (_progress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 4),
                    Text(
                      '${((_progress ?? 0) * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_snapshotSupported == true) ...[
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l.remoteTab_nodeSnapshot, style: theme.textTheme.titleSmall),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: l.common_refresh,
                        onPressed:
                            _snapshotBusy ? null : () => _loadSnapshots(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.remoteTab_nodeSnapshotDesc('{data}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.camera, size: 18),
                    label: Text(l.remoteTab_createSnapshot),
                    onPressed: _snapshotBusy ? null : _createSnapshot,
                  ),
                  if (_snapshotBusy) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _snapshotStatus ?? l.remoteTab_statusProcessing,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (_snapshotProgress != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _snapshotProgress),
                      const SizedBox(height: 4),
                      Text(
                        '${((_snapshotProgress ?? 0) * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  if (_snapshots.isEmpty && !_snapshotBusy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l.remoteTab_noSnapshots,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final item in _snapshots)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.camera, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.fileName,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (item.mtime.isNotEmpty)
                                    Text(
                                      item.mtime,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                theme.colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.restore, size: 18),
                              tooltip: l.remoteTab_restore,
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  _snapshotBusy ? null : () => _restoreSnapshot(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.download, size: 18),
                              tooltip: l.remoteTab_download,
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  _snapshotBusy ? null : () => _downloadSnapshot(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: l.remoteTab_delete,
                              visualDensity: VisualDensity.compact,
                              onPressed:
                                  _snapshotBusy ? null : () => _deleteSnapshot(item),
                            ),
                          ],
                        ),
                      ),
                  if (_snapshotError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _snapshotError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_zip,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.remoteTab_nodeBackupFiles, style: theme.textTheme.titleSmall),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: l.common_refresh,
                      onPressed: _busy ? null : _load,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_zips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l.remoteTab_noZipBackups,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final entry in _zips)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_zip, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            _formatSize(entry.size),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download, size: 18),
                            tooltip: l.remoteTab_download,
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy ? null : () => _download(entry),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: l.remoteTab_delete,
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy ? null : () => _delete(entry),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(1)} ${units[i]}';
  }
}
