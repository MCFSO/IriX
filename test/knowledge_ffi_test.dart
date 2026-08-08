// knowledge_ffi 集成测试
// 使用临时 SQLite 库验证 Rust 向量知识库 FFI 封装：
// init / add / search / list_documents / delete_document / stats。
// 需要先构建 Rust vector_store 模块并复制动态库到 windows/runner/ 或项目根目录。

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/knowledge_ffi.dart';

void main() {
  late String dbPath;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('knowledge_test');
    dbPath =
        '${dir.path}${Platform.pathSeparator}kb_${Random().nextInt(100000)}.db';
  });

  tearDown(() async {
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
    final wal = File('$dbPath-wal');
    if (await wal.exists()) await wal.delete();
    final shm = File('$dbPath-shm');
    if (await shm.exists()) await shm.delete();
    await Directory(p.dirname(dbPath)).delete(recursive: true);
  });

  test('init & stats 基本操作', () async {
    final r = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'init',
      args: {'dimension': 4},
    );
    expect(r['dimension'], 4);

    final stats = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'stats',
    );
    expect(stats['document_count'], 0);
    expect(stats['chunk_count'], 0);
    expect(stats['dimension'], 4);
  });

  test('add & search 相似度检索', () async {
    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'init',
      args: {'dimension': 3},
    );

    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'add',
      args: {
        'doc_id': 'd1',
        'title': '魔兽',
        'created_at': '2026-01-01T00:00:00Z',
        'chunks': [
          {'text': '末影龙是结束之地的 Boss', 'embedding': [1.0, 0.0, 0.0]},
          {'text': '下界合金装备最坚固', 'embedding': [0.0, 1.0, 0.0]},
        ],
      },
    );
    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'add',
      args: {
        'doc_id': 'd2',
        'title': '红石',
        'created_at': '2026-01-02T00:00:00Z',
        'chunks': [
          {'text': '红石中继器可延长信号', 'embedding': [0.0, 0.0, 1.0]},
        ],
      },
    );

    final res = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'search',
      args: {'embedding': [0.9, 0.1, 0.1], 'top_k': 3},
    );
    final results = res['results'] as List;
    expect(results, isNotEmpty);
    // 距离应较小（相似度高）
    expect((results.first as Map)['distance'], lessThan(1.0));
    expect((results.first as Map)['text'], contains('末影龙'));

    // list_documents
    final docs = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'list_documents',
    );
    expect((docs['documents'] as List).length, 2);

    // 覆盖 d1
    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'add',
      args: {
        'doc_id': 'd1',
        'title': '魔兽新',
        'created_at': '2026-01-03T00:00:00Z',
        'chunks': [
          {'text': '新版末影龙更强', 'embedding': [1.0, 1.0, 1.0]},
        ],
      },
    );
    final stats = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'stats',
    );
    expect(stats['document_count'], 2);
    expect(stats['chunk_count'], 2);

    // 删除
    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'delete_document',
      args: {'doc_id': 'd2'},
    );
    final stats2 = await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'stats',
    );
    expect(stats2['document_count'], 1);
    expect(stats2['chunk_count'], 1);
  });

  test('维度不匹配报错', () async {
    await VectorStoreFfi.instance.request(
      dbPath: dbPath,
      op: 'init',
      args: {'dimension': 3},
    );
    expect(
      () => VectorStoreFfi.instance.request(
        dbPath: dbPath,
        op: 'add',
        args: {
          'doc_id': 'd',
          'title': 't',
          'chunks': [
            {'text': 'x', 'embedding': [1.0, 2.0]},
          ],
        },
      ),
      throwsA(
        isA<VectorStoreFfiException>().having(
          (e) => e.toString(),
          'error',
          contains('维度'),
        ),
      ),
    );
  });

  test('未知操作报错', () async {
    expect(
      () => VectorStoreFfi.instance.request(
        dbPath: dbPath,
        op: 'unknown_op',
      ),
      throwsA(
        isA<VectorStoreFfiException>().having(
          (e) => e.toString(),
          'error',
          contains('不支持的向量库操作'),
        ),
      ),
    );
  });
}