// Java 管理服务（移植自 HMCL JavaManager）
//
// 对外唯一业务入口，聚合：
//   JavaScanner   —— 候选路径搜索（HMCL Searcher）
//   JavaDetector  —— 单个可执行文件探测（HMCL JavaInfoUtils）
//   JavaRepository—— 受管安装的清单/卸载（HMCL HMCLJavaRepository）
//   JavaSettings  —— 用户添加/禁用/选择列表（HMCL UserSettings）
//
// 对应 HMCL JavaManager 的公开能力：
//   refresh()                 → refresh()
//   getAllJava()              → runtimes
//   getAddJavaTask(binary)    → addByPath()
//   getUninstallJavaTask(j)   → uninstall()
//   removeJava(j)             → disable() / enable()
//   findSuitableJava(...)     → findSuitableFor()

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/java_runtime.dart';
import 'java_detector.dart';
import 'java_repository.dart';
import 'java_scanner.dart';
import 'java_settings.dart';

/// Java 运行时的全局管理器。
class JavaService extends ChangeNotifier {
  JavaService._();

  static final JavaService instance = JavaService._();

  /// 已发现的全部 Java 运行时（按 HMCL 排序规则）。
  List<JavaRuntime> _runtimes = const [];
  List<JavaRuntime> get runtimes => List.unmodifiable(_runtimes);

  bool _loading = false;
  bool get isLoading => _loading;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 上次扫描的错误信息（null 表示正常）。
  String? _error;
  String? get error => _error;

  /// 全部被禁用的 java 路径。
  Set<String> _disabled = {};
  Set<String> get disabled => Set.unmodifiable(_disabled);

  /// 刷新：重新扫描系统全部 Java（对应 HMCL `JavaManager.refresh`）。
  ///
  /// 扫描期间置 [isLoading]，完成后通知监听者。
  Future<void> refresh({bool useCache = true}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (!useCache) JavaDetector.instance.clearCache();

      _disabled = await JavaSettings.instance.getDisabled();
      final userAdded = await JavaSettings.instance.getUserAdded();

      final candidates = await JavaScanner.instance.scan(
        extraPaths: userAdded,
        disabled: _disabled,
      );

      // 受管仓库中的安装需要标记 isManaged，扫描器已按目录来源设置。
      final detected = await JavaDetector.instance.detectAll(candidates);

      // 以真实路径去重（符号链接可能指向同一 JDK）。
      final unique = <String, JavaRuntime>{};
      for (final runtime in detected) {
        // 用户在界面上禁用的路径实时过滤（禁用后立即刷新列表）。
        if (_disabled.contains(runtime.binary)) continue;
        unique.putIfAbsent(runtime.binary, () => runtime);
      }

      final list = unique.values.toList()..sort();
      _runtimes = list;
      _initialized = true;
    } catch (e, st) {
      _error = e.toString();
      debugPrint('Java refresh failed: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 惰性初始化：首次访问时扫描一次。
  Future<void> ensureInitialized() async {
    if (_initialized || _loading) return;
    await refresh();
  }

  /// 手动添加指定路径的 Java（对应 HMCL `getAddJavaTask`）。
  ///
  /// [path] 可以是 java 可执行文件、java home 或 bin 目录。
  /// 成功返回运行时，失败返回 null 并抛出原因见 [lastAddError]。
  String? lastAddError;

  Future<JavaRuntime?> addByPath(String path) async {
    lastAddError = null;

    // 复用扫描器的路径归一化语义。
    final candidates = await JavaScanner.instance.scan(
      extraPaths: [path],
      disabled: const {},
    );

    // 只取与用户输入对应的那一个候选。
    final target = candidates
        .map((c) => c.path)
        .where((c) => _samePath(c, path))
        .firstOrNull;

    final resolved = target ?? candidates.map((c) => c.path).firstOrNull;

    if (resolved == null) {
      lastAddError = '无法识别该路径下的 Java';
      return null;
    }

    final runtime = await JavaDetector.instance.detect(resolved);
    if (runtime == null) {
      lastAddError = '该 Java 无法执行或版本信息解析失败';
      return null;
    }

    // 解除禁用并记入用户添加列表（HMCL：remove(disabledJava) + add(userJava)）。
    await JavaSettings.instance.enable(runtime.binary);
    _disabled = await JavaSettings.instance.getDisabled();
    await JavaSettings.instance.addUserAdded(runtime.binary);

    if (!_runtimes.any((r) => r.binary == runtime.binary)) {
      _runtimes = [..._runtimes, runtime]..sort();
    }
    notifyListeners();
    return runtime;
  }

  /// 禁用某个 Java（对应 HMCL `removeJava`：从可用列表移除并记住禁用）。
  ///
  /// 系统安装无法安全删除文件，故禁用而非卸载；受管安装请用 [uninstall]。
  Future<void> disable(JavaRuntime runtime) async {
    await JavaSettings.instance.disable(runtime.binary);
    _disabled = await JavaSettings.instance.getDisabled();
    _runtimes = _runtimes.where((r) => r.binary != runtime.binary).toList();
    notifyListeners();
  }

  /// 解除禁用（对应 HMCL JavaRestorePage 的恢复）。
  Future<void> enable(String binary) async {
    await JavaSettings.instance.enable(binary);
    _disabled = await JavaSettings.instance.getDisabled();
    unawaited(refresh(useCache: true));
  }

  /// 卸载受管安装（对应 HMCL `getUninstallJavaTask`）。
  ///
  /// 仅允许卸载位于 IriX 受管仓库内、且带清单的安装，
  /// 避免误删用户系统 JDK（对齐 HMCL 的 `isManaged` 前置判断）。
  Future<bool> uninstall(JavaRuntime runtime) async {
    if (!runtime.isManaged) return false;

    final root = await JavaRepository.instance.root();
    if (!_isWithin(root, runtime.binary)) return false;

    // 目录名即安装名（<root>/<name>/bin/java）。
    final name = _relativeName(root, runtime.binary);
    if (name == null) return false;

    await JavaRepository.instance.uninstall(name);
    _runtimes = _runtimes.where((r) => r.binary != runtime.binary).toList();
    notifyListeners();
    return true;
  }

  /// 为指定大版本挑选最合适的 Java（简化版 HMCL `findSuitableJava`）。
  ///
  /// 优先精确匹配大版本；其次取不小于需求的最小版本；最后取最大版本。
  JavaRuntime? findSuitableFor(int majorVersion) {
    if (_runtimes.isEmpty) return null;

    final exact = _runtimes.where((r) => r.parsedVersion == majorVersion);
    if (exact.isNotEmpty) {
      return exact.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    }

    final greater = _runtimes.where((r) => r.parsedVersion > majorVersion);
    if (greater.isNotEmpty) {
      return greater.reduce(
        (a, b) => a.parsedVersion <= b.parsedVersion ? a : b,
      );
    }

    return _runtimes.reduce(
      (a, b) => a.parsedVersion >= b.parsedVersion ? a : b,
    );
  }

  /// 当前选中的 Java（未选择时返回第一个可用运行时）。
  JavaRuntime? get selected {
    final path = _selectedPath;
    if (path != null) {
      for (final r in _runtimes) {
        if (r.binary == path) return r;
      }
    }
    return _runtimes.isEmpty ? null : _runtimes.first;
  }

  String? _selectedPath;

  /// 加载持久化的选中项（启动时调用一次）。
  Future<void> loadSelected() async {
    _selectedPath = await JavaSettings.instance.getSelected();
  }

  /// 设置选中项。
  Future<void> select(JavaRuntime? runtime) async {
    _selectedPath = runtime?.binary;
    await JavaSettings.instance.setSelected(_selectedPath);
    notifyListeners();
  }

  // === 路径工具 ===

  bool _samePath(String a, String b) {
    final na = a.replaceAll('\\', '/').toLowerCase();
    final nb = b.replaceAll('\\', '/').toLowerCase();
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  bool _isWithin(String root, String path) {
    final nr = root.replaceAll('\\', '/').toLowerCase();
    final np = path.replaceAll('\\', '/').toLowerCase();
    return np.startsWith(nr);
  }

  /// 从 `<root>/<name>/bin/java` 中取出 `<name>`。
  String? _relativeName(String root, String binary) {
    final nr = root.replaceAll('\\', '/');
    final np = binary.replaceAll('\\', '/');
    if (!np.toLowerCase().startsWith(nr.toLowerCase())) return null;

    var rel = np.substring(nr.length);
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    final slash = rel.indexOf('/');
    if (slash <= 0) return null;
    return rel.substring(0, slash);
  }
}
