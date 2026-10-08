// 原生插件服务（业务包装）
//
// 封装对 PluginHostNative（Rust xmc_plugin_host）的调用，提供插件列表、安装、
// 启用/禁用、卸载、详情（README）与事件派发等业务方法。
//
// 插件的加载、事件分发、权限检查全部在 Rust 侧完成；本服务只负责 FFI 调用
// 与把 Rust 返回的 JSON 解析为 Dart 模型。

import 'app_paths.dart';
import 'plugin_ffi.dart';

/// 宿主版本号（用于 manifest 的 min_app_version 校验，需与发布版本保持一致）。
const String kHostVersion = '1.0.0';

/// 原生插件服务单例。
class PluginService {
  PluginService._();
  static final PluginService instance = PluginService._();

  /// FFI 是否已初始化（动态库加载 + plg_init 成功）。
  bool _initialized = false;

  /// 确保 FFI 可用并已完成 plg_init。
  ///
  /// 首次调用会加载动态库并以数据根目录下的 `plugins/native` 作为插件根目录。
  Future<void> init({bool force = false}) async {
    // 动态库加载失败会抛 PluginHostException。
    final native = PluginHostNative.instance;
    if (_initialized && !force) return;

    final dir = await AppPaths.instance.pluginsRoot();
    final rc = native.initialize(baseDir: dir, hostVersion: kHostVersion);
    if (rc != 0) {
      throw PluginHostException(native.getLastError() ?? '插件系统初始化失败');
    }
    _initialized = true;
  }

  /// 重新扫描（回读 Rust 注册表最新状态）。
  Future<void> refresh() async {
    await init();
    PluginHostNative.instance.list();
  }

  /// 列出所有插件。
  Future<List<PluginInfo>> list() async {
    await init();
    return PluginHostNative.instance.list();
  }

  /// 单个插件详情。
  Future<PluginInfo?> detail(String id) async {
    await init();
    return PluginHostNative.instance.detail(id);
  }

  /// 读取插件 README。
  Future<String> readme(String id) async {
    await init();
    return PluginHostNative.instance.readme(id);
  }

  /// 安装插件包（zip 路径）。
  ///
  /// 成功返回 `(插件 id, 可选加载告警)`；包本身无效（zip 损坏、manifest 非法、
  /// 版本不兼容）时抛出 [PluginHostException]。加载告警表示包已装好但当前无法
  /// 加载（如平台缺少对应动态库），调用方应把原因提示给用户。
  Future<({String id, String? warning})> install(String zipPath) async {
    await init();
    final result = PluginHostNative.instance.install(zipPath);
    if (!result.ok) {
      throw PluginHostException(result.message);
    }
    return (id: result.id!, warning: result.warning);
  }

  /// 卸载插件。已加载插件会被标记为“重启后生效”。
  Future<void> uninstall(String id) async {
    await init();
    PluginHostNative.instance.uninstall(id);
  }

  /// 启用 / 禁用插件。
  Future<void> toggle(String id, bool enabled) async {
    await init();
    PluginHostNative.instance.toggle(id, enabled);
  }

  /// 向所有启用插件派发事件，返回每个插件的结果。
  Future<List<Map<String, dynamic>>> dispatch(
    String eventType,
    String payload,
  ) async {
    await init();
    return PluginHostNative.instance.dispatch(eventType, payload);
  }
}
