// 节点 API 客户端
// 同时服务于 MCSManager 面板节点与 IriX 本地节点（Go 守护进程）：
// 两者提供同一风格的 HTTP API（见 apis/ 目录），因此共用一套客户端。
//
// 约定：
// - 请求头携带 X-Requested-With: XMLHttpRequest（MCSM 必需）
// - API 密钥通过 apikey 查询参数传递（MCSM 与本地节点均支持）
// - 统一响应体 {status, data, time}；status != 200 时抛出 NodeApiException

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/node.dart';
import '../models/remote.dart';

/// 节点 API 异常。
class NodeApiException implements Exception {
  /// HTTP 状态码（网络错误时为 0）。
  final int statusCode;

  /// 错误消息。
  final String message;

  const NodeApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// 下载票据（含直连下载地址）。
class DownloadTicket {
  final String password;
  final String addr;
  final String fileName;

  const DownloadTicket({
    required this.password,
    required this.addr,
    required this.fileName,
  });

  /// 拼接直连下载 URL。
  String get url => 'http://$_hostPort/download/$password/$fileName';

  /// 将 addr（host:port）规范化为 http://host:port。
  String get _hostPort => addr.contains('://') ? addr : 'http://$addr';
}

/// 上传票据。
class UploadTicket {
  final String password;
  final String addr;
  final String uploadDir;

  const UploadTicket({
    required this.password,
    required this.addr,
    required this.uploadDir,
  });

  String get url => '${addr.contains('://') ? addr : 'http://$addr'}/upload/$password';
}

/// 节点 API 客户端。
class NodeApiClient {
  NodeApiClient({
    required this.baseUrl,
    this.apiKey = '',
    this.timeout = const Duration(seconds: 15),
  });

  /// API 基地址，例如 http://127.0.0.1:12346。
  final String baseUrl;

  /// API 密钥（本地节点可为空）。
  final String apiKey;

  /// 请求超时。
  final Duration timeout;

  /// 便捷构造：由节点信息创建客户端。
  factory NodeApiClient.of(NodeInfo node) =>
      NodeApiClient(baseUrl: node.address, apiKey: node.apiKey);

  static const Map<String, String> _headers = {
    'X-Requested-With': 'XMLHttpRequest',
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// 拼接带 apikey 的请求 URI。
  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{...?query};
    if (apiKey.isNotEmpty) {
      q['apikey'] = apiKey;
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }

  /// 发送请求并解析统一响应体，返回 data 字段。
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryOnce = true,
  }) async {
    final uri = _uri(path, query);
    final headers = body != null ? _headers : const {
      'X-Requested-With': 'XMLHttpRequest',
    };
    http.Response resp;
    try {
      resp = switch (method) {
        'GET' => await http.get(uri, headers: headers).timeout(timeout),
        'POST' => await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout),
        'PUT' => await http
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout),
        'DELETE' => await http
            .delete(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout),
        _ => throw NodeApiException(0, '不支持的请求方法: $method'),
      };
    } on SocketException {
      throw NodeApiException(0, '无法连接到节点 $baseUrl，请检查地址与网络');
    } on HttpException {
      throw NodeApiException(0, '无法连接到节点 $baseUrl，请检查地址与网络');
    } on TimeoutException {
      throw NodeApiException(0, '连接节点 $baseUrl 超时');
    }

    if (resp.statusCode == 401 && retryOnce && apiKey.isEmpty) {
      throw NodeApiException(401, '节点需要 API 密钥');
    }
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, 'HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = _decode(resp);
    final status = (decoded['status'] as num?)?.toInt() ?? 500;
    if (status != 200) {
      final data = decoded['data'];
      final message = data is String
          ? data
          : '节点返回错误（status $status）';
      throw NodeApiException(status, message);
    }
    return decoded['data'];
  }

  /// 解码响应体，兼容 UTF-8 与 GBK 等编码。
  dynamic _decode(http.Response resp) {
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      // 尝试按响应头 charset 解码
      final charset = resp.headers['content-type']?.contains('gbk') ?? false;
      final raw = charset
          ? _decodeGbk(resp.bodyBytes)
          : utf8.decode(resp.bodyBytes, allowMalformed: true);
      try {
        return jsonDecode(raw);
      } catch (_) {
        throw NodeApiException(resp.statusCode, '节点返回了无法解析的数据');
      }
    }
  }

  /// GBK 字节解码（仅当面板返回 GBK 编码时使用）。
  String _decodeGbk(List<int> bytes) {
    // 简化实现：GBK 编码的 JSON 通常为 ASCII 结构 + 中文内容，
    // 回退到 Latin-1 保留字节，避免解析崩溃。
    return String.fromCharCodes(bytes);
  }

  // ==================== 概览 ====================

  /// 获取节点概览（GET /api/overview）。
  Future<OverviewData> overview() async {
    final data = await _request('GET', '/api/overview');
    return OverviewData.fromJson({'data': data ?? {}});
  }

  /// 测试连接：请求概览，返回成功与否。
  Future<bool> ping() async {
    try {
      await overview();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ==================== 实例 ====================

  /// 获取实例列表（GET /api/service/remote_service_instances）。
  Future<List<RemoteInstance>> listInstances({
    required String daemonId,
    int page = 1,
    int pageSize = 100,
    String? name,
    String? status,
  }) async {
    final data = await _request(
      'GET',
      '/api/service/remote_service_instances',
      query: {
        'daemonId': daemonId,
        'page': '$page',
        'page_size': '$pageSize',
        'instance_name': name ?? '',
        'status': status ?? '',
      },
    ) as Map<String, dynamic>? ?? {};
    final list = <RemoteInstance>[];
    for (final item in (data['data'] as List<dynamic>? ?? [])) {
      if (item is Map<String, dynamic>) {
        list.add(RemoteInstance.fromJson(item));
      }
    }
    return list;
  }

  /// 获取实例详情（GET /api/instance）。
  Future<RemoteInstance> getInstance({
    required String uuid,
    required String daemonId,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance',
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
    return RemoteInstance.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 创建实例（POST /api/instance），返回新实例 UUID。
  Future<String> createInstance({
    required String daemonId,
    required Map<String, dynamic> config,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance',
      query: {'daemonId': daemonId},
      body: config,
    ) as Map<String, dynamic>?;
    return data?['instanceUuid'] as String? ?? '';
  }

  /// 更新实例配置（PUT /api/instance）。
  Future<void> updateInstance({
    required String uuid,
    required String daemonId,
    required Map<String, dynamic> config,
  }) async {
    await _request(
      'PUT',
      '/api/instance',
      query: {'uuid': uuid, 'daemonId': daemonId},
      body: config,
    );
  }

  /// 删除实例（DELETE /api/instance）。
  Future<void> deleteInstances({
    required List<String> uuids,
    required String daemonId,
    bool deleteFile = false,
  }) async {
    await _request(
      'DELETE',
      '/api/instance',
      query: {'daemonId': daemonId},
      body: {'uuids': uuids, 'deleteFile': deleteFile},
    );
  }

  /// 实例操作（启动/停止/重启/强制终止）。
  Future<void> instanceAction({
    required String uuid,
    required String daemonId,
    required RemoteAction action,
  }) async {
    final path = switch (action) {
      RemoteAction.start => '/api/protected_instance/open',
      RemoteAction.stop => '/api/protected_instance/stop',
      RemoteAction.restart => '/api/protected_instance/restart',
      RemoteAction.kill => '/api/protected_instance/kill',
    };
    await _request(
      'GET',
      path,
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
  }

  /// 发送命令（GET /api/protected_instance/command）。
  Future<void> sendCommand({
    required String uuid,
    required String daemonId,
    required String command,
  }) async {
    await _request(
      'GET',
      '/api/protected_instance/command',
      query: {'uuid': uuid, 'daemonId': daemonId, 'command': command},
    );
  }

  /// 获取输出日志（GET /api/protected_instance/outputlog）。
  Future<String> outputLog({
    required String uuid,
    required String daemonId,
    int? size,
  }) async {
    final data = await _request(
      'GET',
      '/api/protected_instance/outputlog',
      query: {
        'uuid': uuid,
        'daemonId': daemonId,
        if (size != null) 'size': '$size',
      },
    );
    return (data as String?) ?? '';
  }

  // ==================== 文件管理 ====================

  /// 获取文件列表（GET /api/files/list）。
  Future<FileListData> listFiles({
    required String daemonId,
    required String uuid,
    String target = '/',
    int page = 1,
    int pageSize = 100,
  }) async {
    final data = await _request(
      'GET',
      '/api/files/list',
      query: {
        'daemonId': daemonId,
        'uuid': uuid,
        'target': target,
        'page': '$page',
        'page_size': '$pageSize',
      },
    );
    return FileListData.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 读取文件内容（PUT /api/files/）。
  Future<String> readFile({
    required String daemonId,
    required String uuid,
    required String target,
  }) async {
    final data = await _request(
      'PUT',
      '/api/files/',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'target': target},
    );
    return (data as String?) ?? '';
  }

  /// 写入文件内容（PUT /api/files/）。
  Future<void> writeFile({
    required String daemonId,
    required String uuid,
    required String target,
    required String text,
  }) async {
    await _request(
      'PUT',
      '/api/files/',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'target': target, 'text': text},
    );
  }

  /// 删除文件/目录（DELETE /api/files）。
  Future<void> deleteFiles({
    required String daemonId,
    required String uuid,
    required List<String> targets,
  }) async {
    await _request(
      'DELETE',
      '/api/files',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'targets': targets},
    );
  }

  /// 移动/重命名（PUT /api/files/move）。
  Future<void> moveFiles({
    required String daemonId,
    required String uuid,
    required List<List<String>> targets,
  }) async {
    await _request(
      'PUT',
      '/api/files/move',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'targets': targets},
    );
  }

  /// 复制（POST /api/files/copy）。
  Future<void> copyFiles({
    required String daemonId,
    required String uuid,
    required List<List<String>> targets,
  }) async {
    await _request(
      'POST',
      '/api/files/copy',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'targets': targets},
    );
  }

  /// 压缩（POST /api/files/compress, type=1）。
  Future<void> compress({
    required String daemonId,
    required String uuid,
    required String source,
    required List<String> targets,
  }) async {
    await _request(
      'POST',
      '/api/files/compress',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'type': 1, 'code': 'utf-8', 'source': source, 'targets': targets},
    );
  }

  /// 解压（POST /api/files/compress, type=2）。
  Future<void> unzip({
    required String daemonId,
    required String uuid,
    required String source,
    required String dest,
  }) async {
    await _request(
      'POST',
      '/api/files/compress',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'type': 2, 'code': 'utf-8', 'source': source, 'targets': [dest]},
    );
  }

  /// 新建目录（POST /api/files/mkdir）。
  Future<void> mkdir({
    required String daemonId,
    required String uuid,
    required String target,
  }) async {
    await _request(
      'POST',
      '/api/files/mkdir',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'target': target},
    );
  }

  /// 新建空文件（POST /api/files/touch）。
  Future<void> touchFile({
    required String daemonId,
    required String uuid,
    required String target,
  }) async {
    await _request(
      'POST',
      '/api/files/touch',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'target': target},
    );
  }

  /// 申请下载票据并下载文件（POST /api/files/download）。
  Future<DownloadTicket> downloadTicket({
    required String daemonId,
    required String uuid,
    required String fileName,
  }) async {
    final data = await _request(
      'POST',
      '/api/files/download',
      query: {
        'daemonId': daemonId,
        'uuid': uuid,
        'file_name': fileName,
      },
    ) as Map<String, dynamic>?;
    return DownloadTicket(
      password: data?['password'] as String? ?? '',
      addr: data?['addr'] as String? ?? '',
      fileName: fileName,
    );
  }

  /// 申请上传票据（POST /api/files/upload）。
  Future<UploadTicket> uploadTicket({
    required String daemonId,
    required String uuid,
    required String uploadDir,
  }) async {
    final data = await _request(
      'POST',
      '/api/files/upload',
      query: {
        'daemonId': daemonId,
        'uuid': uuid,
        'upload_dir': uploadDir,
      },
    ) as Map<String, dynamic>?;
    return UploadTicket(
      password: data?['password'] as String? ?? '',
      addr: data?['addr'] as String? ?? '',
      uploadDir: uploadDir,
    );
  }

  /// 直连下载文件字节流（GET /download/{password}/...）。
  Future<List<int>> directDownload(DownloadTicket ticket) async {
    final resp = await http.get(Uri.parse(ticket.url)).timeout(timeout);
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '下载失败（HTTP ${resp.statusCode}）');
    }
    return resp.bodyBytes;
  }

  /// 直连上传文件（POST /upload/{password}，multipart 字段名 file）。
  Future<void> directUpload({
    required UploadTicket ticket,
    required String localPath,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw NodeApiException(0, '本地文件不存在: $localPath');
    }
    final req = http.MultipartRequest('POST', Uri.parse(ticket.url))
      ..files.add(await http.MultipartFile.fromPath('file', localPath));
    final streamed = await req.send().timeout(timeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '上传失败（HTTP ${resp.statusCode}）');
    }
  }

  // ==================== 用户管理（MCSM 面板）====================

  /// 获取用户列表（GET /api/auth/search）。
  Future<UserListData> listUsers({
    int page = 1,
    int pageSize = 50,
    String? userName,
    int? role,
  }) async {
    final data = await _request(
      'GET',
      '/api/auth/search',
      query: {
        'page': '$page',
        'page_size': '$pageSize',
        'userName': ?userName,
        if (role != null) 'role': '$role',
      },
    );
    return UserListData.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 创建用户（POST /api/auth）。
  Future<void> createUser({
    required String username,
    required String password,
    required int permission,
  }) async {
    await _request(
      'POST',
      '/api/auth',
      body: {'username': username, 'password': password, 'permission': permission},
    );
  }

  /// 更新用户（PUT /api/auth）。
  Future<void> updateUser({required Map<String, dynamic> config}) async {
    await _request(
      'PUT',
      '/api/auth',
      body: {'uuid': config['uuid'], 'config': config},
    );
  }

  /// 删除用户（DELETE /api/auth，body 为 uuid 数组）。
  Future<void> deleteUsers(List<String> uuids) async {
    await _request('DELETE', '/api/auth', body: uuids);
  }

  // ==================== Docker 环境（MCSM 面板）====================

  /// 获取镜像列表（GET /api/environment/image）。
  Future<List<Map<String, dynamic>>> listImages(String daemonId) async {
    final data = await _request(
      'GET',
      '/api/environment/image',
      query: {'daemonId': daemonId},
    );
    return _listOfMaps(data);
  }

  /// 获取容器列表（GET /api/environment/containers）。
  Future<List<Map<String, dynamic>>> listContainers(String daemonId) async {
    final data = await _request(
      'GET',
      '/api/environment/containers',
      query: {'daemonId': daemonId},
    );
    return _listOfMaps(data);
  }

  /// 获取网络列表（GET /api/environment/network）。
  Future<List<Map<String, dynamic>>> listNetworks(String daemonId) async {
    final data = await _request(
      'GET',
      '/api/environment/network',
      query: {'daemonId': daemonId},
    );
    return _listOfMaps(data);
  }

  /// 构建镜像（POST /api/environment/image）。
  Future<void> createImage({
    required String daemonId,
    required String dockerFile,
    required String name,
    required String tag,
  }) async {
    await _request(
      'POST',
      '/api/environment/image',
      query: {'daemonId': daemonId},
      body: {'dockerFile': dockerFile, 'name': name, 'tag': tag},
    );
  }

  /// 构建进度（GET /api/environment/progress）。
  /// 返回 {镜像名: -1=失败, 1=构建中, 2=完成}。
  Future<Map<String, int>> buildProgress(String daemonId) async {
    final data = await _request(
      'GET',
      '/api/environment/progress',
      query: {'daemonId': daemonId},
    );
    final map = <String, int>{};
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        map[entry.key] = (entry.value as num?)?.toInt() ?? -1;
      }
    }
    return map;
  }

  /// 将响应转为 Map 列表（兼容不同面板返回 null 的情况）。
  List<Map<String, dynamic>> _listOfMaps(dynamic data) {
    if (data is! List) return [];
    return data.whereType<Map<String, dynamic>>().toList();
  }
}

/// 实例操作类型。
enum RemoteAction { start, stop, restart, kill }
