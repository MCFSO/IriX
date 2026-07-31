import 'dart:convert';

import 'package:http/http.dart' as http;

const _baseUrl = 'https://api.mslmc.cn/v4';

class MslApiService {
  const MslApiService._();
  static const instance = MslApiService._();

  String get _ua => 'IriX/1.0.0 (https://github.com/mcfso/xmcserverlancher)';

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: {'User-Agent': _ua},
    );
    if (res.statusCode != 200) {
      throw Exception('MSL API $res.statusCode: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['code'] != 200) {
      throw Exception(body['message'] ?? 'MSL API error');
    }
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, List<String>>> getMirrorsGrouped() async {
    final data = await _get('/mirrors');
    return data.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  Future<List<String>> getMirrorsFlat() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/mirrors?view=list'),
      headers: {'User-Agent': _ua},
    );
    if (response.statusCode != 200) {
      throw Exception('MSL API ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != 200) {
      throw Exception(body['message'] ?? 'MSL API error');
    }
    return List<String>.from(body['data'] as List);
  }

  Future<MslServerInfo> getServerInfo(String server) async {
    final data = await _get('/mirrors/$server');
    return MslServerInfo(
      description: data['description'] as String?,
      versions: List<String>.from(data['versions'] as List),
    );
  }

  Future<MslDownloadInfo> getDownloadUrl(String server, String version) async {
    final data = await _get('/download/server/$server/$version');
    return MslDownloadInfo(
      url: data['url'] as String,
      sha256: data['sha256'] as String?,
    );
  }
}

class MslServerInfo {
  final String? description;
  final List<String> versions;
  const MslServerInfo({this.description, required this.versions});
}

class MslDownloadInfo {
  final String url;
  final String? sha256;
  const MslDownloadInfo({required this.url, this.sha256});
}
