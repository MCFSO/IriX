// OTA 更新提醒窗
//
// 两处入口复用同一个对话框：
// - 启动自动检查 / 设置页「检查更新」发现新版本时弹出；
// - 内含更新说明（GitHub Release 正文的 Markdown）、安装包信息、
//   下载进度与安装按钮，并在需要时倒计时退出应用以完成安装。
//
// 交互约定（与 apple_widgets 的暗色风格一致）：
// - 「稍后提醒」/「跳过此版本」关闭对话框，后者会记住版本号不再打扰；
// - 「下载并安装」先下载并用 SHA-256 校验，再给出「安装并重启」；
// - 平台无法静默安装时（MSIX / dmg / deb / 便携 zip）改为打开安装包并提示。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/update_info.dart';
import '../services/update_service.dart';
import '../utils/apple_widgets.dart';

/// 对话框关闭时用户的选择。
enum UpdateDialogResult {
  /// 稍后提醒（下次启动再提示）。
  later,

  /// 跳过此版本。
  skipped,

  /// 已启动安装流程。
  installed,
}

/// 弹出「发现新版本」对话框。
///
/// [runningInstances] > 0 时提示更新会重启应用、运行中的服务器会被接管；
/// [manual] 表示由设置页主动检查触发（此时不显示「稍后提醒」的弱化文案差异）。
Future<UpdateDialogResult> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo info,
  int runningInstances = 0,
  bool manual = false,
}) async {
  final result = await showAppDialog<UpdateDialogResult>(
    context,
    (_) => _UpdateDialog(
      info: info,
      runningInstances: runningInstances,
      manual: manual,
    ),
  );
  return result ?? UpdateDialogResult.later;
}

enum _Phase { idle, downloading, ready, installing, done }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.info,
    required this.runningInstances,
    required this.manual,
  });

  final UpdateInfo info;
  final int runningInstances;
  final bool manual;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  UpdateProgress? _progress;
  String? _error;
  String? _filePath;
  String? _note;
  Timer? _exitTimer;
  int _exitCountdown = 3;

  /// 用户选中的安装包（默认用打分最高的那个，可在下拉里切换包型）。
  late UpdateAsset? _asset = widget.info.asset;

  /// 当前对话框对应的更新（带用户选择的包型）。
  UpdateInfo get _info => widget.info.withAsset(_asset);

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(theme, l),
                const SizedBox(height: 12),
                if (widget.runningInstances > 0) ...[
                  _warningBanner(theme, l),
                  const SizedBox(height: 12),
                ],
                Flexible(child: _releaseNotes(theme, l)),
                if (_phase == _Phase.idle && _info.assetChoices.length > 1) ...[
                  const SizedBox(height: 10),
                  _assetSelector(theme, l),
                ],
                if (_phase == _Phase.downloading) ...[
                  const SizedBox(height: 16),
                  _downloadProgress(theme, l),
                ],
                if (_phase == _Phase.done) ...[
                  const SizedBox(height: 12),
                  _doneBanner(theme, l),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _actions(theme, l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // === 头部：图标 + 版本信息 + 安装包信息 ===

  Widget _header(ThemeData theme, AppLocalizations l) {
    final info = _info;
    final published = info.release.publishedAt;
    final subtitleParts = <String>[
      l.update_transition(
        'v${info.currentVersion}',
        info.versionLabel,
      ),
      if (published != null)
        l.update_publishedAt(
          DateFormat('yyyy-MM-dd').format(published.toLocal()),
        ),
      if (info.asset != null)
        l.update_assetInfo(info.asset!.name, info.asset!.sizeLabel),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.system_update_alt,
            color: theme.colorScheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.update_availableTitle(info.versionLabel),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitleParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _warningBanner(ThemeData theme, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.update_runningInstancesWarning('${widget.runningInstances}'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  // === 更新说明 ===

  Widget _releaseNotes(ThemeData theme, AppLocalizations l) {
    final notes = _info.release.notes.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.update_releaseNotes,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: notes.isEmpty
                  ? Text(l.update_releaseNotesEmpty, style: theme.textTheme.bodySmall)
                  : MarkdownBody(
                      data: notes,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodySmall,
                        listBullet: theme.textTheme.bodySmall,
                        h1: theme.textTheme.titleSmall,
                        h2: theme.textTheme.titleSmall,
                        h3: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        tableBody: theme.textTheme.bodySmall,
                        tableHead: theme.textTheme.bodySmall,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 安装包类型选择（同一版本通常同时提供 exe/msix/zip、dmg/zip 等）。
  ///
  /// 默认选中打分最高的包型（由 `UpdateService.rankAssets` 决定），
  /// 商店版/便携版用户可在这里换成自己要的包。
  Widget _assetSelector(ThemeData theme, AppLocalizations l) {
    final choices = _info.assetChoices;
    return Row(
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          l.update_packageType,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<UpdateAsset>(
              value: _asset,
              isDense: true,
              isExpanded: true,
              borderRadius: BorderRadius.circular(10),
              style: theme.textTheme.bodySmall,
              items: [
                for (final asset in choices)
                  DropdownMenuItem<UpdateAsset>(
                    value: asset,
                    child: Text(
                      l.update_assetInfo(asset.name, asset.sizeLabel),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _asset = value;
                _progress = null;
                _error = null;
              }),
            ),
          ),
        ),
      ],
    );
  }

  // === 下载进度 ===
  Widget _downloadProgress(ThemeData theme, AppLocalizations l) {
    final progress = _progress;
    final percent = progress?.percent;
    final downloaded = formatBytes(progress?.downloadedBytes ?? 0);
    final total = progress == null || progress.totalBytes <= 0
        ? '?'
        : formatBytes(progress.totalBytes);
    final speed = formatBytes(progress?.speedBytesPerSec.round() ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.update_downloading, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        AppleProgressIndicator(value: percent == null ? null : percent / 100),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                percent == null
                    ? l.update_downloadProgressUnknown(downloaded)
                    : l.update_downloadProgress(
                        percent.toStringAsFixed(0),
                        downloaded,
                        total,
                      ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              l.update_downloadSpeed(speed),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneBanner(ThemeData theme, AppLocalizations l) {
    final exiting = _exitTimer != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _note ?? l.update_downloadDone,
                style: theme.textTheme.bodySmall,
              ),
              if (exiting) ...[
                const SizedBox(height: 4),
                Text(
                  l.update_exitCountdown('$_exitCountdown'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // === 底部按钮 ===

  Widget _actions(ThemeData theme, AppLocalizations l) {
    switch (_phase) {
      case _Phase.idle:
        return Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(UpdateDialogResult.later),
              child: Text(l.update_later),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: _skip,
              child: Text(l.update_skipVersion),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _info.release.htmlUrl.isEmpty
                  ? UpdateService.instance.openReleasePage()
                  : UpdateService.instance.openReleasePage(
                      htmlUrl: _info.release.htmlUrl,
                    ),
              child: Text(l.update_openReleasePage),
            ),
            const SizedBox(width: 8),
            AppleButton(
              onPressed: _info.hasAsset ? _download : null,
              child: Text(
                _info.hasAsset
                    ? l.update_downloadAndInstall
                    : l.update_openReleasePage,
              ),
            ),
          ],
        );
      case _Phase.downloading:
        return Row(
          children: [
            Expanded(
              child: Text(
                l.update_keepRunningHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpdateDialogResult.later),
              child: Text(l.update_background),
            ),
          ],
        );
      case _Phase.ready:
        return Row(
          children: [
            TextButton(
              onPressed: _filePath == null
                  ? null
                  : () => UpdateService.instance.revealInFolder(_filePath!),
              child: Text(l.update_revealFile),
            ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpdateDialogResult.later),
              child: Text(l.update_later),
            ),
            const SizedBox(width: 8),
            AppleButton(
              onPressed: _install,
              child: Text(l.update_installAndRestart),
            ),
          ],
        );
      case _Phase.installing:
      case _Phase.done:
        return Row(
          children: [
            if (_filePath != null)
              TextButton(
                onPressed: () =>
                    UpdateService.instance.revealInFolder(_filePath!),
                child: Text(l.update_revealFile),
              ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(UpdateDialogResult.installed),
              child: Text(l.common_close),
            ),
          ],
        );
    }
  }

  // === 行为 ===

  Future<void> _skip() async {
    await UpdateService.instance.skipVersion(_info);
    if (!mounted) return;
    Navigator.of(context).pop(UpdateDialogResult.skipped);
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _progress = null;
    });
    try {
      final path = await UpdateService.instance.downloadUpdate(
        _info,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _filePath = path;
        _note = null;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = '$e';
      });
    }
  }

  Future<void> _install() async {
    final path = _filePath;
    if (path == null) return;
    setState(() {
      _phase = _Phase.installing;
      _error = null;
    });
    try {
      final result = await UpdateService.instance.installUpdate(_info, path);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _filePath = result.path;
        _note = result.message;
      });
      if (result.appMustExit) {
        _startExitCountdown();
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _error = '$e';
      });
    }
  }

  /// 安装程序已启动：倒计时退出，让它替换正在使用的可执行文件。
  void _startExitCountdown() {
    // 测试环境不要真的退出进程。
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _exitCountdown = 3;
    _exitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _exitCountdown--);
      if (_exitCountdown <= 0) {
        timer.cancel();
        exit(0);
      }
    });
  }
}
