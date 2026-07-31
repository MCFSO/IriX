// 数据库连接详情页面
// 关系型（MySQL/MariaDB/PostgreSQL）：数据库 → 表 → 数据 三级浏览，支持执行 SQL
// Redis：Key 前缀搜索、查看、添加与删除
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/db_page_settings.dart';
import '../services/remote_db_service.dart';
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

  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _loadInitial();
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
    try {
      if (_isRedis) {
        await _service.getRedisKeys(_connection, pattern: '*');
      } else {
        await _service.getDatabases(_connection);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('连接成功')));
      _refreshCurrent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接失败: $e')));
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
    final creds = await showAppDialog<
        ({String database, String username, String password})>(
      context,
      (ctx) => _CreateDatabaseDialog(
        type: _connection.type,
      ),
    );
    if (creds == null || !mounted) return;
    try {
      await _service.createDatabaseWithUser(
        _connection,
        database: creds.database,
        username: creds.username,
        password: creds.password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建数据库 ${creds.database}')),
      );
      _loadDatabases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _confirmDropDatabase(String database) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除数据库'),
        content: Text('确定要删除数据库 $database 吗？\n此操作不可恢复！'),
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
    if (confirmed != true || !mounted) return;
    try {
      await _service.dropDatabase(_connection, database);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除数据库 $database')));
      if (_selectedDb == database) {
        _selectedDb = null;
        _level = 1;
      }
      _loadDatabases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
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
    try {
      await _service.redisDelete(_connection, key);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 $key')));
      _loadRedisKeys();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${_connection.name} - 数据库')),
      body: Column(
        children: [
          _buildInfoCard(),
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
                    _typeIcon(_connection.type),
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('连接信息', style: theme.textTheme.titleMedium),
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
                  const Text(
                    '已连接',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow('类型', _connection.type.label),
              _infoRow('地址', '${_connection.host}:${_connection.port}'),
              _infoRow('用户', _connection.username ?? '-'),
              _infoRow('数据库', _connection.databaseName ?? '无'),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('测试连接'),
                  ),
                  if (!_isRedis) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _showSqlDialog,
                      icon: const Icon(Icons.terminal, size: 18),
                      label: const Text('执行 SQL'),
                    ),
                  ],
                ],
              ),
            ],
          ),
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
            FilledButton(onPressed: onRetry, child: const Text('重试')),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('数据库', style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _showCreateDatabaseDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建数据库'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _databases.isEmpty
              ? const Center(child: Text('未找到数据库'))
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
                              tooltip: '删除',
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
    return Column(
      children: [
        _buildLevelHeader(title: '数据库: ${_selectedDb ?? ''}'),
        Expanded(
          child: _tables.isEmpty
              ? const Center(child: Text('该数据库没有表'))
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
                label: const Text('返回'),
              ),
              Expanded(
                child: Text(
                  '表: ${_selectedTable ?? ''}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _showAddRowDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加行'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(_totalRows == 0 ? '该表没有数据' : '当前页无数据'),
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
                tooltip: '上一页',
                onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '第 $_page / $maxPage 页 · 共 $_totalRows 行 · 每页 $_pageSize 行',
                style: theme.textTheme.bodySmall,
              ),
              IconButton(
                tooltip: '下一页',
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
            affected > 0 ? '已保存' : '未找到匹配行，数据未修改',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      if (affected > 0) _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _showAddRowDialog() async {
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
      ).showSnackBar(const SnackBar(content: Text('已添加行')));
      _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加失败: $e')));
    }
  }

  Future<void> _confirmDeleteRow(Map<String, dynamic> row) async {
    final confirmed = await showAppDialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('删除行'),
        content: const Text('确定要删除这一行吗？此操作不可恢复！'),
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
    if (confirmed != true || !mounted) return;
    final db = _selectedDb;
    final table = _selectedTable;
    if (db == null || table == null) return;
    try {
      final affected = await _service.deleteRow(_connection, db, table, row);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 $affected 行')));
      _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  /// 层级标题栏：返回按钮 + 当前层级标题。
  Widget _buildLevelHeader({required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('返回'),
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
                label: const Text('返回'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _redisSearchController,
                  onChanged: _onRedisSearchChanged,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: '前缀搜索 Key',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '添加 Key',
                onPressed: _addRedisKey,
              ),
            ],
          ),
        ),
        Expanded(
          child: _redisKeys.isEmpty
              ? const Center(child: Text('没有匹配的 Key'))
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.key, color: Theme.of(context).colorScheme.primary),
        title: Text(
          key,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: '查看',
              onPressed: () => _viewRedisKey(key),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
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
    if (widget.rows.isEmpty) {
      return const Center(child: Text('无数据'));
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
              label: Text(
                '',
                style: TextStyle(
                  color: theme.colorScheme.error,
                ),
              ),
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

  DataRow _buildRow(List<String> cols, int rowIndex, Map<String, dynamic> row,
      ThemeData theme) {
    return DataRow(
      cells: [
        for (final c in cols)
          DataCell(
            _editing == (rowIndex, c) ? _buildEditor(c) : _buildCell(row[c]),
            onTap: () => _startEdit(rowIndex, c, row[c]),
          ),
        DataCell(
          IconButton(
            tooltip: '删除行',
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
    return AlertDialog(
      title: const Text('添加行'),
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
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
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
    if (rows.isEmpty) {
      return const Center(child: Text('无数据'));
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
                cells: [
                  for (final c in cols) DataCell(_buildCell(row[c])),
                ],
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
    return AlertDialog(
      title: const Text('执行 SQL'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _sqlController,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
                  child: const Text('取消'),
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
                      : const Text('执行'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseSelector() {
    if (widget.databases.isEmpty) {
      return Text(
        '未找到数据库',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: _selectedDb,
      decoration: const InputDecoration(
        labelText: '数据库',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('选择数据库')),
        for (final db in widget.databases)
          DropdownMenuItem<String?>(value: db, child: Text(db)),
      ],
      onChanged: _running ? null : (v) => _selectedDb = v,
    );
  }

  Widget _buildResultArea() {
    final theme = Theme.of(context);
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
          '执行后在此显示结果',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      );
    }
    if (_resultRows.isNotEmpty) {
      return _SqlResultTable(rows: _resultRows);
    }
    if (_isQueryStatement(_lastSql!)) {
      return const Center(child: Text('查询返回 0 行'));
    }
    return Center(child: Text('受影响行数: ${_affected ?? 0}'));
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
      ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.keyName,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(width: 480, height: 320, child: _buildContent(theme)),
      actions: [
        TextButton.icon(
          onPressed: _deleting ? null : _delete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('删除'),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
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
          _value ?? '(空)',
          style: const TextStyle(
            fontFamily: 'monospace',
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
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Key 不能为空');
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
    return AlertDialog(
      title: const Text('添加 Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _keyController,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Key 名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              labelText: '值',
              border: OutlineInputBorder(),
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
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    final database = _databaseController.text.trim();
    if (database.isEmpty) {
      setState(() => _databaseError = '请输入数据库名称');
      return;
    }
    final username =
        _autoGenerate ? _generatedUsername : _usernameController.text.trim();
    final password =
        _autoGenerate ? _generatedPassword : _passwordController.text;
    if (username.isEmpty) {
      setState(() => _databaseError = '请输入用户名');
      return;
    }
    if (password.isEmpty) {
      setState(() => _databaseError = '请输入密码');
      return;
    }
    Navigator.of(context).pop((
      database: database,
      username: username,
      password: password,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('新建数据库'),
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
                  labelText: '数据库名称',
                  hintText: widget.type == DbType.postgres
                      ? '小写字母/数字/下划线'
                      : '例如 minecraft',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _databaseError,
                ),
              ),
              const SizedBox(height: 16),
              Text('数据库专用账号', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.auto_awesome, size: 18),
                    label: Text('自动生成'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.edit_outlined, size: 18),
                    label: Text('自定义'),
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
                _readOnlyField('用户名', _generatedUsername, false),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _readOnlyField('密码', _generatedPassword, true),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '重新生成',
                      icon: const Icon(Icons.refresh),
                      onPressed: _generate,
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '将创建独立数据库并授予该账号全部权限',
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
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
