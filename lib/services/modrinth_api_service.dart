// Modrinth API v2 服务
// 文档: https://docs.modrinth.com
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/modrinth.dart';

/// Modrinth API 异常
class ModrinthApiException implements Exception {
  final String message;
  final int? statusCode;

  const ModrinthApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ModrinthApiException($statusCode): $message';
}

/// Modrinth API 服务
class ModrinthApiService {
  ModrinthApiService({http.Client? client})
      : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.modrinth.com/v2';
  static const String _userAgent =
      'IriX/1.0.0 (https://github.com/mcfso/xmcserverlancher)';

  final http.Client _client;

  /// 搜索项目
  ///
  /// [query] 搜索关键词
  /// [facets] 过滤条件，格式为 [["project_type:mod"], ["categories:fabric"]]
  /// [index] 排序方式: relevance, downloads, follows, newest, updated
  /// [offset] 分页偏移
  /// [limit] 每页数量 (最大 100)
  Future<ModrinthSearchResult> search({
    String query = '',
    List<List<String>>? facets,
    String index = 'relevance',
    int offset = 0,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: <String, String>{
        if (query.isNotEmpty) 'query': query,
        if (facets != null && facets.isNotEmpty)
          'facets': jsonEncode(facets),
        'index': index,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );

    final response = await _get(uri);
    return ModrinthSearchResult.fromJson(
        response as Map<String, dynamic>);
  }

  /// 获取项目详情
  Future<ModrinthProject> getProject(String idOrSlug) async {
    final uri = Uri.parse('$_baseUrl/project/$idOrSlug');
    final response = await _get(uri);
    return ModrinthProject.fromJson(response as Map<String, dynamic>);
  }

  /// 获取项目的版本列表（所有版本，自动分页加载）
  ///
  /// [gameVersions] 过滤游戏版本
  /// [loaders] 过滤加载器
  Future<List<ModrinthVersion>> getProjectVersions(
    String idOrSlug, {
    List<String>? gameVersions,
    List<String>? loaders,
  }) async {
    const pageSize = 100;
    final all = <ModrinthVersion>[];
    int offset = 0;
    while (true) {
      final uri = Uri.parse('$_baseUrl/project/$idOrSlug/version').replace(
        queryParameters: <String, String>{
          if (gameVersions != null && gameVersions.isNotEmpty)
            'game_versions': jsonEncode(gameVersions),
          if (loaders != null && loaders.isNotEmpty)
            'loaders': jsonEncode(loaders),
          'offset': offset.toString(),
          'limit': pageSize.toString(),
        },
      );
      final response = await _get(uri);
      final list = response as List<dynamic>;
      final page = list
          .map((e) => ModrinthVersion.fromJson(e as Map<String, dynamic>))
          .toList();
      all.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  /// 获取单个版本详情
  Future<ModrinthVersion> getVersion(String versionId) async {
    final uri = Uri.parse('$_baseUrl/version/$versionId');
    final response = await _get(uri);
    return ModrinthVersion.fromJson(response as Map<String, dynamic>);
  }

  /// 获取分类标签
  Future<List<ModrinthTag>> getCategoryTags() async {
    final uri = Uri.parse('$_baseUrl/tag/category');
    final response = await _get(uri);
    final list = response as List<dynamic>;
    return list
        .map((e) =>
            ModrinthTag.fromJson(e as Map<String, dynamic>, ModrinthTagType.category))
        .toList();
  }

  /// 获取加载器标签
  Future<List<ModrinthTag>> getLoaderTags() async {
    final uri = Uri.parse('$_baseUrl/tag/loader');
    final response = await _get(uri);
    final list = response as List<dynamic>;
    return list
        .map((e) =>
            ModrinthTag.fromJson(e as Map<String, dynamic>, ModrinthTagType.loader))
        .toList();
  }

  /// 获取游戏版本标签
  Future<List<ModrinthGameVersionTag>> getGameVersionTags() async {
    final uri = Uri.parse('$_baseUrl/tag/game_version');
    final response = await _get(uri);
    final list = response as List<dynamic>;
    return list
        .map((e) =>
            ModrinthGameVersionTag.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 统一 GET 请求
  Future<dynamic> _get(Uri uri) async {
    try {
      final response = await _client.get(uri, headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ModrinthApiException(
          '请求失败: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      return jsonDecode(response.body);
    } on FormatException catch (e) {
      throw ModrinthApiException('JSON 解析失败: ${e.message}');
    } on http.ClientException catch (e) {
      throw ModrinthApiException('网络错误: ${e.message}');
    }
  }

  void dispose() {
    _client.close();
  }
}
