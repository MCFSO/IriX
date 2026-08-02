// OAuth 本地回调服务器
//
// 用于网页授权登录（如 OpenFrp / Natayark ID）：
// App 在 127.0.0.1 随机端口起一个临时 HTTP 服务器，
// 浏览器完成登录授权后跳转到 `http://127.0.0.1:<port>/callback?code=xxx`，
// 由本服务器捕获 code 并返回给调用方。

import 'dart:async';
import 'dart:io';

/// 捕获 OAuth 回调 code 的本地服务器。
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

  /// 等待浏览器回调并返回 `code` 参数。
  ///
  /// 超时或服务器被 [stop] 关闭时返回 null。
  Future<String?> waitForCode({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final server = _server;
    if (server == null) return null;
    try {
      final request = await server.first.timeout(timeout);
      final code = request.uri.queryParameters['code'];
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><head><meta charset="utf-8"></head><body>'
        '<h3>授权成功</h3><p>已获取登录凭据，可以关闭此页面并返回 IriX。</p>'
        '</body></html>',
      );
      await request.response.close();
      return code;
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
