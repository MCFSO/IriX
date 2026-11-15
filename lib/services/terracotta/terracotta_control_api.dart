// 陶瓦联机（Terracotta）本地控制 API 客户端。
//
// 联机核心在 `http://127.0.0.1:<port>` 暴露一组极简 HTTP 接口（全部 GET）：
//   GET /state                          当前状态快照（带自增 index）
//   GET /state/ide                      回到空闲态（等待房主/房客选择）
//   GET /state/scanning?player=&public_nodes=...   房主：扫描局域网世界
//   GET /state/guesting?room=&player=&public_nodes=...  房客：加入房间
//   GET /log?fetch=true                 导出联机核心日志（纯文本）
// 公共节点列表来自 `https://terracotta.glavo.site/nodes`。
//
// 与 HMCL 一致：所有请求都走项目统一的 Rust HTTP（`HttpFfiService`），
// Dart 侧不引入 `package:http`。

import 'dart:convert';

import '../dev_log.dart';
import '../http_ffi.dart';
import 'terracotta_metadata.dart';

/// 控制 API 抽象（测试可注入假实现）。
abstract class TerracottaControlApi {
  /// 读取 `/state`（原始 JSON）。
  Future<Map<String, dynamic>> fetchState(int port);

  /// `/state/ide`：回到空闲态。
  Future<void> setWaiting(int port);

  /// `/state/scanning`：房主开始扫描局域网世界。
  Future<void> setScanning(
    int port, {
    required String player,
    required List<String> publicNodes,
  });

  /// `/state/guesting`：房客加入指定房间。
  Future<void> setGuesting(
    int port, {
    required String room,
    required String player,
    required List<String> publicNodes,
  });

  /// `/log?fetch=true`：导出联机核心日志文本。
  Future<String?> exportLog(int port);

  /// 拉取公共节点地址列表。
  Future<List<String>> fetchPublicNodes();
}

/// 基于 Rust `HttpFfiService` 的实现。
class HttpTerracottaControlApi implements TerracottaControlApi {
  HttpTerracottaControlApi({
    HttpFfiService? http,
    this.timeout = const Duration(seconds: 10),
  }) : _http = http ?? HttpFfiService.instance;

  final HttpFfiService _http;
  final Duration timeout;

  String _base(int port) => 'http://127.0.0.1:$port';

  @override
  Future<Map<String, dynamic>> fetchState(int port) async {
    final response = await _http.get('${_base(port)}/state', timeout: timeout);
    if (response.statusCode != 200) {
      throw HttpFfiException(
        '联机核心返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('/state 返回的不是 JSON 对象');
    }
    return decoded.cast<String, dynamic>();
  }

  @override
  Future<void> setWaiting(int port) async {
    await _getNoContent('${_base(port)}/state/ide');
  }

  @override
  Future<void> setScanning(
    int port, {
    required String player,
    required List<String> publicNodes,
  }) async {
    final query = <String>[
      'player=${Uri.encodeQueryComponent(player)}',
      for (final node in publicNodes)
        'public_nodes=${Uri.encodeQueryComponent(node)}',
    ].join('&');
    await _getNoContent('${_base(port)}/state/scanning?$query');
  }

  @override
  Future<void> setGuesting(
    int port, {
    required String room,
    required String player,
    required List<String> publicNodes,
  }) async {
    final query = <String>[
      'room=${Uri.encodeQueryComponent(room)}',
      'player=${Uri.encodeQueryComponent(player)}',
      for (final node in publicNodes)
        'public_nodes=${Uri.encodeQueryComponent(node)}',
    ].join('&');
    await _getNoContent('${_base(port)}/state/guesting?$query');
  }

  @override
  Future<String?> exportLog(int port) async {
    final response = await _http.get(
      '${_base(port)}/log?fetch=true',
      timeout: const Duration(seconds: 30),
    );
    if (response.statusCode != 200) return null;
    final body = response.body;
    return body.isEmpty ? null : body;
  }

  @override
  Future<List<String>> fetchPublicNodes() async {
    try {
      final response = await _http.get(
        kTerracottaNodeListUrl,
        timeout: const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        DevLog.instance.devWarn('terracotta', '节点列表返回 ${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      final urls = <String>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final url = item['url']?.toString();
        if (url == null || url.isEmpty) continue;
        // 这里不做区域过滤：本应用没有可靠的机器归属地判定，交给联机核心
        // 在握手时自行选路（比按错误区域过滤掉全部节点更稳）。
        if (Uri.tryParse(url)?.hasScheme != true) {
          DevLog.instance.devWarn('terracotta', '非法节点地址: $url');
          continue;
        }
        urls.add(url);
      }
      DevLog.instance.devInfo('terracotta', '公共节点 ${urls.length} 个');
      return urls;
    } catch (e) {
      DevLog.instance.devWarn('terracotta', '拉取节点列表失败: $e');
      return const [];
    }
  }

  Future<void> _getNoContent(String url) async {
    final response = await _http.get(url, timeout: timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpFfiException(
        '联机核心返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}
