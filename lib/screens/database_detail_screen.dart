// 数据库连接详情页面
// 关系型（MySQL/MariaDB/PostgreSQL）：数据库 → 表 → 数据 三级浏览，支持执行 SQL
// Redis：Key 前缀搜索、查看、添加与删除
import 'dart:async';

import 'package:flutter/material.dart';

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
      final rows = await _service.queryTable(
        _connection,
        db,
        table,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _columns = rows.isNotEmpty ? rows.first.keys.toList() : [];
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
    if (_databases.isEmpty) {
      return const Center(child: Text('未找到数据库'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _databases.length,
      itemBuilder: (context, index) {
        final db = _databases[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Icon(Icons.dns, color: theme.colorScheme.primary),
            title: Text(db),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectDatabase(db),
          ),
        );
      },
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
    return Column(
      children: [
        _buildLevelHeader(title: '表: ${_selectedTable ?? ''}'),
        if (_rows.length >= 100)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange[300],
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '表数据较多，仅显示前 100 行',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: _rows.isEmpty
              ? const Center(child: Text('该表没有数据'))
              : _ResultTable(rows: _rows, columns: _columns),
        ),
      ],
    );
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
class _ResultTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<String>? columns;

  const _ResultTable({required this.rows, this.columns});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('无数据'));
    }
    final cols = columns ?? rows.first.keys.toList();
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
          ],
          rows: [
            for (final row in rows.take(100))
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
      return _ResultTable(rows: _resultRows);
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
