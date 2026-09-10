// 应用数据目录解析服务（AppPaths）
//
// Windows 上应用数据默认不再写入系统盘（C:）。数据根目录按以下优先级选择：
// 1. exe 同目录 `data_root.txt` 中指定的绝对路径（用户手动覆盖，任意盘均可）；
// 2. exe 所在目录（不在系统盘且可写时，与 instances/ 等既有目录保持一致）；
// 3. 从 D: 到 Z: 顺序扫描，取第一个可写盘根下的 `IriX` 文件夹；
// 4. 以上都不可用时回退应用文档目录（旧行为，usingFallback == true）。
// 非 Windows 平台保持应用文档目录不变。
//
// 根目录切换后，首次启动会自动搬迁旧文档目录下的数据：
// - 数据库（irix.db / xmc_orchestrator.db）与旧版迁移 JSON：小文件，
//   在 DatabaseManager.init 之前同步复制（ensureInitialized 内完成）；
// - 日志 / JDK / frpc / 集群镜像 / 守护进程数据：体积可能很大，在数据库
//   就绪后后台逐文件复制→校验→删除源文件（startBackgroundMigration），
//   被占用的文件跳过、下次启动自动重试。
//
// 新增落盘数据时统一经本服务取目录，禁止直接调用
// getApplicationDocumentsDirectory() / Directory.systemTemp（临时文件用
// createTempDir）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_manager.dart';

/// 应用数据目录解析（单例）。
class AppPaths {
  AppPaths._();
  static final AppPaths instance = AppPaths._();

  /// exe 旁的数据目录指定文件（内容为绝对路径）。
  static const String _markerFileName = 'data_root.txt';

  /// 扫描非系统盘时创建的目录名。
  static const String _scannedFolderName = 'IriX';

  Future<void>? _initFuture;
  String? _root;
  bool _isFallback = false;
  bool _backgroundStarted = false;
  static int _tempCounter = 0;

  /// 数据根目录；ensureInitialized 完成前为 null。
  String? get rootSync => _root;

  /// 是否回退到了应用文档目录（未找到可用的非系统盘）。
  bool get usingFallback => _isFallback;

  /// 解析数据根目录并同步迁移数据库等小文件。
  ///
  /// 必须在 DatabaseManager.init 之前 await 完成。
  Future<void> ensureInitialized() => _initFuture ??= _doInit();

  /// 数据根目录（未初始化时惰性初始化）。
  Future<String> root() async {
    await ensureInitialized();
    return _root!;
  }

  /// 日志目录（实例日志 / frpc 日志 / 开发者日志的父目录）。
  Future<String> logsDir() async => p.join(await root(), 'logs');

  /// JDK 安装根目录。
  Future<String> javaRoot() async => p.join(await root(), 'java');

  /// frpc 程序与配置根目录。
  Future<String> frpcRoot() async => p.join(await root(), 'ofrp');

  /// 集群迁移镜像根目录。
  Future<String> clusterMirrorRoot() async =>
      p.join(await root(), 'cluster_mirrors');

  /// 临时目录根：Windows 数据根目录不在系统盘时用 `<root>/temp`，
  /// 其余情况（回退文档目录或非 Windows 平台）沿用系统临时目录。
  Future<String> tempRoot() async {
    if (Platform.isWindows && !_isFallback) {
      final dir = Directory(p.join(await root(), 'temp'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }
    return Directory.systemTemp.path;
  }

  /// 在临时目录下创建带前缀的唯一工作目录（调用方用完负责删除）。
  Future<Directory> createTempDir(String prefix) async {
    final base = await tempRoot();
    final unique = '${DateTime.now().microsecondsSinceEpoch}_${_tempCounter++}';
    return Directory(p.join(base, '$prefix$unique')).create(recursive: true);
  }

  /// 数据库就绪后调用一次：后台搬迁旧文档目录下的大数据目录。
  void startBackgroundMigration() {
    if (_backgroundStarted || _isFallback || _root == null) return;
    _backgroundStarted = true;
    unawaited(_migrateBulkyData());
  }

  Future<void> _doInit() async {
    await _resolveRoot();
    await _migrateSmallFiles();
  }

  // ======================== 根目录解析 ========================

  Future<void> _resolveRoot() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);

    // 0) 用户在 exe 旁放置 data_root.txt 可强制指定数据目录。
    try {
      final marker = File(p.join(exeDir, _markerFileName));
      if (await marker.exists()) {
        final content = (await marker.readAsString()).trim();
        if (content.isNotEmpty && await _ensureWritableDir(content)) {
          _root = p.normalize(content);
          return;
        }
      }
    } catch (_) {}

    if (Platform.isWindows) {
      final systemDrive =
          _driveOf(Platform.environment['SystemRoot'] ?? r'C:\Windows') ?? 'C:';

      // 1) exe 不在系统盘且目录可写：数据随安装位置。
      final exeDrive = _driveOf(exeDir);
      if (exeDrive != null &&
          exeDrive != systemDrive &&
          await _isWritableDir(exeDir)) {
        _root = p.normalize(exeDir);
        return;
      }

      // 2) 扫描其余盘符，取第一个可写盘根下的 IriX 目录。
      for (var code = 0x44; code <= 0x5A; code++) {
        final drive = String.fromCharCode(code);
        if ('$drive:' == systemDrive) continue;
        try {
          if (!await Directory('$drive:\\').exists()) continue;
        } catch (_) {
          continue;
        }
        final candidate = p.join('$drive:\\', _scannedFolderName);
        if (await _ensureWritableDir(candidate)) {
          _root = candidate;
          return;
        }
      }
    }

    // 3) 兜底：应用文档目录（旧行为）。
    try {
      _root = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      _root = Directory.current.path;
    }
    _isFallback = true;
  }

  /// 提取 Windows 盘符（如 `D:`）；UNC 路径等返回 null。
  static String? _driveOf(String path) {
    final m = RegExp(r'^([A-Za-z]):').firstMatch(p.normalize(path));
    return m == null ? null : '${m.group(1)!.toUpperCase()}:';
  }

  /// 确保目录存在且可写（写探针文件验证）。
  Future<bool> _ensureWritableDir(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return await _isWritableDir(path);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isWritableDir(String path) async {
    try {
      final probe = File(p.join(path, '.irix_write_probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ======================== 旧数据迁移 ========================

  /// 同步迁移数据库与旧版迁移 JSON：先复制到 `.irix-migrating` 临时名
  /// 再改名，保证目标处不会出现半截文件。新位置已有同名文件时以新位置
  /// 为准（源文件保留，作为回退副本）。
  Future<void> _migrateSmallFiles() async {
    if (_isFallback || _root == null) return;
    try {
      final legacy = (await getApplicationDocumentsDirectory()).path;
      if (p.equals(legacy, _root!)) return;
      for (final name in const [
        'irix.db',
        'irix.db-journal',
        'irix.db-wal',
        'irix.db-shm',
        'xmc_orchestrator.db',
        'instances.json',
        'config_annotations.json',
      ]) {
        await _migrateFile(p.join(legacy, name), p.join(_root!, name));
      }
    } catch (e) {
      debugPrint('AppPaths: 小文件迁移失败（忽略，下次启动重试）: $e');
    }
  }

  Future<void> _migrateFile(String srcPath, String dstPath) async {
    try {
      final src = File(srcPath);
      if (!await src.exists()) return;
      final dst = File(dstPath);
      if (await dst.exists()) return;
      final tmp = File('$dstPath.irix-migrating');
      if (await tmp.exists()) {
        await tmp.delete();
      }
      await src.copy(tmp.path);
      await tmp.rename(dstPath);
    } catch (_) {
      // 单个文件失败不阻塞其余迁移。
    }
  }

  Future<void> _migrateBulkyData() async {
    try {
      final legacy = (await getApplicationDocumentsDirectory()).path;
      final root = _root!;
      if (p.equals(legacy, root)) return;

      // frpc 体积小且运行时按新路径查找，优先搬，避免重复下载；
      // 服务端日志可无限增长，紧随其后。
      await _moveTree(p.join(legacy, 'ofrp'), p.join(root, 'ofrp'));
      await _moveTree(p.join(legacy, 'logs'), p.join(root, 'logs'));
      // JDK 按版本目录搬迁，并修正 settings 中的绝对路径。
      final legacyJava = p.join(legacy, 'irix', 'java');
      await _moveTree(legacyJava, p.join(root, 'java'));
      await _remapJdkSettings(legacyJava);
      await _moveTree(
        p.join(legacy, 'cluster_mirrors'),
        p.join(root, 'cluster_mirrors'),
      );
      // 守护进程数据为小文件：复制到新位置，原目录保留作备份。
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        await _copyTree(p.join(appData, 'irix-node'), p.join(root, 'irix-node'));
      }
      // 清理搬空的旧目录（仍有占用文件时删除失败，下次启动重试）。
      try {
        final javaDir = Directory(legacyJava);
        if (await javaDir.exists()) await javaDir.delete();
        final irixDir = Directory(p.join(legacy, 'irix'));
        if (await irixDir.exists()) await irixDir.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('AppPaths: 后台迁移失败（忽略，下次启动重试）: $e');
    }
  }

  /// 把 settings 中指向旧 JDK 根目录的绝对路径（jdk_home_*）改写为
  /// 新根目录下的对应路径。
  Future<void> _remapJdkSettings(String legacyJavaRoot) async {
    try {
      final settings =
          await DatabaseManager.instance.getSettingsWithPrefix('jdk_home_');
      final legacyNorm = p.normalize(legacyJavaRoot);
      for (final entry in settings.entries) {
        final norm = p.normalize(entry.value);
        if (norm != legacyNorm && !p.isWithin(legacyNorm, norm)) continue;
        final rel = p.relative(norm, from: legacyNorm);
        final base = await javaRoot();
        final newPath =
            (rel == '.' || rel.isEmpty) ? base : p.join(base, rel);
        await DatabaseManager.instance.setSetting(entry.key, newPath);
      }
    } catch (e) {
      debugPrint('AppPaths: JDK 路径修正失败（忽略）: $e');
    }
  }

  /// 递归搬运目录：同卷直接改名，跨卷逐文件复制→长度校验→删除源文件。
  Future<void> _moveTree(String srcPath, String dstPath) async {
    try {
      final src = Directory(srcPath);
      if (!await src.exists()) return;
      final dst = Directory(dstPath);
      if (!await dst.exists()) {
        await dst.create(recursive: true);
      }
      await _moveChildren(src, dst);
      await _pruneIfEmpty(src);
    } catch (e) {
      debugPrint('AppPaths: 迁移目录 $srcPath 失败（忽略）: $e');
    }
  }

  Future<void> _moveChildren(Directory src, Directory dst) async {
    await for (final entity in src.list()) {
      final target = p.join(dst.path, p.basename(entity.path));
      try {
        if (entity is File) {
          await _moveFile(entity, File(target));
        } else if (entity is Directory) {
          final targetDir = Directory(target);
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          await _moveChildren(entity, targetDir);
        }
      } catch (e) {
        debugPrint('AppPaths: 跳过 ${entity.path}: $e');
      }
    }
  }

  Future<void> _moveFile(File src, File dst) async {
    if (await dst.exists() && await src.length() == await dst.length()) {
      await src.delete();
      return;
    }
    try {
      await src.rename(dst.path);
      return;
    } catch (_) {
      // 跨卷或源被占用：回退复制，删除失败则留待下次启动重试。
    }
    await src.copy(dst.path);
    if (await dst.exists() && await src.length() == await dst.length()) {
      try {
        await src.delete();
      } catch (_) {}
    }
  }

  /// 递归删除已搬空的目录；任何一级仍非空或删除失败即停止。
  Future<void> _pruneIfEmpty(Directory dir) async {
    try {
      var empty = true;
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          await _pruneIfEmpty(entity);
          if (await entity.exists()) empty = false;
        } else {
          empty = false;
        }
        if (!empty) break;
      }
      if (empty) {
        await dir.delete();
      }
    } catch (_) {}
  }

  /// 递归复制目录（保留源文件，用于小体量的守护进程数据）。
  Future<void> _copyTree(String srcPath, String dstPath) async {
    if (srcPath.isEmpty) return;
    try {
      final src = Directory(srcPath);
      if (!await src.exists()) return;
      final dst = Directory(dstPath);
      if (!await dst.exists()) {
        await dst.create(recursive: true);
      }
      await for (final entity in src.list()) {
        final target = p.join(dstPath, p.basename(entity.path));
        if (entity is File) {
          if (!await File(target).exists()) {
            await entity.copy(target);
          }
        } else if (entity is Directory) {
          await _copyTree(entity.path, target);
        }
      }
    } catch (e) {
      debugPrint('AppPaths: 复制 $srcPath 失败（忽略）: $e');
    }
  }
}
