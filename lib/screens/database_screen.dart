// 数据库 — 远程数据库连接管理页面
// 提供 MySQL / MariaDB / PostgreSQL / Redis 连接的增删改查与连接测试
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/remote_db_service.dart';
import '../utils/apple_widgets.dart';
import 'database_detail_screen.dart';

/// 数据库连接管理页面。
///
/// 顶部为标题与"添加连接"按钮，下方展示已保存的连接列表；
/// 点击卡片或"连接"按钮会先测试连通性，成功后跳转详情页。
class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  /// 已保存的连接列表。
  List<DbConnectionInfo> _connections = [];

  /// 是否正在加载列表。
  bool _loading = true;

  /// 列表加载失败的错误信息。
  String? _error;

  /// 正在测试连接的连接 id（卡片内显示小进度圈）。
  String? _connectingId;

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
      final list = await RemoteDatabaseService.instance.getAllConnections();
      if (!mounted) return;
      setState(() {
        _connections = list;
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

  /// 测试连接并跳转详情页。
  Future<void> _connect(DbConnectionInfo connection) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = connection.id);
    try {
      final error = await RemoteDatabaseService.instance.testConnection(
        connection,
      );
      if (!mounted) return;
      if (error == null) {
        await pushPage<void>(
          context,
          (_) => DatabaseDetailScreen(connection: connection),
        );
      } else {
        _showErrorDialog(error);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(e.toString());
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  /// 打开添加/编辑对话框，保存成功后刷新列表。
  Future<void> _openEditor([DbConnectionInfo? existing]) async {
    final saved = await showAppDialog<bool>(
      context,
      (_) => _ConnectionDialog(existing: existing),
    );
    if (saved == true && mounted) {
      final l = AppLocalizations.of(context);
      _load();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbScreen_saved)));
    }
  }

  /// 删除连接（带确认对话框）。
  Future<void> _delete(DbConnectionInfo connection) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (_) => AlertDialog(
        title: Text(l.dbScreen_deleteTitle),
        content: Text(l.dbScreen_deleteConfirm(connection.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.common_cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await RemoteDatabaseService.instance.deleteConnection(connection.id);
      _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbScreen_deleted)));
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(e.toString());
    }
  }

  /// 显示连接失败对话框。
  void _showErrorDialog(String message) {
    final l = AppLocalizations.of(context);
    showAppDialog<void>(
      context,
      (_) => AlertDialog(
        title: Text(l.dbScreen_connectionFailed),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.common_ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.dbScreen_title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppleButton(
                  onPressed: () => _openEditor(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 18),
                      const SizedBox(width: 4),
                      Text(l.dbScreen_addConnection),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 提示文字
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              l.dbScreen_manageHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
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
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(l.common_retry)),
          ],
        ),
      );
    }
    if (_connections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(l.dbScreen_emptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l.dbScreen_emptyAddHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _connections.length,
      itemBuilder: (context, index) {
        final connection = _connections[index];
        return _ConnectionCard(
          connection: connection,
          connecting: _connectingId == connection.id,
          onConnect: () => _connect(connection),
          onEdit: () => _openEditor(connection),
          onDelete: () => _delete(connection),
        );
      },
    );
  }
}

/// 数据库连接卡片。
///
/// 展示类型图标、名称、类型标签与连接信息，
/// 点击卡片主体或"连接"按钮测试并跳转详情页。
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.connecting,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final DbConnectionInfo connection;

  /// 当前是否正在测试此连接。
  final bool connecting;

  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 类型图标：mysql/mariadb 用存储类图标，postgres 用关系图，redis 用火焰。
  IconData get _typeIcon => switch (connection.type) {
    DbType.mysql => Icons.storage,
    DbType.mariadb => Icons.dns,
    DbType.postgres => Icons.account_tree,
    DbType.redis => Icons.local_fire_department,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final username = connection.username;
    final database = connection.databaseName;
    final subInfo = [
      if (username != null && username.isNotEmpty) username,
      if (database != null && database.isNotEmpty) database,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onConnect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 类型图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _typeIcon,
                      size: 32,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 名称与连接信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                connection.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TypeTag(type: connection.type),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${connection.host}:${connection.port}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (subInfo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subInfo,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 编辑 / 删除
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        visualDensity: VisualDensity.compact,
                        tooltip: l.common_edit,
                        onPressed: onEdit,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        visualDensity: VisualDensity.compact,
                        tooltip: l.common_delete,
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 连接按钮
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: connecting ? null : onConnect,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.link, size: 16),
                            const SizedBox(width: 4),
                            Text(l.dbScreen_connect),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 数据库类型标签。
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.type});

  final DbType type;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(type.label, style: TextStyle(color: primary, fontSize: 12)),
    );
  }
}

/// 添加 / 编辑连接对话框。
///
/// 保存时校验名称、主机非空且端口在 1-65535 之间；
/// 编辑时保留原 id 与 createdAt，新增时按微秒时间戳 36 进制生成 id。
class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.existing});

  /// 编辑时的原连接；为 null 表示新增。
  final DbConnectionInfo? existing;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _databaseController = TextEditingController();

  late DbType _type;
  late bool _useSsl;

  String? _nameError;
  String? _hostError;
  String? _portError;

  bool get _isEdit => widget.existing != null;

  /// 生成连接唯一标识：微秒时间戳 36 进制 + 随机后缀。
  static String _generateId() {
    final random = Random();
    final suffix = random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _type = existing.type;
      _useSsl = existing.useSsl;
      _nameController.text = existing.name;
      _hostController.text = existing.host;
      _portController.text = '${existing.port}';
      _usernameController.text = existing.username ?? '';
      _passwordController.text = existing.password ?? '';
      _databaseController.text = existing.databaseName ?? '';
    } else {
      _type = DbType.mysql;
      _useSsl = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _databaseController.dispose();
    super.dispose();
  }

  void _onTypeChanged(DbType? type) {
    if (type == null || type == _type) return;
    setState(() {
      _type = type;
    });
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    setState(() {
      _nameError = name.isEmpty ? l.dbScreen_nameRequired : null;
      _hostError = host.isEmpty ? l.dbScreen_hostRequired : null;
      _portError = (port == null || port < 1 || port > 65535)
          ? l.dbScreen_portRange
          : null;
    });
    if (_nameError != null || _hostError != null || _portError != null) return;

    final existing = widget.existing;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final database = _databaseController.text.trim();
    final connection = DbConnectionInfo(
      id: existing?.id ?? _generateId(),
      name: name,
      type: _type,
      host: host,
      port: port!,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      databaseName: database.isEmpty ? null : database,
      useSsl: _useSsl,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    await RemoteDatabaseService.instance.saveConnection(connection);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_isEdit ? l.dbScreen_editTitle : l.dbScreen_addConnection),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l.common_name,
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DbType>(
                key: ValueKey(_type),
                initialValue: _type,
                decoration: InputDecoration(labelText: l.dbDetail_type),
                items: [
                  for (final type in DbType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: _onTypeChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: l.dbScreen_host,
                  hintText: l.dbScreen_hostHint,
                  errorText: _hostError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l.dbScreen_port,
                  errorText: _portError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: l.dbScreen_usernameOptional,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.dbScreen_passwordOptional,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _databaseController,
                decoration: InputDecoration(
                  labelText: l.dbScreen_databaseNameOptional,
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.dbScreen_useSsl),
                subtitle: Text(l.dbScreen_sslSubtitle),
                value: _useSsl,
                onChanged: (v) => setState(() => _useSsl = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.common_cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.common_save)),
      ],
    );
  }
}
