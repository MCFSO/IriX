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
import '../models/node_ops.dart';
import '../models/remote.dart';
import '../models/vault.dart';
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

  /// Vault 会话令牌（NODE_API.md §9 数据面门禁）。
  ///
  /// 非空时所有请求自动附带 `X-Vault-Token` 请求头（保险库锁定/未初始化/
  /// 迁移中时服务端返回 403）。由调用方在解锁 / 恢复 / 初始化后写入；
  /// 节点不支持保险库时保持为空，不影响其他请求。
  ///
  /// 注意：多数调用方每次请求新建 [NodeApiClient.of] 客户端，会话令牌
  /// 不会跨调用点保留 —— 保险库流程请持有同一个客户端实例。
  String vaultToken = '';

  /// 账户会话令牌（账户认证接口，见 accounts_handlers.go）。
  ///
  /// 非空时所有请求自动附带 `X-Auth-Token` 请求头。与 [apiKey] 通道并存：
  /// apikey 直通 root 管理员，账户会话令牌走按端点开关鉴权的普通账户。
  /// [accountLogin] 成功后由调用方写入；未启用账户系统的节点保持为空。
  String authToken = '';

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
  ///
  /// [vaultToken] 非空时覆盖 [vaultToken] 字段（初始化 / 恢复等需要以
  /// initToken、恢复会话令牌发请求的场景），否则使用字段当前值。
  Map<String, String> _withAuth(
    Map<String, String> headers, {
    String? vaultToken,
  }) {
    var result = headers;
    if (apiKey.isNotEmpty) {
      result = {...result, 'X-Api-Key': apiKey};
    }
    if (authToken.isNotEmpty) {
      result = {...result, 'X-Auth-Token': authToken};
    }
    final token = vaultToken ?? this.vaultToken;
    if (token.isNotEmpty) {
      result = {...result, 'X-Vault-Token': token};
    }
    return result;
  }

  /// 发送请求并解析统一响应体，返回 data 字段。
  ///
  /// [timeout] 覆盖默认请求超时（大文件压缩 / 传输等长耗时操作使用）；
  /// [vaultToken] 覆盖 [vaultToken] 字段（一次性场景：initToken /
  /// 恢复会话令牌）。
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryOnce = true,
    Duration? timeout,
    String? vaultToken,
  }) async {
    final uri = _uri(path, query);
    final base = body != null
        ? _headers
        : const {'X-Requested-With': 'XMLHttpRequest'};
    final headers = _withAuth(base, vaultToken: vaultToken);
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

  /// 获取实例插件 / Mod 元数据（GET /api/instance/plugins）。
  ///
  /// 节点端解析 jar 内 plugin.yml / paper-plugin.yml / fabric.mod.json /
  /// META-INF/mods.toml（见 docs/irix-node-local-parity.md §4.4）；
  /// 节点不支持时抛 [NodeApiException]（404 等），由调用方回退到
  /// 文件列表展示。
  Future<List<RemotePluginMeta>> instancePlugins({
    required String uuid,
    required String daemonId,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/plugins',
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
    final list = <RemotePluginMeta>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['items'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          list.add(RemotePluginMeta.fromJson(item));
        }
      }
    } else if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          list.add(RemotePluginMeta.fromJson(item));
        }
      }
    }
    return list;
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
  /// [permanent] 为 true 时同时写入 fstab（jail 启动自动挂载，
  /// 重启不丢失）——nullfs 也适用。
  Future<void> bastilleJailMountAdd(
    String name, {
    String? src,
    required String dst,
    required String fstype,
    String? options,
    bool permanent = false,
  }) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/mounts',
      body: {
        if (src != null && src.isNotEmpty) 'src': src,
        'dst': dst,
        'fstype': fstype,
        if (options != null && options.isNotEmpty) 'options': options,
        if (permanent) 'permanent': true,
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

  // ==================== Jail 文件管理（Bastille，见 irix-node-container-api.md §4.14）====================

  /// 列出 jail 内目录（GET /api/bastille/jails/{name}/files）。
  ///
  /// [path] 为 jail 内绝对路径（如 `/data`）；返回
  /// `{ items: [{name, path, isDir, size, mtime}], total }`。
  Future<Map<String, dynamic>> bastilleJailFiles(
    String name, {
    String path = '/',
    int page = 1,
    int pageSize = 200,
  }) async {
    final data = await _request(
      'GET',
      '/api/bastille/jails/$name/files',
      query: {'path': path, 'page': '$page', 'page_size': '$pageSize'},
    );
    if (data is Map<String, dynamic>) return data;
    if (data is List) return {'items': data, 'total': data.length};
    return {};
  }

  /// 读取 jail 内文本文件（GET /api/bastille/jails/{name}/files/content）。
  Future<String> bastilleJailFileContent(String name, String path) async {
    final data = await _request(
      'GET',
      '/api/bastille/jails/$name/files/content',
      query: {'path': path},
    );
    return (data as String?) ?? '';
  }

  /// 写入 jail 内文本文件（PUT /api/bastille/jails/{name}/files/content）。
  Future<void> writeBastilleJailFile(
    String name,
    String path,
    String content,
  ) async {
    await _request(
      'PUT',
      '/api/bastille/jails/$name/files/content',
      body: {'path': path, 'content': content},
    );
  }

  /// 删除 jail 内文件 / 目录（DELETE /api/bastille/jails/{name}/files，
  /// 目录递归删除）。
  Future<void> deleteBastilleJailFile(String name, String path) async {
    await _request(
      'DELETE',
      '/api/bastille/jails/$name/files',
      query: {'path': path},
    );
  }

  /// 新建目录（POST /api/bastille/jails/{name}/files/mkdir）。
  Future<void> bastilleJailMkdir(String name, String path) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/files/mkdir',
      body: {'path': path},
    );
  }

  /// 新建空文件（POST /api/bastille/jails/{name}/files/touch）。
  Future<void> bastilleJailTouch(String name, String path) async {
    await _request(
      'POST',
      '/api/bastille/jails/$name/files/touch',
      body: {'path': path},
    );
  }

  /// 上传本地文件到 jail 内目录（POST /api/bastille/jails/{name}/files/upload，
  /// multipart 字段名 file）。
  ///
  /// 与直连上传同款手工 multipart 构造，网络传输由 Rust http_client 负责。
  Future<void> bastilleJailFileUpload(
    String name,
    String dir,
    String localPath,
  ) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw NodeApiException(0, '本地文件不存在: $localPath');
    }
    final boundary = 'IriX${DateTime.now().microsecondsSinceEpoch}';
    final fileName = p.basename(localPath);
    final bytes = await file.readAsBytes();
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
      _uri('/api/bastille/jails/$name/files/upload', {'path': dir}).toString(),
      headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
      body: body.takeBytes(),
      timeout: timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '上传失败（HTTP ${resp.statusCode}）');
    }
  }

  /// 下载 jail 内文件原始字节（GET /api/bastille/jails/{name}/files/download，
  /// 二进制响应）。
  ///
  /// 注意：大文件请先落临时文件再写目标路径；本方法一次性读入内存。
  Future<List<int>> bastilleJailFileDownload(String name, String path) async {
    final uri = _uri('/api/bastille/jails/$name/files/download', {
      'path': path,
    });
    final resp = await HttpFfiService.instance.get(
      uri.toString(),
      timeout: timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '下载失败（HTTP ${resp.statusCode}）');
    }
    return resp.bodyBytes;
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

  // ==================== 加密保险库 Vault（irix-node，见 NODE_API.md §9）====================

  /// 获取保险库状态（GET /api/vault/status）。
  ///
  /// 节点未启用 vault（`-vault` 未开）时返回 `enabled: false`。
  Future<VaultStatus> vaultStatus() async {
    final data = await _request('GET', '/api/vault/status');
    return VaultStatus.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 申请签名挑战（POST /api/vault/challenge）。
  ///
  /// [purpose] 为 `unlock`（解锁签名）、`cert-bind`（绑定 / 换绑证书签名）
  /// 或 `recovery`（恢复流程，docs/vault-design.md §10）；挑战一次性使用
  /// （首次使用即作废），5 分钟有效。签名由客户端本地完成
  /// （见 `vault_crypto.dart` 的 [VaultPrivateKey] / signChallenge，
  /// 前缀按 purpose 区分，与 [VaultChallengePurpose] 对应）。
  Future<VaultChallenge> vaultChallenge({required String purpose}) async {
    final data = await _request(
      'POST',
      '/api/vault/challenge',
      body: {'purpose': purpose},
    );
    return VaultChallenge.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 解锁保险库（POST /api/vault/unlock）。
  ///
  /// [signature] 为客户端对 `IRIX-VAULT-UNLOCK:1: + challenge` 的签名
  /// （RSA PKCS#1 v1.5 + SHA-256 或 ECDSA ASN.1 DER，base64 无填充，
  /// 见 vault_crypto.dart 的 [VaultChallengePurpose.unlock]），
  /// 私钥永不上送；未绑定证书时可省略。成功后请把返回的
  /// `sessionToken` 写入 [vaultToken] 字段，后续数据面请求自动携带。
  /// [newPassword] 用于密码过期（status.passwordExpired / forceExpire）
  /// 时同请求完成解锁 + 改密（rewrap，docs/vault-design.md A3/D15）。
  Future<VaultSession> vaultUnlock({
    required String user,
    required String password,
    String? totp,
    required String challengeId,
    String? signature,
    String? newPassword,
  }) async {
    final data = await _request(
      'POST',
      '/api/vault/unlock',
      body: {
        'user': user,
        'password': password,
        if (totp != null && totp.isNotEmpty) 'totp': totp,
        'challengeId': challengeId,
        if (signature != null && signature.isNotEmpty) 'signature': signature,
        if (newPassword != null && newPassword.isNotEmpty)
          'newPassword': newPassword,
      },
    );
    return VaultSession.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 立即锁定（POST /api/vault/lock，需 `X-Vault-Token`）。
  Future<void> vaultLock({String? vaultToken}) async {
    await _request('POST', '/api/vault/lock', vaultToken: vaultToken);
  }

  /// 恢复会话（POST /api/vault/recovery）→ 5 分钟恢复会话。
  ///
  /// 请求体按 docs/vault-design.md §10：`{ recoveryToken, newPassword?,
  /// newTotp?, newCert? }` —— 可同请求完成重设密码 / 重绑 TOTP / 换绑
  /// 证书；[user] 为 NODE_API.md §9.1 的兼容可选字段。
  ///
  /// 返回的 `sessionToken` 仅用于改密 / 重绑 TOTP / 换绑证书，
  /// 数据面请求不接受恢复会话。
  Future<VaultSession> vaultRecovery({
    required String recoveryToken,
    String? user,
    String? newPassword,
    String? newTotp,
    String? newCert,
  }) async {
    final data = await _request(
      'POST',
      '/api/vault/recovery',
      body: {
        'recoveryToken': recoveryToken,
        if (user != null && user.isNotEmpty) 'user': user,
        if (newPassword != null && newPassword.isNotEmpty)
          'newPassword': newPassword,
        if (newTotp != null && newTotp.isNotEmpty) 'newTotp': newTotp,
        if (newCert != null && newCert.isNotEmpty) 'newCert': newCert,
      },
    );
    return VaultSession.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 初始化保险库（POST /api/vault/init，仅未初始化时可用）。
  ///
  /// 返回的 [VaultInitResult] 含 TOTP 密钥与恢复令牌（recoveryToken
  /// 仅显示一次，客户端须提示用户保存）。后续 TOTP 校验 / 证书绑定
  /// 以 `initToken` 作为 `X-Vault-Token` 发送。
  Future<VaultInitResult> vaultInit({
    required String user,
    required String password,
  }) async {
    final data = await _request(
      'POST',
      '/api/vault/init',
      body: {'user': user, 'password': password},
    );
    return VaultInitResult.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 校验 TOTP 动态码（POST /api/vault/totp/verify）。
  ///
  /// [vaultToken] 传 initToken（初始化流程）或恢复 / 解锁会话令牌；
  /// 缺省使用 [vaultToken] 字段。
  Future<void> vaultTotpVerify(String code, {String? vaultToken}) async {
    await _request(
      'POST',
      '/api/vault/totp/verify',
      body: {'code': code},
      vaultToken: vaultToken,
    );
  }

  /// 重绑 TOTP（POST /api/vault/totp/reset，恢复 / 解锁会话）。
  ///
  /// 返回新的 TOTP 密钥（Base32 / otpauth URI），客户端应提示重新录入。
  Future<Map<String, dynamic>?> vaultTotpReset({String? vaultToken}) async {
    final data = await _request(
      'POST',
      '/api/vault/totp/reset',
      vaultToken: vaultToken,
    );
    return data is Map<String, dynamic> ? data : null;
  }

  /// 绑定证书（POST /api/vault/cert，SPKI 指纹绑定）。
  ///
  /// [certPem] 为标准 PEM 证书（P12 在客户端解析为 PEM，见
  /// `vault_crypto.dart` 的 importPkcs12 / importPem）；[signature] 为
  /// 对 challenge（purpose=`cert-bind`）的签名
  /// （[VaultChallengePurpose.certBind] 前缀）。证书绑定后解锁可仅凭
  /// 证书签名免密码 / 免 TOTP；换发证书（同钥）不破坏绑定（SPKI 指纹）。
  Future<void> vaultCert({
    required String certPem,
    required String challengeId,
    required String signature,
    String? vaultToken,
  }) async {
    await _request(
      'POST',
      '/api/vault/cert',
      body: {
        'certPem': certPem,
        'challengeId': challengeId,
        'signature': signature,
      },
      vaultToken: vaultToken,
    );
  }

  /// 修改密码（POST /api/vault/password）。
  ///
  /// 解锁会话需 [oldPassword]；恢复会话免旧密码。
  Future<void> vaultPassword({
    String? oldPassword,
    required String newPassword,
    String? vaultToken,
  }) async {
    await _request(
      'POST',
      '/api/vault/password',
      body: {
        if (oldPassword != null && oldPassword.isNotEmpty)
          'oldPassword': oldPassword,
        'newPassword': newPassword,
      },
      vaultToken: vaultToken,
    );
  }

  /// 用户列表（GET /api/vault/users）。
  Future<List<VaultUser>> vaultUsers({String? vaultToken}) async {
    final data = await _request(
      'GET',
      '/api/vault/users',
      vaultToken: vaultToken,
    );
    final list = <VaultUser>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          list.add(VaultUser.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 添加用户（POST /api/vault/user/add，恢复 / 解锁会话）。
  Future<void> vaultUserAdd({
    required String user,
    required String password,
    String? vaultToken,
  }) async {
    await _request(
      'POST',
      '/api/vault/user/add',
      body: {'user': user, 'password': password},
      vaultToken: vaultToken,
    );
  }

  /// 删除用户（POST /api/vault/user/remove；禁止删除最后一个用户）。
  Future<void> vaultUserRemove(String user, {String? vaultToken}) async {
    await _request(
      'POST',
      '/api/vault/user/remove',
      body: {'user': user},
      vaultToken: vaultToken,
    );
  }

  /// 启动两阶段迁移（POST /api/vault/migrate：instances.json +
  /// vaultFiles 文件树；幂等续跑）。
  Future<void> vaultMigrate({String? vaultToken}) async {
    await _request('POST', '/api/vault/migrate', vaultToken: vaultToken);
  }

  /// 迁移状态（GET /api/vault/migrate/status）。
  Future<VaultMigrateStatus> vaultMigrateStatus({String? vaultToken}) async {
    final data = await _request(
      'GET',
      '/api/vault/migrate/status',
      vaultToken: vaultToken,
    );
    return VaultMigrateStatus.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 生成加密备份包（POST /api/vault/backup）。
  ///
  /// 返回备份信息（路径 / 大小等，字段由服务端定义），下载走
  /// downloadTicket + 直连下载。
  Future<Map<String, dynamic>?> vaultBackup({String? vaultToken}) async {
    final data = await _request(
      'POST',
      '/api/vault/backup',
      vaultToken: vaultToken,
    );
    return data is Map<String, dynamic> ? data : null;
  }

  // ==================== 实例日志 / 指标（irix-node）====================

  /// 读取实例历史日志（GET /api/instance/logs，见 instance_logs.go）。
  ///
  /// [tail] 返回最后 N 行（默认 1000；显式 0 表示全部）；
  /// [since] 为 unix 毫秒，返回该时间点后追加的行（断线补发用）。
  Future<String> instanceLogs({
    required String uuid,
    required String daemonId,
    int? tail,
    int? since,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/logs',
      query: {
        'uuid': uuid,
        'daemonId': daemonId,
        if (tail != null) 'tail': '$tail',
        if (since != null) 'since': '$since',
      },
    );
    return (data as String?) ?? '';
  }

  /// 清空实例日志（DELETE /api/instance/logs，见 instance_logs.go）。
  Future<void> clearInstanceLogs({
    required String uuid,
    required String daemonId,
  }) async {
    await _request(
      'DELETE',
      '/api/instance/logs',
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
  }

  /// 实例实时运行指标（GET /api/instance/stats，见 instance_stats.go）。
  ///
  /// 返回 pid / CPU / 内存 / 网络 / 运行时长，以及解析出的 players /
  /// maxPlayers / tps（未解析时字段为 -1）。
  Future<InstanceStatsData> instanceStats({
    required String uuid,
    required String daemonId,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/stats',
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
    return InstanceStatsData.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 实例监控历史采样（GET /api/instance/metrics，见 instance_metrics.go）。
  ///
  /// 节点每 15s 采样一次运行中实例，环形保留 60 条（15 分钟）。
  /// [minutes] 默认 15，最大 60。返回采样列表。
  Future<List<MetricSample>> instanceMetrics({
    required String uuid,
    required String daemonId,
    int minutes = 15,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/metrics',
      query: {
        'uuid': uuid,
        'daemonId': daemonId,
        'minutes': '$minutes',
      },
    );
    final samples = <MetricSample>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['samples'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          samples.add(MetricSample.fromJson(item));
        }
      }
    }
    return samples;
  }

  /// AI 结构化日志查询（GET /api/instance/logs/query，见 instance_metrics.go）。
  ///
  /// 退化实现：tail 全文 + 关键词过滤。[keyword] 为空时返回最近 [maxLines] 行。
  /// 返回匹配行列表与总数。
  Future<Map<String, dynamic>> logsQuery({
    required String uuid,
    required String daemonId,
    String? keyword,
    int? maxLines,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/logs/query',
      query: {
        'uuid': uuid,
        'daemonId': daemonId,
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
        if (maxLines != null) 'maxLines': '$maxLines',
      },
    );
    return data is Map<String, dynamic> ? data : {};
  }

  // ==================== 实例导入（irix-node）====================

  /// 从节点侧目录导入创建实例（POST /api/instance/import，见 instance_import.go）。
  ///
  /// 节点校验目录存在 → 扫描服务端特征（*.jar / eula.txt / server.properties
  /// 等）→ 自动创建实例（cwd=该目录）。返回新实例 UUID。
  Future<String> importInstance({
    required String daemonId,
    required String path,
    String? nickname,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance/import',
      body: {
        'daemonId': daemonId,
        'path': path,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      },
    );
    return (data is Map ? data['instanceUuid'] : null) as String? ?? '';
  }

  // ==================== 实例快照 / 备份（irix-node）====================

  /// 创建实例快照（POST /api/instance/snapshot，见 backup.go）。
  ///
  /// 实例 cwd 打成 zip 存入节点备份区，任务化（[snapshotProgress] 轮询）。
  /// 返回任务 id。
  Future<String> instanceSnapshot({
    required String uuid,
    required String daemonId,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance/snapshot',
      body: {'uuid': uuid, 'daemonId': daemonId},
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// 快照 / 恢复任务进度（GET /api/instance/snapshot-progress，见 backup.go）。
  ///
  /// 字段对齐文档 §4.5：`status` / `percent` / `message` / `archivePath`。
  Future<NodeTaskProgress> snapshotProgress(String jobId) async {
    final data = await _request(
      'GET',
      '/api/instance/snapshot-progress',
      query: {'jobId': jobId},
    );
    return NodeTaskProgress.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 恢复实例快照（POST /api/instance/restore，见 backup.go）。
  ///
  /// 先自动停止实例 → 解压覆盖 cwd → 保持停止，任务化。返回任务 id。
  Future<String> instanceRestore({
    required String uuid,
    required String daemonId,
    required String archivePath,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance/restore',
      body: {'uuid': uuid, 'daemonId': daemonId, 'archivePath': archivePath},
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// 列出实例备份（GET /api/instance/backups，见 backup.go）。
  Future<List<BackupItem>> listBackups({
    required String uuid,
    required String daemonId,
  }) async {
    final data = await _request(
      'GET',
      '/api/instance/backups',
      query: {'uuid': uuid, 'daemonId': daemonId},
    );
    final list = <BackupItem>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['items'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          list.add(BackupItem.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 删除指定备份（DELETE /api/instance/backups，见 backup.go）。
  ///
  /// [paths] 为备份文件绝对路径列表（须位于实例备份区内）。
  Future<void> deleteBackups({
    required String uuid,
    required String daemonId,
    required List<String> paths,
  }) async {
    await _request(
      'DELETE',
      '/api/instance/backups',
      query: {'uuid': uuid, 'daemonId': daemonId},
      body: {'paths': paths},
    );
  }

  /// 申请备份下载票据（POST /api/instance/backups/download，见 backup.go）。
  ///
  /// 票据绑定单个备份文件，直连下载走 [DownloadTicket]。
  Future<DownloadTicket> backupDownloadTicket({
    required String uuid,
    required String path,
    Duration? timeout,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance/backups/download',
      query: {'uuid': uuid},
      body: {'path': path},
      timeout: timeout ?? this.timeout,
    );
    final map = data is Map<String, dynamic> ? data : {};
    return DownloadTicket(
      password: map['password'] as String? ?? '',
      addr: map['addr'] as String? ?? '',
      fileName: path.split('/').last,
    );
  }

  // ==================== 实例核心下载（irix-node）====================

  /// 下载服务端核心到实例根目录（POST /api/instance/download-core，见 core_download.go）。
  ///
  /// 节点直连下载核心 jar（客户端不中转字节），可选 [sha512] 流式校验，
  /// 完成后 rename 就位。任务化（[snapshotProgress] 同款进度轮询复用，
  /// 字段为 `status` / `percent` / `message` / `path`）。
  Future<String> downloadCore({
    required String uuid,
    required String url,
    required String fileName,
    String? sha512,
  }) async {
    final data = await _request(
      'POST',
      '/api/instance/download-core',
      body: {
        'uuid': uuid,
        'url': url,
        'fileName': fileName,
        if (sha512 != null && sha512.isNotEmpty) 'sha512': sha512,
      },
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// 核心下载任务进度（GET /api/instance/download-core-progress，见 core_download.go）。
  ///
  /// 字段对齐 snapshotProgress：`status` / `percent` / `message` / `path`。
  Future<NodeTaskProgress> coreDownloadProgress(String jobId) async {
    final data = await _request(
      'GET',
      '/api/instance/download-core-progress',
      query: {'jobId': jobId},
    );
    return NodeTaskProgress.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  // ==================== Java 运行时（irix-node）====================

  /// 检测节点上的全部 Java 运行时（GET /api/runtime/java，见 runtime.go）。
  ///
  /// [default] 为可用版本号最高的运行时（无可用时为 null）。
  Future<({JavaRuntime? defaultRuntime, List<JavaRuntime> all})>
      javaRuntimes() async {
    final data = await _request('GET', '/api/runtime/java');
    final all = <JavaRuntime>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['all'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          all.add(JavaRuntime.fromJson(item));
        }
      }
      final def = data['default'];
      final defaultRuntime =
          def is Map<String, dynamic> ? JavaRuntime.fromJson(def) : null;
      return (defaultRuntime: defaultRuntime, all: all);
    }
    return (defaultRuntime: null, all: all);
  }

  /// 安装指定大版本 JDK（POST /api/runtime/java/install，见 jdk_install.go）。
  ///
  /// 节点直连 Adoptium 下载并解压到 `{data}/jdk/jdk-<major>/`。返回任务 id。
  Future<String> installJava(int major) async {
    final data = await _request(
      'POST',
      '/api/runtime/java/install',
      body: {'major': major},
    );
    return (data is Map ? data['jobId'] : null) as String? ?? '';
  }

  /// JDK 安装进度（GET /api/runtime/java/install-progress，见 jdk_install.go）。
  Future<NodeTaskProgress> javaInstallProgress(String jobId) async {
    final data = await _request(
      'GET',
      '/api/runtime/java/install-progress',
      query: {'jobId': jobId},
    );
    return NodeTaskProgress.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 卸载指定版本 JDK（DELETE /api/runtime/java?major=，见 jdk_install.go）。
  Future<void> uninstallJava(int major) async {
    await _request(
      'DELETE',
      '/api/runtime/java',
      query: {'major': '$major'},
    );
  }

  // ==================== 实例级回收站（irix-node）====================

  /// 删除文件到回收站（POST /api/files/trash，见 trash.go）。
  ///
  /// [targets] 为实例内路径列表（相对 cwd）；节点不支持时调用方回退硬删除。
  Future<void> trashFiles({
    required String daemonId,
    required String uuid,
    required List<String> targets,
  }) async {
    await _request(
      'POST',
      '/api/files/trash',
      query: {'daemonId': daemonId},
      body: {'uuid': uuid, 'targets': targets},
    );
  }

  /// 列出回收站内容（GET /api/files/trash/list，见 trash.go）。
  Future<List<TrashItem>> trashList({
    required String daemonId,
    required String uuid,
  }) async {
    final data = await _request(
      'GET',
      '/api/files/trash/list',
      query: {'daemonId': daemonId, 'uuid': uuid},
    );
    final list = <TrashItem>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['items'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          list.add(TrashItem.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 恢复回收站条目（POST /api/files/trash/restore，见 trash.go）。
  ///
  /// 返回 `{id: 实际恢复路径}`；目标冲突时节点自动改名。
  Future<Map<String, String>> trashRestore({
    required String daemonId,
    required String uuid,
    required List<String> ids,
  }) async {
    final data = await _request(
      'POST',
      '/api/files/trash/restore',
      query: {'daemonId': daemonId},
      body: {'uuid': uuid, 'ids': ids},
    );
    final map = <String, String>{};
    if (data is Map) {
      for (final key in data.keys) {
        map[key] = (data[key] as String?) ?? '';
      }
    }
    return map;
  }

  /// 永久删除回收站内容（POST /api/files/trash/empty，见 trash.go）。
  ///
  /// [ids] 为空（null 或不传）时清空全部。
  Future<void> trashEmpty({
    required String daemonId,
    required String uuid,
    List<String>? ids,
  }) async {
    await _request(
      'POST',
      '/api/files/trash/empty',
      query: {'daemonId': daemonId},
      body: {
        'uuid': uuid,
        if (ids != null) 'ids': ids,
      },
    );
  }

  // ==================== 节点端内网穿透 FRP（irix-node）====================

  /// frpc 二进制状态与隧道列表（GET /api/frp/status，见 frp.go）。
  Future<({FrpcBinaryInfo binary, List<FrpTunnelInfo> tunnels})> frpStatus()
      async {
    final data = await _request('GET', '/api/frp/status');
    final tunnels = <FrpTunnelInfo>[];
    if (data is Map<String, dynamic>) {
      for (final item in (data['tunnels'] as List<dynamic>? ?? [])) {
        if (item is Map<String, dynamic>) {
          tunnels.add(FrpTunnelInfo.fromJson(item));
        }
      }
      final bin = data['binary'];
      final binary =
          bin is Map<String, dynamic> ? FrpcBinaryInfo.fromJson(bin) : null;
      return (
        binary: binary ?? const FrpcBinaryInfo(),
        tunnels: tunnels,
      );
    }
    return (binary: const FrpcBinaryInfo(), tunnels: tunnels);
  }

  /// 创建并启动隧道（POST /api/frp/tunnels，见 frp.go）。
  ///
  /// [config] 字段随 [provider]（self：完整 toml；openfrp/sakura：node/port 等）。
  /// 返回隧道 id。
  Future<String> frpCreateTunnel({
    required String name,
    required String provider,
    required Map<String, dynamic> config,
  }) async {
    final data = await _request(
      'POST',
      '/api/frp/tunnels',
      body: {'name': name, 'provider': provider, 'config': config},
    );
    return (data is Map ? data['tunnelId'] : null) as String? ?? '';
  }

  /// 启停单隧道（POST /api/frp/tunnels/{id}/start|stop，见 frp.go）。
  Future<void> frpTunnelAction(String id, String action) async {
    await _request('POST', '/api/frp/tunnels/$id/$action');
  }

  /// 删除隧道（DELETE /api/frp/tunnels/{id}，见 frp.go）。
  Future<void> frpDeleteTunnel(String id) async {
    await _request('DELETE', '/api/frp/tunnels/$id');
  }

  /// 隧道运行日志（GET /api/frp/tunnels/{id}/logs，见 frp.go）。
  ///
  /// [tailKb] 返回最后 N KB（默认 100）。
  Future<String> frpTunnelLogs(String id, {int tailKb = 100}) async {
    final data = await _request(
      'GET',
      '/api/frp/tunnels/$id/logs',
      query: {'tail': '$tailKb'},
    );
    return (data as String?) ?? '';
  }

  /// 上传 frpc 二进制（POST /api/frp/binary，multipart 字段 file）。
  ///
  /// 与直连上传同款手工 multipart 构造，网络传输由 Rust http_client 负责。
  Future<Map<String, dynamic>?> frpUploadBinary(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw NodeApiException(0, '本地文件不存在: $localPath');
    }
    final boundary = 'IriX${DateTime.now().microsecondsSinceEpoch}';
    final fileName = p.basename(localPath);
    final bytes = await file.readAsBytes();
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
      _uri('/api/frp/binary').toString(),
      headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
      body: body.takeBytes(),
      timeout: timeout,
    );
    if (resp.statusCode >= 400) {
      throw NodeApiException(resp.statusCode, '上传失败（HTTP ${resp.statusCode}）');
    }
    final decoded = _decode(resp);
    final status = (decoded['status'] as num?)?.toInt() ?? 500;
    if (status != 200) {
      final d = decoded['data'];
      throw NodeApiException(
        status,
        d is String ? d : '节点返回错误（status $status）',
      );
    }
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  // ==================== 负载调谐 / 审计日志（irix-node）====================

  /// 节点负载调谐状态（GET /api/load，见 loadtuner.go）。
  ///
  /// 返回 state（idle/normal/busy）、gomaxprocs、gcPercent、cpuBusy 等。
  Future<Map<String, dynamic>> nodeLoad() async {
    final data = await _request('GET', '/api/load');
    return data is Map<String, dynamic> ? data : {};
  }

  /// 读取审计日志（GET /api/audit/log，见 audit.go）。
  ///
  /// [tail] 返回最后 N 行（默认 500；0 表示全部，上限 20000）；
  /// [since] 为 unix 毫秒，返回该时间点后新增内容（增量轮询）。
  Future<String> auditLog({int? tail, int? since}) async {
    final data = await _request(
      'GET',
      '/api/audit/log',
      query: {
        if (tail != null) 'tail': '$tail',
        if (since != null) 'since': '$since',
      },
    );
    return (data as String?) ?? '';
  }

  // ==================== 账户认证（irix-node，见 accounts_handlers.go）====================

  /// 登录并写入会话令牌（POST /api/auth/login）。
  ///
  /// 成功后把返回的 token 写入 [authToken] 字段，后续请求自动附带；
  /// root 首次登录（尚未设独立密码）[mustChangePassword] 为 true。
  Future<Map<String, dynamic>> accountLogin({
    required String username,
    required String password,
  }) async {
    final data = await _request(
      'POST',
      '/api/auth/login',
      body: {'username': username, 'password': password},
    );
    if (data is Map<String, dynamic>) {
      final token = data['token'] as String? ?? '';
      if (token.isNotEmpty) authToken = token;
      return data;
    }
    return {};
  }

  /// 退出登录（POST /api/auth/logout，删除当前会话）。
  Future<void> accountLogout() async {
    await _request('POST', '/api/auth/logout');
    authToken = '';
  }

  /// 当前账户信息（GET /api/accounts/me）。
  Future<Map<String, dynamic>> accountMe() async {
    final data = await _request('GET', '/api/accounts/me');
    return data is Map<String, dynamic> ? data : {};
  }

  /// 权限目录（GET /api/accounts/catalog，分组 + 端点 + 描述）。
  Future<List<PermissionGroup>> permissionCatalog() async {
    final data = await _request('GET', '/api/accounts/catalog');
    final list = <PermissionGroup>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          list.add(PermissionGroup.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 修改密码（PUT /api/accounts/password，两种模式）：
  /// - 自己改密：[oldPassword] + [newPassword]（root 首次改密 oldPassword=配对码）；
  /// - 管理员重置：[username] + [newPassword]（无需旧密码，需管理员会话）。
  Future<void> changeAccountPassword({
    String? oldPassword,
    String? newPassword,
    String? username,
  }) async {
    await _request(
      'PUT',
      '/api/accounts/password',
      body: {
        if (oldPassword != null && oldPassword.isNotEmpty)
          'oldPassword': oldPassword,
        if (newPassword != null && newPassword.isNotEmpty)
          'newPassword': newPassword,
        if (username != null && username.isNotEmpty) 'username': username,
      },
    );
  }

  /// 账户列表（GET /api/accounts，管理员）。
  Future<List<AccountInfo>> accountsList() async {
    final data = await _request('GET', '/api/accounts');
    final list = <AccountInfo>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          list.add(AccountInfo.fromJson(item));
        }
      }
    }
    return list;
  }

  /// 创建账户（POST /api/accounts，管理员）。
  Future<void> createAccount({
    required String username,
    required String password,
    bool isAdmin = false,
  }) async {
    await _request(
      'POST',
      '/api/accounts',
      body: {'username': username, 'password': password, 'isAdmin': isAdmin},
    );
  }

  /// 删除账户（DELETE /api/accounts?username=，管理员；root 不可删）。
  Future<void> deleteAccount(String username) async {
    await _request(
      'DELETE',
      '/api/accounts',
      query: {'username': username},
    );
  }

  /// 修改账户端点开关（PUT /api/accounts/permissions，管理员）。
  ///
  /// 整组开关：[group] + [enabled]；逐条开关：[permissions]（端点→bool 映射）。
  Future<void> setAccountPermissions({
    required String username,
    String? group,
    bool? enabled,
    Map<String, bool>? permissions,
  }) async {
    await _request(
      'PUT',
      '/api/accounts/permissions',
      body: {
        'username': username,
        if (group != null && group.isNotEmpty) 'group': group,
        if (enabled != null) 'enabled': enabled,
        if (permissions != null) 'permissions': permissions,
      },
    );
  }

  // ==================== 集群节点 API（irix-node，见 cluster.go）====================

  /// 集群状态（GET /api/cluster/status）。
  Future<ClusterStatusData> clusterStatus() async {
    final data = await _request('GET', '/api/cluster/status');
    return ClusterStatusData.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// 已登记的对等节点列表（GET /api/cluster/peers）。
  Future<List<Map<String, dynamic>>> clusterPeers() async {
    final data = await _request('GET', '/api/cluster/peers');
    final list = <Map<String, dynamic>>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) list.add(item);
      }
    }
    return list;
  }

  /// 递归枚举同步区目录（GET /api/cluster/sync/list，单次返回整树）。
  Future<Map<String, dynamic>> clusterSyncList({String? path}) async {
    final data = await _request(
      'GET',
      '/api/cluster/sync/list',
      query: {if (path != null && path.isNotEmpty) 'path': path},
    );
    return data is Map<String, dynamic> ? data : {};
  }

  /// 递归枚举实例工作目录（GET /api/instance/sync/list，单次返回整树）。
  Future<Map<String, dynamic>> instanceSyncList(String uuid) async {
    final data = await _request(
      'GET',
      '/api/instance/sync/list',
      query: {'uuid': uuid},
    );
    return data is Map<String, dynamic> ? data : {};
  }

  /// 同步区文件列表（GET /api/cluster/files/list）。
  Future<Map<String, dynamic>> clusterFileList(
    String path, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final data = await _request(
      'GET',
      '/api/cluster/files/list',
      query: {
        'path': path,
        'page': '$page',
        'page_size': '$pageSize',
      },
    );
    return data is Map<String, dynamic> ? data : {};
  }

  /// 同步区创建目录（POST /api/cluster/files/mkdir）。
  Future<void> clusterMkdir(String path) async {
    await _request('POST', '/api/cluster/files/mkdir', body: {'path': path});
  }

  /// 同步区删除文件 / 目录（DELETE /api/cluster/files）。
  Future<void> clusterDelete(List<String> targets) async {
    await _request(
      'DELETE',
      '/api/cluster/files',
      body: {'targets': targets},
    );
  }

  /// 同步区下载票据（POST /api/cluster/files/download，目录范围票据）。
  Future<DownloadTicket> clusterDownloadTicket(String path) async {
    final data = await _request(
      'POST',
      '/api/cluster/files/download',
      body: {'path': path},
    );
    final map = data is Map<String, dynamic> ? data : {};
    return DownloadTicket(
      password: map['password'] as String? ?? '',
      addr: map['addr'] as String? ?? '',
      fileName: path.split('/').last,
    );
  }

  /// 同步区上传票据（POST /api/cluster/files/upload）。
  Future<UploadTicket> clusterUploadTicket(String uploadDir) async {
    final data = await _request(
      'POST',
      '/api/cluster/files/upload',
      body: {'upload_dir': uploadDir},
    );
    final map = data is Map<String, dynamic> ? data : {};
    return UploadTicket(
      password: map['password'] as String? ?? '',
      addr: map['addr'] as String? ?? '',
      uploadDir: uploadDir,
    );
  }

  // ==================== 控制台 WebSocket（irix-node，见 console_ws.go）====================

  /// 建立实时控制台 WebSocket 连接（GET /api/instance/console/ws）。
  ///
  /// 返回 [NodeConsoleConnection]：服务端逐行推文本帧（保留 ANSI），
  /// [send] 发送命令，[events] 流暴露输出行与进程退出通知。内置 30s 心跳。
  ///
  /// 旧节点 / MCSM 面板不支持升级（非 101）时抛出 [NodeConsoleUpgradeException]，
  /// 调用方捕获后回退 outputlog 轮询 + command。
  ///
  /// 鉴权：WebSocket 握手无法自定义请求头，节点侧 `authOK` 同时接受查询参数
  /// 的 apikey，故此处把 [apiKey] 拼到查询参数（MCSM apiKeyInQuery 不在此使用，
  /// 升级即便成功也不应漏掉 apikey）。
  Future<NodeConsoleConnection> connectConsoleWs({
    required String uuid,
    required String daemonId,
    String? since,
  }) async {
    final q = <String, String>{
      'uuid': uuid,
      'daemonId': daemonId,
      if (apiKey.isNotEmpty) 'apikey': apiKey,
      if (since != null && since.isNotEmpty) 'since': since,
    };
    final uri = _uri('/api/instance/console/ws', q);
    return NodeConsoleConnection.connect(uri.toString(), timeout: timeout);
  }
}

/// 控制台 WebSocket 升级失败（节点不支持 / 旧 MCSM 面板）。
class NodeConsoleUpgradeException implements Exception {
  final String message;
  const NodeConsoleUpgradeException(this.message);
  @override
  String toString() => message;
}

/// 控制台 WebSocket 事件。
sealed class NodeConsoleEvent {
  const NodeConsoleEvent();
}

/// 一行服务器原始输出（含 ANSI 转义）。
class NodeConsoleLine extends NodeConsoleEvent {
  final String line;
  const NodeConsoleLine(this.line);
}

/// 节点通知进程已退出。
class NodeConsoleExit extends NodeConsoleEvent {
  const NodeConsoleExit();
}

/// 实时控制台 WebSocket 连接封装（见 console_ws.go 文本帧协议）。
class NodeConsoleConnection {
  NodeConsoleConnection._(this._ws)
      : _controller = StreamController<NodeConsoleEvent>.broadcast() {
    _startHeartbeat();
    _listen();
  }

  /// 建立连接（含升级失败检测）。
  static Future<NodeConsoleConnection> connect(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    late final WebSocket ws;
    try {
      ws = await WebSocket.connect(url).timeout(timeout);
    } on WebSocketException catch (e) {
      throw NodeConsoleUpgradeException('控制台 WebSocket 升级失败：$e');
    } on TimeoutException {
      throw NodeConsoleUpgradeException('控制台 WebSocket 连接超时');
    } catch (e) {
      // 旧节点对升级请求返回普通 HTTP（非 101）：dart:io 抛 FormatException 等。
      throw NodeConsoleUpgradeException('控制台 WebSocket 不可用：$e');
    }
    return NodeConsoleConnection._(ws);
  }

  final WebSocket _ws;
  final StreamController<NodeConsoleEvent> _controller;

  /// 事件流：输出行 / 进程退出。
  Stream<NodeConsoleEvent> get events => _controller.stream;

  Timer? _heartbeat;

  void _startHeartbeat() {
    // 客户端每 30s 发送 ping 文本帧；节点 90s 无帧则断开。
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _ws.add('ping');
      } on StateError {
        // 连接已关闭
      }
    });
  }

  void _listen() {
    _ws.listen(
      (dynamic data) {
        if (data is! String) return;
        // 进程退出时节点发「[节点] 进程已退出，输出结束」并关闭。
        if (data == '[节点] 进程已退出，输出结束') {
          _controller.add(const NodeConsoleExit());
        } else {
          _controller.add(NodeConsoleLine(data));
        }
      },
      onError: (Object _) => _safeClose(),
      onDone: () => _safeClose(),
    );
  }

  /// 发送控制台命令（文本帧；等效 POST /api/protected_instance/command）。
  void send(String command) {
    if (command.isEmpty) return;
    try {
      _ws.add(command);
    } on StateError {
      // 连接已关闭
    }
  }

  bool _closed = false;

  void _safeClose() {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    try {
      _ws.close();
    } on StateError {
      // 已关闭
    }
    if (!_controller.isClosed) {
      _controller.add(const NodeConsoleExit());
      _controller.close();
    }
  }

  /// 关闭连接。
  void close() => _safeClose();
}

/// 实例操作类型。
enum RemoteAction { start, stop, restart, kill }
