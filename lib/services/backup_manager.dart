// 实例备份业务层（全量备份 + 增量备份）
//
// 定位：Dart 侧唯一备份业务入口，负责
// - 备份仓库路径解析（统一走 AppPaths：`<数据根>/backups/<实例 id>/`）；
// - 调用 Rust（`xmc_backup` 的 `backup_request`）并解析 JSON 结果；
// - 把 Rust 返回的原始 Map 转成强类型模型，供 UI 直接渲染。
//
// 两类备份：
// - 全量备份（[BackupKind.full]）：整个实例目录 → 单个 ZIP 归档（Rust 并行 Deflate）；
// - 增量备份（[BackupKind.incremental]）：Linux/macOS 用 rsync 硬链接快照，
//   Windows 用 SHA-256 哈希比对 + 内容寻址存储（全部在 Rust 内实现）。
//
// 具体落盘布局与算法见 `rust/backup/src/{repo,snapshot,cas,hardlink,rsync,full}.rs`。

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'backup_ffi.dart';

/// 备份类型。
enum BackupKind {
  /// 全量备份：整个实例目录打包为一个 ZIP 归档。
  full,

  /// 增量备份：硬链接快照（Linux/macOS）/ 内容寻址存储（Windows）。
  incremental,
}

/// 一条备份记录（全量 ZIP 或增量快照）。
@immutable
class BackupEntry {
  /// 备份名（`YYYYMMDD-HHMMSS`，同名时 Rust 侧追加 `-2`、`-3`）。
  final String name;

  /// 类型。
  final BackupKind kind;

  /// 创建时间（本地时区）。
  final DateTime createdAt;

  /// 实际使用的策略：`zip` / `rsync-hardlink` / `hardlink` / `cas`。
  final String strategy;

  /// 文件数。
  final int files;

  /// 逻辑字节数（源文件之和）。
  final int bytesTotal;

  /// 实际占用字节数（ZIP 体积 / 本次新增落盘字节）。
  final int storedBytes;

  /// 耗时（毫秒）。
  final int durationMs;

  /// 增量基线快照名（首个快照为 null）。
  final String? parent;

  final int filesNew;
  final int filesModified;
  final int filesDeleted;
  final int filesUnchanged;

  /// 相对基线新增实际写入的字节数。
  final int bytesAdded;

  /// 相对基线复用（硬链接 / 已存在对象）的字节数。
  final int bytesReused;

  /// 全量备份的压缩级别（0-9）。
  final int compressionLevel;

  /// 目录数。
  final int dirs;

  /// 被跳过的符号链接数。
  final int symlinksSkipped;

  /// 策略回退说明（如「未找到 rsync，已改用原生硬链接快照」）。
  final String? note;

  const BackupEntry({
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.strategy,
    this.files = 0,
    this.bytesTotal = 0,
    this.storedBytes = 0,
    this.durationMs = 0,
    this.parent,
    this.filesNew = 0,
    this.filesModified = 0,
    this.filesDeleted = 0,
    this.filesUnchanged = 0,
    this.bytesAdded = 0,
    this.bytesReused = 0,
    this.compressionLevel = 0,
    this.dirs = 0,
    this.symlinksSkipped = 0,
    this.note,
  });

  /// 解析 `snapshot_create` / `status.snapshots` 的条目。
  factory BackupEntry.fromSnapshotJson(Map<String, dynamic> json) {
    return BackupEntry(
      name: _string(json, 'name') ?? '',
      kind: BackupKind.incremental,
      createdAt: _dateTime(json, 'createdAt'),
      strategy: _string(json, 'strategy') ?? 'hardlink',
      files: _int(json, 'filesTotal'),
      bytesTotal: _int(json, 'bytesTotal'),
      storedBytes: _int(json, 'storedBytes'),
      durationMs: _int(json, 'durationMs'),
      parent: _string(json, 'parent'),
      filesNew: _int(json, 'filesNew'),
      filesModified: _int(json, 'filesModified'),
      filesDeleted: _int(json, 'filesDeleted'),
      filesUnchanged: _int(json, 'filesUnchanged'),
      bytesAdded: _int(json, 'bytesAdded'),
      bytesReused: _int(json, 'bytesReused'),
      dirs: _int(json, 'dirs'),
      symlinksSkipped: _int(json, 'symlinksSkipped'),
      note: _string(json, 'note'),
    );
  }

  /// 解析 `full_create` / `status.full` 的条目。
  factory BackupEntry.fromFullJson(Map<String, dynamic> json) {
    return BackupEntry(
      name: _string(json, 'name') ?? '',
      kind: BackupKind.full,
      createdAt: _dateTime(json, 'createdAt'),
      strategy: 'zip',
      files: _int(json, 'files'),
      bytesTotal: _int(json, 'bytesTotal'),
      storedBytes: _int(json, 'storedBytes'),
      durationMs: _int(json, 'durationMs'),
      compressionLevel: _int(json, 'compressionLevel'),
      bytesAdded: _int(json, 'storedBytes'),
      bytesReused: 0,
    );
  }

  bool get isIncremental => kind == BackupKind.incremental;

  /// 展示用大小：优先逻辑大小，缺失时退回实际占用
  /// （手工放入仓库的 ZIP 没有摘要，只有文件体积）。
  int get displayBytes => bytesTotal > 0 ? bytesTotal : storedBytes;
}

/// 备份仓库概览（含全量与增量两类备份，按时间倒序合并）。
@immutable
class BackupRepositoryStatus {
  /// 仓库绝对路径。
  final String repoRoot;

  /// 当前平台的增量策略：`rsync-hardlink` / `hardlink` / `cas`。
  final String strategy;

  /// 是否检测到 rsync 命令。
  final bool rsyncAvailable;

  /// rsync 版本首行（可选）。
  final String? rsyncVersion;

  /// 全部备份（最新在前）。
  final List<BackupEntry> entries;

  /// 全部备份的逻辑字节数之和。
  final int totalLogicalBytes;

  /// 全部备份的实际占用之和。
  final int totalStoredBytes;

  const BackupRepositoryStatus({
    required this.repoRoot,
    required this.strategy,
    required this.rsyncAvailable,
    this.rsyncVersion,
    this.entries = const [],
    this.totalLogicalBytes = 0,
    this.totalStoredBytes = 0,
  });

  factory BackupRepositoryStatus.fromJson({
    required String repoRoot,
    required Map<String, dynamic> json,
  }) {
    final snapshots = json['snapshots'];
    final full = json['full'];
    final entries = <BackupEntry>[
      if (snapshots is List)
        for (final item in snapshots)
          if (item is Map<String, dynamic>) BackupEntry.fromSnapshotJson(item),
      if (full is List)
        for (final item in full)
          if (item is Map<String, dynamic>) BackupEntry.fromFullJson(item),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return BackupRepositoryStatus(
      repoRoot: _string(json, 'repoRoot') ?? repoRoot,
      strategy: _string(json, 'strategy') ?? 'hardlink',
      rsyncAvailable: json['rsyncAvailable'] == true,
      rsyncVersion: _string(json, 'rsyncVersion'),
      entries: entries,
      totalLogicalBytes: _int(json, 'totalLogicalBytes'),
      totalStoredBytes: _int(json, 'totalStoredBytes'),
    );
  }

  bool get isEmpty => entries.isEmpty;
}

/// 恢复结果。
@immutable
class BackupRestoreInfo {
  final String name;
  final BackupKind kind;
  final int files;
  final int bytes;
  final int pruned;
  final int durationMs;

  const BackupRestoreInfo({
    required this.name,
    required this.kind,
    this.files = 0,
    this.bytes = 0,
    this.pruned = 0,
    this.durationMs = 0,
  });

  factory BackupRestoreInfo.fromJson(Map<String, dynamic> json) {
    return BackupRestoreInfo(
      name: _string(json, 'name') ?? '',
      kind: _string(json, 'kind') == 'full'
          ? BackupKind.full
          : BackupKind.incremental,
      files: _int(json, 'files'),
      bytes: _int(json, 'bytes'),
      pruned: _int(json, 'pruned'),
      durationMs: _int(json, 'durationMs'),
    );
  }
}

/// 校验结果。
@immutable
class BackupVerifyResult {
  final String name;
  final String strategy;
  final int checked;
  final int hashed;
  final int missing;
  final int sizeMismatch;
  final int hashMismatch;
  final List<String> problems;

  const BackupVerifyResult({
    required this.name,
    required this.strategy,
    this.checked = 0,
    this.hashed = 0,
    this.missing = 0,
    this.sizeMismatch = 0,
    this.hashMismatch = 0,
    this.problems = const [],
  });

  factory BackupVerifyResult.fromJson(Map<String, dynamic> json) {
    final problems = json['problems'];
    return BackupVerifyResult(
      name: _string(json, 'name') ?? '',
      strategy: _string(json, 'strategy') ?? '',
      checked: _int(json, 'checked'),
      hashed: _int(json, 'hashed'),
      missing: _int(json, 'missing'),
      sizeMismatch: _int(json, 'sizeMismatch'),
      hashMismatch: _int(json, 'hashMismatch'),
      problems: [
        if (problems is List)
          for (final item in problems)
            if (item is String) item,
      ],
    );
  }

  bool get ok => missing == 0 && sizeMismatch == 0 && hashMismatch == 0;

  int get problemCount => missing + sizeMismatch + hashMismatch;
}

/// 备份操作失败（含「用户取消」）。
class BackupException implements Exception {
  final String message;
  final bool cancelled;

  const BackupException(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

/// 备份操作接口。
///
/// UI 只依赖该抽象（见 `screens/instance_backup_tab.dart`），方便 widget 测试
/// 注入假实现，避免在测试环境触碰真实数据目录/数据库。
abstract interface class BackupOperations {
  /// 读取仓库概览（含全部全量/增量备份）。
  Future<BackupRepositoryStatus> status({
    required String instanceId,
    required String rootPath,
  });

  /// 全量备份：整个实例目录 → 单个 ZIP 归档。
  Future<BackupEntry> createFullBackup({
    required String instanceId,
    required String rootPath,
    required int compressionLevel,
    void Function(double? progress)? onProgress,
  });

  /// 增量备份：只保存相对上一个快照的变化内容。
  Future<BackupEntry> createIncrementalBackup({
    required String instanceId,
    required String rootPath,
    String? parent,
    void Function(double? progress)? onProgress,
  });

  /// 用指定备份覆盖恢复实例目录。
  Future<BackupRestoreInfo> restoreBackup({
    required BackupEntry entry,
    required String instanceId,
    required String rootPath,
    bool prune,
    void Function(double? progress)? onProgress,
  });

  /// 校验增量快照完整性。
  Future<BackupVerifyResult> verifyBackup({
    required BackupEntry entry,
    required String instanceId,
    bool deep,
    void Function(double? progress)? onProgress,
  });

  /// 删除备份。
  Future<void> deleteBackup({
    required BackupEntry entry,
    required String instanceId,
  });

  /// 回收未被引用的内容寻址对象，返回释放的字节数。
  Future<int> collectGarbage(String instanceId);

  /// 取消当前备份/恢复。
  void cancel();
}

/// 备份业务入口（全量备份 / 增量备份）。
class BackupManager implements BackupOperations {
  BackupManager._();

  static final BackupManager instance = BackupManager._();

  final BackupService _ffi = BackupService.instance;

  /// 指定实例的备份仓库目录（`<数据根>/backups/<实例 id>/`）。
  Future<String> repositoryPath(String instanceId) =>
      AppPaths.instance.instanceBackupsRoot(instanceId);

  /// 生成备份名：本地时间 `YYYYMMDD-HHMMSS`。
  ///
  /// Rust 侧会在重名时自动追加 `-2`、`-3`，因此这里不需要查重。
  String newBackupName([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// 读取仓库概览（含全部全量/增量备份）。
  @override
  Future<BackupRepositoryStatus> status({
    required String instanceId,
    required String rootPath,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request('status', {
      'repoRoot': repoRoot,
      'sourceRoot': rootPath,
    });
    if (!result.ok) {
      throw BackupException(result.error ?? '读取备份列表失败');
    }
    return BackupRepositoryStatus.fromJson(
      repoRoot: repoRoot,
      json: result.data,
    );
  }

  /// 全量备份：整个实例目录 → 单个 ZIP 归档。
  ///
  /// [onProgress] 为进度回调（0.0 ~ 1.0）；Rust 无法预估时传 null（不确定进度）。
  @override
  Future<BackupEntry> createFullBackup({
    required String instanceId,
    required String rootPath,
    int compressionLevel = 6,
    void Function(double? progress)? onProgress,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request(
      'full_create',
      {
        'repoRoot': repoRoot,
        'sourceRoot': rootPath,
        'name': newBackupName(),
        'compressionLevel': compressionLevel,
      },
      onProgress: _sink(onProgress),
    );
    if (!result.ok) {
      throw _failure(result, '全量备份失败');
    }
    return BackupEntry.fromFullJson(result.data);
  }

  /// 增量备份：只保存相对上一个快照的变化内容。
  ///
  /// - Linux/macOS：`rsync --link-dest` 硬链接快照（缺失 rsync 时由 Rust 原生
  ///   硬链接快照兜底）；
  /// - Windows：SHA-256 哈希比对 + 内容寻址存储。
  ///
  /// [parent] 为空表示自动使用最新快照作为增量基线。
  @override
  Future<BackupEntry> createIncrementalBackup({
    required String instanceId,
    required String rootPath,
    String? parent,
    void Function(double? progress)? onProgress,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request(
      'snapshot_create',
      {
        'repoRoot': repoRoot,
        'sourceRoot': rootPath,
        'name': newBackupName(),
        'label': 'manual',
        if (parent != null && parent.isNotEmpty) 'parent': parent,
      },
      onProgress: _sink(onProgress),
    );
    if (!result.ok) {
      throw _failure(result, '增量备份失败');
    }
    return BackupEntry.fromSnapshotJson(result.data);
  }

  /// 用指定备份覆盖恢复实例目录（同名文件会被覆盖）。
  @override
  Future<BackupRestoreInfo> restoreBackup({
    required BackupEntry entry,
    required String instanceId,
    required String rootPath,
    bool prune = false,
    void Function(double? progress)? onProgress,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final isFull = entry.kind == BackupKind.full;
    final result = await _ffi.request(
      isFull ? 'full_restore' : 'snapshot_restore',
      {
        'repoRoot': repoRoot,
        'name': entry.name,
        'targetRoot': rootPath,
        if (!isFull) 'prune': prune,
      },
      onProgress: _sink(onProgress),
    );
    if (!result.ok) {
      throw _failure(result, '恢复备份失败');
    }
    return BackupRestoreInfo.fromJson(result.data);
  }

  /// 校验增量快照完整性（[deep] 时逐个比对内容哈希，较慢）。
  @override
  Future<BackupVerifyResult> verifyBackup({
    required BackupEntry entry,
    required String instanceId,
    bool deep = false,
    void Function(double? progress)? onProgress,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request(
      'snapshot_verify',
      {'repoRoot': repoRoot, 'name': entry.name, 'deep': deep},
      onProgress: _sink(onProgress),
    );
    if (!result.ok) {
      throw _failure(result, '校验备份失败');
    }
    return BackupVerifyResult.fromJson(result.data);
  }

  /// 删除备份（增量快照会顺带回收未被引用的内容对象）。
  @override
  Future<void> deleteBackup({
    required BackupEntry entry,
    required String instanceId,
  }) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request(
      entry.kind == BackupKind.full ? 'full_delete' : 'snapshot_delete',
      {'repoRoot': repoRoot, 'name': entry.name},
    );
    if (!result.ok) {
      throw _failure(result, '删除备份失败');
    }
  }

  /// 回收未被任何快照引用的内容寻址对象，返回释放的字节数。
  @override
  Future<int> collectGarbage(String instanceId) async {
    final repoRoot = await repositoryPath(instanceId);
    final result = await _ffi.request('gc', {'repoRoot': repoRoot});
    if (!result.ok) {
      throw _failure(result, '回收备份空间失败');
    }
    return _int(result.data, 'bytesFreed');
  }

  /// 取消当前备份/恢复（Rust 侧轮询取消标志，rsync 会直接 kill 子进程）。
  @override
  void cancel() => _ffi.cancel();

  /// 把 Rust 的 `(已处理, 总量)` 回调换算成 0.0~1.0 进度。
  void Function(int, int)? _sink(void Function(double? progress)? onProgress) {
    if (onProgress == null) return null;
    return (processed, total) {
      if (total <= 0) {
        onProgress(null);
        return;
      }
      onProgress((processed / total).clamp(0.0, 1.0));
    };
  }

  BackupException _failure(BackupOpResult result, String fallback) {
    final message = (result.error == null || result.error!.isEmpty)
        ? fallback
        : result.error!;
    return BackupException(message, cancelled: result.cancelled);
  }
}

// ======================== JSON 取值辅助 ========================

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

String? _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

DateTime _dateTime(Map<String, dynamic> json, String key) {
  final seconds = _int(json, key);
  if (seconds <= 0) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
