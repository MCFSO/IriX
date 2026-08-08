// 远程数据库连接管理服务
//
// 负责管理保存在本地 db_connections 表中的远程数据库连接信息，
// 并提供针对 MySQL / MariaDB / PostgreSQL / Redis 四种数据库的连接测试、
// 数据库/表浏览、数据查询与任意 SQL 执行能力。
//
// 所有数据库网络操作统一由 Rust 执行（xmc_db_client 动态库，经
// [DbClientFfi] 调用），Dart 侧不直接使用任何数据库客户端包。
// 连接方式为"即用即连、用完即关"，不维护长连接，简单可靠。
// 网络/认证类错误直接向上抛出，由 UI 层统一展示。

import 'dart:math';

import '../services/database_manager.dart';
import 'db_client_ffi.dart';

/// 支持的远程数据库类型
enum DbType {
  mysql,
  mariadb,
  postgres,
  redis;

  /// 显示名称
  String get label => switch (this) {
    DbType.mysql => 'MySQL',
    DbType.mariadb => 'MariaDB',
    DbType.postgres => 'PostgreSQL',
    DbType.redis => 'Redis',
  };

  /// 从字符串解析（表内存储值），未知值回退到 MySQL
  static DbType fromString(String s) => switch (s) {
    'mysql' => DbType.mysql,
    'mariadb' => DbType.mariadb,
    'postgres' => DbType.postgres,
    'redis' => DbType.redis,
    _ => DbType.mysql,
  };

  /// 默认端口
  int get defaultPort => switch (this) {
    DbType.mysql => 3306,
    DbType.mariadb => 3306,
    DbType.postgres => 5432,
    DbType.redis => 6379,
  };
}

/// 一条远程数据库连接配置
class DbConnectionInfo {
  final String id;
  String name;
  DbType type;
  String host;
  int port;
  String? username;
  String? password;
  String? databaseName;
  final DateTime createdAt;

  DbConnectionInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    this.port = 3306,
    this.username,
    this.password,
    this.databaseName,
    required this.createdAt,
  });

  /// 从 db_connections 表行（snake_case）转换
  static DbConnectionInfo fromDbRow(Map<String, dynamic> row) {
    return DbConnectionInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      type: DbType.fromString(row['type'] as String),
      host: row['host'] as String,
      port: (row['port'] as int?) ?? 3306,
      username: row['username'] as String?,
      password: row['password'] as String?,
      databaseName: row['database_name'] as String?,
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// 转换为 snake_case 表行
  Map<String, dynamic> toDbRow() => {
    'id': id,
    'name': name,
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'database_name': databaseName,
    'created_at': createdAt.toIso8601String(),
  };
}

/// 一条数据库用户信息
class DbUserInfo {
  final String username;

  /// 登录主机（MySQL/MariaDB 才有，如 '%' / 'localhost'）。
  final String? host;

  const DbUserInfo({required this.username, this.host});
}

/// 远程数据库操作服务（单例）
class RemoteDatabaseService {
  static final RemoteDatabaseService instance = RemoteDatabaseService._();
  RemoteDatabaseService._();

  // === 连接配置的本地持久化 ===

  /// 读取所有已保存的远程数据库连接
  Future<List<DbConnectionInfo>> getAllConnections() async {
    final rows = await DatabaseManager.instance.getAllDbConnections();
    return rows.map(DbConnectionInfo.fromDbRow).toList();
  }

  /// 保存（新增或覆盖）一条连接
  Future<void> saveConnection(DbConnectionInfo conn) async {
    await DatabaseManager.instance.insertDbConnection(conn.toDbRow());
  }

  /// 删除指定 id 的连接
  Future<void> deleteConnection(String id) async {
    await DatabaseManager.instance.deleteDbConnection(id);
  }

  // === 内部：统一 FFI 调用 ===

  /// 调用 Rust 数据库客户端（xmc_db_client）。
  /// 连接信息固定取 [info]，操作参数见各方法。
  Future<Map<String, dynamic>> _call(
    DbConnectionInfo info,
    String op,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 120),
  }) {
    return DbClientFfi.instance.request(
      dbType: info.type.name,
      host: info.host,
      port: info.port,
      username: info.username,
      password: info.password,
      database: info.databaseName,
      op: op,
      args: args,
      timeout: timeout,
    );
  }

  // === 连接测试 ===

  /// 测试连接是否可用。成功返回 null，失败返回错误消息。
  Future<String?> testConnection(DbConnectionInfo info) async {
    try {
      await _call(info, 'test_connection', const {});
      return null;
    } catch (e) {
      final msg = e.toString();
      return msg.replaceFirst('DbClientFfiException: ', '');
    }
  }

  // === 数据库 / 表浏览 ===

  /// 获取数据库/命名空间列表。MySQL/PG 返回数据库名列表，Redis 返回 ['default']。
  Future<List<String>> getDatabases(DbConnectionInfo info) async {
    final result = await _call(info, 'get_databases', const {});
    return [
      for (final name in (result['databases'] as List? ?? const []))
        name.toString(),
    ];
  }

  /// 获取指定数据库中的表列表。Redis 不支持，返回空列表（UI 层判断）。
  Future<List<String>> getTables(DbConnectionInfo info, String database) async {
    final result = await _call(
      info,
      'get_tables',
      {'database': database},
    );
    return [
      for (final name in (result['tables'] as List? ?? const [])) name.toString(),
    ];
  }

  // === 数据查询 ===

  /// 查询表中第 [offset] 行起的 [limit] 行数据（默认 100 行，offset 默认 0）。
  /// 返回 [{column: value, ...}, ...]。
  Future<List<Map<String, dynamic>>> queryTable(
    DbConnectionInfo info,
    String database,
    String table, {
    int limit = 100,
    int offset = 0,
  }) async {
    final result = await _call(
      info,
      'query_table',
      {'database': database, 'table': table, 'limit': limit, 'offset': offset},
    );
    return [
      for (final row in (result['rows'] as List? ?? const []))
        Map<String, dynamic>.from(row as Map),
    ];
  }

  /// 统计表中的总行数（用于分页）。
  Future<int> countRows(
    DbConnectionInfo info,
    String database,
    String table,
  ) async {
    final result = await _call(
      info,
      'count_rows',
      {'database': database, 'table': table},
    );
    return (result['count'] as num?)?.toInt() ?? 0;
  }

  /// 执行任意 SQL 并返回结果。SELECT 返回行列表，其他返回消息。错误抛异常。
  Future<({List<Map<String, dynamic>> rows, int affected})> executeQuery(
    DbConnectionInfo info,
    String database,
    String sql,
  ) async {
    if (info.type == DbType.redis) {
      throw UnsupportedError('Redis 不支持 SQL，请使用 Redis 专用操作');
    }
    final trimmed = sql.trimLeft().toUpperCase();
    final isQuery =
        trimmed.startsWith('SELECT') ||
        trimmed.startsWith('SHOW') ||
        trimmed.startsWith('WITH') ||
        trimmed.startsWith('DESC') ||
        trimmed.startsWith('DESCRIBE') ||
        trimmed.startsWith('EXPLAIN');

    final result = await _call(
      info,
      'execute',
      {'database': database, 'sql': sql, 'is_query': isQuery},
    );
    final affected = (result['affected'] as num?)?.toInt() ?? 0;
    if (!isQuery) {
      return (
        rows: [
          {'message': '执行成功，影响 $affected 行'},
        ],
        affected: affected,
      );
    }
    return (
      rows: [
        for (final row in (result['rows'] as List? ?? const []))
          Map<String, dynamic>.from(row as Map),
      ],
      affected: affected,
    );
  }

  // === Redis 专用操作 ===

  /// 按模式获取键列表，默认 '*'。
  Future<List<String>> getRedisKeys(
    DbConnectionInfo info, {
    String pattern = '*',
  }) async {
    final result = await _call(info, 'redis_keys', {'pattern': pattern});
    return [
      for (final key in (result['keys'] as List? ?? const [])) key.toString(),
    ];
  }

  /// 读取指定键的值（不存在返回 null）。
  Future<String?> redisGet(DbConnectionInfo info, String key) async {
    final result = await _call(info, 'redis_get', {'key': key});
    return result['value'] as String?;
  }

  /// 设置指定键的值。
  Future<void> redisSet(DbConnectionInfo info, String key, String value) async {
    await _call(info, 'redis_set', {'key': key, 'value': value});
  }

  /// 删除指定键。
  Future<void> redisDelete(DbConnectionInfo info, String key) async {
    await _call(info, 'redis_delete', {'key': key});
  }

  // === 数据库管理 ===

  /// 生成随机数据库专用账号：用户名含库名前缀 + 4 位随机，密码 16 位强字符。
  static ({String username, String password}) generateCredentials(
    String databaseName,
  ) {
    final rand = Random.secure();
    const letterDigits = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const strong =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        'abcdefghijklmnopqrstuvwxyz0123456789!@#%^&*-_';

    final base = databaseName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    final safeBase = base.isEmpty
        ? 'db'
        : base.substring(0, base.length > 12 ? 12 : base.length);

    String randomSuffix(int n) => String.fromCharCodes(
      List.generate(
        n,
        (_) => letterDigits.codeUnitAt(rand.nextInt(letterDigits.length)),
      ),
    );

    final username = 'user_${safeBase}_${randomSuffix(4)}';
    final password = String.fromCharCodes(
      List.generate(16, (_) => strong.codeUnitAt(rand.nextInt(strong.length))),
    );
    return (username: username, password: password);
  }

  /// 新建数据库并创建该库专用账号：CREATE DATABASE + CREATE USER + GRANT。
  ///
  /// MySQL/MariaDB 账号允许任意主机登录（'%'）；PostgreSQL 授予库级全部权限。
  /// 任一步失败会抛出异常（部分语句可能已执行，需人工检查）。
  Future<void> createDatabaseWithUser(
    DbConnectionInfo info, {
    required String database,
    required String username,
    required String password,
  }) async {
    await _call(
      info,
      'create_database_with_user',
      {'database': database, 'username': username, 'password': password},
    );
  }

  /// 删除数据库（DROP DATABASE）。Redis 不支持。
  Future<void> dropDatabase(DbConnectionInfo info, String database) async {
    await _call(info, 'drop_database', {'database': database});
  }

  // === 用户管理 ===

  /// 获取数据库用户列表（仅关系型）。Redis 不支持，返回空列表。
  Future<List<DbUserInfo>> getUsers(DbConnectionInfo info) async {
    final result = await _call(info, 'get_users', const {});
    return [
      for (final user in (result['users'] as List? ?? const []))
        DbUserInfo(
          username: ((user as Map)['username'] ?? '').toString(),
          host: (user['host'] as String?)?.isNotEmpty == true
              ? user['host'] as String
              : null,
        ),
    ];
  }

  /// 新建数据库用户。
  ///
  /// MySQL/MariaDB 可指定登录主机（默认 '%' 允许任意主机）。
  /// PostgreSQL 直接创建可登录角色。
  Future<void> createUser(
    DbConnectionInfo info, {
    required String username,
    required String password,
    String host = '%',
  }) async {
    await _call(
      info,
      'create_user',
      {'username': username, 'password': password, 'host': host},
    );
  }

  /// 删除数据库用户。MySQL/MariaDB 需指定登录主机（默认 '%'）。
  Future<void> dropUser(
    DbConnectionInfo info, {
    required String username,
    String? host,
  }) async {
    await _call(
      info,
      'drop_user',
      {'username': username, 'host': host ?? '%'},
    );
  }

  // === 行级数据编辑 ===

  /// 获取表的主键列名列表（无主键返回空列表）。
  Future<List<String>> getPrimaryKeys(
    DbConnectionInfo info,
    String database,
    String table,
  ) async {
    final result = await _call(
      info,
      'get_primary_keys',
      {'database': database, 'table': table},
    );
    return [
      for (final key in (result['keys'] as List? ?? const [])) key.toString(),
    ];
  }

  /// 更新一行数据：UPDATE 以主键定位（无主键则用整行旧值匹配）。
  ///
  /// [newValues] 仅包含被修改的列；空字符串视为 NULL。
  /// 返回受影响行数。
  Future<int> updateRow(
    DbConnectionInfo info,
    String database,
    String table, {
    required Map<String, dynamic> newValues,
    required Map<String, dynamic> whereRow,
  }) async {
    final pks = await getPrimaryKeys(info, database, table);
    return _updateRowWithWhere(
      info,
      database,
      table,
      newValues: newValues,
      whereRow: whereRow,
      whereCols: pks.isNotEmpty
          ? pks
          : whereRow.keys.where((k) => k != 'rowKey').toList(),
    );
  }

  /// 以指定列（通常为主键）定位更新一行。列值取自 FFI 提供的数据。
  Future<int> _updateRowWithWhere(
    DbConnectionInfo info,
    String database,
    String table, {
    required Map<String, dynamic> newValues,
    required Map<String, dynamic> whereRow,
    required List<String> whereCols,
  }) async {
    if (whereCols.isEmpty) {
      throw StateError('无法定位数据行（表为空 WHERE）');
    }
    final whereMap = <String, dynamic>{
      for (final col in whereCols) if (whereRow.containsKey(col)) col: whereRow[col],
    };
    final result = await _call(
      info,
      'update_row',
      {
        'database': database,
        'table': table,
        'new_values': newValues,
        'where_row': whereMap,
      },
    );
    return (result['affected'] as num?)?.toInt() ?? 0;
  }

  /// 插入一行：INSERT 全部列。空字符串视为 NULL。
  Future<void> insertRow(
    DbConnectionInfo info,
    String database,
    String table,
    Map<String, dynamic> values,
  ) async {
    await _call(
      info,
      'insert_row',
      {'database': database, 'table': table, 'values': values},
    );
  }

  /// 删除一行：以主键定位（无主键则用整行旧值匹配）。返回受影响行数。
  Future<int> deleteRow(
    DbConnectionInfo info,
    String database,
    String table,
    Map<String, dynamic> whereRow,
  ) async {
    final pks = await getPrimaryKeys(info, database, table);
    final whereCols = pks.isNotEmpty
        ? pks
        : whereRow.keys.where((k) => k != 'rowKey').toList();
    if (whereCols.isEmpty) {
      throw StateError('无法定位数据行（表为空 WHERE）');
    }
    final whereMap = <String, dynamic>{
      for (final col in whereCols)
        if (whereRow.containsKey(col)) col: whereRow[col],
    };
    final result = await _call(
      info,
      'delete_row',
      {'database': database, 'table': table, 'where_row': whereMap},
    );
    return (result['affected'] as num?)?.toInt() ?? 0;
  }
}