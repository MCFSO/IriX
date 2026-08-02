// 远程数据库连接管理服务
//
// 负责管理保存在本地 db_connections 表中的远程数据库连接信息，
// 并提供针对 MySQL / MariaDB / PostgreSQL / Redis 四种数据库的连接测试、
// 数据库/表浏览、数据查询与任意 SQL 执行能力。
//
// 所有网络操作均为"即用即连、用完即关"，不维护长连接，简单可靠。
// 网络/认证类错误直接向上抛出，由 UI 层统一展示。
//
// 注意：mysql_dart 包的连接默认走 TLS，本地/内网服务器需传 secure: false；
//       redis 包 4.x 无 RedisClient，使用 RedisConnection().connect(host, port)
//       返回 Command，认证通过 AUTH 命令完成，keys/del 通过 send_object 发送。

import 'dart:math';

import 'package:mysql_dart/mysql_client.dart' as mysql;
import 'package:postgres/postgres.dart' as pg;
import 'package:redis/redis.dart';

import '../services/database_manager.dart';

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

  // === 连接测试 ===

  /// 测试连接是否可用。成功返回 null，失败返回错误消息。
  Future<String?> testConnection(DbConnectionInfo info) async {
    try {
      switch (info.type) {
        case DbType.mysql:
        case DbType.mariadb:
          final conn = await _connectMysql(info);
          await conn.close();
          return null;
        case DbType.postgres:
          final conn = await _connectPostgres(info);
          await conn.close();
          return null;
        case DbType.redis:
          final cmd = await _redisConnect(info);
          try {
            final pong = await cmd.send_object(['PING']);
            if (pong != 'PONG') {
              return 'PING 响应异常: $pong';
            }
            return null;
          } finally {
            await cmd.get_connection().close();
          }
      }
    } catch (e) {
      return e.toString();
    }
  }

  // === 数据库 / 表浏览 ===

  /// 获取数据库/命名空间列表。MySQL/PG 返回数据库名列表，Redis 返回 ['default']。
  Future<List<String>> getDatabases(DbConnectionInfo info) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          final results = await conn.execute('SHOW DATABASES');
          return [
            for (final row in results.rows) (row.colAt(0) ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          final result = await conn.execute(
            'SELECT datname FROM pg_database WHERE datistemplate = false '
            'ORDER BY datname',
          );
          return [
            for (final row in result)
              (row.toColumnMap().values.firstOrNull ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.redis:
        return const ['default'];
    }
  }

  /// 获取指定数据库中的表列表。Redis 不支持，返回空列表（UI 层判断）。
  Future<List<String>> getTables(DbConnectionInfo info, String database) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final results = await conn.execute('SHOW TABLES');
          return [
            for (final row in results.rows) (row.colAt(0) ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final result = await conn.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public' "
            'ORDER BY tablename',
          );
          return [
            for (final row in result)
              (row.toColumnMap().values.firstOrNull ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.redis:
        return const [];
    }
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
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final sql =
              'SELECT * FROM `${_escMysqlIdent(table)}` '
              'LIMIT ? OFFSET ?';
          final results = await conn.execute(sql, [limit, offset]);
          return [
            for (final row in results.rows)
              Map<String, dynamic>.from(row.assoc()),
          ];
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final result = await conn.execute(
            'SELECT * FROM "${_escPgIdent(table)}" '
            'LIMIT @limit OFFSET @offset',
            parameters: {'limit': limit, 'offset': offset},
          );
          return [
            for (final row in result)
              Map<String, dynamic>.from(row.toColumnMap()),
          ];
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持表查询');
    }
  }

  /// 统计表中的总行数（用于分页）。
  Future<int> countRows(
    DbConnectionInfo info,
    String database,
    String table,
  ) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final results = await conn.execute(
            'SELECT COUNT(*) AS c FROM `${_escMysqlIdent(table)}`',
          );
          if (results.rows.isEmpty) return 0;
          return int.tryParse(results.rows.first.colAt(0) ?? '0') ?? 0;
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final result = await conn.execute(
            'SELECT COUNT(*) AS c FROM "${_escPgIdent(table)}"',
          );
          if (result.isEmpty) return 0;
          final v = result.first.toColumnMap().values.first;
          return v is int ? v : int.tryParse(v.toString()) ?? 0;
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持表查询');
    }
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

    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final results = await conn.execute(sql);
          final affected = results.affectedRows.toInt();
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
              for (final row in results.rows)
                Map<String, dynamic>.from(row.assoc()),
            ],
            affected: affected,
          );
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final result = await conn.execute(sql);
          final affected = result.affectedRows;
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
              for (final row in result)
                Map<String, dynamic>.from(row.toColumnMap()),
            ],
            affected: affected,
          );
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持 SQL');
    }
  }

  // === Redis 专用操作 ===

  /// 按模式获取键列表，默认 '*'。
  Future<List<String>> getRedisKeys(
    DbConnectionInfo info, {
    String pattern = '*',
  }) async {
    final cmd = await _redisConnect(info);
    try {
      final resp = await cmd.send_object(['KEYS', pattern]);
      if (resp is! List) return const [];
      return resp.map((e) => e.toString()).toList();
    } finally {
      await cmd.get_connection().close();
    }
  }

  /// 读取指定键的值（不存在返回 null）。
  Future<String?> redisGet(DbConnectionInfo info, String key) async {
    final cmd = await _redisConnect(info);
    try {
      final value = await cmd.get(key);
      return value?.toString();
    } finally {
      await cmd.get_connection().close();
    }
  }

  /// 设置指定键的值。
  Future<void> redisSet(DbConnectionInfo info, String key, String value) async {
    final cmd = await _redisConnect(info);
    try {
      await cmd.set(key, value);
    } finally {
      await cmd.get_connection().close();
    }
  }

  /// 删除指定键。
  Future<void> redisDelete(DbConnectionInfo info, String key) async {
    final cmd = await _redisConnect(info);
    try {
      await cmd.send_object(['DEL', key]);
    } finally {
      await cmd.get_connection().close();
    }
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
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          final dbName = _escMysqlIdent(database);
          final user = _escMysqlIdent(username);
          final pwd = _escMysqlStr(password);
          await conn.execute(
            'CREATE DATABASE `$dbName` '
            'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
          );
          await conn.execute("CREATE USER '$user'@'%' IDENTIFIED BY '$pwd'");
          await conn.execute(
            "GRANT ALL PRIVILEGES ON `$dbName`.* TO '$user'@'%'",
          );
          await conn.execute('FLUSH PRIVILEGES');
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          final dbName = _escPgIdent(database);
          final user = _escPgIdent(username);
          final pwd = _escPgStr(password);
          await conn.execute('CREATE DATABASE "$dbName"');
          await conn.execute('CREATE USER "$user" WITH PASSWORD \'$pwd\'');
          await conn.execute(
            'GRANT ALL PRIVILEGES ON DATABASE "$dbName" TO "$user"',
          );
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持创建数据库');
    }
  }

  /// 删除数据库（DROP DATABASE）。Redis 不支持。
  Future<void> dropDatabase(DbConnectionInfo info, String database) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          await conn.execute('DROP DATABASE `${_escMysqlIdent(database)}`');
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          await conn.execute('DROP DATABASE "${_escPgIdent(database)}"');
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持删除数据库');
    }
  }

  // === 用户管理 ===

  /// 获取数据库用户列表（仅关系型）。Redis 不支持，返回空列表。
  Future<List<DbUserInfo>> getUsers(DbConnectionInfo info) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          final results = await conn.execute(
            'SELECT User, Host FROM mysql.user ORDER BY User',
          );
          return [
            for (final row in results.rows)
              DbUserInfo(
                username: (row.colAt(0) ?? '').toString(),
                host: (row.colAt(1) ?? '').toString(),
              ),
          ];
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          final result = await conn.execute(
            'SELECT usename FROM pg_user ORDER BY usename',
          );
          return [
            for (final row in result)
              DbUserInfo(
                username: (row.toColumnMap().values.firstOrNull ?? '')
                    .toString(),
              ),
          ];
        } finally {
          await conn.close();
        }
      case DbType.redis:
        return const [];
    }
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
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          final user = _escMysqlIdent(username);
          final pwd = _escMysqlStr(password);
          final h = _escMysqlStr(host);
          await conn.execute("CREATE USER '$user'@'$h' IDENTIFIED BY '$pwd'");
          await conn.execute('FLUSH PRIVILEGES');
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          final user = _escPgIdent(username);
          final pwd = _escPgStr(password);
          await conn.execute('CREATE USER "$user" WITH PASSWORD \'$pwd\'');
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持用户管理');
    }
  }

  /// 删除数据库用户。MySQL/MariaDB 需指定登录主机（默认 '%'）。
  Future<void> dropUser(
    DbConnectionInfo info, {
    required String username,
    String? host,
  }) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info);
        try {
          final user = _escMysqlIdent(username);
          final h = _escMysqlStr(host ?? '%');
          await conn.execute("DROP USER '$user'@'$h'");
          await conn.execute('FLUSH PRIVILEGES');
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info);
        try {
          final user = _escPgIdent(username);
          await conn.execute('DROP USER "$user"');
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持用户管理');
    }
  }

  // === 行级数据编辑 ===

  /// 获取表的主键列名列表（无主键返回空列表）。
  Future<List<String>> getPrimaryKeys(
    DbConnectionInfo info,
    String database,
    String table,
  ) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final sql =
              "SELECT kcu.column_name FROM information_schema.table_constraints tc "
              "JOIN information_schema.key_column_usage kcu "
              "  ON tc.constraint_name = kcu.constraint_name "
              " AND tc.table_schema = kcu.table_schema "
              "WHERE tc.constraint_type = 'PRIMARY KEY' "
              "  AND tc.table_schema = DATABASE() "
              "  AND tc.table_name = '${_escMysqlStr(table)}' "
              "ORDER BY kcu.ordinal_position";
          final results = await conn.execute(sql);
          return [
            for (final row in results.rows) (row.colAt(0) ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final sql =
              "SELECT kcu.column_name FROM information_schema.table_constraints tc "
              "JOIN information_schema.key_column_usage kcu "
              "  ON tc.constraint_name = kcu.constraint_name "
              " AND tc.table_schema = kcu.table_schema "
              "WHERE tc.constraint_type = 'PRIMARY KEY' "
              "  AND tc.table_schema = 'public' "
              "  AND tc.table_name = '${_escPgStr(table)}' "
              "ORDER BY kcu.ordinal_position";
          final result = await conn.execute(sql);
          return [
            for (final row in result)
              (row.toColumnMap().values.firstOrNull ?? '').toString(),
          ];
        } finally {
          await conn.close();
        }
      case DbType.redis:
        return const [];
    }
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
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final pks = await getPrimaryKeys(info, database, table);
          final whereCols = pks.isNotEmpty
              ? pks
              : whereRow.keys.where((k) => k != 'rowKey').toList();
          final setClause = newValues.entries
              .map(
                (e) => '`${_escMysqlIdent(e.key)}` = ${_mysqlValue(e.value)}',
              )
              .join(', ');
          final whereClause = whereCols
              .map(
                (k) => '`${_escMysqlIdent(k)}` = ${_mysqlValue(whereRow[k])}',
              )
              .join(' AND ');
          if (whereClause.isEmpty) {
            throw StateError('无法定位数据行（表为空 WHERE）');
          }
          final results = await conn.execute(
            'UPDATE `${_escMysqlIdent(table)}` SET $setClause WHERE $whereClause',
          );
          return results.affectedRows.toInt();
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final pks = await getPrimaryKeys(info, database, table);
          final whereCols = pks.isNotEmpty
              ? pks
              : whereRow.keys.where((k) => k != 'rowKey').toList();
          final setClause = newValues.entries
              .map((e) => '"${_escPgIdent(e.key)}" = ${_pgValue(e.value)}')
              .join(', ');
          final whereClause = whereCols
              .map((k) => '"${_escPgIdent(k)}" = ${_pgValue(whereRow[k])}')
              .join(' AND ');
          if (whereClause.isEmpty) {
            throw StateError('无法定位数据行（表为空 WHERE）');
          }
          final result = await conn.execute(
            'UPDATE "${_escPgIdent(table)}" SET $setClause WHERE $whereClause',
          );
          return result.affectedRows;
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持表编辑');
    }
  }

  /// 插入一行：INSERT 全部列。空字符串视为 NULL。
  Future<void> insertRow(
    DbConnectionInfo info,
    String database,
    String table,
    Map<String, dynamic> values,
  ) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final cols = values.keys.map(_escMysqlIdent).toList();
          final vals = values.values.map(_mysqlValue).toList();
          await conn.execute(
            'INSERT INTO `${_escMysqlIdent(table)}` '
            '(${cols.map((c) => '`$c`').join(', ')}) VALUES (${vals.join(', ')})',
          );
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final cols = values.keys.map(_escPgIdent).toList();
          final vals = values.values.map(_pgValue).toList();
          await conn.execute(
            'INSERT INTO "${_escPgIdent(table)}" '
            '(${cols.map((c) => '"$c"').join(', ')}) VALUES (${vals.join(', ')})',
          );
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持表编辑');
    }
  }

  /// 删除一行：以主键定位（无主键则用整行旧值匹配）。返回受影响行数。
  Future<int> deleteRow(
    DbConnectionInfo info,
    String database,
    String table,
    Map<String, dynamic> whereRow,
  ) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final pks = await getPrimaryKeys(info, database, table);
          final whereCols = pks.isNotEmpty
              ? pks
              : whereRow.keys.where((k) => k != 'rowKey').toList();
          final whereClause = whereCols
              .map(
                (k) => '`${_escMysqlIdent(k)}` = ${_mysqlValue(whereRow[k])}',
              )
              .join(' AND ');
          if (whereClause.isEmpty) {
            throw StateError('无法定位数据行（表为空 WHERE）');
          }
          final results = await conn.execute(
            'DELETE FROM `${_escMysqlIdent(table)}` WHERE $whereClause',
          );
          return results.affectedRows.toInt();
        } finally {
          await conn.close();
        }
      case DbType.postgres:
        final conn = await _connectPostgres(info, database: database);
        try {
          final pks = await getPrimaryKeys(info, database, table);
          final whereCols = pks.isNotEmpty
              ? pks
              : whereRow.keys.where((k) => k != 'rowKey').toList();
          final whereClause = whereCols
              .map((k) => '"${_escPgIdent(k)}" = ${_pgValue(whereRow[k])}')
              .join(' AND ');
          if (whereClause.isEmpty) {
            throw StateError('无法定位数据行（表为空 WHERE）');
          }
          final result = await conn.execute(
            'DELETE FROM "${_escPgIdent(table)}" WHERE $whereClause',
          );
          return result.affectedRows;
        } finally {
          await conn.close();
        }
      case DbType.redis:
        throw UnsupportedError('Redis 不支持表编辑');
    }
  }

  // === 内部工具 ===

  /// 空字符串密码/用户名归一化为 null
  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

  /// MySQL 标识符转义（反引号内的反引号翻倍）
  static String _escMysqlIdent(String ident) => ident.replaceAll('`', '``');

  /// MySQL 字符串字面量转义（反斜杠与单引号）
  static String _escMysqlStr(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "''");

  /// PostgreSQL 标识符转义（双引号内的双引号翻倍）
  static String _escPgIdent(String ident) => ident.replaceAll('"', '""');

  /// PostgreSQL 字符串字面量转义（单引号翻倍）
  static String _escPgStr(String s) => s.replaceAll("'", "''");

  /// MySQL 值序列化：null → NULL，空字符串 → NULL，其余转义为字符串字面量
  static String _mysqlValue(Object? v) {
    if (v == null) return 'NULL';
    final s = v.toString();
    if (s.isEmpty) return 'NULL';
    return "'${_escMysqlStr(s)}'";
  }

  /// PostgreSQL 值序列化：null → NULL，空字符串 → NULL，其余转义为字符串字面量
  static String _pgValue(Object? v) {
    if (v == null) return 'NULL';
    final s = v.toString();
    if (s.isEmpty) return 'NULL';
    return "'${_escPgStr(s)}'";
  }

  static Future<mysql.MySQLConnection> _connectMysql(
    DbConnectionInfo info, {
    String? database,
  }) async {
    final conn = await mysql.MySQLConnection.createConnection(
      host: info.host,
      port: info.port,
      userName: info.username ?? 'root',
      password: info.password ?? '',
      databaseName: database ?? info.databaseName,
      secure: false,
      // MySQL 8+ 默认 caching_sha2_password，非 TLS 连接需允许获取服务器公钥
      allowPublicKeyRetrieval: true,
    );
    await conn.connect();
    return conn;
  }

  static Future<pg.Connection> _connectPostgres(
    DbConnectionInfo info, {
    String? database,
  }) {
    return pg.Connection.open(
      pg.Endpoint(
        host: info.host,
        port: info.port,
        database: database ?? info.databaseName ?? 'postgres',
        username: info.username ?? 'postgres',
        password: info.password,
      ),
      settings: pg.ConnectionSettings(sslMode: pg.SslMode.disable),
    );
  }

  /// 建立 Redis 连接并完成认证（如有密码），返回命令句柄。
  /// 关闭连接请调用 `cmd.get_connection().close()`。
  static Future<Command> _redisConnect(DbConnectionInfo info) async {
    final conn = RedisConnection();
    final cmd = await conn.connect(info.host, info.port);
    final pwd = _nonEmpty(info.password);
    if (pwd != null) {
      final user = _nonEmpty(info.username);
      await cmd.send_object(user == null ? ['AUTH', pwd] : ['AUTH', user, pwd]);
    }
    return cmd;
  }
}
