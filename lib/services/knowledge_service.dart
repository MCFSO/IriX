// AI 知识库服务（RAG）
//
// 管理本地向量知识库（sqlite-vec，经 xmc_vector_store FFI）：
// - 用户导入 .txt/.md 文档，自动分块后调用 AI 模型的 /embeddings 接口
//   生成向量并写入库；
// - AI 对话时对查询向量做余弦相似度检索，把命中片段作为上下文；
// - embedding 复用 AI 设置中的模型（baseUrl + apiKey + embeddingModel 名），
//   不引入额外的 embedding 服务。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/ai_settings.dart';
import '../services/http_ffi.dart';
import '../services/knowledge_ffi.dart';

/// 知识库中的一个文档条目（元数据）。
class KnowledgeDocument {
  final String id;
  final String title;
  final String createdAt;
  final int chunkCount;

  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.chunkCount,
  });

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) =>
      KnowledgeDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        chunkCount: (json['chunk_count'] as num?)?.toInt() ?? 0,
      );
}

/// 一条检索命中。
class KnowledgeHit {
  final String docId;
  final String title;
  final String text;
  final double distance;

  const KnowledgeHit({
    required this.docId,
    required this.title,
    required this.text,
    required this.distance,
  });

  factory KnowledgeHit.fromJson(Map<String, dynamic> json) => KnowledgeHit(
    docId: json['doc_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    text: json['text'] as String? ?? '',
    distance: (json['distance'] as num?)?.toDouble() ?? 0,
  );
}

/// 知识库状态统计。
class KnowledgeStats {
  final int documentCount;
  final int chunkCount;
  final int dimension;

  const KnowledgeStats({
    required this.documentCount,
    required this.chunkCount,
    required this.dimension,
  });

  factory KnowledgeStats.fromJson(Map<String, dynamic> json) => KnowledgeStats(
    documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
    chunkCount: (json['chunk_count'] as num?)?.toInt() ?? 0,
    dimension: (json['dimension'] as num?)?.toInt() ?? 0,
  );
}

/// AI 知识库服务（单例）。
class KnowledgeService {
  static final KnowledgeService instance = KnowledgeService._();
  KnowledgeService._();

  /// 知识库数据库文件路径（首次访问时解析）。
  Future<String> get _dbPath async {
    final dir = await getKnowledgeDir();
    return p.join(dir.path, 'knowledge.db');
  }

  /// 知识库目录（文档目录/ai_knowledge）。
  static Future<Directory> getKnowledgeDir() async {
    final base = await getAiKnowledgeBaseDir();
    final dir = Directory(p.join(base, 'ai_knowledge'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // === 基础操作 ===

  /// 初始化知识库（幂等）。[dimension] 为 embedding 维度，首次创建时使用。
  Future<void> init({int? dimension}) async {
    await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'init',
      args: {'dimension': ?dimension},
    );
  }

  /// 状态统计。
  Future<KnowledgeStats> stats() async {
    final result = await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'stats',
    );
    return KnowledgeStats.fromJson(result);
  }

  /// 文档列表（按创建时间倒序）。
  Future<List<KnowledgeDocument>> listDocuments() async {
    final result = await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'list_documents',
    );
    return [
      for (final item in (result['documents'] as List? ?? const []))
        KnowledgeDocument.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// 删除文档（含全部分块与向量）。
  Future<void> deleteDocument(String docId) async {
    await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'delete_document',
      args: {'doc_id': docId},
    );
  }

  // === embedding ===

  /// 调用 AI 模型的 /embeddings 接口生成向量。
  ///
  /// [model] 使用该模型配置（baseUrl/apiKey）；embedding 模型名取
  /// [AiModelConfig.embeddingModel]，为空时回退到模型名本身。
  /// 返回与 [texts] 一一对应的向量列表。
  Future<List<List<double>>> embedTexts(
    AiModelConfig model,
    List<String> texts,
  ) async {
    if (texts.isEmpty) return [];
    final embedModel = (model.embeddingModel?.trim().isNotEmpty ?? false)
        ? model.embeddingModel!.trim()
        : model.name;

    final body = jsonEncode({
      'model': embedModel,
      'input': texts,
    });

    final res = await HttpFfiService.instance.post(
      _embeddingEndpoint(model.baseUrl),
      headers: {
        'Content-Type': 'application/json',
        if (model.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${model.apiKey.trim()}',
      },
      body: body,
      timeout: const Duration(seconds: 120),
    );
    if (res.statusCode != 200) {
      throw Exception('Embedding API ${res.statusCode}: ${_snippet(res.body)}');
    }
    final json =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = json['data'] as List?;
    if (data == null || data.isEmpty) {
      throw Exception('Embedding API 返回为空（data 为空）');
    }
    final vectors = <List<double>>[];
    for (final item in data) {
      final emb = (item as Map)['embedding'] as List?;
      if (emb == null) continue;
      vectors.add([for (final v in emb) (v as num).toDouble()]);
    }
    if (vectors.length != texts.length) {
      throw Exception('Embedding 数量不匹配: ${vectors.length} != ${texts.length}');
    }
    return vectors;
  }

  /// 拼接 /embeddings 端点地址。
  static String _embeddingEndpoint(String baseUrl) {
    final url = baseUrl.trim();
    if (url.isEmpty) throw Exception('未配置 AI 服务地址');
    if (url.endsWith('/embeddings')) return url;
    return '${url.replaceAll(RegExp(r'/+$'), '')}/embeddings';
  }

  // === 文档导入 ===

  /// 导入文档：读取文件 → 分块 → 批量 embedding → 写入知识库。
  ///
  /// 返回生成的 doc id；失败抛异常。知识库首次创建时按 embedding 维度初始化。
  Future<String> importDocument(
    AiModelConfig model, {
    required String title,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      throw Exception('文档内容为空');
    }
    final chunks = _splitChunks(content);
    if (chunks.isEmpty) {
      throw Exception('文档内容为空');
    }

    // 生成向量（模型未启用 embedding 时会失败并给出提示）。
    final vectors = await embedTexts(model, chunks);
    final dimension = vectors.first.length;

    // 初始化（幂等，维度校验在 Rust 侧完成）。
    await init(dimension: dimension);

    final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'add',
      args: {
        'doc_id': docId,
        'title': title,
        'created_at': DateTime.now().toIso8601String(),
        'chunks': [
          for (var i = 0; i < chunks.length; i++)
            {'text': chunks[i], 'embedding': vectors[i]},
        ],
      },
      timeout: const Duration(seconds: 120),
    );
    return docId;
  }

  /// 按段落切分文档：优先按空行分段，段太长再按 500 字符折半。
  static List<String> _splitChunks(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return [];

    const maxChunk = 500;
    final rawSegments = normalized.split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    for (var seg in rawSegments) {
      seg = seg.trim();
      if (seg.isEmpty) continue;
      if (seg.length <= maxChunk) {
        chunks.add(seg);
        continue;
      }
      // 长段落按句子/逗号粗切，再按 maxChunk 兜底。
      final parts = seg.split(RegExp(r'(?<=[。！？!?.])\s*'));
      var buf = '';
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        if (buf.length + trimmed.length > maxChunk && buf.isNotEmpty) {
          chunks.add(buf);
          buf = trimmed;
        } else {
          buf = buf.isEmpty ? trimmed : '$buf$trimmed';
        }
      }
      if (buf.isNotEmpty) chunks.add(buf);
    }
    return chunks;
  }

  // === 检索 ===

  /// 对 [query] 做向量检索，返回最相似的 [topK] 个分块。
  ///
  /// 知识库为空返回空列表；embedding 失败抛异常。
  Future<List<KnowledgeHit>> search(
    AiModelConfig model,
    String query, {
    int topK = 5,
  }) async {
    final current = await stats();
    if (current.documentCount == 0) return [];

    final vectors = await embedTexts(model, [query]);
    final result = await VectorStoreFfi.instance.request(
      dbPath: await _dbPath,
      op: 'search',
      args: {'embedding': vectors.first, 'top_k': topK},
    );
    return [
      for (final item in (result['results'] as List? ?? const []))
        KnowledgeHit.fromJson(item as Map<String, dynamic>),
    ];
  }

  static String _snippet(String body) {
    final trimmed = body.trim();
    return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
  }
}

/// 知识库目录的父目录（应用文档目录）。
Future<String> getAiKnowledgeBaseDir() async {
  final appDir = await getApplicationDocumentsDirectory();
  return appDir.path;
}
