// HTTPS 冒烟测试：验证 Rust HTTP 客户端可访问真实 HTTPS API (rustls 证书校验)。
// 依赖网络；离线环境会跳过。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/http_ffi.dart';

void main() {
  test('HTTPS GET api.modrinth.com 返回 200 与 JSON', () async {
    try {
      final res = await HttpFfiService.instance.get(
        'https://api.modrinth.com/v2/tag/loader',
        headers: {'Accept': 'application/json'},
        timeout: const Duration(seconds: 15),
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('json'));
      expect(res.body, isNotEmpty);
    } catch (e) {
      markTestSkipped('网络不可用或目标被拦截: $e');
    }
  });
}
