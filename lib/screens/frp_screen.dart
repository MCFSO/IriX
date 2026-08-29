// FRP 端口映射页面
//
// 顶部可切换 FRP 提供商（OpenFrp / 自建 frps）：
// - OpenFrp：Authorization 会话密钥登录，隧道由 API 管理；
// - 自建 frps：配置服务器地址 + token，隧道保存在本地。
// 新建隧道可选择实例自动读取 server.properties 的 server-port，
// 下载 frpc 后一键启动/停止隧道，真正实现端口映射。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/server_instance.dart';
import '../services/chmlfrp_provider.dart';
import '../services/custom_frp_provider.dart';
import '../services/frp_provider.dart';
import '../services/frpc_manager.dart';
import '../services/hayfrp_provider.dart';
import '../services/ofrp_service.dart';
import '../services/oauth_callback_server.dart';
import '../services/openfrp_provider.dart';
import '../services/sakurafrp_provider.dart';
import '../services/font_settings.dart';
import '../state/app_state.dart';
import '../utils/apple_widgets.dart';

class FrpScreen extends StatefulWidget {
  const FrpScreen({super.key});

  @override
  State<FrpScreen> createState() => _FrpScreenState();
}

class _FrpScreenState extends State<FrpScreen> {
  late FrpProvider _provider;
  String _providerId = FrpProviderKind.openfrp.id;

  FrpAccountInfo? _account;
  List<FrpTunnel>? _tunnels;
  bool _loading = true;
  String? _error;

  /// 右侧日志面板当前选中的隧道 id（null 表示未选择）。
  String? _selectedTunnelId;

  /// 日志面板滚动控制器（自动滚到最新）。
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _providerId = await FrpProviderRegistry.getCurrentId();
    if (!mounted) return;
    _provider = FrpProviderRegistry.create(_providerId);
    await _loadAll();
  }

  Future<void> _switchProvider(String id) async {
    if (id == _providerId) return;
    setState(() {
      _providerId = id;
      _provider = FrpProviderRegistry.create(id);
      _account = null;
      _tunnels = null;
      _error = null;
      _loading = true;
    });
    await FrpProviderRegistry.setCurrentId(id);
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await _provider.loadAccount();
      final tunnels = await _provider.listTunnels();
      if (!mounted) return;
      setState(() {
        _account = account;
        _tunnels = tunnels;
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

  Future<void> _login() async {
    final l = AppLocalizations.of(context);
    final Map<String, String>? credentials;
    switch (FrpProviderKind.fromId(_providerId)) {
      case FrpProviderKind.openfrp:
        credentials = await showAppDialog<Map<String, String>>(
          context,
          (_) => const _OpenFrpLoginDialog(),
        );
      case FrpProviderKind.custom:
        credentials = await showAppDialog<Map<String, String>>(
          context,
          (_) => const _CustomLoginDialog(),
        );
      case FrpProviderKind.chmlfrp:
        credentials = await showAppDialog<Map<String, String>>(
          context,
          (_) => const _ChmlFrpLoginDialog(),
        );
      case FrpProviderKind.sakurafrp:
        credentials = await showAppDialog<Map<String, String>>(
          context,
          (_) => const _SakuraFrpLoginDialog(),
        );
      case FrpProviderKind.hayfrp:
        credentials = await showAppDialog<Map<String, String>>(
          context,
          (_) => const _HayFrpLoginDialog(),
        );
    }
    if (credentials == null || !mounted) return;
    try {
      final account = await _provider.login(credentials);
      if (!mounted) return;
      setState(() => _account = account);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_loginFailed(e.toString()))));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.frp_logoutTitle),
          content: Text(l.frp_logoutConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.common_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.frp_logout),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _provider.logout();
    if (!mounted) return;
    setState(() {
      _account = null;
      _tunnels = null;
      _error = null;
    });
  }

  Future<void> _addTunnel() async {
    final l = AppLocalizations.of(context);
    final draft = await showAppDialog<FrpTunnelDraft>(
      context,
      (ctx) => _NewTunnelDialog(
        provider: _provider,
        instances: context.read<AppState>().instances,
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await _provider.createTunnel(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_tunnelCreated)));
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_createFailed(e.toString()))));
    }
  }

  Future<void> _deleteTunnel(FrpTunnel tunnel) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.frp_deleteTunnelTitle),
          content: Text(l.frp_deleteTunnelConfirm(tunnel.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.common_cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.common_delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _provider.deleteTunnel(tunnel.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_deleted(tunnel.name))));
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_deleteFailed(e.toString()))));
    }
  }

  Future<void> _toggleTunnel(FrpTunnel tunnel) async {
    final l = AppLocalizations.of(context);
    if (_provider.isTunnelRunning(tunnel.id)) {
      await _provider.stopTunnel(tunnel.id);
    } else {
      try {
        await _provider.startTunnel(tunnel.id);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.frp_startFailed(e.toString()))));
      }
    }
    if (!mounted) return;
    setState(() => _selectedTunnelId = tunnel.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final loggedIn = _account != null;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.frp_title),
            const SizedBox(width: 12),
            // 提供商切换
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _providerId,
                  isDense: true,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  items: [
                    for (final kind in FrpProviderKind.values)
                      DropdownMenuItem(value: kind.id, child: Text(kind.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) _switchProvider(v);
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (loggedIn) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.common_refresh,
              onPressed: _loadAll,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l.frp_logout,
              onPressed: _logout,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_account == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_account == null) {
      return _buildLoginPrompt(theme);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadAll, child: Text(l.common_retry)),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildUserCard(theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                l.frp_tunnelCount(_tunnels?.length ?? 0),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addTunnel,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.frp_addTunnel),
              ),
            ],
          ),
        ),
        // 左侧隧道列表 + 右侧日志面板
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: _buildTunnelList(theme)),
              SizedBox(width: 320, child: _buildLogPanel(theme)),
            ],
          ),
        ),
        // OpenFrp OPENAPI 使用条款要求的来源注明（仅 OpenFrp 提供商）。
        if (_provider is OpenFrpProvider)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l.frp_openfrpDisclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// 右侧日志面板：显示选中隧道的完整日志（自动滚动到最新）。
  Widget _buildLogPanel(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.frp_log,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.frp_clearMemoryLog,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear_all, size: 18),
                    onPressed: () => FrpcManager.instance.clearOutput(
                      _provider.tunnelKey(_selectedTunnelId ?? ''),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListenableBuilder(
                listenable: FrpcManager.instance,
                builder: (context, _) {
                  final key = _provider.tunnelKey(_selectedTunnelId ?? '');
                  final output = FrpcManager.instance.outputFor(key);
                  final text = output == null || output.isEmpty
                      ? l.frp_noLogYet
                      : output;
                  final controller = _logScrollController;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (controller.hasClients) {
                      controller.jumpTo(controller.position.maxScrollExtent);
                    }
                  });
                  return SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        fontFamily: FontSettings.instance.terminalFamily,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(ThemeData theme) {
    final isCustom = _provider is CustomFrpProvider;
    final isChmlFrp = _provider is ChmlFrpProvider;
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '${_provider.label} · ${l.frp_portMapping}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isCustom
                  ? l.frp_loginPromptCustom
                  : isChmlFrp
                  ? l.frp_loginPromptChml
                  : l.frp_loginPromptOpen,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _login,
              icon: const Icon(Icons.login, size: 18),
              label: Text(isCustom ? l.frp_configFrps : '${l.frp_login} ${_provider.label}'),
            ),
            if (isChmlFrp) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: _openRegisterPage,
                child: Text(l.frp_noAccountRegister),
              ),
            ],
            const SizedBox(height: 16),
            if (_provider is OpenFrpProvider)
              Text(
                l.frp_openfrpDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRegisterPage() async {
    final l = AppLocalizations.of(context);
    final uri = Uri.parse(chmlFrpRegisterUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_cannotOpenRegisterPage)));
    }
  }

  Widget _buildUserCard(ThemeData theme) {
    final account = _account;
    final l = AppLocalizations.of(context);
    if (account == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          account.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (account.group != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        account.group!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (account.traffic != null)
                    _statItem(theme, l.frp_traffic, account.traffic!),
                  if (account.usage != null)
                    _statItem(theme, l.frp_tunnels, account.usage!),
                  if (account.extra != null)
                    _statItem(theme, l.frp_status, account.extra!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(ThemeData theme, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTunnelList(ThemeData theme) {
    final tunnels = _tunnels ?? [];
    final l = AppLocalizations.of(context);
    if (tunnels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(l.frp_noTunnelsYet, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l.frp_addTunnelHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: FrpcManager.instance,
      builder: (context, _) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tunnels.length,
          itemBuilder: (context, index) =>
              _buildTunnelCard(theme, tunnels[index]),
        );
      },
    );
  }

  Widget _buildTunnelCard(ThemeData theme, FrpTunnel tunnel) {
    final running = _provider.isTunnelRunning(tunnel.id);
    final selected = tunnel.id == _selectedTunnelId;
    final l = AppLocalizations.of(context);
    final typeIcon = switch (tunnel.type) {
      'udp' => Icons.bolt,
      'http' => Icons.language,
      'https' => Icons.lock,
      'stcp' || 'xtcp' => Icons.shield_outlined,
      _ => Icons.link,
    };
    final remoteText = tunnel.type == 'http' || tunnel.type == 'https'
        ? tunnel.remoteAddress.isEmpty
              ? l.frp_domainLabel(tunnel.domain ?? '-')
              : tunnel.remoteAddress
        : l.frp_remotePort((tunnel.remotePort ?? '-').toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedTunnelId = tunnel.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(typeIcon, size: 24, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                tunnel.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _TypeTag(text: tunnel.type.toUpperCase()),
                          ],
                        ),
                        if (tunnel.nodeName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tunnel.nodeName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _StatusDot(
                    color: tunnel.online
                        ? Colors.green
                        : running
                        ? Colors.orange
                        : theme.colorScheme.outline,
                    label: tunnel.online
                        ? l.frp_online
                        : running
                        ? l.frp_connecting
                        : l.frp_offline,
                  ),
                  IconButton(
                    tooltip: running ? l.frp_stop : l.frp_start,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      running ? Icons.stop_circle_outlined : Icons.play_circle,
                      color: running ? theme.colorScheme.error : Colors.green,
                    ),
                    onPressed: () => _toggleTunnel(tunnel),
                  ),
                  IconButton(
                    tooltip: l.common_delete,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteTunnel(tunnel),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.frp_localMapping(tunnel.localAddr, tunnel.localPort, remoteText),
                style: theme.textTheme.bodySmall,
              ),
              if (tunnel.remoteAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  l.frp_connectAddress(tunnel.remoteAddress),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: FontSettings.instance.terminalFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (tunnel.useEncryption ||
                  tunnel.useCompression ||
                  !tunnel.enabled) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (tunnel.useEncryption)
                      _buildMiniTag(text: l.frp_encrypt, theme: theme),
                    if (tunnel.useCompression) ...[
                      const SizedBox(width: 6),
                      _buildMiniTag(text: l.frp_compress, theme: theme),
                    ],
                    if (!tunnel.enabled) ...[
                      const SizedBox(width: 6),
                      _buildMiniTag(text: l.frp_disabledLabel, theme: theme),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTag({required String text, required ThemeData theme}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String text;

  const _TypeTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: primary, fontSize: 11)),
    );
  }
}

/// OpenFrp 登录对话框：Remote Login 远程安全登录（ofapi.md 推荐方案）。
///
/// 流程：生成 Curve25519 密钥对 → 请求授权 → 浏览器打开授权页 →
/// 每 5 秒轮询授权结果（最长 5 分钟）→ 解密得到 Authorization。
class _OpenFrpLoginDialog extends StatefulWidget {
  const _OpenFrpLoginDialog();

  @override
  State<_OpenFrpLoginDialog> createState() => _OpenFrpLoginDialogState();
}

class _OpenFrpLoginDialogState extends State<_OpenFrpLoginDialog> {
  bool _loading = false;
  bool _cancelled = false;
  String? _error;
  String _status = '';

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _cancelled = false;
      _error = null;
      _status = l.frp_requestingAuth;
    });
    final api = OfrpService.instance;
    try {
      // 1. 生成 Curve25519 密钥对并请求授权。
      final keys = await api.generateRemoteLoginKeys();
      final request = await api.requestRemoteLogin(keys.publicKey);

      // 2. 拉起浏览器打开授权页。
      final launched = await launchUrl(
        Uri.parse(request.authorizationUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception(l.frp_cannotOpenBrowser);
      }

      // 3. 轮询授权结果（每 5 秒，最长 5 分钟）。
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      String? auth;
      Object? lastError;
      while (!_cancelled && DateTime.now().isBefore(deadline)) {
        try {
          final poll = await api.pollRemoteLogin(request.requestUuid);
          if (mounted) setState(() => _status = l.frp_authorizedDecrypting);
          auth = await OfrpService.decryptAuthorization(
            poll.authorizationData,
            keys.keyPair,
            poll.serverPublicKey,
          );
          break;
        } on PendingAuthorizationException {
          // 尚未授权，继续轮询。
          if (mounted) setState(() => _status = l.frp_waitingBrowserAuth);
        } catch (e) {
          // 真实错误（网络/解密失败等），立即停止并展示。
          lastError = e;
          break;
        }
        await Future.delayed(const Duration(seconds: 5));
      }
      if (_cancelled) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (auth == null || auth.isEmpty) {
        throw Exception(lastError?.toString() ?? l.frp_authTimeout);
      }
      if (!mounted) return;
      Navigator.of(context).pop({'authorization': auth});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _status = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.frp_loginOpenFrpTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.frp_openfrpAuthDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _status.isEmpty ? l.frp_waitingBrowserAuth : _status,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_loading) {
              setState(() => _cancelled = true);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(_loading ? l.common_cancel : l.common_close),
        ),
        FilledButton(
          onPressed: _loading ? null : _start,
          child: Text(l.frp_authorizeInBrowser),
        ),
      ],
    );
  }
}

/// 自建 frps 登录（配置）对话框。
class _CustomLoginDialog extends StatefulWidget {
  const _CustomLoginDialog();

  @override
  State<_CustomLoginDialog> createState() => _CustomLoginDialogState();
}

class _CustomLoginDialogState extends State<_CustomLoginDialog> {
  final _serverController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final server = _serverController.text.trim();
    if (server.isEmpty) {
      setState(() => _error = l.frp_enterServerAddress);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await CustomFrpProvider().login({
        'server': server,
        'token': _tokenController.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop({'server': server, 'token': _tokenController.text.trim()});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.frp_configSelfHosted),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _serverController,
                autofocus: true,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.frp_serverAddress,
                  hintText: 'frps.example.com:7000',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                obscureText: true,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.frp_authToken,
                  hintText: l.frp_authTokenHint,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l.frp_selfHostedHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.common_save),
        ),
      ],
    );
  }
}

/// ChmlFrp 登录对话框：SSO 网页授权登录。
///
/// 浏览器打开 cf-v2.uapis.cn/sso/authorize 登录授权后，
/// 自动跳回本地回调（#access_token=...），无需复制粘贴。
/// 不提供注册功能，通过链接跳转到官网注册页。
class _ChmlFrpLoginDialog extends StatefulWidget {
  const _ChmlFrpLoginDialog();

  @override
  State<_ChmlFrpLoginDialog> createState() => _ChmlFrpLoginDialogState();
}

class _ChmlFrpLoginDialogState extends State<_ChmlFrpLoginDialog> {
  final OAuthCallbackServer _callback = OAuthCallbackServer();
  bool _loading = false;
  bool _cancelled = false;
  String? _error;

  @override
  void dispose() {
    _cancelled = true;
    _callback.stop();
    super.dispose();
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _cancelled = false;
      _error = null;
    });
    try {
      await _callback.start();
      // H-5：携带一次性随机 state，回调时校验，防止本机进程抢答伪造 token。
      final state = _callback.state ?? '';
      final returnUrl = Uri.encodeComponent(
        'http://127.0.0.1:${_callback.port}/callback?state=$state',
      );
      final authorizeUrl =
          '$chmlFrpApiBase/sso/authorize?return_url=$returnUrl&state=$state';
      final launched = await launchUrl(
        Uri.parse(authorizeUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception(l.frp_cannotOpenBrowser);
      }
      final params = await _callback.waitForParams();
      if (_cancelled) return;
      if (params == null) {
        throw Exception(l.frp_authCallbackTimeout);
      }
      final accessToken = params['access_token'];
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(l.frp_noAccessToken);
      }
      if (!mounted) return;
      Navigator.of(context).pop({
        'access_token': accessToken,
        'refresh_token': params['refresh_token'] ?? '',
        'expires_at': params['expires_at'] ?? '',
        'expires_in': params['expires_in'] ?? '',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      await _callback.stop();
    }
  }

  Future<void> _openRegister() async {
    final l = AppLocalizations.of(context);
    final uri = Uri.parse(chmlFrpRegisterUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.frp_cannotOpenRegisterPage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.frp_loginChmlFrpTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.frp_chmlfrpAuthDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _openRegister,
                child: Text(l.frp_noAccountRegister),
              ),
              Text(
                l.frp_chmlfrpNoRegister,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l.frp_waitingBrowserAuth, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_loading) {
              setState(() => _cancelled = true);
              _callback.stop();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(_loading ? l.common_cancel : l.common_close),
        ),
        FilledButton(
          onPressed: _loading ? null : _start,
          child: Text(l.frp_authorizeInBrowser),
        ),
      ],
    );
  }
}

/// SakuraFrp 登录对话框：粘贴访问密钥（Access Token）。
class _SakuraFrpLoginDialog extends StatefulWidget {
  const _SakuraFrpLoginDialog();

  @override
  State<_SakuraFrpLoginDialog> createState() => _SakuraFrpLoginDialogState();
}

class _SakuraFrpLoginDialogState extends State<_SakuraFrpLoginDialog> {
  final _tokenController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// 访问密钥是否隐藏（默认隐藏，眼睛按钮切换显示）。
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l = AppLocalizations.of(context);
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = l.frp_enterAccessToken);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SakuraFrpProvider().login({'token': token});
      if (!mounted) return;
      Navigator.of(context).pop({'token': token});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.frp_loginSakuraFrpTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _tokenController,
                maxLines: 2,
                obscureText: _obscureToken,
                enableSuggestions: false,
                autocorrect: false,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 12),
                decoration: InputDecoration(
                  labelText: l.frp_accessToken,
                  hintText: l.frp_accessTokenHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureToken ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    tooltip: _obscureToken ? l.frp_show : l.frp_hide,
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l.frp_sakurafrpTokenHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.frp_login),
        ),
      ],
    );
  }
}

/// HayFrp 登录对话框：用户名/邮箱 + 密码。
class _HayFrpLoginDialog extends StatefulWidget {
  const _HayFrpLoginDialog();

  @override
  State<_HayFrpLoginDialog> createState() => _HayFrpLoginDialogState();
}

class _HayFrpLoginDialogState extends State<_HayFrpLoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l = AppLocalizations.of(context);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = l.frp_enterUsernamePassword);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await HayFrpProvider().login({
        'username': username,
        'password': password,
      });
      if (!mounted) return;
      Navigator.of(context).pop({'username': username, 'password': password});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.frp_loginHayFrpTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _usernameController,
                autofocus: true,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.frp_usernameOrEmail,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: l.frp_password,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l.frp_hayfrpTokenHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.frp_login),
        ),
      ],
    );
  }
}

/// 新建隧道对话框。
///
/// 端口来源二选一：
/// - 选择实例：读取该实例 server.properties 中的 server-port 自动填写
///   （没有 server.properties 的实例不会出现在列表中）；
/// - 手动填写。
class _NewTunnelDialog extends StatefulWidget {
  final FrpProvider provider;
  final List<ServerInstance> instances;

  const _NewTunnelDialog({required this.provider, required this.instances});

  @override
  State<_NewTunnelDialog> createState() => _NewTunnelDialogState();
}

class _NewTunnelDialogState extends State<_NewTunnelDialog> {
  final _nameController = TextEditingController();
  final _localAddrController = TextEditingController(text: '127.0.0.1');
  final _localPortController = TextEditingController();
  final _remotePortController = TextEditingController();
  final _domainController = TextEditingController();

  List<FrpNode>? _nodes;
  String? _nodesError;

  String? _selectedNodeId;
  String _type = 'tcp';
  bool _encrypt = true;
  bool _gzip = true;

  /// 端口来源：true 选择实例，false 手动填写。
  bool _useInstance = true;
  String? _selectedInstancePath;

  bool get _hasNodes => widget.provider is! CustomFrpProvider;

  @override
  void initState() {
    super.initState();
    if (_hasNodes) {
      _loadNodes();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _localAddrController.dispose();
    _localPortController.dispose();
    _remotePortController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _loadNodes() async {
    setState(() {
      _nodes = null;
      _nodesError = null;
    });
    try {
      final nodes = await widget.provider.listNodes();
      if (!mounted) return;
      setState(() => _nodes = nodes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _nodesError = e.toString());
    }
  }

  /// 有 server.properties 的实例列表（含自动读取的端口）。
  List<({ServerInstance instance, int port})> get _instanceCandidates => [
    for (final instance in widget.instances)
      if (readInstanceServerPort(instance.rootPath) != null)
        (instance: instance, port: readInstanceServerPort(instance.rootPath)!),
  ];

  void _onInstanceSelected(String? path) {
    setState(() => _selectedInstancePath = path);
    if (path == null) return;
    for (final candidate in _instanceCandidates) {
      if (candidate.instance.rootPath == path) {
        _localPortController.text = '${candidate.port}';
        break;
      }
    }
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final type = _type;
    final localAddr = _localAddrController.text.trim();
    final localPort = int.tryParse(_localPortController.text.trim());
    final remotePort = int.tryParse(_remotePortController.text.trim());
    final nodeId = int.tryParse(_selectedNodeId ?? '');
    final isWeb = type == 'http' || type == 'https';
    final domain = _domainController.text.trim();

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
      _toast(l.frp_tunnelNameRule);
      return;
    }
    if (_hasNodes && nodeId == null) {
      _toast(l.frp_selectNode);
      return;
    }
    if (localAddr.isEmpty) {
      _toast(l.frp_enterLocalAddr);
      return;
    }
    if (localPort == null || localPort < 1 || localPort > 65535) {
      _toast(l.frp_localPortRange);
      return;
    }
    if (isWeb) {
      if (domain.isEmpty) {
        _toast(l.frp_webNeedsDomain);
        return;
      }
    } else if (remotePort == null || remotePort < 1 || remotePort > 65535) {
      _toast(l.frp_remotePortRange);
      return;
    }

    Navigator.of(context).pop(
      FrpTunnelDraft(
        name: name,
        nodeId: nodeId,
        type: type,
        localAddr: localAddr,
        localPort: localPort,
        remotePort: isWeb ? null : remotePort,
        domain: isWeb ? domain : '',
        encrypt: _encrypt,
        gzip: _gzip,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final isWeb = _type == 'http' || _type == 'https';
    return AlertDialog(
      title: Text(l.frp_addTunnel),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.frp_tunnelName,
                  hintText: l.frp_tunnelNameHint,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_hasNodes) _buildNodeSelector(theme),
              if (_hasNodes) const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l.frp_tunnelType,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  DropdownMenuItem(value: 'udp', child: Text('UDP')),
                  if (widget.provider.supportsWebTunnels) ...[
                    DropdownMenuItem(value: 'http', child: Text('HTTP')),
                    DropdownMenuItem(
                      value: 'https',
                      child: Text('HTTPS'),
                    ),
                  ],
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _localAddrController,
                style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.frp_localAddress,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.storage, size: 16),
                    label: Text(l.frp_selectInstance),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.edit_outlined, size: 16),
                    label: Text(l.frp_manualInput),
                  ),
                ],
                selected: {_useInstance},
                onSelectionChanged: (s) =>
                    setState(() => _useInstance = s.first),
              ),
              const SizedBox(height: 12),
              if (_useInstance)
                _buildInstanceSelector(theme)
              else
                TextField(
                  controller: _localPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.frp_localPort,
                    hintText: l.frp_localPortExample,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              if (_useInstance) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _localPortController,
                  readOnly: true,
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.frp_localPortAuto,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (!isWeb) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _remotePortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.frp_remotePortLabel,
                    hintText: l.frp_remotePortHint,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _domainController,
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.frp_bindDomain,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      value: _encrypt,
                      onChanged: (v) => setState(() => _encrypt = v ?? false),
                      title: Text(l.frp_encrypt, style: const TextStyle(fontSize: 13)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      value: _gzip,
                      onChanged: (v) => setState(() => _gzip = v ?? false),
                      title: Text(l.frp_compress, style: const TextStyle(fontSize: 13)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.frp_create)),
      ],
    );
  }

  Widget _buildNodeSelector(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_nodesError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l.frp_nodeLoadFailed(_nodesError!),
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
          TextButton(onPressed: _loadNodes, child: Text(l.common_retry)),
        ],
      );
    }
    if (_nodes == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final nodes = _nodes!;
    if (nodes.isEmpty) {
      return Text(l.frp_noAvailableNodes, style: TextStyle(color: theme.colorScheme.error));
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedNodeId,
      decoration: InputDecoration(
        labelText: l.frp_node,
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final node in nodes)
          DropdownMenuItem(
            value: '${node.id}',
            child: Text(node.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _selectedNodeId = v),
    );
  }

  Widget _buildInstanceSelector(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final candidates = _instanceCandidates;
    if (candidates.isEmpty) {
      return Text(
        l.frp_noAvailableInstances,
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedInstancePath,
      decoration: InputDecoration(
        labelText: l.frp_instanceAutoPort,
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final candidate in candidates)
          DropdownMenuItem(
            value: candidate.instance.rootPath,
            child: Text(
              l.frp_instancePort(candidate.instance.name, candidate.port),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _onInstanceSelected,
    );
  }
}
