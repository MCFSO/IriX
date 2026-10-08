// 插件宿主动态库 FFI 封装（Rust xmc_plugin_host）
//
// 通过 dart:ffi 调用 Rust 侧暴露的插件管理接口：
//   plg_init / plg_list / plg_detail / plg_readme / plg_install /
//   plg_uninstall / plg_toggle / plg_dispatch / plg_shutdown。
// 插件的加载、事件分发、权限检查全部在 Rust 侧完成，此处只做参数序列化。
//
// Rust 返回的 JSON 字符串用 `free_string` 释放，错误用 `get_last_error` 读取。

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'rust_lib.dart';

// ===== FFI 函数签名 typedef =====
typedef PlgInitC = Int32 Function(
  Pointer<Utf8> baseDir,
  Pointer<Utf8> hostVersion,
);
typedef PlgInitDart = int Function(
  Pointer<Utf8> baseDir,
  Pointer<Utf8> hostVersion,
);

typedef PlgShutdownC = Void Function();
typedef PlgShutdownDart = void Function();

typedef PlgStringFnC = Pointer<Utf8> Function(Pointer<Utf8> arg);
typedef PlgStringFnDart = Pointer<Utf8> Function(Pointer<Utf8> arg);

typedef PlgListC = Pointer<Utf8> Function();
typedef PlgListDart = Pointer<Utf8> Function();

typedef PlgInstallC = Pointer<Utf8> Function(Pointer<Utf8> zipPath);
typedef PlgInstallDart = Pointer<Utf8> Function(Pointer<Utf8> zipPath);

typedef PlgUninstallC = Int32 Function(Pointer<Utf8> id);
typedef PlgUninstallDart = int Function(Pointer<Utf8> id);

typedef PlgToggleC = Int32 Function(Pointer<Utf8> id, Int32 enabled);
typedef PlgToggleDart = int Function(Pointer<Utf8> id, int enabled);

typedef PlgDispatchC =
    Pointer<Utf8> Function(Pointer<Utf8> eventType, Pointer<Utf8> payload);
typedef PlgDispatchDart =
    Pointer<Utf8> Function(Pointer<Utf8> eventType, Pointer<Utf8> payload);

/// 单个插件信息（列表详情共用）。
class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String type;
  final String entry;
  final String minAppVersion;
  final List<String> permissions;
  final bool enabled;
  final bool loaded;
  final String status;
  final String? error;
  final bool pendingRestart;
  final String dir;

  PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.type,
    required this.entry,
    required this.minAppVersion,
    required this.permissions,
    required this.enabled,
    required this.loaded,
    required this.status,
    required this.error,
    required this.pendingRestart,
    required this.dir,
  });

  factory PluginInfo.fromJson(Map<String, dynamic> json) {
    return PluginInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
      minAppVersion: json['min_app_version'] as String? ?? '',
      permissions: ((json['permissions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      enabled: json['enabled'] as bool? ?? false,
      loaded: json['loaded'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      error: json['error'] as String?,
      pendingRestart: json['pending_restart'] as bool? ?? false,
      dir: json['dir'] as String? ?? '',
    );
  }

  /// 状态是否可交互（正常可启用/禁用）。
  bool get isInteractive =>
      status != 'pending_restart' && status != 'crashed';
}

/// 插件宿主动态库 FFI 单例。
class PluginHostNative {
  static PluginHostNative? _instance;
  late final DynamicLibrary _lib;
  late final PlgInitDart _plgInit;
  late final PlgShutdownDart _plgShutdown;
  late final PlgListDart _plgList;
  late final PlgStringFnDart _plgDetail;
  late final PlgStringFnDart _plgReadme;
  late final PlgInstallDart _plgInstall;
  late final PlgUninstallDart _plgUninstall;
  late final PlgToggleDart _plgToggle;
  late final PlgDispatchDart _plgDispatch;

  PluginHostNative._(this._lib) {
    _plgInit = _lib.lookupFunction<PlgInitC, PlgInitDart>('plg_init');
    _plgShutdown =
        _lib.lookupFunction<PlgShutdownC, PlgShutdownDart>('plg_shutdown');
    _plgList = _lib.lookupFunction<PlgListC, PlgListDart>('plg_list');
    _plgDetail = _lib.lookupFunction<PlgStringFnC, PlgStringFnDart>('plg_detail');
    _plgReadme =
        _lib.lookupFunction<PlgStringFnC, PlgStringFnDart>('plg_readme');
    _plgInstall =
        _lib.lookupFunction<PlgInstallC, PlgInstallDart>('plg_install');
    _plgUninstall =
        _lib.lookupFunction<PlgUninstallC, PlgUninstallDart>('plg_uninstall');
    _plgToggle = _lib.lookupFunction<PlgToggleC, PlgToggleDart>('plg_toggle');
    _plgDispatch =
        _lib.lookupFunction<PlgDispatchC, PlgDispatchDart>('plg_dispatch');
  }

  /// 单例（首次访问时加载动态库）。
  static PluginHostNative get instance => init();

  static PluginHostNative init() {
    if (_instance != null) return _instance!;
    final lib = openRustLibrary('plugin_host');
    _instance = PluginHostNative._(lib);
    return _instance!;
  }

  /// 读取 Rust 最近一次错误字符串（free_string 释放）。
  String? getLastError() => readLastError(_lib);

  /// 初始化插件系统。baseDir 为插件根目录。
  int initialize({required String baseDir, required String hostVersion}) {
    final dirPtr = baseDir.toNativeUtf8();
    final verPtr = hostVersion.toNativeUtf8();
    try {
      return _plgInit(dirPtr, verPtr);
    } finally {
      calloc.free(dirPtr);
      calloc.free(verPtr);
    }
  }

  /// 关闭全部插件。
  void shutdown() => _plgShutdown();

  /// 列出所有插件。
  List<PluginInfo> list() {
    final ptr = _plgList();
    if (ptr == nullptr) {
      throw PluginHostException(getLastError() ?? '插件列表获取失败');
    }
    try {
      final decoded = jsonDecode(ptr.toDartString()) as List;
      return decoded
          .map((e) => PluginInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      freeRustString(_lib, ptr);
    }
  }

  /// 单个插件详情。
  PluginInfo? detail(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      final ptr = _plgDetail(idPtr);
      if (ptr == nullptr) return null;
      try {
        final decoded = jsonDecode(ptr.toDartString()) as Map<String, dynamic>;
        return PluginInfo.fromJson(decoded);
      } finally {
        freeRustString(_lib, ptr);
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  /// 读取插件 README。
  String readme(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      final ptr = _plgReadme(idPtr);
      if (ptr == nullptr) return '';
      try {
        return ptr.toDartString();
      } finally {
        freeRustString(_lib, ptr);
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  /// 安装插件包。返回 (ok, id, message)。
  ({bool ok, String? id, String message}) install(String zipPath) {
    final zipPtr = zipPath.toNativeUtf8();
    try {
      final ptr = _plgInstall(zipPtr);
      if (ptr == nullptr) {
        throw PluginHostException(getLastError() ?? '安装失败');
      }
      try {
        final decoded = jsonDecode(ptr.toDartString()) as Map<String, dynamic>;
        return (
          ok: decoded['ok'] as bool? ?? false,
          id: decoded['id'] as String?,
          message: decoded['message'] as String? ?? '',
        );
      } finally {
        freeRustString(_lib, ptr);
      }
    } finally {
      calloc.free(zipPtr);
    }
  }

  /// 卸载插件。已加载插件标记为重启后生效。
  void uninstall(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      final rc = _plgUninstall(idPtr);
      if (rc != 0) {
        throw PluginHostException(getLastError() ?? '卸载失败');
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  /// 启用 / 禁用插件。
  void toggle(String id, bool enabled) {
    final idPtr = id.toNativeUtf8();
    try {
      final rc = _plgToggle(idPtr, enabled ? 1 : 0);
      if (rc != 0) {
        throw PluginHostException(getLastError() ?? '切换失败');
      }
    } finally {
      calloc.free(idPtr);
    }
  }

  /// 向所有启用插件派发事件。返回每个插件的分发结果 JSON 列表。
  List<Map<String, dynamic>> dispatch(String eventType, String payload) {
    final eventPtr = eventType.toNativeUtf8();
    final payloadPtr = payload.toNativeUtf8();
    try {
      final ptr = _plgDispatch(eventPtr, payloadPtr);
      if (ptr == nullptr) {
        throw PluginHostException(getLastError() ?? '事件分发失败');
      }
      try {
        final decoded = jsonDecode(ptr.toDartString()) as List;
        return decoded.map((e) => (e as Map).cast<String, dynamic>()).toList();
      } finally {
        freeRustString(_lib, ptr);
      }
    } finally {
      calloc.free(eventPtr);
      calloc.free(payloadPtr);
    }
  }
}

/// 插件宿主动态库调用异常。
class PluginHostException implements Exception {
  final String message;
  PluginHostException(this.message);

  @override
  String toString() => message;
}
