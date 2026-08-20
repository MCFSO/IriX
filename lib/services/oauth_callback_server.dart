// OAuth/SSO 本地回调服务器
//
// 用于网页授权登录（如 ChmlFrp SSO）：
// App 在 127.0.0.1 随机端口起一个临时 HTTP 服务器，
// 浏览器完成登录授权后跳转到 `http://127.0.0.1:<port>/callback#token=xxx`，
// 由本服务器捕获回调参数（query 与 fragment/hash 均支持）并返回给调用方。
//
// 安全（H-5）：启动时生成一次性随机 state，调用方应将其拼入授权 URL；
// 回调必须携带匹配的 state 才会被接受，防止本机其他进程抢答伪造 token
// （token fixation）。

import 'dart:async';
import 'dart:io';
import 'dart:math';

/// 捕获 OAuth 回调参数的本地服务器。
class OAuthCallbackServer {
  HttpServer? _server;
  int? _port;
  String? _state;

  /// 实际监听端口（未启动时为 0）。
  int get port => _port ?? 0;

  /// 本次回调的一次性随机 state（[start] 时生成，[stop] 时清空）。
  ///
  /// 调用方应将其作为 `state` 参数拼入授权 URL；服务端若透传该参数，
  /// [waitForParams] 会校验一致性，不匹配的回调将被拒绝。
  String? get state => _state;

  /// 启动服务器，监听 127.0.0.1 的随机空闲端口。
  Future<void> start() async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    // 一次性随机 state（24 字节十六进制，H-5）。
    final rng = Random.secure();
    _state = List<int>.generate(24, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 等待浏览器回调，返回合并后的参数（query 优先，其次 fragment）。
  ///
  /// 回调中携带的 `state` 与 [state] 不一致时视为伪造请求，直接拒绝
  /// 并继续等待真实回调（因此返回 null 只表示超时/服务器关闭）。
  /// 服务端不回显 state 时（无 state 参数）兼容放行并记录调试信息。
  ///
  /// 超时或服务器被 [stop] 关闭时返回 null。
  Future<Map<String, String>?> waitForParams({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final server = _server;
    if (server == null) return null;
    final expected = _state;
    try {
      // 循环读取直到拿到 state 匹配的回调或超时。
      final deadline = DateTime.now().add(timeout);
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) return null;
        final request = await server.first.timeout(remaining);
        final params = <String, String>{};
        if (request.uri.fragment.isNotEmpty) {
          params.addAll(Uri.splitQueryString(request.uri.fragment));
        }
        params.addAll(request.uri.queryParameters);
        final got = params['state'];
        // H-5：state 校验三道闸——
        // 1) 缺少 state（服务端未回传或攻击者构造）一律拒绝，防止同机
        //    攻击者发不含 state 的请求注入伪造 token（token fixation）；
        // 2) state 与本次会话不匹配一律拒绝。
        if (expected != null && (got == null || got != expected)) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><body><h3>回调校验失败（state 缺失或不匹配），请重试登录。</h3></body></html>',
          );
          await request.response.close();
          continue;
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><head><meta charset="utf-8"></head><body>'
          '<h3>登录成功</h3><p>已获取登录凭据，可以关闭此页面并返回 IriX。</p>'
          '</body></html>',
        );
        await request.response.close();
        return params;
      }
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
    _state = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}
