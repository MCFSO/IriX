// db_client_ffi 集成测试
// 验证 Rust 侧远程数据库客户端 FFI 封装：
// 库加载、操作分发、参数校验错误、连接失败错误路径（无真实数据库）。
// 需要先构建 Rust db_client 模块并复制动态库到 windows/runner/ 或项目根目录。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/db_client_ffi.dart';

void main() {
  test('加载动态库并调用未知操作返回错误', () async {
    await expectLater(
      DbClientFfi.instance.request(
        dbType: 'mysql',
        host: '127.0.0.1',
        port: 1,
        op: 'no_such_op',
      ),
      throwsA(
        isA<DbClientFfiException>().having(
          (e) => e.message,
          'message',
          contains('不支持的数据库操作'),
        ),
      ),
    );
  });

  test('连接不存在的端口返回连接错误', () async {
    await expectLater(
      DbClientFfi.instance.request(
        dbType: 'mysql',
        host: '127.0.0.1',
        port: 1, // 未被监听的端口
        username: 'root',
        password: '',
        op: 'test_connection',
        timeout: const Duration(seconds: 10),
      ),
      throwsA(
        isA<DbClientFfiException>().having(
          (e) => e.message,
          'message',
          contains('MySQL 连接失败'),
        ),
      ),
    );
  });

  test('Redis 连接不存在的端口返回连接错误', () async {
    // 前提：本机未运行 Redis 时，连接失败属正常；验证错误信息通道可用。
    await expectLater(
      DbClientFfi.instance.request(
        dbType: 'redis',
        host: '127.0.0.1',
        port: 1,
        op: 'test_connection',
        timeout: const Duration(seconds: 10),
      ),
      throwsA(isA<DbClientFfiException>()),
    );
  });

  test('PostgreSQL 连接不存在的端口返回连接错误', () async {
    await expectLater(
      DbClientFfi.instance.request(
        dbType: 'postgres',
        host: '127.0.0.1',
        port: 1,
        username: 'postgres',
        op: 'test_connection',
        timeout: const Duration(seconds: 10),
      ),
      throwsA(
        isA<DbClientFfiException>().having(
          (e) => e.message,
          'message',
          contains('PostgreSQL 连接失败'),
        ),
      ),
    );
  });

  test('Redis get_databases 不发起连接直接返回 default', () async {
    // Redis 的 get_databases 是本地逻辑（返回 ['default']），无需真实连接。
    final result = await DbClientFfi.instance.request(
      dbType: 'redis',
      host: '127.0.0.1',
      port: 6379,
      op: 'get_databases',
    );
    expect(result['databases'], ['default']);
  });
}
