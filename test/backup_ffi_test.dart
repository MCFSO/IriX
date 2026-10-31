// backup_ffi 集成测试
// 验证 Rust 备份 FFI（xmc_backup）的全量备份与增量备份：
// - 全量：整个实例目录 → ZIP，列表 / 恢复 / 删除；
// - 增量：Windows 走 SHA-256 哈希比对 + 内容寻址存储（CAS），Linux/macOS 走
//   rsync 硬链接快照（rsync 不可用时回退 Rust 原生硬链接快照），
//   校验「第二次快照只新增变化内容」、恢复与校验、删除后回收空间；
// - 进度回调、参数校验、取消返回码。
//
// 需要编译并复制 xmc_backup 动态库（见 build_rust.bat / build_rust.sh）。
// 若动态库不在搜索路径，则用例自动跳过（CI 未复制库时不失败）。
//   flutter test test/backup_ffi_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:irix/services/backup_ffi.dart';

/// 探测 xmc_backup 动态库是否在搜索路径中（cwd / 项目根 / 平台目录）。
bool _libraryAvailable() {
  final libName = Platform.isWindows
      ? 'xmc_backup.dll'
      : Platform.isMacOS
      ? 'libxmc_backup.dylib'
      : 'libxmc_backup.so';
  final candidates = [
    p.join(Directory.current.path, libName),
    p.join(Directory.current.path, 'windows', 'runner', libName),
    p.join(Directory.current.path, 'linux', libName),
    p.join(Directory.current.path, 'macos', libName),
  ];
  return candidates.any((path) => File(path).existsSync());
}

void main() {
  final available = _libraryAvailable();
  final skipReason = available ? null : '未找到 xmc_backup 动态库（先运行 build_rust）';

  late Directory sandbox;
  late String sourceRoot;
  late String repoRoot;

  final service = BackupService.instance;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('xmc_backup_ffi_');
    sourceRoot = p.join(sandbox.path, 'instance');
    repoRoot = p.join(sandbox.path, 'repo');
    Directory(p.join(sourceRoot, 'world', 'region')).createSync(recursive: true);
    File(p.join(sourceRoot, 'server.properties'))
        .writeAsStringSync('motd=hello\n');
    File(p.join(sourceRoot, 'world', 'level.dat')).writeAsStringSync('level');
    File(p.join(sourceRoot, 'world', 'region', 'r.0.0.mca'))
        .writeAsBytesSync(List<int>.filled(4096, 7));
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  group('backup_ffi', () {
    test('status 返回平台增量策略与空列表', () async {
      final result = await service.request('status', {
        'repoRoot': repoRoot,
        'sourceRoot': sourceRoot,
      });
      expect(result.ok, isTrue, reason: result.error);
      expect(result.data['snapshots'], isEmpty);
      expect(result.data['full'], isEmpty);
      final strategy = result.data['strategy'] as String;
      expect(strategy, isNotEmpty);
      if (Platform.isWindows) {
        expect(strategy, 'cas', reason: 'Windows 应使用哈希比对 + 内容寻址存储');
      } else {
        expect(
          strategy,
          anyOf('rsync-hardlink', 'hardlink'),
          reason: 'Linux/macOS 应使用 rsync 硬链接快照（或原生回退）',
        );
      }
    }, skip: skipReason);

    test('全量备份：创建 / 列表 / 恢复 / 删除', () async {
      final progress = <double>[];
      final created = await service.request(
        'full_create',
        {
          'repoRoot': repoRoot,
          'sourceRoot': sourceRoot,
          'name': '20260101-000000',
          'compressionLevel': 6,
        },
        onProgress: (processed, total) {
          if (total > 0) progress.add(processed / total);
        },
      );
      expect(created.ok, isTrue, reason: created.error);
      expect(created.data['name'], '20260101-000000');
      expect(created.data['files'], 3);
      expect(created.data['storedBytes'] as int, greaterThan(0));
      expect(
        File(p.join(repoRoot, 'full', '20260101-000000.zip')).existsSync(),
        isTrue,
        reason: 'ZIP 归档应落在仓库 full/ 下',
      );

      final status = await service.request('status', {'repoRoot': repoRoot});
      expect(status.ok, isTrue, reason: status.error);
      final full = status.data['full'] as List;
      expect(full, hasLength(1));
      expect(status.data['totalStoredBytes'] as int, greaterThan(0));

      // 恢复：先清空实例目录里的一个文件，确认恢复会补回
      File(p.join(sourceRoot, 'server.properties')).deleteSync();
      final restored = await service.request('full_restore', {
        'repoRoot': repoRoot,
        'name': '20260101-000000',
        'targetRoot': sourceRoot,
      });
      expect(restored.ok, isTrue, reason: restored.error);
      expect(restored.data['files'], 3);
      expect(
        File(p.join(sourceRoot, 'server.properties')).readAsStringSync(),
        'motd=hello\n',
      );

      final deleted = await service.request('full_delete', {
        'repoRoot': repoRoot,
        'name': '20260101-000000',
      });
      expect(deleted.ok, isTrue, reason: deleted.error);
      final after = await service.request('status', {'repoRoot': repoRoot});
      expect(after.data['full'], isEmpty);
    }, skip: skipReason);

    test('增量备份：只存变化内容 / 恢复 / 校验 / 删除', () async {
      final first = await service.request(
        'snapshot_create',
        {
          'repoRoot': repoRoot,
          'sourceRoot': sourceRoot,
          'name': '20260101-010000',
        },
      );
      expect(first.ok, isTrue, reason: first.error);
      expect(first.data['filesTotal'], 3);
      expect(first.data['filesNew'], 3);
      expect(first.data['parent'], isNull, reason: '第一个快照没有增量基线');
      final totalBytes = first.data['bytesTotal'] as int;
      expect(totalBytes, greaterThan(4096));
      final strategy = first.data['strategy'] as String;

      // 只改一个文件 → 第二个快照应复用绝大部分内容
      File(p.join(sourceRoot, 'server.properties'))
          .writeAsStringSync('motd=changed\n');
      final second = await service.request(
        'snapshot_create',
        {
          'repoRoot': repoRoot,
          'sourceRoot': sourceRoot,
          'name': '20260101-020000',
        },
        onProgress: (processed, total) {
          expect(total, greaterThanOrEqualTo(0));
        },
      );
      expect(second.ok, isTrue, reason: second.error);
      expect(second.data['parent'], '20260101-010000');
      expect(second.data['filesModified'], 1);
      expect(second.data['filesUnchanged'], 2);
      expect(
        second.data['bytesAdded'] as int,
        lessThan(totalBytes ~/ 2),
        reason: '增量备份不应重新写入未变化的 4KB 数据',
      );
      expect(second.data['bytesReused'] as int, greaterThan(4000));

      // 快照列表按时间倒序
      final status = await service.request('status', {'repoRoot': repoRoot});
      final snapshots = status.data['snapshots'] as List;
      expect(snapshots, hasLength(2));
      expect(snapshots.first['name'], '20260101-020000');

      // 校验（深度哈希比对）
      final verify = await service.request('snapshot_verify', {
        'repoRoot': repoRoot,
        'name': '20260101-020000',
        'deep': true,
      });
      expect(verify.ok, isTrue, reason: verify.error);
      expect(verify.data['checked'], 3);
      expect(verify.data['missing'], 0);
      expect(verify.data['sizeMismatch'], 0);
      expect(verify.data['hashMismatch'], 0);
      if (strategy == 'cas') {
        expect(
          verify.data['hashed'],
          3,
          reason: 'CAS 策略下每个条目都有内容哈希',
        );
      }

      // 恢复到独立目录，验证增量快照的完整内容
      final restoreTarget = p.join(sandbox.path, 'restored');
      final restored = await service.request('snapshot_restore', {
        'repoRoot': repoRoot,
        'name': '20260101-020000',
        'targetRoot': restoreTarget,
      });
      expect(restored.ok, isTrue, reason: restored.error);
      expect(restored.data['kind'], 'snapshot');
      expect(restored.data['files'], 3);
      expect(
        File(p.join(restoreTarget, 'server.properties')).readAsStringSync(),
        'motd=changed\n',
        reason: '恢复的应是第二份快照的内容',
      );
      expect(
        File(
          p.join(restoreTarget, 'world', 'region', 'r.0.0.mca'),
        ).lengthSync(),
        4096,
      );

      // 删除一个快照：CAS 策略下应回收无人引用的对象
      final deleted = await service.request('snapshot_delete', {
        'repoRoot': repoRoot,
        'name': '20260101-010000',
      });
      expect(deleted.ok, isTrue, reason: deleted.error);
      expect(deleted.data['kind'], 'snapshot');
      final remaining = await service.request('status', {'repoRoot': repoRoot});
      expect(remaining.data['snapshots'], hasLength(1));
    }, skip: skipReason);

    test('参数校验：缺失 repoRoot 与非法快照名', () async {
      final missing = await service.request('status', {});
      expect(missing.ok, isFalse);
      expect(missing.error, contains('repoRoot'));

      final illegal = await service.request('snapshot_create', {
        'repoRoot': repoRoot,
        'sourceRoot': sourceRoot,
        'name': '../evil',
      });
      expect(illegal.ok, isFalse);
      expect(illegal.error, contains('名称'));

      final unknown = await service.request('nope', {});
      expect(unknown.ok, isFalse);
      expect(unknown.error, contains('未知操作'));
    }, skip: skipReason);

    test('取消标志让新任务正常开始（cancel 后仍可备份）', () async {
      service.cancel();
      final result = await service.request('snapshot_create', {
        'repoRoot': repoRoot,
        'sourceRoot': sourceRoot,
        'name': '20260101-030000',
      });
      expect(result.ok, isTrue, reason: '每个 backup_request 开始时会清空取消标志');
    }, skip: skipReason);
  });
}
