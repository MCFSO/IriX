// Hangar (PaperMC) API v1 服务
// 文档: https://docs.papermc.io/hangar/api
//
// 仅使用公开只读端点，无需 API Key。
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/hangar.dart';

/// Hangar API 异常。
class HangarApiException implements Exception {
  final String message;
  final int? statusCode;

  const HangarApiException(this.message, {this.statusCode});

  @override
  String toString() => 'HangarApiException($statusCode): $message';
}

/// Hangar API 服务。
class HangarApiService {
  HangarApiService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _baseUrl = 'https://hangar.papermc.io/api/v1';
  static const String _userAgent =
      'IriX/1.0.0 (https://github.com/mcfso/xmcserverlancher)';

  final http.Client _client;

  /// 搜索项目。
  ///
  /// [query] 搜索关键词；[platform] 平台过滤 (paper/velocity/...)；
  /// [category] 分类 (admin_tools/...); [sort] 排序 (newest/.../stars/downloads)。
  Future<({List<HangarProjectHit> hits, int total})> search({
    String query = '',
    String? platform,
    String? category,
    String sort = 'newest',
    int offset = 0,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/projects').replace(
      queryParameters: <String, String>{
        if (query.isNotEmpty) 'q': query,
        if (platform != null && platform.isNotEmpty) 'platform': platform,
        if (category != null && category.isNotEmpty) 'category': category,
        'sort': sort,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );

    final json = await _get(uri) as Map<String, dynamic>;
    final result = (json['result'] as List<dynamic>? ?? const [])
        .map((e) => HangarProjectHit.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};
    final total = (pagination['count'] as num?)?.toInt() ?? result.length;
    return (hits: result, total: total);
  }

  /// 获取项目详情。
  Future<HangarProject> getProject(String slug) async {
    final uri = Uri.parse('$_baseUrl/projects/$slug');
    final json = await _get(uri) as Map<String, dynamic>;
    return HangarProject.fromJson(json);
  }

  /// 获取项目的所有版本（自动分页加载）。
  Future<List<HangarVersion>> getVersions(String slug) async {
    const pageSize = 50;
    final all = <HangarVersion>[];
    int offset = 0;
    while (true) {
      final uri = Uri.parse('$_baseUrl/projects/$slug/versions').replace(
        queryParameters: <String, String>{
          'offset': offset.toString(),
          'limit': pageSize.toString(),
        },
      );
      final json = await _get(uri) as Map<String, dynamic>;
      final result = (json['result'] as List<dynamic>? ?? const [])
          .map((e) =>
              HangarVersion.fromJson(e as Map<String, dynamic>, slug))
          .toList();
      all.addAll(result);
      final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};
      final total = (pagination['count'] as num?)?.toInt() ?? all.length;
      if (all.length >= total || result.isEmpty) break;
      offset += pageSize;
    }
    return all;
  }

  /// 统一 GET 请求。
  Future<dynamic> _get(Uri uri) async {
    try {
      final response = await _client.get(uri, headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HangarApiException(
          '请求失败: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return jsonDecode(response.body);
    } on FormatException catch (e) {
      throw HangarApiException('JSON 解析失败: ${e.message}');
    } on http.ClientException catch (e) {
      throw HangarApiException('网络错误: ${e.message}');
    }
  }

  void dispose() {
    _client.close();
  }
}
