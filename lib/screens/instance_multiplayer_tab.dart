// 实例「联机」Tab：陶瓦联机（Terracotta）控制台。
//
// 界面结构对照 HMCL `ui/terracotta/TerracottaControllerPage`：
//   状态标题 + 进度条 → 当前状态下可执行的动作卡片 → 玩家列表 → 署名/恢复入口。
// 与 HMCL 的区别：本应用是服务器管理器，没有「启动游戏」这一层，房主模式仍按
// 陶瓦联机协议扫描本机局域网世界，因此提示文案按「先在客户端对局域网开放」改写。
//
// 联机核心进程与状态机在 `TerracottaManager`（全局单例），本文件只做展示与
// 交互；所有文案走 AppLocalizations（lib/l10n/*.arb）。

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/terracotta/terracotta_manager.dart';
import '../services/terracotta/terracotta_metadata.dart';
import '../services/terracotta/terracotta_state.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

/// 实例详情页的「联机」Tab。
class InstanceMultiplayerTab extends StatefulWidget {
  const InstanceMultiplayerTab({
    super.key,
    required this.instanceId,
    required this.instanceName,
    this.manager,
  });

  /// 当前实例 id（用于判断实例是否已启动、启动实例）。
  final String instanceId;

  /// 当前实例名（默认作为联机玩家名）。
  final String instanceName;

  /// 管理器（测试可注入假实现）。
  final TerracottaManager? manager;

  @override
  State<InstanceMultiplayerTab> createState() => _InstanceMultiplayerTabState();
}

class _InstanceMultiplayerTabState extends State<InstanceMultiplayerTab> {
  late final TerracottaManager _manager =
      widget.manager ?? TerracottaManager.instance;

  /// 已自动复制过的邀请码（状态刷新时不重复弹提示）。
  String? _copiedRoom;

  /// 上一次向用户提示过的错误，避免重复弹 SnackBar。
  String? _shownError;

  @override
  void initState() {
    super.initState();
    final name = widget.instanceName.trim();
    _manager.playerName = name.isEmpty ? 'IriX' : name;
    _manager.addListener(_onManagerChanged);
    _manager.setActive(true);
    unawaited(_manager.ensureInitialized());
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _manager.setActive(false);
    super.dispose();
  }

  void _onManagerChanged() {
    if (!mounted) {
      return;
    }
    final state = _manager.state;
    // 房主开房成功后自动复制邀请码（与 HMCL 行为一致，只在首次出现时复制）。
    if (state is TerracottaHostOk && state.room != _copiedRoom) {
      _copiedRoom = state.room;
      unawaited(_copyText(state.room));
    }
    final error = _manager.lastActionError;
    if (error != null && error != _shownError) {
      _shownError = error;
      final l = AppLocalizations.of(context);
      _toast(l.multiplayer_actionFailed(error));
    }
    setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    _toast(l.multiplayer_roomCodeCopied);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = _manager.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _StatusCard(
          statusText: _statusText(l, state),
          progress: _progress(state),
          detail: _detailText(l, state),
        ),
        const SizedBox(height: 12),
        ..._actionsFor(l, state),
        if (_profilesOf(state).isNotEmpty) ...[
          const SizedBox(height: 12),
          _PlayersCard(profiles: _profilesOf(state)),
        ],
        const SizedBox(height: 12),
        _AttributionCard(
          manager: _manager,
          onOpenUrl: _openUrl,
          onExportLogs: _exportLogs,
          onReset: _manager.resetCore,
        ),
      ],
    );
  }

  /// 顶部状态文案。
  String _statusText(AppLocalizations l, TerracottaState state) {
    return switch (state) {
      TerracottaBootstrap() => l.multiplayer_statusBootstrap,
      TerracottaUninitialized() => l.multiplayer_statusUninitialized,
      TerracottaPreparing() => l.multiplayer_statusPreparing,
      TerracottaLaunching() => l.multiplayer_statusLaunching,
      TerracottaUnknown() => l.multiplayer_statusLaunching,
      TerracottaWaiting() => l.multiplayer_statusWaiting,
      TerracottaHostScanning() => l.multiplayer_statusScanning,
      TerracottaHostStarting() => l.multiplayer_statusHostStarting,
      TerracottaHostOk() => l.multiplayer_statusHostOk,
      TerracottaGuestConnecting() => l.multiplayer_statusGuestStarting,
      TerracottaGuestStarting() => l.multiplayer_statusGuestStarting,
      TerracottaGuestOk() => l.multiplayer_statusGuestOk,
      TerracottaExceptionState() => l.multiplayer_statusException,
      TerracottaFatal(:final type) => _fatalText(l, type),
    };
  }

  /// 进度条数值：null 表示不确定进度。
  double? _progress(TerracottaState state) {
    return switch (state) {
      TerracottaPreparing(:final progress) => progress,
      TerracottaUninitialized() => 0,
      TerracottaWaiting() || TerracottaHostOk() || TerracottaGuestOk() => 1,
      TerracottaFatal() || TerracottaExceptionState() => 1,
      _ => null,
    };
  }

  /// 状态下的补充说明（可为 null）。
  String? _detailText(AppLocalizations l, TerracottaState state) {
    return switch (state) {
      TerracottaExceptionState(:final type) => _exceptionText(l, type),
      TerracottaFatal(:final type) => _fatalText(l, type),
      TerracottaGuestStarting(:final difficulty) =>
        '${_difficultyText(l, difficulty)}\n${l.multiplayer_difficultyNote}',
      TerracottaGuestOk(:final url) => l.multiplayer_guestOkUrl(url),
      TerracottaUninitialized() => l.multiplayer_notice,
      _ => null,
    };
  }

  String _fatalText(AppLocalizations l, TerracottaFatalType type) {
    return switch (type) {
      TerracottaFatalType.os => l.multiplayer_fatalOs,
      TerracottaFatalType.network => l.multiplayer_fatalNetwork,
      TerracottaFatalType.install => l.multiplayer_fatalInstall,
      TerracottaFatalType.terracotta => l.multiplayer_fatalTerracotta,
      TerracottaFatalType.unknown => l.multiplayer_fatalUnknown,
    };
  }

  String _exceptionText(AppLocalizations l, TerracottaExceptionType type) {
    return switch (type) {
      TerracottaExceptionType.pingHostFail =>
        l.multiplayer_exceptionPingHostFail,
      TerracottaExceptionType.pingHostRst => l.multiplayer_exceptionPingHostRst,
      TerracottaExceptionType.guestEtCrash =>
        l.multiplayer_exceptionGuestEtCrash,
      TerracottaExceptionType.hostEtCrash => l.multiplayer_exceptionHostEtCrash,
      TerracottaExceptionType.pingServerRst =>
        l.multiplayer_exceptionPingServerRst,
      TerracottaExceptionType.scaffoldingInvalidResponse =>
        l.multiplayer_exceptionScaffoldingInvalid,
    };
  }

  List<TerracottaProfile> _profilesOf(TerracottaState state) {
    return switch (state) {
      TerracottaHostOk(:final profiles) => profiles,
      TerracottaGuestOk(:final profiles) => profiles,
      _ => const [],
    };
  }

  /// 当前状态对应的动作列表。
  List<Widget> _actionsFor(AppLocalizations l, TerracottaState state) {
    switch (state) {
      case TerracottaBootstrap():
      case TerracottaLaunching():
      case TerracottaUnknown():
        // 起核心/握手阶段没有可执行动作，只显示顶部进度。
        return const [];

      case TerracottaUninitialized(:final hasLegacy):
        return [
          _ActionTile(
            icon: Icons.cloud_download_outlined,
            title: hasLegacy
                ? l.multiplayer_updateCore
                : l.multiplayer_downloadCore,
            subtitle: l.multiplayer_statusUninitialized,
            onTap: _manager.downloadBundle,
          ),
          _ActionTile(
            icon: Icons.folder_open_outlined,
            title: l.multiplayer_installLocal,
            subtitle: l.multiplayer_installLocalDesc,
            onTap: _pickLocalBundle,
          ),
          _DownloadSourcesCard(onOpenUrl: _openUrl),
        ];

      case TerracottaPreparing():
        return [
          _ActionTile(
            icon: Icons.folder_open_outlined,
            title: l.multiplayer_installLocal,
            subtitle: l.multiplayer_installLocalDesc,
            onTap: _pickLocalBundle,
          ),
          _DownloadSourcesCard(onOpenUrl: _openUrl),
        ];

      case TerracottaWaiting():
        return [
          _ActionTile(
            icon: Icons.wifi_tethering,
            title: l.multiplayer_hostTitle,
            subtitle: l.multiplayer_hostDesc,
            onTap: _startHosting,
          ),
          _ActionTile(
            icon: Icons.group_add_outlined,
            title: l.multiplayer_guestTitle,
            subtitle: l.multiplayer_guestDesc,
            onTap: _joinRoom,
          ),
        ];

      case TerracottaHostScanning():
        return [
          _ActionTile(
            icon: Icons.stop_circle_outlined,
            title: l.multiplayer_actionBack,
            subtitle: l.multiplayer_scanningBack,
            onTap: _manager.backToWaiting,
          ),
          _InfoCard(text: l.multiplayer_scanningDesc),
        ];

      case TerracottaHostStarting():
        return [
          _ActionTile(
            icon: Icons.stop_circle_outlined,
            title: l.multiplayer_actionBack,
            subtitle: l.multiplayer_hostStartingBack,
            onTap: _manager.backToWaiting,
          ),
        ];

      case TerracottaHostOk(:final room):
        return [
          _RoomCodeCard(room: room, onCopy: () => _copyText(room)),
          _ActionTile(
            icon: Icons.copy_all_outlined,
            title: l.multiplayer_copyRoomCode,
            subtitle: l.multiplayer_roomCodeDesc,
            onTap: () => _copyText(room),
          ),
          _ActionTile(
            icon: Icons.logout,
            title: l.multiplayer_actionBack,
            subtitle: l.multiplayer_hostOkBack,
            onTap: _manager.backToWaiting,
          ),
        ];

      case TerracottaGuestConnecting():
      case TerracottaGuestStarting():
        return [
          _ActionTile(
            icon: Icons.stop_circle_outlined,
            title: l.multiplayer_actionBack,
            subtitle: l.multiplayer_guestBack,
            onTap: _manager.backToWaiting,
          ),
        ];

      case TerracottaGuestOk(:final url):
        return [
          _InfoCard(text: l.multiplayer_guestOkTitle),
          if (url.isNotEmpty)
            _ActionTile(
              icon: Icons.link,
              title: l.multiplayer_copyUrl,
              subtitle: url,
              onTap: () => _copyText(url),
            ),
          _ActionTile(
            icon: Icons.logout,
            title: l.multiplayer_actionBack,
            subtitle: l.multiplayer_guestBack,
            onTap: _manager.backToWaiting,
          ),
        ];

      case TerracottaExceptionState():
        return [
          _ActionTile(
            icon: Icons.refresh,
            title: l.multiplayer_retry,
            subtitle: l.multiplayer_exceptionBack,
            onTap: _manager.backToWaiting,
          ),
          _ActionTile(
            icon: Icons.description_outlined,
            title: l.multiplayer_exportLog,
            subtitle: l.multiplayer_exportLogDesc,
            onTap: _exportLogs,
          ),
        ];

      case TerracottaFatal(:final type):
        return [
          if (type != TerracottaFatalType.os)
            _ActionTile(
              icon: Icons.restore,
              title: l.multiplayer_retry,
              subtitle: _fatalText(l, type),
              onTap: _manager.recover,
            ),
          if (type == TerracottaFatalType.network)
            _DownloadSourcesCard(onOpenUrl: _openUrl),
          if (type != TerracottaFatalType.os)
            _ActionTile(
              icon: Icons.description_outlined,
              title: l.multiplayer_exportLog,
              subtitle: l.multiplayer_exportLogDesc,
              onTap: _exportLogs,
            ),
        ];
    }
  }

  /// 房主：先确认实例/局域网世界准备情况，再开始扫描。
  Future<void> _startHosting() async {
    final l = AppLocalizations.of(context);
    final appState = context.read<AppState>();
    final running = appState.managerFor(widget.instanceId)?.isRunning ?? false;
    if (running) {
      await _manager.startHostScanning();
      return;
    }
    final decision = await showAppDialog<bool>(
      context,
      (context) => AlertDialog(
        title: Text(l.multiplayer_hostNeedRunningTitle),
        content: Text(l.multiplayer_hostNeedRunningDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.multiplayer_hostSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.multiplayer_hostStartInstance),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (decision == true) {
      await appState.startInstance(widget.instanceId);
    }
    await _manager.startHostScanning();
  }

  /// 房客：输入邀请码并加入。
  Future<void> _joinRoom() async {
    final l = AppLocalizations.of(context);
    final code = await showAppDialog<String>(
      context,
      (context) => const _InviteCodeDialog(),
    );
    if (!mounted || code == null) return;
    if (code.trim().isEmpty) {
      _toast(l.multiplayer_guestEmpty);
      return;
    }
    final result = await _manager.joinRoom(code);
    if (!mounted) return;
    switch (result) {
      case TerracottaJoinResult.invalidRoom:
        _toast(l.multiplayer_guestInvalid);
      case TerracottaJoinResult.notReady:
        _toast(l.multiplayer_fatalTerracotta);
      case TerracottaJoinResult.accepted:
        break;
    }
  }

  /// 选择本地官方联机核心包（tar.gz）。
  Future<void> _pickLocalBundle() async {
    final l = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (!mounted || result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    final outcome = await _manager.installFromLocalBundle(path);
    if (!mounted) return;
    switch (outcome) {
      case TerracottaInstallResult.ok:
        _toast(l.multiplayer_installLocalDone);
      case TerracottaInstallResult.invalidPackage:
        _toast(l.multiplayer_installLocalInvalid);
      case TerracottaInstallResult.failed:
        _toast(l.multiplayer_actionFailed(_manager.lastActionError ?? ''));
    }
  }

  Future<void> _exportLogs() async {
    final l = AppLocalizations.of(context);
    final path = await _manager.exportLogs();
    if (!mounted) return;
    if (path == null) {
      _toast(l.multiplayer_exportLogFailed);
    } else {
      _toast(l.multiplayer_exportLogDone(path));
    }
  }

  String _difficultyText(AppLocalizations l, TerracottaDifficulty difficulty) {
    return switch (difficulty) {
      TerracottaDifficulty.unknown => l.multiplayer_difficultyUnknown,
      TerracottaDifficulty.easiest => l.multiplayer_difficultyEasiest,
      TerracottaDifficulty.simple => l.multiplayer_difficultySimple,
      TerracottaDifficulty.medium => l.multiplayer_difficultyMedium,
      TerracottaDifficulty.tough => l.multiplayer_difficultyTough,
    };
  }
}

/// 顶部状态卡片：标题 + 进度条 + 说明。
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.statusText,
    required this.progress,
    this.detail,
  });

  final String statusText;
  final double? progress;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(statusText, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 可点击的动作行。
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppleCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}

/// 纯说明卡片。
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppleCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 房间邀请码展示。
class _RoomCodeCard extends StatelessWidget {
  const _RoomCodeCard({required this.room, required this.onCopy});

  final String room;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AppleCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onCopy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l.multiplayer_roomCode,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            room,
            style: theme.textTheme.headlineMedium?.copyWith(
              letterSpacing: 4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 第三方下载渠道（自动下载失败时的兜底）。
class _DownloadSourcesCard extends StatelessWidget {
  const _DownloadSourcesCard({required this.onOpenUrl});

  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AppleCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.multiplayer_downloadSources, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            l.multiplayer_downloadSourcesDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.multiplayer_downloadExpected(TerracottaMetadata.packageName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final link in TerracottaMetadata.packageLinks)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenUrl(link.url),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(link.title),
              ),
            ),
        ],
      ),
    );
  }
}

/// 玩家列表。
class _PlayersCard extends StatelessWidget {
  const _PlayersCard({required this.profiles});

  final List<TerracottaProfile> profiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AppleCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.multiplayer_playerList, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          for (final profile in profiles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isEmpty ? '—' : profile.name,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (profile.vendor.isNotEmpty)
                          Text(
                            profile.vendor,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _KindChip(kind: profile.kind),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final TerracottaPlayerKind kind;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = switch (kind) {
      TerracottaPlayerKind.host => l.multiplayer_playerKindHost,
      TerracottaPlayerKind.local => l.multiplayer_playerKindLocal,
      TerracottaPlayerKind.guest => l.multiplayer_playerKindGuest,
    };
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.primary),
      ),
    );
  }
}

/// 署名 / 许可证 / 日志 / 重置。
///
/// 联机核心是第三方 AGPL-3.0 作品，这里按许可证要求显著标注来源与许可信息。
class _AttributionCard extends StatelessWidget {
  const _AttributionCard({
    required this.manager,
    required this.onOpenUrl,
    required this.onExportLogs,
    required this.onReset,
  });

  final TerracottaManager manager;
  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function() onExportLogs;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AppleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.multiplayer_attributionTitle,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          Text(
            l.multiplayer_attribution(kTerracottaLicense),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => onOpenUrl(kTerracottaHomepage),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.multiplayer_openHomepage),
              ),
              TextButton.icon(
                onPressed: () => onExportLogs(),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: Text(l.multiplayer_exportLog),
              ),
              TextButton.icon(
                onPressed: () => onReset(),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(l.multiplayer_resetCore),
              ),
            ],
          ),
          if (manager.coreReady) ...[
            const SizedBox(height: 4),
            Text(
              l.multiplayer_corePort(manager.port ?? 0),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 邀请码输入弹窗。
///
/// 控制器由弹窗自己持有并释放：若在 `showDialog` 返回后立刻 dispose，
/// 关闭动画仍在重建 TextField，会触发「controller used after dispose」。
class _InviteCodeDialog extends StatefulWidget {
  const _InviteCodeDialog();

  @override
  State<_InviteCodeDialog> createState() => _InviteCodeDialogState();
}

class _InviteCodeDialogState extends State<_InviteCodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.multiplayer_guestPromptTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: l.multiplayer_guestPromptHint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.multiplayer_actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.multiplayer_guestTitle)),
      ],
    );
  }
}
