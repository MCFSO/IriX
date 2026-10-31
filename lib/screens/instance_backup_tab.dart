// 实例备份主页（备份 Tab 内容）
//
// 产品要求：进入实例的「备份」页，主操作区只有两个按钮 ——
// 「全量备份」与「增量备份」；下方是可查看历史的备份列表（列表行不是按钮，
// 点按后在弹窗里做恢复/校验/删除）。
//
// 算法与落盘全部由 Rust（`xmc_backup`）实现：
// - 全量备份：整个实例目录 → 单个 ZIP 归档（并行 Deflate 压缩）；
// - 增量备份：Linux/macOS 用 `rsync --link-dest` 硬链接快照（rsync 缺失时回退
//   Rust 原生硬链接快照），Windows 用 SHA-256 哈希比对 + 内容寻址存储。
//
// 备份仓库：`<数据根>/backups/<实例 id>/`（见 AppPaths.instanceBackupsRoot）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/backup_manager.dart';
import '../services/backup_settings.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

/// 备份相关策略/类型文案。
String backupStrategyLabel(AppLocalizations l, String strategy) {
  switch (strategy) {
    case 'rsync-hardlink':
      return l.instanceDetail_backupStrategyRsync;
    case 'cas':
      return l.instanceDetail_backupStrategyCas;
    case 'hardlink':
      return l.instanceDetail_backupStrategyHardlink;
    case 'zip':
      return l.instanceDetail_backupStrategyZip;
    default:
      return strategy;
  }
}

/// 字节数转可读文本（与项目其它页面的格式保持一致）。
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1073741824) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

/// 本地时间 `YYYY-MM-DD HH:mm:ss`。
String _formatDateTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// 耗时秒数（保留一位小数）。
String _formatSeconds(int milliseconds) =>
    (milliseconds / 1000).toStringAsFixed(1);

/// 实例备份主页：只有「全量备份」「增量备份」两个按钮。
class InstanceBackupTab extends StatefulWidget {
  const InstanceBackupTab({
    super.key,
    required this.instanceId,
    required this.rootPath,
    this.manager,
  });

  final String instanceId;
  final String rootPath;

  /// 备份操作实现；默认使用 [BackupManager.instance]，widget 测试可注入假实现。
  final BackupOperations? manager;

  @override
  State<InstanceBackupTab> createState() => _InstanceBackupTabState();
}

class _InstanceBackupTabState extends State<InstanceBackupTab>
    with AutomaticKeepAliveClientMixin<InstanceBackupTab> {
  BackupOperations get _manager => widget.manager ?? BackupManager.instance;

  BackupRepositoryStatus? _status;
  String? _loadError;
  bool _loading = true;

  /// 是否有备份/恢复/校验在进行。
  bool _busy = false;
  String _busyLabel = '';
  double? _progress;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _ticker;

  /// 已点击取消（Rust 侧还在收尾，期间不再重复发取消请求）。
  bool _cancelRequested = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final status = await _manager.status(
        instanceId: widget.instanceId,
        rootPath: widget.rootPath,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  /// 统一的忙碌态包装：进度卡片 + 计时 + 取消。
  Future<T?> _withProgress<T>(
    String label,
    Future<T> Function(void Function(double? progress) onProgress) body, {
    bool autoRefresh = true,
  }) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _busyLabel = label;
      _progress = null;
      _cancelRequested = false;
      _elapsed
        ..reset()
        ..start();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _busy) setState(() {});
    });
    try {
      return await body((progress) {
        if (mounted) setState(() => _progress = progress);
      });
    } finally {
      _ticker?.cancel();
      _ticker = null;
      _elapsed.stop();
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
          _progress = null;
          _cancelRequested = false;
        });
      }
      if (autoRefresh) unawaited(_refresh());
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 失败提示：取消由 [_cancel] 统一提示，这里不重复弹。
  String _errorText(AppLocalizations l, Object error) {
    if (error is BackupException && error.cancelled) {
      return l.instanceDetail_backupCancelled;
    }
    final message = error is BackupException ? error.message : error.toString();
    return l.instanceDetail_backupFailed(message);
  }

  // ======================== 两个主操作 ========================

  /// 全量备份：整个实例目录 → 单个 ZIP 归档。
  Future<void> _startFullBackup() async {
    final l = AppLocalizations.of(context);
    final level = await BackupSettings.getLevel(widget.instanceId);
    try {
      final entry = await _withProgress<BackupEntry>(
        l.instanceDetail_backupRunningFull,
        (onProgress) => _manager.createFullBackup(
          instanceId: widget.instanceId,
          rootPath: widget.rootPath,
          compressionLevel: level,
          onProgress: onProgress,
        ),
      );
      if (entry == null) return;
      _snack(l.instanceDetail_backupFullDone(entry.name));
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(l, e));
    }
  }

  /// 增量备份：只保存相对上次快照的变化内容。
  Future<void> _startIncrementalBackup() async {
    final l = AppLocalizations.of(context);
    try {
      final entry = await _withProgress<BackupEntry>(
        l.instanceDetail_backupRunningIncremental,
        (onProgress) => _manager.createIncrementalBackup(
          instanceId: widget.instanceId,
          rootPath: widget.rootPath,
          onProgress: onProgress,
        ),
      );
      if (entry == null) return;
      _snack(
        l.instanceDetail_backupIncrementalDone(
          entry.name,
          _formatBytes(entry.bytesAdded),
          _formatBytes(entry.bytesReused),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(l, e));
    }
  }

  void _cancel() {
    final l = AppLocalizations.of(context);
    // 只置取消标志：Rust 侧在下一个检查点退出，届时 _withProgress 收尾并刷新。
    // 这里不提前清 _busy，避免旧任务还在跑时又启动新任务。
    if (_cancelRequested) return;
    setState(() => _cancelRequested = true);
    _manager.cancel();
    _snack(l.instanceDetail_backupCancelled);
  }

  // ======================== 备份详情 / 恢复 / 校验 / 删除 ========================

  Future<void> _showEntryDetail(BackupEntry entry) async {
    await showAppDialog<void>(
      context,
      (dialogContext) => _BackupDetailDialog(
        entry: entry,
        onRestore: () {
          Navigator.of(dialogContext).pop();
          unawaited(_restoreEntry(entry));
        },
        onVerify: () {
          Navigator.of(dialogContext).pop();
          unawaited(_verifyEntry(entry));
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          unawaited(_deleteEntry(entry));
        },
      ),
    );
  }

  Future<void> _restoreEntry(BackupEntry entry) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final instance = state.instances
        .where((e) => e.id == widget.instanceId)
        .firstOrNull;
    final running = instance?.status.isActive ?? false;

    final confirmed = await showAppDialog<bool>(
      context,
      (dialogContext) => _ConfirmBackupDialog(
        title: l.instanceDetail_backupRestoreConfirmTitle,
        content: running
            ? '${l.instanceDetail_backupRestoreConfirmContent(entry.name)}\n\n'
                  '${l.instanceDetail_backupRestoreStopHint}'
            : l.instanceDetail_backupRestoreConfirmContent(entry.name),
        confirmLabel: l.instanceDetail_backupRestore,
        destructive: !running,
      ),
    );
    if (confirmed != true) return;

    try {
      final info = await _withProgress<BackupRestoreInfo>(
        l.instanceDetail_backupRestoring,
        (onProgress) => _manager.restoreBackup(
          entry: entry,
          instanceId: widget.instanceId,
          rootPath: widget.rootPath,
          onProgress: onProgress,
        ),
      );
      if (info == null) return;
      _snack(l.instanceDetail_backupRestoreDone(info.files.toString()));
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(l, e));
    }
  }

  Future<void> _verifyEntry(BackupEntry entry) async {
    final l = AppLocalizations.of(context);
    try {
      final result = await _withProgress<BackupVerifyResult>(
        l.instanceDetail_backupVerifying,
        (onProgress) => _manager.verifyBackup(
          entry: entry,
          instanceId: widget.instanceId,
          deep: true,
          onProgress: onProgress,
        ),
      );
      if (result == null || !mounted) return;
      await showAppDialog<void>(
        context,
        (dialogContext) => _VerifyResultDialog(result: result),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(_errorText(l, e));
    }
  }

  Future<void> _deleteEntry(BackupEntry entry) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (dialogContext) => _ConfirmBackupDialog(
        title: l.instanceDetail_backupDeleteConfirmTitle,
        content: l.instanceDetail_backupDeleteConfirmContent(entry.name),
        confirmLabel: l.common_delete,
        destructive: true,
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.deleteBackup(
        entry: entry,
        instanceId: widget.instanceId,
      );
      if (!mounted) return;
      _snack(l.instanceDetail_backupDeleted);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _snack(l.instanceDetail_backupFailed(e.toString()));
    }
  }

  // ======================== UI ========================

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);

    if (_loading && _status == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l.instanceDetail_backupLoading),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _BackupActionCard(
                  icon: Icons.archive_outlined,
                  title: l.instanceDetail_backupFull,
                  subtitle: l.instanceDetail_backupFullDesc,
                  onPressed: _busy ? null : _startFullBackup,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BackupActionCard(
                  icon: Icons.history_toggle_off,
                  title: l.instanceDetail_backupIncremental,
                  subtitle: l.instanceDetail_backupIncrementalDesc,
                  onPressed: _busy ? null : _startIncrementalBackup,
                ),
              ),
            ],
          ),
        ),
        if (_busy) _buildProgressCard(),
        if (_loadError != null) _buildErrorCard(),
        const Divider(height: 1),
        _buildHistoryHeader(),
        Expanded(child: _buildHistory()),
      ],
    );
  }

  /// 顶部仓库信息（只读，不是按钮）。
  Widget _buildHeader() {
    final l = AppLocalizations.of(context);
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l.instanceDetail_backupRepoLabel,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  status.repoRoot,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(
                icon: Icons.call_merge,
                text:
                    '${l.instanceDetail_backupIncrementalMode}'
                    '：${backupStrategyLabel(l, status.strategy)}',
              ),
              if (!status.rsyncAvailable && status.strategy == 'hardlink')
                _Chip(
                  icon: Icons.info_outline,
                  text: l.instanceDetail_backupRsyncMissing,
                  muted: true,
                ),
              if (status.strategy == 'rsync-hardlink' &&
                  status.rsyncVersion != null)
                _Chip(
                  icon: Icons.terminal,
                  text: status.rsyncVersion!,
                  muted: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _busyLabel,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    l.instanceDetail_backupElapsed(
                      _formatSeconds(_elapsed.elapsedMilliseconds),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _cancelRequested ? null : _cancel,
                    child: Text(l.instanceDetail_backupCancel),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppleProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? l.instanceDetail_backupProgressHint
                    : '${(_progress! * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.instanceDetail_backupLoadFailed(_loadError ?? ''),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _refresh,
                child: Text(l.common_retry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryHeader() {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _status;
    final count = status?.entries.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(l.instanceDetail_backupHistory, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(
            count == 0
                ? ''
                : l.instanceDetail_backupHistorySummary(
                    count,
                    _formatBytes(status?.totalStoredBytes ?? 0),
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    final l = AppLocalizations.of(context);
    final entries = _status?.entries ?? const <BackupEntry>[];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.instanceDetail_backupEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _BackupHistoryRow(
          entry: entry,
          onTap: () => _showEntryDetail(entry),
        );
      },
    );
  }
}

/// 一个大操作按钮（图标 + 主标题 + 说明）。
class _BackupActionCard extends StatelessWidget {
  const _BackupActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return AppleButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
        disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: enabled ? null : Colors.grey),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: enabled
                  ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 只读信息胶囊。
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: muted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 备份历史行（点按打开详情弹窗；行本身不是操作按钮）。
class _BackupHistoryRow extends StatelessWidget {
  const _BackupHistoryRow({required this.entry, required this.onTap});

  final BackupEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final incremental = entry.isIncremental;
    final detail = incremental
        ? l.instanceDetail_backupChangeStats(
            _formatBytes(entry.bytesAdded),
            entry.filesModified.toString(),
            entry.filesDeleted.toString(),
            entry.filesUnchanged.toString(),
          )
        : l.instanceDetail_backupFileCount(entry.files.toString());
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: incremental
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                incremental ? Icons.link : Icons.archive_outlined,
                size: 18,
                color: incremental
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateTime(entry.createdAt),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${incremental ? l.instanceDetail_backupKindIncremental : l.instanceDetail_backupKindFull}'
                    ' · ${_formatBytes(entry.displayBytes)}'
                    ' · ${backupStrategyLabel(l, entry.strategy)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 备份详情弹窗。
class _BackupDetailDialog extends StatelessWidget {
  const _BackupDetailDialog({
    required this.entry,
    required this.onRestore,
    required this.onVerify,
    required this.onDelete,
  });

  final BackupEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final incremental = entry.isIncremental;
    final rows = <(String, String)>[
      (l.common_name, entry.name),
      (
        l.instanceDetail_backupKindLabel,
        incremental
            ? l.instanceDetail_backupKindIncremental
            : l.instanceDetail_backupKindFull,
      ),
      (l.instanceDetail_backupCreatedAt, _formatDateTime(entry.createdAt)),
      (l.instanceDetail_backupStrategy, backupStrategyLabel(l, entry.strategy)),
      (l.instanceDetail_backupSize, _formatBytes(entry.displayBytes)),
      (l.instanceDetail_backupStoredSize, _formatBytes(entry.storedBytes)),
      (l.instanceDetail_backupFileCountLabel, entry.files.toString()),
      (
        l.instanceDetail_backupDuration,
        '${_formatSeconds(entry.durationMs)} ${l.instanceDetail_backupSecondsUnit}',
      ),
      if (incremental)
        (
          l.instanceDetail_backupParent,
          entry.parent == null || entry.parent!.isEmpty
              ? l.instanceDetail_backupNoParent
              : entry.parent!,
        ),
      if (incremental)
        (
          l.instanceDetail_backupChangeLabel,
          l.instanceDetail_backupChangeStats(
            _formatBytes(entry.bytesAdded),
            entry.filesModified.toString(),
            entry.filesDeleted.toString(),
            entry.filesUnchanged.toString(),
          ),
        ),
      if (!incremental)
        (
          l.instanceDetail_backupCompression,
          compressionLevelLabel(entry.compressionLevel),
        ),
      if (entry.symlinksSkipped > 0)
        (
          l.instanceDetail_backupNote,
          l.instanceDetail_backupSymlinksSkipped(
            entry.symlinksSkipped.toString(),
          ),
        ),
      if (entry.note != null && entry.note!.isNotEmpty)
        (l.instanceDetail_backupNote, entry.note!),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.instanceDetail_backupDetailTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    row.$1,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    row.$2,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.common_close),
                    ),
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(l.common_delete),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                    if (incremental)
                      OutlinedButton.icon(
                        onPressed: onVerify,
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: Text(l.instanceDetail_backupVerify),
                      ),
                    FilledButton.icon(
                      onPressed: onRestore,
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: Text(l.instanceDetail_backupRestore),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 恢复/删除确认弹窗。
class _ConfirmBackupDialog extends StatelessWidget {
  const _ConfirmBackupDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    this.destructive = false,
  });

  final String title;
  final String content;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(content, style: theme.textTheme.bodySmall),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l.common_cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                              foregroundColor: theme.colorScheme.onError,
                            )
                          : null,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 校验结果弹窗。
class _VerifyResultDialog extends StatelessWidget {
  const _VerifyResultDialog({required this.result});

  final BackupVerifyResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ok = result.ok;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ok ? Icons.verified : Icons.error_outline,
                      color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok
                            ? l.instanceDetail_backupVerifyOk(
                                result.checked.toString(),
                              )
                            : l.instanceDetail_backupVerifyFailed(
                                result.problemCount.toString(),
                              ),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l.instanceDetail_backupVerifyDetail(
                    result.hashed.toString(),
                    backupStrategyLabel(l, result.strategy),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (result.problems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final problem in result.problems)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '· $problem',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.common_ok),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
