// backup_manager 模型与解析单元测试
// 只测试纯 Dart 逻辑（JSON → 模型、备份名生成、进度映射），不触碰 FFI / 文件系统。
// 端到端行为见 test/backup_ffi_test.dart。

import 'package:flutter_test/flutter_test.dart';

import 'package:irix/services/backup_manager.dart';

void main() {
  group('backup_manager 模型解析', () {
    test('newBackupName 生成本地时间 YYYYMMDD-HHMMSS', () {
      final name = BackupManager.instance.newBackupName(
        DateTime(2026, 1, 2, 3, 4, 5),
      );
      expect(name, '20260102-030405');
    });

    test('快照 JSON → BackupEntry（增量）', () {
      final entry = BackupEntry.fromSnapshotJson({
        'name': '20260102-030405',
        'createdAt': 1767225845,
        'parent': '20260101-000000',
        'strategy': 'cas',
        'label': 'manual',
        'sourceRoot': 'D:/instances/survival',
        'filesTotal': 128,
        'filesNew': 4,
        'filesModified': 2,
        'filesDeleted': 1,
        'filesUnchanged': 121,
        'bytesTotal': 10485760,
        'bytesAdded': 4096,
        'bytesReused': 10481664,
        'durationMs': 3210,
        'storedBytes': 4096,
        'dirs': 12,
        'symlinksSkipped': 0,
        'note': 'rsync 回退',
      });
      expect(entry.name, '20260102-030405');
      expect(entry.kind, BackupKind.incremental);
      expect(entry.isIncremental, isTrue);
      expect(entry.parent, '20260101-000000');
      expect(entry.strategy, 'cas');
      expect(entry.files, 128);
      expect(entry.bytesAdded, 4096);
      expect(entry.bytesReused, 10481664);
      expect(entry.createdAt.millisecondsSinceEpoch, 1767225845000);
      expect(entry.note, 'rsync 回退');
    });

    test('全量 JSON → BackupEntry（ZIP）', () {
      final entry = BackupEntry.fromFullJson({
        'name': '20260102-040506',
        'createdAt': 1767225845,
        'sourceRoot': 'D:/instances/survival',
        'compressionLevel': 6,
        'files': 128,
        'bytesTotal': 10485760,
        'storedBytes': 5242880,
        'durationMs': 1500,
      });
      expect(entry.kind, BackupKind.full);
      expect(entry.isIncremental, isFalse);
      expect(entry.strategy, 'zip');
      expect(entry.compressionLevel, 6);
      expect(entry.storedBytes, 5242880);
    });

    test('status JSON 合并全量/增量并按时间倒序', () {
      final status = BackupRepositoryStatus.fromJson(
        repoRoot: 'D:/data/backups/abc',
        json: {
          'repoRoot': 'D:/data/backups/abc',
          'strategy': 'rsync-hardlink',
          'rsyncAvailable': true,
          'rsyncVersion': 'rsync  version 3.2.7  protocol version 31',
          'totalLogicalBytes': 31457280,
          'totalStoredBytes': 6291456,
          'snapshots': [
            {'name': 'snap-old', 'createdAt': 1000, 'strategy': 'rsync-hardlink'},
            {'name': 'snap-new', 'createdAt': 3000, 'strategy': 'rsync-hardlink'},
          ],
          'full': [
            {'name': 'full-mid', 'createdAt': 2000, 'files': 3},
          ],
        },
      );
      expect(status.strategy, 'rsync-hardlink');
      expect(status.rsyncAvailable, isTrue);
      expect(status.entries.map((e) => e.name).toList(), [
        'snap-new',
        'full-mid',
        'snap-old',
      ]);
      expect(status.totalStoredBytes, 6291456);
      expect(status.entries[1].kind, BackupKind.full);
    });

    test('恢复结果与校验结果', () {
      final restore = BackupRestoreInfo.fromJson({
        'name': 'snap-new',
        'kind': 'snapshot',
        'strategy': 'cas',
        'files': 128,
        'bytes': 10485760,
        'pruned': 2,
        'durationMs': 900,
      });
      expect(restore.kind, BackupKind.incremental);
      expect(restore.files, 128);
      expect(restore.pruned, 2);

      final okVerify = BackupVerifyResult.fromJson({
        'name': 'snap-new',
        'strategy': 'cas',
        'checked': 128,
        'hashed': 128,
        'missing': 0,
        'sizeMismatch': 0,
        'hashMismatch': 0,
        'problems': <String>[],
      });
      expect(okVerify.ok, isTrue);
      expect(okVerify.problemCount, 0);

      final badVerify = BackupVerifyResult.fromJson({
        'name': 'snap-new',
        'strategy': 'cas',
        'checked': 128,
        'hashed': 3,
        'missing': 1,
        'sizeMismatch': 2,
        'hashMismatch': 0,
        'problems': ['a.txt 缺失', 'b.txt 大小不匹配'],
      });
      expect(badVerify.ok, isFalse);
      expect(badVerify.problemCount, 3);
      expect(badVerify.problems, hasLength(2));
    });

    test('BackupException 保留取消标记', () {
      const cancelled = BackupException('用户取消', cancelled: true);
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.toString(), '用户取消');
    });
  });
}
