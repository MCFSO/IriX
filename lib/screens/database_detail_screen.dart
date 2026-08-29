// 数据库连接详情页面
// 关系型（MySQL/MariaDB/PostgreSQL）：数据库 → 表 → 数据 三级浏览，支持执行 SQL
// Redis：Key 前缀搜索、查看、添加与删除
import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/db_page_settings.dart';
import '../services/remote_db_service.dart';
import '../services/font_settings.dart';
import '../utils/apple_widgets.dart';

/// 数据库连接详情页面，浏览远程数据库内容。
class DatabaseDetailScreen extends StatefulWidget {
  final DbConnectionInfo connection;

  const DatabaseDetailScreen({super.key, required this.connection});

  @override
  State<DatabaseDetailScreen> createState() => _DatabaseDetailScreenState();
}

class _DatabaseDetailScreenState extends State<DatabaseDetailScreen> {
  late final DbConnectionInfo _connection;
  final RemoteDatabaseService _service = RemoteDatabaseService.instance;

  // 关系型层级: 1 数据库列表 / 2 表列表 / 3 数据浏览
  int _level = 1;
  String? _selectedDb;
  String? _selectedTable;
  List<String> _databases = [];
  List<String> _tables = [];
  List<Map<String, dynamic>> _rows = [];
  List<String> _columns = [];

  // 数据浏览分页（第 3 层）
  int _page = 1;
  int _pageSize = DbPageSettings.defaultPageSize;
  int _totalRows = 0;

  bool _loading = false;
  String? _error;

  // Redis
  List<String> _redisKeys = [];
  String _redisPattern = '*';
  final TextEditingController _redisSearchController = TextEditingController();
  Timer? _debounce;

  bool get _isRedis => _connection.type == DbType.redis;

  // 用户管理（仅关系型数据库）
  List<DbUserInfo> _users = [];
  bool _usersLoading = true;
  String? _usersError;

  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _loadInitial();
    _loadUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _redisSearchController.dispose();
    super.dispose();
  }

  void _loadInitial() {
    if (_isRedis) {
      _loadRedisKeys();
    } else {
      _loadDatabases();
    }
  }

  // ---------- 数据加载 ----------

  Future<void> _loadDatabases() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final databases = await _service.getDatabases(_connection);
      if (!mounted) return;
      setState(() {
        _databases = databases;
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

  Future<void> _loadTables() async {
    final db = _selectedDb;
    if (db == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await _service.getTables(_connection, db);
      if (!mounted) return;
      setState(() {
        _tables = tables;
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

  Future<void> _loadRows() async {
    final db = _selectedDb;
    final table = _selectedTable;
    if (db == null || table == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _pageSize = DbPageSettings.pageSize;
      final total = await _service.countRows(_connection, db, table);
      final maxPage = total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
      if (_page > maxPage) _page = maxPage;
      final rows = await _service.queryTable(
        _connection,
        db,
        table,
        limit: _pageSize,
        offset: (_page - 1) * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _columns = rows.isNotEmpty ? rows.first.keys.toList() : [];
        _totalRows = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _rows = [];
        _columns = [];
        _loading = false;
      });
    }
  }

  void _goToPage(int page) {
    if (page < 1) return;
    final maxPage = _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;
    if (page > maxPage) return;
    if (page == _page) return;
    setState(() => _page = page);
    _loadRows();
  }

  Future<void> _loadRedisKeys() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keys = await _service.getRedisKeys(
        _connection,
        pattern: _redisPattern,
      );
      if (!mounted) return;
      setState(() {
        _redisKeys = keys;
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

  /// 按当前层级重新加载数据。
  void _retryCurrentLevel() {
    switch (_level) {
      case 2:
        _loadTables();
      case 3:
        _loadRows();
      default:
        _loadDatabases();
    }
  }

  void _refreshCurrent() {
    if (_isRedis) {
      _loadRedisKeys();
    } else {
      _retryCurrentLevel();
    }
  }

  // ---------- 层级导航 ----------

  void _selectDatabase(String db) {
    setState(() {
      _level = 2;
      _selectedDb = db;
      _selectedTable = null;
    });
    _loadTables();
  }

  void _selectTable(String table) {
    setState(() {
      _level = 3;
      _selectedTable = table;
      _page = 1;
      _totalRows = 0;
    });
    _loadRows();
  }

  void _goBack() {
    setState(() {
      if (_level == 3) {
        _level = 2;
        _selectedTable = null;
      } else {
        _level = 1;
        _selectedDb = null;
      }
    });
  }

  // ---------- 顶部操作 ----------

  Future<void> _testConnection() async {
    final l = AppLocalizations.of(context);
    try {
      if (_isRedis) {
        await _service.getRedisKeys(_connection, pattern: '*');
      } else {
        await _service.getDatabases(_connection);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_connectionSuccess)));
      _refreshCurrent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_connectionFailed(e.toString()))));
    }
  }

  void _showSqlDialog() {
    showAppDialog(
      context,
      (ctx) => _SqlDialog(
        connection: _connection,
        databases: _databases,
        initialDatabase: _selectedDb,
      ),
    );
  }

  // ---------- 数据库管理 ----------

  Future<void> _showCreateDatabaseDialog() async {
    final l = AppLocalizations.of(context);
    final creds =
        await showAppDialog<
          ({String database, String username, String password})
        >(context, (ctx) => _CreateDatabaseDialog(type: _connection.type));
    if (creds == null || !mounted) return;
    try {
      await _service.createDatabaseWithUser(
        _connection,
        database: creds.database,
        username: creds.username,
        password: creds.password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_databaseCreated(creds.database))),
      );
      _loadDatabases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_createFailed(e.toString()))));
    }
  }

  Future<void> _confirmDropDatabase(String database) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.dbDetail_dropDatabaseTitle),
        content: Text(l.dbDetail_dropDatabaseConfirm(database)),
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
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.dropDatabase(_connection, database);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_databaseDeleted(database))),
      );
      if (_selectedDb == database) {
        _selectedDb = null;
        _level = 1;
      }
      _loadDatabases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  // ---------- Redis 操作 ----------

  void _onRedisSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final trimmed = text.trim();
      final pattern = trimmed.isEmpty ? '*' : '$trimmed*';
      if (pattern == _redisPattern) return;
      setState(() => _redisPattern = pattern);
      _loadRedisKeys();
    });
  }

  void _resetRedisPattern() {
    _redisSearchController.clear();
    setState(() => _redisPattern = '*');
    _loadRedisKeys();
  }

  Future<void> _viewRedisKey(String key) async {
    final deleted = await showAppDialog<bool>(
      context,
      (ctx) => _RedisValueDialog(connection: _connection, keyName: key),
    );
    if (deleted == true && mounted) {
      _loadRedisKeys();
    }
  }

  Future<void> _addRedisKey() async {
    final saved = await showAppDialog<bool>(
      context,
      (ctx) => _RedisAddKeyDialog(connection: _connection),
    );
    if (saved == true && mounted) {
      _loadRedisKeys();
    }
  }

  Future<void> _deleteRedisKey(String key) async {
    final l = AppLocalizations.of(context);
    try {
      await _service.redisDelete(_connection, key);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_redisKeyDeleted(key))));
      _loadRedisKeys();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  // ---------- 用户管理 ----------

  Future<void> _loadUsers() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await _service.getUsers(_connection);
      if (!mounted) return;
      setState(() {
        _users = users;
        _usersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _usersError = e.toString();
        _usersLoading = false;
      });
    }
  }

  Future<void> _showCreateUserDialog() async {
    final l = AppLocalizations.of(context);
    final creds =
        await showAppDialog<({String username, String password, String host})>(
          context,
          (ctx) => _CreateUserDialog(connection: _connection),
        );
    if (creds == null || !mounted) return;
    try {
      await _service.createUser(
        _connection,
        username: creds.username,
        password: creds.password,
        host: creds.host,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_userCreated(creds.username))),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_createFailed(e.toString()))));
    }
  }

  Future<void> _confirmDropUser(DbUserInfo user) async {
    final l = AppLocalizations.of(context);
    final hostText = user.host == null ? '' : '@${user.host}';
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.dbDetail_dropUserTitle),
        content: Text(l.dbDetail_dropUserConfirm('${user.username}$hostText')),
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
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.dropUser(
        _connection,
        username: user.username,
        host: user.host,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_userDeleted(user.username))),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  // ---------- 用户管理对话框 ----------

  Future<void> _showUserManagementDialog() async {
    await showAppDialog<void>(
      context,
      (_) => _DbUserManagementDialog(connection: _connection),
    );
    _loadUsers(); // 对话框关闭后刷新顶部用户列表卡
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.dbDetail_title(_connection.name))),
      body: Column(
        children: [
          // 顶部：连接信息（左）与用户管理（右）对半分布
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildInfoCard()),
                const SizedBox(width: 8),
                Expanded(child: _buildUserCard()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isRedis ? _buildRedisView() : _buildRelationalView(),
          ),
        ],
      ),
    );
  }

  /// 顶部连接信息卡。
  Widget _buildInfoCard() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _typeIcon(_connection.type),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l.dbDetail_connectionInfo, style: theme.textTheme.titleMedium),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l.dbDetail_connected,
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(l.dbDetail_type, _connection.type.label),
            _infoRow(l.dbDetail_address, '${_connection.host}:${_connection.port}'),
            _infoRow(l.dbDetail_user, _connection.username ?? '-'),
            _infoRow(l.dbDetail_database, _connection.databaseName ?? l.dbDetail_none),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _testConnection,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.dbDetail_testConnection),
                ),
                if (!_isRedis) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _showSqlDialog,
                    icon: const Icon(Icons.terminal, size: 18),
                    label: Text(l.dbDetail_runSql),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _showUserManagementDialog,
                    icon: const Icon(Icons.manage_accounts, size: 18),
                    label: Text(l.dbDetail_userManagement),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// 顶部用户管理卡（与连接信息卡左右对半）。
  Widget _buildUserCard() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_accounts,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l.dbDetail_userManagement, style: theme.textTheme.titleMedium),
                const Spacer(),
                if (!_isRedis)
                  FilledButton.tonalIcon(
                    onPressed: _showCreateUserDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.dbDetail_newUser),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildUserList(theme),
          ],
        ),
      ),
    );
  }

  /// 用户管理卡内容：加载中 / 错误 / 空态 / 用户列表。
  Widget _buildUserList(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_isRedis) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l.dbDetail_redisNoUserManagement,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_usersLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_usersError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _usersError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: _loadUsers, child: Text(l.common_retry)),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l.dbDetail_noUsers,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              Icons.person_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              user.username,
              style: TextStyle(
                fontFamily: FontSettings.instance.terminalFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: user.host == null
                ? null
                : Text(
                    '@${user.host}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: FontSettings.instance.terminalFamily,
                    ),
                  ),
            trailing: IconButton(
              tooltip: l.common_delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDropUser(user),
            ),
          );
        },
      ),
    );
  }

  IconData _typeIcon(DbType type) {
    return switch (type) {
      DbType.mysql => Icons.dns,
      DbType.mariadb => Icons.storage,
      DbType.postgres => Icons.hub,
      DbType.redis => Icons.flash_on,
    };
  }

  /// 内容区错误提示。
  Widget _buildError(String message, {required VoidCallback onRetry}) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l.common_retry)),
          ],
        ),
      ),
    );
  }

  /// 关系型数据库三级浏览视图。
  Widget _buildRelationalView() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(_error!, onRetry: _retryCurrentLevel);
    }
    return switch (_level) {
      2 => _buildTableList(),
      3 => _buildDataBrowse(),
      _ => _buildDatabaseList(),
    };
  }

  Widget _buildDatabaseList() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(l.dbDetail_database, style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _showCreateDatabaseDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.dbDetail_newDatabase),
              ),
            ],
          ),
        ),
        Expanded(
          child: _databases.isEmpty
              ? Center(child: Text(l.dbDetail_noDatabases))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _databases.length,
                  itemBuilder: (context, index) {
                    final db = _databases[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.dns,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(db),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l.common_delete,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmDropDatabase(db),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => _selectDatabase(db),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTableList() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        _buildLevelHeader(title: l.dbDetail_databasePrefix(_selectedDb ?? '')),
        Expanded(
          child: _tables.isEmpty
              ? Center(child: Text(l.dbDetail_noTables))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _tables.length,
                  itemBuilder: (context, index) {
                    final table = _tables[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.table_chart,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(table),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _selectTable(table),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDataBrowse() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final maxPage = _totalRows == 0 ? 1 : ((_totalRows - 1) ~/ _pageSize) + 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(l.common_back),
              ),
              Expanded(
                child: Text(
                  l.dbDetail_tablePrefix(_selectedTable ?? ''),
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _showAddRowDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.dbDetail_addRow),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(
                    _totalRows == 0
                        ? l.dbDetail_noDataInTable
                        : l.dbDetail_noDataInPage,
                  ),
                )
              : _EditableTable(
                  rows: _rows,
                  columns: _columns,
                  onCellEdited: _onCellEdited,
                  onDeleteRow: (row) => _confirmDeleteRow(row),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l.dbDetail_prevPage,
                onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                l.dbDetail_pageInfo(_page, maxPage, _totalRows, _pageSize),
                style: theme.textTheme.bodySmall,
              ),
              IconButton(
                tooltip: l.dbDetail_nextPage,
                onPressed: _page < maxPage ? () => _goToPage(_page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 行级编辑 ----------

  Future<void> _onCellEdited(
    Map<String, dynamic> row,
    String column,
    String newValue,
  ) async {
    final l = AppLocalizations.of(context);
    final db = _selectedDb;
    final table = _selectedTable;
    if (db == null || table == null) return;
    try {
      final affected = await _service.updateRow(
        _connection,
        db,
        table,
        newValues: {column: newValue},
        whereRow: row,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            affected > 0 ? l.dbDetail_saved : l.dbDetail_noMatchingRow,
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      if (affected > 0) _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_saveFailed(e.toString()))));
    }
  }

  Future<void> _showAddRowDialog() async {
    final l = AppLocalizations.of(context);
    final values = await showAppDialog<Map<String, dynamic>>(
      context,
      (ctx) => _AddRowDialog(columns: _columns),
    );
    if (values == null || !mounted) return;
    final db = _selectedDb;
    final table = _selectedTable;
    if (db == null || table == null) return;
    try {
      await _service.insertRow(_connection, db, table, values);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_rowAdded)));
      _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_addFailed(e.toString()))));
    }
  }

  Future<void> _confirmDeleteRow(Map<String, dynamic> row) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.dbDetail_deleteRow),
        content: Text(l.dbDetail_deleteRowConfirm),
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
      ),
    );
    if (confirmed != true || !mounted) return;
    final db = _selectedDb;
    final table = _selectedTable;
    if (db == null || table == null) return;
    try {
      final affected = await _service.deleteRow(_connection, db, table, row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.dbDetail_rowsDeleted(affected))),
      );
      _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  /// 层级标题栏：返回按钮 + 当前层级标题。
  Widget _buildLevelHeader({required String title}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l.common_back),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Redis Key 列表视图。
  Widget _buildRedisView() {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(_error!, onRetry: _loadRedisKeys);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _redisPattern == '*' ? null : _resetRedisPattern,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(l.common_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _redisSearchController,
                  onChanged: _onRedisSearchChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: l.dbDetail_searchKeyPrefix,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: l.dbDetail_addRedisKey,
                onPressed: _addRedisKey,
              ),
            ],
          ),
        ),
        Expanded(
          child: _redisKeys.isEmpty
              ? Center(child: Text(l.dbDetail_noMatchingKeys))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _redisKeys.length,
                  itemBuilder: (context, index) =>
                      _buildRedisKeyItem(_redisKeys[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildRedisKeyItem(String key) {
    final l = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.key, color: Theme.of(context).colorScheme.primary),
        title: Text(
          key,
          style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: l.dbDetail_view,
              onPressed: () => _viewRedisKey(key),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.common_delete,
              onPressed: () => _deleteRedisKey(key),
            ),
          ],
        ),
      ),
    );
  }
}

/// 通用数据表（可双向滚动），供数据浏览与 SQL 结果共用。
/// 可编辑数据表格：点击单元格进入编辑，回车/失焦保存；行尾可删除。
class _EditableTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String>? columns;
  final void Function(Map<String, dynamic> row, String column, String newValue)
  onCellEdited;
  final void Function(Map<String, dynamic> row) onDeleteRow;

  const _EditableTable({
    required this.rows,
    this.columns,
    required this.onCellEdited,
    required this.onDeleteRow,
  });

  @override
  State<_EditableTable> createState() => _EditableTableState();
}

class _EditableTableState extends State<_EditableTable> {
  /// 当前正在编辑的单元格：(行索引, 列名)。
  (int, String)? _editing;

  /// 编辑中的输入控制器（仅编辑时创建）。
  TextEditingController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _startEdit(int rowIndex, String column, Object? value) {
    setState(() {
      _editing = (rowIndex, column);
      _controller?.dispose();
      _controller = TextEditingController(
        text: value == null ? '' : value.toString(),
      );
    });
  }

  void _finishEdit(bool commit) {
    final editing = _editing;
    final controller = _controller;
    if (editing == null || controller == null) return;
    final (rowIndex, column) = editing;
    final oldValue = widget.rows[rowIndex][column];
    final newText = controller.text;
    setState(() {
      _editing = null;
      _controller = null;
    });
    final isNull = oldValue == null;
    final changed = isNull
        ? newText.isNotEmpty
        : newText != oldValue.toString();
    if (commit && changed) {
      widget.onCellEdited(widget.rows[rowIndex], column, newText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (widget.rows.isEmpty) {
      return Center(child: Text(l.dbDetail_noData));
    }
    final cols = widget.columns ?? widget.rows.first.keys.toList();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            theme.colorScheme.surfaceContainerHighest,
          ),
          columns: [
            for (final c in cols)
              DataColumn(
                label: Text(
                  c,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            DataColumn(
              label: Text('', style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
          rows: [
            for (var i = 0; i < widget.rows.length && i < 100; i++)
              _buildRow(cols, i, widget.rows[i], theme),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(
    List<String> cols,
    int rowIndex,
    Map<String, dynamic> row,
    ThemeData theme,
  ) {
    final l = AppLocalizations.of(context);
    return DataRow(
      cells: [
        for (final c in cols)
          DataCell(
            _editing == (rowIndex, c) ? _buildEditor(c) : _buildCell(row[c]),
            onTap: () => _startEdit(rowIndex, c, row[c]),
          ),
        DataCell(
          IconButton(
            tooltip: l.dbDetail_deleteRow,
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () => widget.onDeleteRow(row),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(String column) {
    return TextField(
      controller: _controller,
      autofocus: true,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => _finishEdit(true),
      onTapOutside: (_) => _finishEdit(true),
    );
  }

  Widget _buildCell(Object? value) {
    if (value == null) {
      return const Text(
        'NULL',
        style: TextStyle(
          color: Colors.grey,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }
    var text = value.toString();
    if (text.length > 60) {
      text = '${text.substring(0, 60)}…';
    }
    return Text(
      text,
      style: const TextStyle(fontSize: 13),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 添加行对话框：为每列输入值（留空表示 NULL）。
class _AddRowDialog extends StatefulWidget {
  final List<String> columns;

  const _AddRowDialog({required this.columns});

  @override
  State<_AddRowDialog> createState() => _AddRowDialogState();
}

class _AddRowDialogState extends State<_AddRowDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final c in widget.columns) {
      _controllers[c] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop({
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dbDetail_addRow),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in widget.columns) ...[
                TextField(
                  controller: _controllers[c],
                  decoration: InputDecoration(
                    labelText: c,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.common_add)),
      ],
    );
  }
}

/// 只读数据表格（SQL 执行结果显示）。
class _SqlResultTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _SqlResultTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return Center(child: Text(l.dbDetail_noData));
    }
    final cols = rows.first.keys.toList();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            theme.colorScheme.surfaceContainerHighest,
          ),
          columns: [
            for (final c in cols)
              DataColumn(
                label: Text(
                  c,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [for (final c in cols) DataCell(_buildCell(row[c]))],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(Object? value) {
    if (value == null) {
      return const Text(
        'NULL',
        style: TextStyle(
          color: Colors.grey,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }
    var text = value.toString();
    if (text.length > 60) {
      text = '${text.substring(0, 60)}…';
    }
    return Text(
      text,
      style: const TextStyle(fontSize: 13),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 执行 SQL 对话框（仅关系型数据库）。
class _SqlDialog extends StatefulWidget {
  final DbConnectionInfo connection;
  final List<String> databases;
  final String? initialDatabase;

  const _SqlDialog({
    required this.connection,
    required this.databases,
    this.initialDatabase,
  });

  @override
  State<_SqlDialog> createState() => _SqlDialogState();
}

class _SqlDialogState extends State<_SqlDialog> {
  final RemoteDatabaseService _service = RemoteDatabaseService.instance;
  final TextEditingController _sqlController = TextEditingController();

  late String? _selectedDb;
  bool _running = false;
  List<Map<String, dynamic>> _resultRows = [];
  int? _affected;
  String? _error;
  String? _lastSql;

  bool get _canExecute =>
      !_running && _selectedDb != null && _sqlController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDb = widget.initialDatabase;
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    final db = _selectedDb;
    final sql = _sqlController.text.trim();
    if (db == null || sql.isEmpty || _running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await _service.executeQuery(widget.connection, db, sql);
      if (!mounted) return;
      setState(() {
        _resultRows = result.rows;
        _affected = result.affected;
        _lastSql = sql;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _resultRows = [];
        _affected = null;
        _lastSql = sql;
        _running = false;
      });
    }
  }

  /// 判断语句是否为查询类（返回行集）。
  bool _isQueryStatement(String sql) {
    final head = sql.trimLeft().toLowerCase();
    return head.startsWith('select') ||
        head.startsWith('show') ||
        head.startsWith('describe') ||
        head.startsWith('desc ') ||
        head.startsWith('explain') ||
        head.startsWith('with');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dbDetail_runSql),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _sqlController,
              maxLines: 6,
              style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'SELECT * FROM table_name WHERE ...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _buildDatabaseSelector(),
            const SizedBox(height: 12),
            Expanded(child: _buildResultArea()),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _running
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l.common_cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canExecute ? _execute : null,
                  child: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.dbDetail_execute),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseSelector() {
    final l = AppLocalizations.of(context);
    if (widget.databases.isEmpty) {
      return Text(
        l.dbDetail_noDatabases,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: _selectedDb,
      decoration: InputDecoration(
        labelText: l.dbDetail_database,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(l.dbDetail_selectDatabase)),
        for (final db in widget.databases)
          DropdownMenuItem<String?>(value: db, child: Text(db)),
      ],
      onChanged: _running ? null : (v) => _selectedDb = v,
    );
  }

  Widget _buildResultArea() {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    if (_running) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_lastSql == null) {
      return Center(
        child: Text(
          l.dbDetail_resultShownAfterRun,
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      );
    }
    if (_resultRows.isNotEmpty) {
      return _SqlResultTable(rows: _resultRows);
    }
    if (_isQueryStatement(_lastSql!)) {
      return Center(child: Text(l.dbDetail_queryNoRows));
    }
    return Center(child: Text(l.dbDetail_affectedRows(_affected ?? 0)));
  }
}

/// 查看 Redis Key 值的对话框。
class _RedisValueDialog extends StatefulWidget {
  final DbConnectionInfo connection;
  final String keyName;

  const _RedisValueDialog({required this.connection, required this.keyName});

  @override
  State<_RedisValueDialog> createState() => _RedisValueDialogState();
}

class _RedisValueDialogState extends State<_RedisValueDialog> {
  final RemoteDatabaseService _service = RemoteDatabaseService.instance;

  String? _value;
  String? _error;
  bool _loading = true;
  bool _deleting = false;

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
      final value = await _service.redisGet(widget.connection, widget.keyName);
      if (!mounted) return;
      setState(() {
        _value = value;
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

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    setState(() => _deleting = true);
    try {
      await _service.redisDelete(widget.connection, widget.keyName);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.keyName,
        style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(width: 480, height: 320, child: _buildContent(theme)),
      actions: [
        TextButton.icon(
          onPressed: _deleting ? null : _delete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.common_delete),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_close),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Text(
          _value ?? l.dbDetail_emptyValue,
          style: TextStyle(
            fontFamily: FontSettings.instance.terminalFamily,
            fontSize: 13,
            height: 1.5,
          ),
          maxLines: 20,
        ),
      ),
    );
  }
}

/// 添加 Redis Key 的对话框。
class _RedisAddKeyDialog extends StatefulWidget {
  final DbConnectionInfo connection;

  const _RedisAddKeyDialog({required this.connection});

  @override
  State<_RedisAddKeyDialog> createState() => _RedisAddKeyDialogState();
}

class _RedisAddKeyDialogState extends State<_RedisAddKeyDialog> {
  final RemoteDatabaseService _service = RemoteDatabaseService.instance;
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = l.dbDetail_keyRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.redisSet(widget.connection, key, _valueController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dbDetail_addRedisKey),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _keyController,
            autofocus: true,
            style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
            decoration: InputDecoration(
              labelText: l.dbDetail_keyName,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            maxLines: 3,
            style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
            decoration: InputDecoration(
              labelText: l.dbDetail_value,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
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

/// 新建用户对话框。
///
/// 输入用户名与密码；MySQL/MariaDB 额外可指定登录主机（默认 '%'）。
/// 确认后返回 (username, password, host)。
class _CreateUserDialog extends StatefulWidget {
  final DbConnectionInfo connection;

  const _CreateUserDialog({required this.connection});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _hostController = TextEditingController(text: '%');

  String? _error;

  bool get _isMysql =>
      widget.connection.type == DbType.mysql ||
      widget.connection.type == DbType.mariadb;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _isMysql ? _hostController.text.trim() : '%';
    if (username.isEmpty) {
      setState(() => _error = l.dbDetail_usernameRequired);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = l.dbDetail_passwordRequired);
      return;
    }
    if (host.isEmpty) {
      setState(() => _error = l.dbDetail_hostRequired);
      return;
    }
    Navigator.of(
      context,
    ).pop((username: username, password: password, host: host));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dbDetail_newUser),
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
                  labelText: l.dbDetail_username,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.dbDetail_password,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_isMysql) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _hostController,
                  style: TextStyle(fontFamily: FontSettings.instance.terminalFamily, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.dbDetail_loginHost,
                    hintText: l.dbDetail_loginHostHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.dbDetail_create)),
      ],
    );
  }
}

/// 新建数据库对话框。
///
/// 输入数据库名，凭据支持两种模式：
/// - 自动生成：随机生成该库专用用户名与强密码（可点击"重新生成"）
/// - 自定义：由用户填写用户名与密码
/// 确认后返回 (database, username, password)，由调用方执行建库。
class _CreateDatabaseDialog extends StatefulWidget {
  final DbType type;

  const _CreateDatabaseDialog({required this.type});

  @override
  State<_CreateDatabaseDialog> createState() => _CreateDatabaseDialogState();
}

class _CreateDatabaseDialogState extends State<_CreateDatabaseDialog> {
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  /// 凭据模式：true 自动生成，false 自定义。
  bool _autoGenerate = true;

  String _generatedUsername = '';
  String _generatedPassword = '';

  String? _databaseError;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _generate() {
    final name = _databaseController.text.trim();
    final creds = RemoteDatabaseService.generateCredentials(
      name.isEmpty ? 'db' : name,
    );
    setState(() {
      _generatedUsername = creds.username;
      _generatedPassword = creds.password;
    });
  }

  /// 只读字段（自动生成的凭据，支持复制）。
  Widget _readOnlyField(String label, String value, bool monospace) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          fontSize: 14,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final database = _databaseController.text.trim();
    if (database.isEmpty) {
      setState(() => _databaseError = l.dbDetail_databaseNameRequired);
      return;
    }
    final username = _autoGenerate
        ? _generatedUsername
        : _usernameController.text.trim();
    final password = _autoGenerate
        ? _generatedPassword
        : _passwordController.text;
    if (username.isEmpty) {
      setState(() => _databaseError = l.dbDetail_usernameRequired);
      return;
    }
    if (password.isEmpty) {
      setState(() => _databaseError = l.dbDetail_passwordRequired);
      return;
    }
    Navigator.of(
      context,
    ).pop((database: database, username: username, password: password));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.dbDetail_newDatabase),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _databaseController,
                autofocus: true,
                onChanged: (_) {
                  if (_autoGenerate) _generate();
                  setState(() => _databaseError = null);
                },
                decoration: InputDecoration(
                  labelText: l.dbDetail_databaseName,
                  hintText: widget.type == DbType.postgres
                      ? l.dbDetail_databaseNameHintPg
                      : l.dbDetail_databaseNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _databaseError,
                ),
              ),
              const SizedBox(height: 16),
              Text(l.dbDetail_databaseAccount, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(l.dbDetail_autoGenerate),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l.dbDetail_custom),
                  ),
                ],
                selected: {_autoGenerate},
                onSelectionChanged: (selection) {
                  setState(() {
                    _autoGenerate = selection.first;
                    if (_autoGenerate) _generate();
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_autoGenerate) ...[
                _readOnlyField(l.dbDetail_username, _generatedUsername, false),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _readOnlyField(l.dbDetail_password, _generatedPassword, true),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l.dbDetail_regenerate,
                      icon: const Icon(Icons.refresh),
                      onPressed: _generate,
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l.dbDetail_username,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l.dbDetail_password,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                l.dbDetail_databaseAccountNote,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
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
        FilledButton(onPressed: _submit, child: Text(l.dbDetail_create)),
      ],
    );
  }
}

/// 用户管理对话框。
///
/// 针对当前已连接的关系型数据库，展示用户列表，支持新建与删除用户。
class _DbUserManagementDialog extends StatefulWidget {
  final DbConnectionInfo connection;

  const _DbUserManagementDialog({required this.connection});

  @override
  State<_DbUserManagementDialog> createState() =>
      _DbUserManagementDialogState();
}

class _DbUserManagementDialogState extends State<_DbUserManagementDialog> {
  final RemoteDatabaseService _service = RemoteDatabaseService.instance;

  List<DbUserInfo> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _service.getUsers(widget.connection);
      if (!mounted) return;
      setState(() {
        _users = users;
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

  Future<void> _showCreateUserDialog() async {
    final l = AppLocalizations.of(context);
    final creds =
        await showAppDialog<({String username, String password, String host})>(
          context,
          (ctx) => _CreateUserDialog(connection: widget.connection),
        );
    if (creds == null || !mounted) return;
    try {
      await _service.createUser(
        widget.connection,
        username: creds.username,
        password: creds.password,
        host: creds.host,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_userCreated(creds.username))),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_createFailed(e.toString()))));
    }
  }

  Future<void> _confirmDropUser(DbUserInfo user) async {
    final l = AppLocalizations.of(context);
    final hostText = user.host == null ? '' : '@${user.host}';
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: Text(l.dbDetail_dropUserTitle),
        content: Text(l.dbDetail_dropUserConfirm('${user.username}$hostText')),
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
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.dropUser(
        widget.connection,
        username: user.username,
        host: user.host,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(l.dbDetail_userDeleted(user.username))),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dbDetail_deleteFailed(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Text(l.dbDetail_userManagement),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.dbDetail_newUser),
          ),
        ],
      ),
      content: SizedBox(width: 480, height: 360, child: _buildBody(theme)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.common_close),
        ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadUsers, child: Text(l.common_retry)),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          l.dbDetail_noUsers,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.person_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            user.username,
            style: TextStyle(
              fontFamily: FontSettings.instance.terminalFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: user.host == null
              ? null
              : Text(
                  '@${user.host}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: FontSettings.instance.terminalFamily,
                  ),
                ),
          trailing: IconButton(
            tooltip: l.common_delete,
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _confirmDropUser(user),
          ),
        );
      },
    );
  }
}
