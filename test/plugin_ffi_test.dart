// 插件系统 FFI 集成测试
//
// 需要先编译 Rust 动态库并复制到项目根目录 / windows/runner：
//   cargo build --release --package xmc_plugin_host
//   copy rust/target/release/xmc_plugin_host.dll .\xmc_plugin_host.dll
// 以及构建并打包示例插件：
//   .\plugins\example_plugin\build_and_package.ps1
// 生成 plugins/irix-example-plugin.zip。
//
// 验证：安装 -> 列表 -> 事件分发 -> 权限过滤 -> README -> 禁用 -> 卸载。
// 注意：原生插件加载后常驻，Windows 下临时目录中的 DLL 被锁，测试结束时无法删除
// 该目录，属预期（进程退出后系统自动清理），此处忽略删除失败。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/plugin_ffi.dart';

void main() {
  late Directory tempDir;
  late String zipPath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('irix_plugin_test_');
    zipPath =
        p.join(Directory.current.path, 'plugins', 'irix-example-plugin.zip');
    expect(File(zipPath).existsSync(), isTrue,
        reason: '示例插件包不存在，请先运行 plugins/example_plugin/build_and_package.ps1');
  });

  tearDownAll(() async {
    // 插件 DLL 常驻（Windows 下被锁），删除可能失败：忽略。
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('安装 / 列表 / 分发 / 权限过滤 / README / 禁用 / 卸载 全流程', () {
    final native = PluginHostNative.instance;

    // 初始化
    final rc = native.initialize(baseDir: tempDir.path, hostVersion: '1.0.0');
    expect(rc, 0, reason: native.getLastError() ?? '');

    // 安装
    final result = native.install(zipPath);
    expect(result.ok, isTrue, reason: result.message);
    expect(result.id, 'com.example.irix.example');

    // 列表
    final list = native.list();
    expect(list.length, 1);
    final plugin = list.first;
    expect(plugin.name, '示例插件');
    expect(plugin.loaded, isTrue, reason: plugin.error ?? '');
    expect(plugin.enabled, isTrue);
    expect(plugin.permissions, contains('instance.read'));

    // 事件分发：插件已授权 instance.read，应成功并回显。
    final payload = jsonEncode({'instance_id': 'demo', 'status': 'running'});
    final dispatch = native.dispatch('instance.started', payload);
    expect(dispatch.length, 1, reason: '至少一个已启用插件应收到事件');
    expect(dispatch.first['ok'], isTrue,
        reason: dispatch.first['error']?.toString());
    final parsed = jsonDecode(dispatch.first['result'] as String)
        as Map<String, dynamic>;
    expect(parsed['plugin'], 'irix-example-plugin');
    expect(parsed['handled_event'], 'instance.started');

    // 权限过滤：示例插件未声明 backup.write，派发 backup.start 时宿主应返回
    // permission_denied（而非投递给插件执行）。
    final denied = native.dispatch('backup.start', '{}');
    expect(denied.length, 1);
    expect(denied.first['status'], 'permission_denied');
    expect(denied.first['ok'], isFalse);

    // README
    final readme = native.readme(plugin.id);
    expect(readme, contains('示例插件'));

    // 禁用后不再派发事件
    native.toggle(plugin.id, false);
    final dispatch2 = native.dispatch('instance.started', payload);
    expect(dispatch2, isEmpty);

    // 卸载（插件已加载 -> 标记重启后生效）
    native.uninstall(plugin.id);
  });
}
