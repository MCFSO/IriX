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
      ).showSnackBar(SnackBar(content: Text('登录失败: $e')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
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
      ).showSnackBar(const SnackBar(content: Text('隧道创建成功')));
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _deleteTunnel(FrpTunnel tunnel) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除隧道'),
        content: Text('确定删除隧道 "${tunnel.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _provider.deleteTunnel(tunnel.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 ${tunnel.name}')));
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  Future<void> _toggleTunnel(FrpTunnel tunnel) async {
    if (_provider.isTunnelRunning(tunnel.id)) {
      await _provider.stopTunnel(tunnel.id);
    } else {
      try {
        await _provider.startTunnel(tunnel.id);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('启动失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn = _account != null;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('FRP 端口映射'),
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
              tooltip: '刷新',
              onPressed: _loadAll,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '退出登录',
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
            FilledButton(onPressed: _loadAll, child: const Text('重试')),
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
                '隧道 (${_tunnels?.length ?? 0})',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addTunnel,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加隧道'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildTunnelList(theme)),
        // OpenFrp OPENAPI 使用条款要求的来源注明（仅 OpenFrp 提供商）。
        if (_provider is OpenFrpProvider)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '此项目由社区开发，OpenFrp 官方不负责除节点问题以外的技术支持',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildLoginPrompt(ThemeData theme) {
    final isCustom = _provider is CustomFrpProvider;
    final isChmlFrp = _provider is ChmlFrpProvider;
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
              '${_provider.label} · 端口映射',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isCustom
                  ? '配置你的 frps 服务器地址与认证 token，\n'
                        '隧道保存在本地，一键启动 frpc 实现内网穿透。'
                  : isChmlFrp
                  ? '登录 ChmlFrp 账号后可为服务器创建端口映射（隧道），\n'
                        '并在 IriX 内一键启动 frpc 实现内网穿透。'
                  : '登录 OpenFrp 后可为服务器创建端口映射（隧道），\n'
                        '并在 IriX 内一键启动 frpc 实现内网穿透。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _login,
              icon: const Icon(Icons.login, size: 18),
              label: Text(isCustom ? '配置 frps' : '登录 ${_provider.label}'),
            ),
            if (isChmlFrp) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: _openRegisterPage,
                child: const Text('还没有账号？去注册'),
              ),
            ],
            const SizedBox(height: 16),
            if (_provider is OpenFrpProvider)
              Text(
                '此项目由社区开发，OpenFrp 官方不负责除节点问题以外的技术支持',
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
    final uri = Uri.parse(chmlFrpRegisterUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开注册页面')));
    }
  }

  Widget _buildUserCard(ThemeData theme) {
    final account = _account;
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
                    _statItem(theme, '剩余流量', account.traffic!),
                  if (account.usage != null)
                    _statItem(theme, '隧道', account.usage!),
                  if (account.extra != null)
                    _statItem(theme, '状态', account.extra!),
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
            Text('还没有隧道', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '点击右上角「添加隧道」创建端口映射',
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
    final output = _provider.tunnelOutput(tunnel.id);
    final typeIcon = switch (tunnel.type) {
      'udp' => Icons.bolt,
      'http' => Icons.language,
      'https' => Icons.lock,
      'stcp' || 'xtcp' => Icons.shield_outlined,
      _ => Icons.link,
    };
    final remoteText = tunnel.type == 'http' || tunnel.type == 'https'
        ? tunnel.remoteAddress.isEmpty
              ? tunnel.domain ?? '域名: ${tunnel.domain ?? '-'}'
              : tunnel.remoteAddress
        : '远程端口 ${tunnel.remotePort ?? '-'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      ? '在线'
                      : running
                      ? '连接中'
                      : '离线',
                ),
                IconButton(
                  tooltip: running ? '停止' : '启动',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    running ? Icons.stop_circle_outlined : Icons.play_circle,
                    color: running ? theme.colorScheme.error : Colors.green,
                  ),
                  onPressed: () => _toggleTunnel(tunnel),
                ),
                IconButton(
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteTunnel(tunnel),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '本地 ${tunnel.localAddr}:${tunnel.localPort}  →  $remoteText',
              style: theme.textTheme.bodySmall,
            ),
            if (tunnel.remoteAddress.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '连接地址 ${tunnel.remoteAddress}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
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
                    _buildMiniTag(text: '加密', theme: theme),
                  if (tunnel.useCompression) ...[
                    const SizedBox(width: 6),
                    _buildMiniTag(text: '压缩', theme: theme),
                  ],
                  if (!tunnel.enabled) ...[
                    const SizedBox(width: 6),
                    _buildMiniTag(text: '未启用', theme: theme),
                  ],
                ],
              ),
            ],
            if (running && output != null && output.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
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

/// OpenFrp 登录对话框。
///
/// 网页授权登录（OAuth 网页传参）：本地起回调服务器，
/// 拉起浏览器到 Natayark ID 授权页，登录授权后自动带回凭据。
/// 面板已不提供 Authorization 复制，故仅保留网页授权方式。
class _OpenFrpLoginDialog extends StatefulWidget {
  const _OpenFrpLoginDialog();

  @override
  State<_OpenFrpLoginDialog> createState() => _OpenFrpLoginDialogState();
}

class _OpenFrpLoginDialogState extends State<_OpenFrpLoginDialog> {
  final OAuthCallbackServer _callback = OAuthCallbackServer();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _callback.stop();
    super.dispose();
  }

  Future<void> _webLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _callback.start();
      final url = OfrpService.buildOAuthAuthorizeUrl(_callback.port);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('无法打开浏览器，请重试');
      }
      final code = await _callback.waitForCode();
      if (code == null || code.isEmpty) {
        throw Exception('等待网页授权超时或已取消');
      }
      final auth = await OfrpService.instance.exchangeOAuthCode(code);
      if (!mounted) return;
      Navigator.of(context).pop({'authorization': auth});
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

  void _cancel() {
    _callback.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('登录 OpenFrp'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '点击下方按钮后将在浏览器中打开 Natayark ID 授权页：\n'
                '登录/授权完成后会自动跳回 IriX，无需复制粘贴任何内容。',
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
                    Text('等待浏览器授权…', style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? _cancel : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _webLogin,
          child: const Text('在浏览器中登录'),
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
    final server = _serverController.text.trim();
    if (server.isEmpty) {
      setState(() => _error = '请输入服务器地址');
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
    return AlertDialog(
      title: const Text('配置自建 frps'),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '服务器地址',
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '认证 token',
                  hintText: 'frps 配置中的 auth.token（可留空）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '隧道将保存在本地，启动时生成 frpc TOML 配置并运行。',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// ChmlFrp 登录对话框：用户名/邮箱 + 密码。
/// 不提供注册功能，通过链接跳转到官网注册页。
class _ChmlFrpLoginDialog extends StatefulWidget {
  const _ChmlFrpLoginDialog();

  @override
  State<_ChmlFrpLoginDialog> createState() => _ChmlFrpLoginDialogState();
}

class _ChmlFrpLoginDialogState extends State<_ChmlFrpLoginDialog> {
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
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ChmlFrpProvider().login({
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

  Future<void> _openRegister() async {
    final uri = Uri.parse(chmlFrpRegisterUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开注册页面')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('登录 ChmlFrp'),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '用户名或邮箱',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _openRegister,
                child: const Text('还没有账号？去注册'),
              ),
              Text(
                'IriX 不提供 ChmlFrp 账号注册，请前往官网注册后登录。',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
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

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = '请输入访问密钥');
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
    return AlertDialog(
      title: const Text('登录 SakuraFrp'),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  labelText: '访问密钥 (Access Token)',
                  hintText: '粘贴 SakuraFrp 访问密钥',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '获取方式：打开 SakuraFrp 控制台 → 账户信息 → 访问密钥，'
                '点击复制后粘贴到此处。',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
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
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
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
    return AlertDialog(
      title: const Text('登录 HayFrp'),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '用户名或邮箱',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '登录获取的 Token 有效期 7 天，每次登录会使上次 Token 失效。',
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
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
    final name = _nameController.text.trim();
    final type = _type;
    final localAddr = _localAddrController.text.trim();
    final localPort = int.tryParse(_localPortController.text.trim());
    final remotePort = int.tryParse(_remotePortController.text.trim());
    final nodeId = int.tryParse(_selectedNodeId ?? '');
    final isWeb = type == 'http' || type == 'https';
    final domain = _domainController.text.trim();

    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
      _toast('隧道名称仅支持英文、数字、- 和 _');
      return;
    }
    if (_hasNodes && nodeId == null) {
      _toast('请选择节点');
      return;
    }
    if (localAddr.isEmpty) {
      _toast('请输入本地地址');
      return;
    }
    if (localPort == null || localPort < 1 || localPort > 65535) {
      _toast('本地端口需在 1-65535 之间');
      return;
    }
    if (isWeb) {
      if (domain.isEmpty) {
        _toast('HTTP/HTTPS 隧道需要填写绑定域名');
        return;
      }
    } else if (remotePort == null || remotePort < 1 || remotePort > 65535) {
      _toast('远程端口需在 1-65535 之间');
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
    final isWeb = _type == 'http' || _type == 'https';
    return AlertDialog(
      title: const Text('添加隧道'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '隧道名称',
                  hintText: '例如 my_server（不支持中文）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_hasNodes) _buildNodeSelector(theme),
              if (_hasNodes) const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: '隧道类型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  const DropdownMenuItem(value: 'udp', child: Text('UDP')),
                  if (widget.provider.supportsWebTunnels) ...[
                    const DropdownMenuItem(value: 'http', child: Text('HTTP')),
                    const DropdownMenuItem(
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '本地地址',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.storage, size: 16),
                    label: Text('选择实例'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.edit_outlined, size: 16),
                    label: Text('手动填写'),
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
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '本地端口',
                    hintText: '例如 25565',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              if (_useInstance) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _localPortController,
                  readOnly: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '本地端口（自动读取）',
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
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '远程端口',
                    hintText: '开放给外部的端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _domainController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '绑定域名',
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
                      title: const Text('加密', style: TextStyle(fontSize: 13)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      value: _gzip,
                      onChanged: (v) => setState(() => _gzip = v ?? false),
                      title: const Text('压缩', style: TextStyle(fontSize: 13)),
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
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }

  Widget _buildNodeSelector(ThemeData theme) {
    if (_nodesError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '节点加载失败: $_nodesError',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
          TextButton(onPressed: _loadNodes, child: const Text('重试')),
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
      return Text('没有可用的节点', style: TextStyle(color: theme.colorScheme.error));
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedNodeId,
      decoration: const InputDecoration(
        labelText: '节点',
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
    final candidates = _instanceCandidates;
    if (candidates.isEmpty) {
      return Text(
        '没有可用实例（需存在 server.properties 才能自动读取端口）',
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedInstancePath,
      decoration: const InputDecoration(
        labelText: '实例（自动读取 server-port）',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final candidate in candidates)
          DropdownMenuItem(
            value: candidate.instance.rootPath,
            child: Text(
              '${candidate.instance.name} · 端口 ${candidate.port}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _onInstanceSelected,
    );
  }
}
