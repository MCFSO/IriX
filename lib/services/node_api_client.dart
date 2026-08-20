// 节点 API 客户端
// 同时服务于 MCSManager 面板节点与 IriX 本地节点（Go 守护进程）：
// 两者提供同一风格的 HTTP API（见 NODE_API.md），因此共用一套客户端。
//
// 约定：
// - 请求头携带 X-Requested-With: XMLHttpRequest（MCSM 必需）
// - API 密钥通过 X-Api-Key 请求头传递（H-6：避免密钥进入 URL 而被
//   代理/访问日志记录）；MCSM 面板兼容旧式 apikey 查询参数时
//   （[NodeApiClient] 构造的 [apiKeyInQuery]），会额外附带查询参数
// - 统一响应体 {status, data, time}；status != 200 时抛出 NodeApiException

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/node.dart';
import '../models/remote.dart';
import '../services/downloader.dart';
import '../services/http_ffi.dart';

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

  String get url =>
      '${addr.contains('://') ? addr : 'http://$addr'}/upload/$password';
}

/// 节点 API 客户端。
class NodeApiClient {
  NodeApiClient({
    required this.baseUrl,
    this.apiKey = '',
    this.timeout = const Duration(seconds: 15),
    this.apiKeyInQuery = false,
  });

  /// API 基地址，例如 http://127.0.0.1:12346。
  final String baseUrl;

  /// API 密钥（本地节点可为空）。
  final String apiKey;

  /// 请求超时。
  final Duration timeout;

  /// 是否同时以 `apikey` 查询参数附带密钥。
  ///
  /// 默认 false（密钥只走 X-Api-Key 请求头，H-6）；MCSM 面板等仅支持
  /// 查询参数的服务端需置 true，代价是密钥会进入访问日志。
  final bool apiKeyInQuery;

  /// 便捷构造：由节点信息创建客户端。
  ///
  /// MCSM 面板仅认查询参数形式的 apikey，因此该类节点保留查询参数
  /// 兼容；IriX 本地节点走请求头（H-6）。
  factory NodeApiClient.of(NodeInfo node) => NodeApiClient(
    baseUrl: node.address,
    apiKey: node.apiKey,
    apiKeyInQuery: node.type == NodeType.mcsm,
  );

  static const Map<String, String> _headers = {
    'X-Requested-With': 'XMLHttpRequest',
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// 拼接请求 URI；仅当 [apiKeyInQuery] 时才附带 apikey 查询参数。
  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{...?query};
    if (apiKeyInQuery && apiKey.isNotEmpty) {
      q['apikey'] = apiKey;
    }
    return Uri.parse('$baseUrl$path').replace(queryParameters: q);
  }

  /// 附加鉴权请求头（H-6：密钥经请求头传递，不进 URL）。
  Map<String, String> _withAuth(Map<String, String> headers) {
    if (apiKey.isEmpty) return headers;
    return {...headers, 'X-Api-Key': apiKey};
  }

  /// 发送请求并解析统一响应体，返回 data 字段。
  ///
  /// [timeout] 覆盖默认请求超时（大文件压缩 / 传输等长耗时操作使用）。
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryOnce = true,
    Duration? timeout,
  }) async {
    final uri = _uri(path, query);
    final base = body != null
        ? _headers
        : const {'X-Requested-With': 'XMLHttpRequest'};
    final headers = _withAuth(base);
    HttpFfiResponse resp;
    try {
      resp = await HttpFfiService.instance.request(
        method: method,
        url: uri.toString(),
        headers: headers,
        body: body == null ? null : utf8.encode(jsonEncode(body)),
        timeout: timeout ?? this.timeout,
      );
    } on HttpFfiException catch (e) {
      if (e.message.contains('超时')) {
        throw NodeApiException(0, '连接节点 $baseUrl 超时');
      }
      throw NodeApiException(0, '无法连接到节点 $baseUrl，请检查地址与网络 (${e.message})');
    }

    if (resp.statusCode == 401 && retryOnce && apiKey.isEmpty) {
      throw NodeApiException(401, '节点需要 API 密钥');
    }
    if (resp.statusCode >= 400) {
      throw NodeApiException(
        resp.statusCode,
        'HTTP ${resp.statusCode}: ${resp.body}',
      );
    }

    final decoded = _decode(resp);
    final status = (decoded['status'] as num?)?.toInt() ?? 500;
    if (status != 200) {
      final data = decoded['data'];
      final message = data is String ? data : '节点返回错误（status $status）';
      throw NodeApiException(status, message);
    }
    return decoded['data'];
  }

  /// 解码响应体，兼容 UTF-8 与 GBK 等编码。
  dynamic _decode(HttpFfiResponse resp) {
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
    final data =
        await _request(
              'GET',
              '/api/service/remote_service_instances',
              query: {
                'daemonId': daemonId,
                'page': '$page',
                'page_size': '$pageSize',
                'instance_name': name ?? '',
                'status': status ?? '',
              },
            )
            as Map<String, dynamic>? ??
        {};
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
    final data =
        await _request(
              'POST',
              '/api/instance',
              query: {'daemonId': daemonId},
              body: config,
            )
            as Map<String, dynamic>?;
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
    await _request('GET', path, query: {'uuid': uuid, 'daemonId': daemonId});
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
  ///
  /// [source] 为要生成的压缩包路径（实例内绝对路径），[targets] 为被压缩
  /// 的路径列表。压缩大目录可能耗时较长，可通过 [timeout] 放大超时。
  Future<void> compress({
    required String daemonId,
    required String uuid,
    required String source,
    required List<String> targets,
    Duration? timeout,
  }) async {
    await _request(
      'POST',
      '/api/files/compress',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {'type': 1, 'code': 'utf-8', 'source': source, 'targets': targets},
      timeout: timeout ?? this.timeout,
    );
  }

  /// 解压（POST /api/files/compress, type=2）。
  ///
  /// 解压大压缩包可能耗时较长，可通过 [timeout] 放大超时。
  Future<void> unzip({
    required String daemonId,
    required String uuid,
    required String source,
    required String dest,
    Duration? timeout,
  }) async {
    await _request(
      'POST',
      '/api/files/compress',
      query: {'daemonId': daemonId, 'uuid': uuid},
      body: {
        'type': 2,
        'code': 'utf-8',
        'source': source,
        'targets': [dest],
      },
      timeout: timeout ?? this.timeout,
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
    Duration? timeout,
  }) async {
    final data =
        await _request(
              'POST',
              '/api/files/download',
              query: {
                'daemonId': daemonId,
                'uuid': uuid,
                'file_name': fileName,
              },
              timeout: timeout ?? this.timeout,
            )
            as Map<String, dynamic>?;
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
    Duration? timeout,
  }) async {
    final data =
        await _request(
              'POST',
              '/api/files/upload',
              query: {
                'daemonId': daemonId,
                'uuid': uuid,
                'upload_dir': uploadDir,
              },
              timeout: timeout ?? this.timeout,
            )
            as Map<String, dynamic>?;
    return UploadTicket(
      password: data?['password'] as String? ?? '',
      addr: data?['addr'] as String? ?? '',
      uploadDir: uploadDir,
    );
  }

  /// 直连下载文件字节流（GET /download/{password}/...）。
  ///
  /// 注意：大文件请改用 [directDownloadToFile]（Rust 下载器流式写盘）。
  Future<List<int>> directDownload(
    DownloadTicket ticket, {
    Duration? timeout,
  }) async {
    final resp = await HttpFfiService.instance.get(
      ticket.url,
      timeout: timeout ?? this.timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '下载失败（HTTP ${resp.statusCode}）');
    }
    return resp.bodyBytes;
  }

  /// 直连下载并流式写入本地文件（复用 Rust 下载器，适合大文件）。
  ///
  /// [onProgress] 下载进度回调（字节）；返回本地文件路径。
  Future<String> directDownloadToFile(
    DownloadTicket ticket,
    String localPath,
    void Function(int downloaded, int total) onProgress, {
    int? threads,
  }) async {
    return Downloader().downloadFile(
      ticket.url,
      localPath,
      (p) => onProgress(p.downloadedBytes, p.totalBytes),
      threads: threads,
    );
  }

  /// 直连上传文件（POST /upload/{password}，multipart 字段名 file）。
  ///
  /// multipart 请求体在 Dart 侧按 RFC 2046 手工构造，
  /// 实际网络传输由 Rust http_client 负责。
  Future<void> directUpload({
    required UploadTicket ticket,
    required String localPath,
    Duration? timeout,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw NodeApiException(0, '本地文件不存在: $localPath');
    }
    final boundary = 'IriX${DateTime.now().microsecondsSinceEpoch}';
    final bytes = await file.readAsBytes();
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="${p.basename(localPath)}"\r\n'
          'Content-Type: application/octet-stream\r\n'
          '\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final resp = await HttpFfiService.instance.post(
      ticket.url,
      headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
      body: body.takeBytes(),
      timeout: timeout ?? this.timeout,
    );
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
      body: {
        'username': username,
        'password': password,
        'permission': permission,
      },
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

  // ==================== 容器环境（irix-node 全功能，见 docs/container-support.md §3）====================

  /// 容器运行时信息（GET /api/container/info）。
  ///
  /// 用于能力探测：返回 `{runtime, platform, version, available}`。
  /// 节点不支持时（MCSM 面板）抛 [NodeApiException]（404 等），由调用方回退。
  Future<Map<String, dynamic>?> containerInfo() async {
    final data = await _request('GET', '/api/container/info');
    return data is Map<String, dynamic> ? data : null;
  }

  /// 容器列表（GET /api/container/ps）。
  Future<List<Map<String, dynamic>>> containerPs({bool all = true}) async {
    final data = await _request(
      'GET',
      '/api/container/ps',
      query: {'all': all ? '1' : '0'},
    );
    return _listOfMaps(data);
  }

  /// 创建容器（POST /api/container/create）。
  Future<void> containerCreate(Map<String, dynamic> config) async {
    await _request('POST', '/api/container/create', body: config);
  }

  /// 容器操作（POST /api/container/{id}/start|stop|restart|kill）。
  Future<void> containerAction(String id, String action) async {
    await _request('POST', '/api/container/$id/$action');
  }

  /// 删除容器（DELETE /api/container/{id}）。
  Future<void> containerRemove(String id, {bool force = false}) async {
    await _request(
      'DELETE',
      '/api/container/$id',
      query: {'force': force ? '1' : '0'},
    );
  }

  /// 容器日志（GET /api/container/{id}/logs）。
  Future<String> containerLogs(String id, {int? tail}) async {
    final data = await _request(
      'GET',
      '/api/container/$id/logs',
      query: {if (tail != null) 'tail': '$tail'},
    );
    return (data as String?) ?? '';
  }

  /// 容器内执行命令（POST /api/container/{id}/exec）。
  Future<void> containerExec(String id, String command) async {
    await _request(
      'POST',
      '/api/container/$id/exec',
      body: {'command': command},
    );
  }

  /// 容器统计（GET /api/container/{id}/stats）。
  Future<Map<String, dynamic>?> containerStats(String id) async {
    final data = await _request('GET', '/api/container/$id/stats');
    return data is Map<String, dynamic> ? data : null;
  }

  /// 镜像列表（GET /api/image/list）。
  Future<List<Map<String, dynamic>>> imageList() async {
    final data = await _request('GET', '/api/image/list');
    return _listOfMaps(data);
  }

  /// 拉取镜像（POST /api/image/pull）。
  Future<void> imagePull(String name) async {
    await _request('POST', '/api/image/pull', body: {'name': name});
  }

  /// 构建镜像（POST /api/image/build），返回任务 id。
  Future<String> imageBuild({
    required String dockerfile,
    required String name,
    required String tag,
  }) async {
    final data = await _request(
      'POST',
      '/api/image/build',
      body: {'dockerfile': dockerfile, 'name': name, 'tag': tag},
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// 构建进度（GET /api/image/build-progress）。
  /// 返回 `{status: building|done|failed, log: [...], image: "name:tag"}`。
  Future<Map<String, dynamic>?> imageBuildProgress(String jobId) async {
    final data = await _request(
      'GET',
      '/api/image/build-progress',
      query: {'jobId': jobId},
    );
    return data is Map<String, dynamic> ? data : null;
  }

  /// 删除镜像（DELETE /api/image/{name}）。
  Future<void> imageRemove(String name) async {
    await _request('DELETE', '/api/image/${Uri.encodeComponent(name)}');
  }

  /// 卷列表（GET /api/volume/list）。
  Future<List<Map<String, dynamic>>> volumeList() async {
    final data = await _request('GET', '/api/volume/list');
    return _listOfMaps(data);
  }

  /// 删除卷（DELETE /api/volume/{name}）。
  Future<void> volumeRemove(String name) async {
    await _request('DELETE', '/api/volume/${Uri.encodeComponent(name)}');
  }

  /// 网络列表（GET /api/network/list）。
  Future<List<Map<String, dynamic>>> networkList() async {
    final data = await _request('GET', '/api/network/list');
    return _listOfMaps(data);
  }

  // ==================== Bastille（irix-node,FreeBSD）====================

  /// 已 bootstrap 的发行版列表（GET /api/bastille/releases）。
  Future<List<Map<String, dynamic>>> bastilleReleases() async {
    final data = await _request('GET', '/api/bastille/releases');
    return _listOfMaps(data);
  }

  /// bootstrap 发行版（POST /api/bastille/bootstrap），返回任务 id。
  Future<String> bastilleBootstrap(String release) async {
    final data = await _request(
      'POST',
      '/api/bastille/bootstrap',
      body: {'release': release},
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// jail 列表（GET /api/bastille/jails）。
  Future<List<Map<String, dynamic>>> bastilleJails() async {
    final data = await _request('GET', '/api/bastille/jails');
    return _listOfMaps(data);
  }

  /// 创建 jail（POST /api/bastille/jails/create）。
  Future<void> bastilleJailCreate(Map<String, dynamic> config) async {
    await _request('POST', '/api/bastille/jails/create', body: config);
  }

  /// jail 操作（POST /api/bastille/jails/{name}/start|stop|restart|destroy）。
  ///
  /// [force] 仅对 destroy 有效：服务端附加 `-a`（`bastille destroy -a`），
  /// 用于摧毁运行中的 jail。
  Future<void> bastilleJailAction(
    String name,
    String action, {
    bool force = false,
  }) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/$action',
      query: {if (force) 'force': '1'},
    );
  }

  /// jail 日志（GET /api/bastille/jails/{name}/console）。
  Future<String> bastilleJailConsole(String name, {int? tail}) async {
    final data = await _request(
      'GET',
      '/api/bastille/jails/$name/console',
      query: {if (tail != null) 'tail': '$tail'},
    );
    return (data as String?) ?? '';
  }

  /// jail 内执行命令（POST /api/bastille/jails/{name}/cmd）。
  Future<void> bastilleJailCmd(String name, String command) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/cmd',
      body: {'command': command},
    );
  }

  /// 模板列表（GET /api/bastille/templates）。
  Future<List<Map<String, dynamic>>> bastilleTemplates() async {
    final data = await _request('GET', '/api/bastille/templates');
    return _listOfMaps(data);
  }

  /// 应用模板（POST /api/bastille/templates/apply）。
  Future<void> bastilleTemplateApply({
    required String jail,
    required String template,
    Map<String, String> args = const {},
  }) async {
    await _request(
      'POST',
      '/api/bastille/templates/apply',
      body: {'jail': jail, 'template': template, 'args': args},
    );
  }

  /// 端口转发（POST /api/bastille/rdr）。
  Future<void> bastilleRdr({
    required String jail,
    required String proto,
    required int hostPort,
    required int jailPort,
  }) async {
    await _request(
      'POST',
      '/api/bastille/rdr',
      body: {
        'jail': jail,
        'proto': proto,
        'hostPort': hostPort,
        'jailPort': jailPort,
      },
    );
  }

  /// 删除端口转发（DELETE /api/bastille/rdr）。
  Future<void> bastilleRdrRemove({
    required String jail,
    required String proto,
    required int hostPort,
    required int jailPort,
  }) async {
    await _request(
      'DELETE',
      '/api/bastille/rdr',
      body: {
        'jail': jail,
        'proto': proto,
        'hostPort': hostPort,
        'jailPort': jailPort,
      },
    );
  }

  /// 端口转发规则列表（GET /api/bastille/rdr）。
  /// [jail] 非空时仅返回该 jail 的规则。
  Future<List<Map<String, dynamic>>> bastilleRdrList({String? jail}) async {
    final data = await _request(
      'GET',
      '/api/bastille/rdr',
      query: {if (jail != null && jail.isNotEmpty) 'jail': jail},
    );
    return _listOfMaps(data);
  }

  /// 环境初始化（POST /api/bastille/setup，`bastille setup`）。
  ///
  /// 返回 `{ok, detail?, checked?}`；[config] 见 BastilleSetupRequest.toJson。
  Future<Map<String, dynamic>?> bastilleSetup(
    Map<String, dynamic> config,
  ) async {
    final data = await _request('POST', '/api/bastille/setup', body: config);
    return data is Map<String, dynamic> ? data : null;
  }

  /// 克隆 jail（POST /api/bastille/jails/{name}/clone，`bastille clone`）。
  Future<void> bastilleJailClone({
    required String jail,
    required String newName,
    String? ip,
  }) async {
    await _request(
      'POST',
      '/api/bastille/jails/$jail/clone',
      body: {'newName': newName, if (ip != null && ip.isNotEmpty) 'ip': ip},
    );
  }

  /// 导出 jail 为归档（POST /api/bastille/jails/{name}/export，`bastille export`）。
  /// 返回宿主机上的归档路径。
  Future<String> bastilleJailExport(String name) async {
    final data = await _request('POST', '/api/bastille/jails/$name/export');
    if (data is Map<String, dynamic>) {
      return data['path'] as String? ?? data['file'] as String? ?? '';
    }
    return data?.toString() ?? '';
  }

  /// 导入归档为 jail（POST /api/bastille/jails/import，`bastille import FILE [RELEASE]`）。
  /// [release] 指定导入到哪个发行版（可选）；[force] 跳过校验和验证（-f）。
  /// 返回新建 jail 名。
  Future<String> bastilleJailImport({
    required String file,
    String? release,
    bool force = false,
  }) async {
    final data = await _request(
      'POST',
      '/api/bastille/jails/import',
      body: {
        'file': file,
        if (release != null && release.isNotEmpty) 'release': release,
        if (force) 'force': true,
      },
    );
    return (data is Map ? data['name'] : null) as String? ?? '';
  }

  /// 设置 jail 资源限制（POST /api/bastille/jails/{name}/limits）。
  ///
  /// 服务端映射：memoryMb → rctl memoryuse；cpus → cpuset；
  /// diskMb → ZFS 数据集配额。
  Future<void> bastilleJailLimits(
    String name, {
    int? memoryMb,
    int? cpus,
    int? diskMb,
  }) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/limits',
      body: {'memoryMb': ?memoryMb, 'cpus': ?cpus, 'diskMb': ?diskMb},
    );
  }

  /// jail 内软件包管理（POST /api/bastille/jails/{name}/pkg，`bastille pkg`）。
  ///
  /// [action] 为 pkg 子命令（install / delete / update / upgrade / autoremove 等），
  /// [packages] 为包名列表（install/delete 时必填）。返回命令输出（尾部）。
  Future<String> bastilleJailPkg(
    String name, {
    required String action,
    List<String> packages = const [],
  }) async {
    final data = await _request(
      'POST',
      '/api/bastille/jails/$name/pkg',
      body: {'action': action, 'packages': packages},
      timeout: const Duration(minutes: 10), // pkg 安装可能较慢
    );
    if (data is Map<String, dynamic>) {
      return data['output'] as String? ?? '';
    }
    return data?.toString() ?? '';
  }

  /// jail 内执行命令并返回输出（POST /api/bastille/jails/{name}/cmd）。
  ///
  /// 与 [bastilleJailCmd] 同一端点，区别是本方法把 `data` 解析为输出文本返回
  /// （用于 `java -version`、`pgrep` 等需要看结果的命令）。
  Future<String> bastilleJailCmdOutput(String name, String command) async {
    final data = await _request(
      'POST',
      '/api/bastille/jails/$name/cmd',
      body: {'command': command},
      timeout: const Duration(minutes: 2),
    );
    if (data is Map<String, dynamic>) {
      return data['output'] as String? ?? '';
    }
    return data?.toString() ?? '';
  }

  /// jail 挂载列表（GET /api/bastille/jails/{name}/mounts）。
  ///
  /// 条目：`{src?, dst, fstype: nullfs|procfs|devfs, options?, permanent}`。
  Future<List<Map<String, dynamic>>> bastilleJailMounts(String name) async {
    final data = await _request('GET', '/api/bastille/jails/$name/mounts');
    return _listOfMaps(data);
  }

  /// 添加挂载（POST /api/bastille/jails/{name}/mounts）。
  ///
  /// [fstype] 为 `nullfs`（宿主机路径挂载，`bastille mount`）或 `procfs`
  /// （写 fstab + 挂载，Java 运行环境需要 /proc 时使用）。
  Future<void> bastilleJailMountAdd(
    String name, {
    String? src,
    required String dst,
    required String fstype,
    String? options,
  }) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/mounts',
      body: {
        if (src != null && src.isNotEmpty) 'src': src,
        'dst': dst,
        'fstype': fstype,
        if (options != null && options.isNotEmpty) 'options': options,
      },
    );
  }

  /// 卸载（DELETE /api/bastille/jails/{name}/mounts?dst=...）。
  Future<void> bastilleJailMountRemove(String name, String dst) async {
    await _request(
      'DELETE',
      '/api/bastille/jails/$name/mounts',
      query: {'dst': dst},
    );
  }

  /// 读取 jail 配置（GET /api/bastille/jails/{name}/config，jail.conf 属性）。
  ///
  /// 返回 `{key: value, ...}`，如 `ip4.addr` / `hostname` / `exec.start`。
  Future<Map<String, dynamic>> bastilleJailConfig(String name) async {
    final data = await _request('GET', '/api/bastille/jails/$name/config');
    if (data is Map<String, dynamic>) return data;
    return {};
  }

  /// 设置 jail 配置项（POST /api/bastille/jails/{name}/config，
  /// `bastille config <jail> <key> <value>`）。
  Future<void> bastilleJailConfigSet(
    String name,
    String key,
    String value,
  ) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/config',
      body: {'key': key, 'value': value},
    );
  }

  /// 删除 jail 配置项（DELETE /api/bastille/jails/{name}/config?key=...）。
  Future<void> bastilleJailConfigRemove(String name, String key) async {
    await _request(
      'DELETE',
      '/api/bastille/jails/$name/config',
      query: {'key': key},
    );
  }

  /// 在 jail 内启动运行会话（POST /api/bastille/jails/{name}/run）。
  ///
  /// 后台执行 `jexec <name> sh -c "cd <cwd> && exec <command>"`，输出保留在
  /// 节点上的会话缓冲/日志文件；[watch] 为 true 时进程退出后节点自动停止 jail
  /// （「容器内进程退出即停止容器」开关）。返回会话 id。
  Future<String> bastilleJailRun(
    String name, {
    required String command,
    String? cwd,
    bool watch = false,
  }) async {
    final data = await _request(
      'POST',
      '/api/bastille/jails/$name/run',
      body: {
        'command': command,
        if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
        if (watch) 'watch': true,
      },
    );
    if (data is Map<String, dynamic>) {
      return data['sessionId'] as String? ?? '';
    }
    return data?.toString() ?? '';
  }

  /// 运行会话状态（GET /api/bastille/jails/{name}/run/{session}）。
  ///
  /// [tail] 指定返回最后 N 行（首次拉取用）；[since] 为字节偏移，只返回该
  /// 偏移之后的新增输出（增量轮询用）。返回
  /// `{running, exitCode?, offset, log}`。
  Future<Map<String, dynamic>?> bastilleJailRunStatus(
    String name,
    String sessionId, {
    int? tail,
    int? since,
  }) async {
    final data = await _request(
      'GET',
      '/api/bastille/jails/$name/run/$sessionId',
      query: {
        if (tail != null) 'tail': '$tail',
        if (since != null) 'since': '$since',
      },
    );
    return data is Map<String, dynamic> ? data : null;
  }

  /// 向运行会话写 stdin（POST /api/bastille/jails/{name}/run/{session}/stdin）。
  Future<void> bastilleJailRunStdin(
    String name,
    String sessionId,
    String input,
  ) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/run/$sessionId/stdin',
      body: {'input': input},
    );
  }

  /// 终止运行会话中的进程（POST /api/bastille/jails/{name}/run/{session}/stop）。
  Future<void> bastilleJailRunStop(String name, String sessionId) async {
    await _request('POST', '/api/bastille/jails/$name/run/$sessionId/stop');
  }

  /// 清理运行会话（DELETE /api/bastille/jails/{name}/run/{session}）。
  Future<void> bastilleJailRunCleanup(String name, String sessionId) async {
    await _request('DELETE', '/api/bastille/jails/$name/run/$sessionId');
  }

  /// 克隆容器（POST /api/container/{id}/clone）。
  Future<void> containerClone(String id, String newName) async {
    await _request('POST', '/api/container/$id/clone', body: {'name': newName});
  }

  /// 更新容器资源限制（POST /api/container/{id}/limits）。
  Future<void> containerUpdateLimits(
    String id, {
    int? memoryMb,
    int? cpus,
  }) async {
    await _request(
      'POST',
      '/api/container/$id/limits',
      body: {'memoryMb': ?memoryMb, 'cpus': ?cpus},
    );
  }

  // ==================== 节点级归档（编排迁移用，见 irix-node-container-api.md §4.8）====================

  /// 压缩节点上的任意路径为归档（POST /api/container/archive）。
  /// 返回节点上归档文件的完整路径。
  Future<String> nodeArchive({required String path, String? archive}) async {
    final data = await _request(
      'POST',
      '/api/container/archive',
      body: {
        'path': path,
        if (archive != null && archive.isNotEmpty) 'archive': archive,
      },
    );
    if (data is Map<String, dynamic>) {
      return data['path'] as String? ?? data['archivePath'] as String? ?? '';
    }
    return data?.toString() ?? '';
  }

  /// 下载节点归档的原始字节（GET /api/container/archive?file=...，二进制响应）。
  Future<List<int>> nodeArchiveDownload(String archive) async {
    final uri = _uri('/api/container/archive', {'file': archive});
    final resp = await HttpFfiService.instance.get(
      uri.toString(),
      timeout: timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(
        resp.statusCode,
        '归档下载失败（HTTP ${resp.statusCode}）',
      );
    }
    return resp.bodyBytes;
  }

  /// 上传归档到节点（POST /api/container/archive/upload，multipart 字段 file）。
  Future<void> nodeArchiveUpload(String fileName, List<int> bytes) async {
    final boundary = 'IriX${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
          'Content-Type: application/octet-stream\r\n'
          '\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final resp = await HttpFfiService.instance.post(
      _uri('/api/container/archive/upload').toString(),
      headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
      body: body.takeBytes(),
      timeout: timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(
        resp.statusCode,
        '归档上传失败（HTTP ${resp.statusCode}）',
      );
    }
  }

  /// 在节点上解压归档到目标目录（POST /api/container/archive/restore）。
  Future<void> nodeArchiveRestore({
    required String file,
    required String destPath,
  }) async {
    await _request(
      'POST',
      '/api/container/archive/restore',
      body: {'file': file, 'destPath': destPath},
    );
  }
}

/// 实例操作类型。
enum RemoteAction { start, stop, restart, kill }
