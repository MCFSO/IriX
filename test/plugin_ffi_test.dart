// 插件系统 FFI 集成测试
//
// 前置条件：
//   1. 已编译 Rust 动态库并复制到项目根目录 / windows/runner / linux：
//        cargo build --release --package xmc_plugin_host
//        （Windows 用 build_rust.bat，Linux/macOS 用 build_rust.sh）
//   2. 存在示例插件包 plugins/irix-example-plugin.zip（**已入库**，也当作用户可安装示例）。
//
// 验证：安装 -> 列表 -> 事件分发 -> 权限过滤 -> README -> 禁用 -> 卸载。
//
// 平台说明：示例包内置的动态库是分平台的（lib/<entry>.<platform>.<ext>）。仓库里
// 提交的是 Windows 版；CI 在测试前会按 runner 平台用 build_and_package.sh 重新打包，
// 因此 Linux CI 会走"已加载"分支。其它平台若未重新打包，宿主会把插件标记为
// not_supported —— 本测试对此同样断言（验证平台库选择逻辑），而不是失败。
//
// 注意：原生插件加载后常驻，Windows 下临时目录中的 DLL 被锁，测试结束时无法删除
// 该目录，属预期（进程退出后系统自动清理），此处忽略删除失败。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/plugin_ffi.dart';

void main() {
  final zipPath =
      p.join(Directory.current.path, 'plugins', 'irix-example-plugin.zip');

  test('安装 / 列表 / 分发 / 权限过滤 / README / 禁用 / 卸载 全流程', () async {
    expect(File(zipPath).existsSync(), isTrue,
        reason: '示例插件包缺失: plugins/irix-example-plugin.zip');

    // 插件 DLL 常驻会锁住目录，临时目录在本测试内创建与清理。
    final tempDir = await Directory.systemTemp.createTemp('irix_plugin_test_');
    final native = PluginHostNative.instance;

    try {
      // 初始化
      final rc = native.initialize(baseDir: tempDir.path, hostVersion: '1.0.0');
      expect(rc, 0, reason: native.getLastError() ?? '');

      // 安装（解压 + manifest 校验 + 落目录）
      final result = native.install(zipPath);
      expect(result.ok, isTrue, reason: result.message);
      expect(result.id, 'com.example.irix.example');

      // 列表：与平台无关的元数据
      final list = native.list();
      expect(list.length, 1);
      final plugin = list.first;
      expect(plugin.name, '示例插件');
      expect(plugin.enabled, isTrue, reason: plugin.error ?? '');
      expect(plugin.permissions, contains('instance.read'));

      if (plugin.loaded) {
        // === 当前平台有对应动态库：走完整加载 + 分发链路 ===

        // 已授权事件（instance.read）：成功并回显
        final payload = jsonEncode({'instance_id': 'demo', 'status': 'running'});
        final dispatch = native.dispatch('instance.started', payload);
        expect(dispatch.length, 1, reason: '至少一个已启用插件应收到事件');
        expect(dispatch.first['ok'], isTrue,
            reason: dispatch.first['error']?.toString());
        final parsed = jsonDecode(dispatch.first['result'] as String)
            as Map<String, dynamic>;
        expect(parsed['plugin'], 'irix-example-plugin');
        expect(parsed['handled_event'], 'instance.started');

        // 权限过滤：示例插件未声明 backup.write，应返回 permission_denied
        final denied = native.dispatch('backup.start', '{}');
        expect(denied.length, 1);
        expect(denied.first['status'], 'permission_denied');
        expect(denied.first['ok'], isFalse);

        // 禁用后不再派发事件
        native.toggle(plugin.id, false);
        expect(native.dispatch('instance.started', payload), isEmpty);
      } else {
        // === 当前平台无对应动态库：验证平台库选择与安全降级 ===
        expect(plugin.status, 'not_supported', reason: plugin.error ?? '');
        expect(plugin.error, isNotNull);
        // 未加载的插件不应收到任何事件
        expect(native.dispatch('instance.started', '{}'), isEmpty);
      }

      // README（与平台无关）
      expect(native.readme(plugin.id), contains('示例插件'));

      // 卸载（插件已加载时标记重启后生效）
      native.uninstall(plugin.id);
    } finally {
      // 插件 DLL 常驻（Windows 下被锁），删除可能失败：忽略。
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
