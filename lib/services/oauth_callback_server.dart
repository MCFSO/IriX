// OAuth/SSO 本地回调服务器
//
// 用于网页授权登录（如 ChmlFrp SSO）：
// App 在 127.0.0.1 随机端口起一个临时 HTTP 服务器，
// 浏览器完成登录授权后跳转到 `http://127.0.0.1:<port>/callback#token=xxx`，
// 由本服务器捕获回调参数（query 与 fragment/hash 均支持）并返回给调用方。

import 'dart:async';
import 'dart:io';

/// 捕获 OAuth 回调参数的本地服务器。
class OAuthCallbackServer {
  HttpServer? _server;
  int? _port;

  /// 实际监听端口（未启动时为 0）。
  int get port => _port ?? 0;

  /// 启动服务器，监听 127.0.0.1 的随机空闲端口。
  Future<void> start() async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
  }

  /// 等待浏览器回调，返回合并后的参数（query 优先，其次 fragment）。
  ///
  /// 超时或服务器被 [stop] 关闭时返回 null。
  Future<Map<String, String>?> waitForParams({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = _server;
    if (server == null) return null;
    try {
      final request = await server.first.timeout(timeout);
      final params = <String, String>{};
      if (request.uri.fragment.isNotEmpty) {
        params.addAll(Uri.splitQueryString(request.uri.fragment));
      }
      params.addAll(request.uri.queryParameters);
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><head><meta charset="utf-8"></head><body>'
        '<h3>登录成功</h3><p>已获取登录凭据，可以关闭此页面并返回 IriX。</p>'
        '</body></html>',
      );
      await request.response.close();
      return params;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 停止服务器。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _port = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}
