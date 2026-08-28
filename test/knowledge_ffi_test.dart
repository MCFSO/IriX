// knowledge_ffi 集成测试
// 验证 Rust 向量知识库 FFI 封装（Milvus 后端）：
// init / add / search / list_documents / delete_document / stats。
//
// 需要本地运行的 Milvus 实例。通过环境变量 MILVUS_URI 提供地址：
//   MILVUS_URI=http://localhost:19530 flutter test test/knowledge_ffi_test.dart
// 未设置 MILVUS_URI 时所有用例自动跳过（CI 无 Milvus 不失败）。
// 也可直接运行 Rust 集成测试：cargo test --release -- --ignored

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/knowledge_ffi.dart';

void main() {
  final uri = Platform.environment['MILVUS_URI'];
  final skip = uri == null || uri.isEmpty;
  final skipReason = skip ? '需要 MILVUS_URI 环境变量（本地 Milvus 实例）' : null;

  // 每个用例使用独立集合，避免相互干扰。
  String connJsonFor(String name) =>
      '{"uri":"${uri ?? "http://localhost:19530"}","token":"","collection":"xmc_test_$name"}';

  group('knowledge_ffi (Milvus)',
      () {
    test('init & stats 基本操作', () async {
      final conn = connJsonFor('init');
      final r = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'init',
        args: {'dimension': 4},
      );
      expect(r['dimension'], 4);

      final stats = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'stats',
      );
      expect(stats['document_count'], 0);
      expect(stats['chunk_count'], 0);
      expect(stats['dimension'], 4);
    }, skip: skipReason);

    test('add & search 相似度检索', () async {
      final conn = connJsonFor('crud');
      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'init',
        args: {'dimension': 3},
      );

      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'add',
        args: {
          'doc_id': 'd1',
          'title': '魔兽',
          'created_at': '2026-01-01T00:00:00Z',
          'chunks': [
            {
              'text': '末影龙是结束之地的 Boss',
              'embedding': [1.0, 0.0, 0.0],
            },
            {
              'text': '下界合金装备最坚固',
              'embedding': [0.0, 1.0, 0.0],
            },
          ],
        },
      );
      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'add',
        args: {
          'doc_id': 'd2',
          'title': '红石',
          'created_at': '2026-01-02T00:00:00Z',
          'chunks': [
            {
              'text': '红石中继器可延长信号',
              'embedding': [0.0, 0.0, 1.0],
            },
          ],
        },
      );

      final res = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'search',
        args: {
          'embedding': [0.9, 0.1, 0.1],
          'top_k': 3,
        },
      );
      final results = res['results'] as List;
      expect(results, isNotEmpty);
      // 余弦距离应较小（相似度高）。
      expect((results.first as Map)['distance'], lessThan(1.0));
      expect((results.first as Map)['text'], contains('末影龙'));

      // list_documents
      final docs = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'list_documents',
      );
      expect((docs['documents'] as List).length, 2);

      // 覆盖 d1
      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'add',
        args: {
          'doc_id': 'd1',
          'title': '魔兽新',
          'created_at': '2026-01-03T00:00:00Z',
          'chunks': [
            {
              'text': '新版末影龙更强',
              'embedding': [1.0, 1.0, 1.0],
            },
          ],
        },
      );
      final stats = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'stats',
      );
      expect(stats['document_count'], 2);
      expect(stats['chunk_count'], 2);

      // 删除
      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'delete_document',
        args: {'doc_id': 'd2'},
      );
      final stats2 = await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'stats',
      );
      expect(stats2['document_count'], 1);
      expect(stats2['chunk_count'], 1);
    }, skip: skipReason);

    test('维度不匹配报错', () async {
      final conn = connJsonFor('dim');
      await VectorStoreFfi.instance.request(
        connJson: conn,
        op: 'init',
        args: {'dimension': 3},
      );
      expect(
        () => VectorStoreFfi.instance.request(
          connJson: conn,
          op: 'add',
          args: {
            'doc_id': 'd',
            'title': 't',
            'chunks': [
              {
                'text': 'x',
                'embedding': [1.0, 2.0],
              },
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
    }, skip: skipReason);

    test('未知操作报错', () async {
      final conn = connJsonFor('unknown');
      expect(
        () => VectorStoreFfi.instance.request(
          connJson: conn,
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
  });
}
