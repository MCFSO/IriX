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
      createdAt: DateTime.tryParse(
            (row['created_at'] as String?) ?? '',
          ) ??
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
  Future<List<String>> getTables(
    DbConnectionInfo info,
    String database,
  ) async {
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

  /// 查询表中前 [limit] 行数据（默认 100）。返回 [{column: value, ...}, ...]。
  Future<List<Map<String, dynamic>>> queryTable(
    DbConnectionInfo info,
    String database,
    String table, {
    int limit = 100,
  }) async {
    switch (info.type) {
      case DbType.mysql:
      case DbType.mariadb:
        final conn = await _connectMysql(info, database: database);
        try {
          final sql = 'SELECT * FROM `${_escMysqlIdent(table)}` LIMIT ?';
          final results = await conn.execute(sql, [limit]);
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
            'SELECT * FROM "${_escPgIdent(table)}" LIMIT @limit',
            parameters: {'limit': limit},
          );
          return [
            for (final row in result) Map<String, dynamic>.from(row.toColumnMap()),
          ];
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
    final isQuery = trimmed.startsWith('SELECT') ||
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
  Future<void> redisSet(
    DbConnectionInfo info,
    String key,
    String value,
  ) async {
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

  // === 内部工具 ===

  /// 空字符串密码/用户名归一化为 null
  static String? _nonEmpty(String? v) =>
      (v == null || v.isEmpty) ? null : v;

  /// MySQL 标识符转义（反引号内的反引号翻倍）
  static String _escMysqlIdent(String ident) =>
      ident.replaceAll('`', '``');

  /// PostgreSQL 标识符转义（双引号内的双引号翻倍）
  static String _escPgIdent(String ident) =>
      ident.replaceAll('"', '""');

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
