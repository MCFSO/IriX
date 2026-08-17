// 本地 MCP (Model Context Protocol) 服务器
//
// 让 Claude Desktop / Cursor 等外部 AI 工具通过 MCP 接入 IriX，
// 复用 AI 助手的工具集（读日志、搜日志、读文件、启停实例、发命令等）。
// 协议：JSON-RPC 2.0 over Streamable HTTP（POST /mcp，响应 application/json）。
//
// 权限模型与聊天式 AI 一致：只读工具直接执行；
// 敏感工具（执行命令、启停实例）会向 App 内弹出权限申请，
// 用户允许后才会真正执行，拒绝时向调用方返回错误。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/ai_assistant_service.dart';
import '../services/ai_settings.dart';
import '../state/app_state.dart';

/// 一次待授权的敏感操作请求。
class McpPermissionRequest {
  /// 发起调用的客户端名称（来自 initialize 的 clientInfo）。
  final String clientName;
  final AiTool tool;
  final Map<String, dynamic> args;
  final Completer<bool> completer = Completer<bool>();

  McpPermissionRequest({
    required this.clientName,
    required this.tool,
    required this.args,
  });

  /// 用户决定：true 允许，false 拒绝。
  void resolve(bool allowed) {
    if (!completer.isCompleted) completer.complete(allowed);
  }
}

/// 本地 MCP 服务器（单例，测试可另建实例）。
class McpServer {
  /// 全局单例（由 HomeScreen 绑定 AppState 并启动）。
  static final McpServer instance = McpServer();

  McpServer([this._state]);

  AppState? _state;
  HttpServer? _server;
  int _port = 0;
  String _clientName = '未知客户端';

  /// 每次启动时随机生成的 bearer token（H-3 鉴权）。
  ///
  /// 所有 /mcp 请求必须携带 `Authorization: Bearer <token>`，
  /// 防止同机恶意进程/网页滥用工具（读取实例文件、触发授权弹窗钓鱼等）。
  String _token = '';

  /// 待授权的请求队列。
  final List<McpPermissionRequest> _queue = [];

  /// 当前需要用户授权的请求（null 表示无）。UI 监听此 notifier 弹窗。
  final ValueNotifier<McpPermissionRequest?> currentRequest = ValueNotifier(
    null,
  );

  /// 绑定应用状态（工具执行依赖实例列表与进程控制）。
  void attachState(AppState state) {
    _state = state;
  }

  bool get running => _server != null;

  /// 实际监听的端口。
  int get port => _port;

  /// 当前会话的鉴权 token（未启动时为空字符串）。
  String get token => _token;

  /// 外部 AI 工具配置使用的端点地址。
  String get endpoint => 'http://127.0.0.1:$_port/mcp';

  /// 端点地址（含 bearer token 查询参数形式，便于不支持 header 的客户端）。
  ///
  /// 注意：token 出现在 URL 中会被进程列表/日志记录，仅作兼容备选；
  /// 推荐使用 [endpoint] + `Authorization` 请求头。
  String get endpointWithToken => 'http://127.0.0.1:$_port/mcp?token=$_token';

  /// 若已在设置中启用则启动，否则不启动。
  Future<bool> startIfEnabled() async {
    if (!await AiSettings.getMcpEnabled()) return false;
    await start(await AiSettings.getMcpPort());
    return running;
  }

  /// 启动服务器，监听 127.0.0.1 的 [port]；端口被占用时向后尝试 20 个。
  Future<void> start(int port) async {
    await stop();
    HttpServer? server;
    for (var p = port; p < port + 20; p++) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        _port = server.port;
        break;
      } catch (_) {}
    }
    if (server == null) {
      throw Exception('无法绑定 MCP 端口 $port-$port+20');
    }
    // 每次启动生成新的随机 token（H-3）。
    _token = _generateToken();
    _server = server;
    server.listen(
      _handleRequest,
      onError: (Object e) {
        debugPrint('MCP server error: $e');
      },
    );
    debugPrint('MCP server listening on $_port');
  }

  /// 生成 32 字节随机 token（十六进制，64 字符）。
  static String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 停止服务器，所有未决授权按拒绝处理。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = 0;
    _token = '';
    for (final request in _queue) {
      request.resolve(false);
    }
    _queue.clear();
    currentRequest.value = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  // === HTTP 处理 ===

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // 鉴权：所有请求（含信息页）必须携带正确的 bearer token（H-3）。
      if (!_authorized(req)) {
        req.response.statusCode = HttpStatus.unauthorized;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': null,
            'error': {'code': -32001, 'message': '未授权：缺少或错误的 Authorization 头'},
          }),
        );
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && req.uri.path == '/') {
        await _serveInfoPage(req);
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/mcp') {
        await _serveRpc(req);
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      debugPrint('MCP request error: $e');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 校验请求鉴权与来源（H-3）。
  ///
  /// - 必须携带 `Authorization: Bearer <token>`（或等价的 ?token= 查询参数）；
  /// - 带 `Origin` 头的浏览器跨源请求仅接受本机来源，其余一律拒绝，
  ///   防止恶意网页触发授权弹窗钓鱼或发起工具调用。
  bool _authorized(HttpRequest req) {
    if (_token.isEmpty) return false;
    final auth = req.headers.value('authorization');
    final tokenOk =
        auth == 'Bearer $_token' ||
        req.uri.queryParameters['token'] == _token;
    if (!tokenOk) return false;
    final origin = req.headers.value('origin');
    if (origin != null && origin.isNotEmpty) {
      final uri = Uri.tryParse(origin);
      if (uri == null) return false;
      final host = uri.host.toLowerCase();
      if (host != '127.0.0.1' &&
          host != 'localhost' &&
          host != '::1' &&
          host != '[::1]') {
        return false;
      }
    }
    return true;
  }

  Future<void> _serveInfoPage(HttpRequest req) async {
    // 信息页不再枚举工具清单，避免向未授权访问者泄露能力面（H-3）。
    req.response.headers.contentType = ContentType.html;
    req.response.write(
      '<html><head><meta charset="utf-8"><title>IriX MCP Server</title></head>'
      '<body style="font-family:sans-serif">'
      '<h1>IriX MCP Server</h1>'
      '<p>端点: <code>$endpoint</code></p>'
      '<p>该服务需要 Authorization bearer token，'
      '请在 IriX 的「AI 设置」中查看完整配置。</p>'
      '</body></html>',
    );
    await req.response.close();
  }

  Future<void> _serveRpc(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not a JSON-RPC object');
      }
      msg = decoded;
    } catch (_) {
      await _writeJson(
        req,
        _error(null, -32700, 'Parse error'),
        status: HttpStatus.badRequest,
      );
      return;
    }

    final id = msg['id'];
    // 无 id 的请求是通知（notifications/*），按协议返回 202 空响应。
    if (id == null) {
      req.response.statusCode = HttpStatus.accepted;
      await req.response.close();
      return;
    }

    final response = await _dispatch(msg);
    await _writeJson(req, response);
  }

  Future<Map<String, dynamic>> _dispatch(Map<String, dynamic> msg) async {
    final id = msg['id'];
    final method = msg['method']?.toString() ?? '';
    final rawParams = msg['params'];
    final params = rawParams is Map<String, dynamic>
        ? rawParams
        : rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : <String, dynamic>{};

    switch (method) {
      case 'initialize':
        final clientInfo = params['clientInfo'];
        if (clientInfo is Map) {
          _clientName = clientInfo['name']?.toString() ?? '未知客户端';
        }
        return _result(id, {
          'protocolVersion': '2025-03-26',
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'IriX', 'version': '1.0.0'},
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {
          'tools': [
            for (final t in AiAssistantService.instance.tools)
              {
                'name': t.name,
                'description': t.description,
                'inputSchema': t.parameters,
              },
          ],
        });
      case 'tools/call':
        return _callTool(id, params);
      case 'resources/list':
        return _result(id, {'resources': []});
      case 'prompts/list':
        return _result(id, {'prompts': []});
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Future<Map<String, dynamic>> _callTool(
    Object? id,
    Map<String, dynamic> params,
  ) async {
    final name = params['name']?.toString() ?? '';
    final tool = AiAssistantService.instance.tools
        .where((t) => t.name == name)
        .firstOrNull;
    if (tool == null) {
      return _error(id, -32602, 'Unknown tool: $name');
    }
    final rawArgs = params['arguments'];
    final args = rawArgs is Map<String, dynamic>
        ? rawArgs
        : rawArgs is Map
        ? Map<String, dynamic>.from(rawArgs)
        : <String, dynamic>{};
    final state = _state;
    if (state == null) {
      return _toolResult(id, 'IriX 应用状态未就绪', isError: true);
    }

    if (tool.permission == AiToolPermission.elevated) {
      final allowed = await _requestPermission(tool, args);
      if (!allowed) {
        return _toolResult(
          id,
          '用户拒绝了该操作: ${tool.describe(args)}',
          isError: true,
        );
      }
    }

    try {
      final text = await tool.handler(state, args);
      return _toolResult(id, text);
    } catch (e) {
      return _toolResult(id, '工具执行失败: $e', isError: true);
    }
  }

  /// 申请用户授权；120 秒内未响应按拒绝处理。
  Future<bool> _requestPermission(
    AiTool tool,
    Map<String, dynamic> args,
  ) async {
    final request = McpPermissionRequest(
      clientName: _clientName,
      tool: tool,
      args: args,
    );
    _queue.add(request);
    _pumpQueue();
    final timer = Timer(const Duration(seconds: 120), () {
      request.resolve(false);
    });
    final allowed = await request.completer.future;
    timer.cancel();
    _queue.remove(request);
    if (identical(currentRequest.value, request)) {
      currentRequest.value = null;
    }
    _pumpQueue();
    return allowed;
  }

  /// 把队首请求暴露给 UI；一次只弹一个授权。
  void _pumpQueue() {
    if (currentRequest.value != null || _queue.isEmpty) return;
    currentRequest.value = _queue.first;
  }

  static Map<String, dynamic> _result(
    Object? id,
    Map<String, dynamic> result,
  ) => {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, dynamic> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static Map<String, dynamic> _toolResult(
    Object? id,
    String text, {
    bool isError = false,
  }) => _result(id, {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': isError,
  });

  Future<void> _writeJson(
    HttpRequest req,
    Map<String, dynamic> body, {
    int status = HttpStatus.ok,
  }) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}
