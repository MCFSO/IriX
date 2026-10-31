// 实例备份主页布局测试
//
// 产品要求：进入实例「备份」页，主操作区只有两个按钮（全量备份 / 增量备份），
// 备份历史为只读列表行（点按在弹窗里操作），页面本身不再有第三个操作按钮。
// 通过注入假的 [BackupOperations] 避免测试环境触碰真实数据目录 / 数据库。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:irix/l10n/app_localizations.dart';
import 'package:irix/screens/instance_backup_tab.dart';
import 'package:irix/services/backup_manager.dart';
import 'package:irix/utils/apple_widgets.dart';

/// 假备份实现：返回预设的仓库概览，其余操作不允许被调用。
class _FakeBackupOperations implements BackupOperations {
  _FakeBackupOperations(this.snapshot);

  final BackupRepositoryStatus snapshot;

  @override
  Future<BackupRepositoryStatus> status({
    required String instanceId,
    required String rootPath,
  }) async => snapshot;

  @override
  Future<BackupEntry> createFullBackup({
    required String instanceId,
    required String rootPath,
    required int compressionLevel,
    void Function(double? progress)? onProgress,
  }) => throw UnimplementedError('布局测试不应触发全量备份');

  @override
  Future<BackupEntry> createIncrementalBackup({
    required String instanceId,
    required String rootPath,
    String? parent,
    void Function(double? progress)? onProgress,
  }) => throw UnimplementedError('布局测试不应触发增量备份');

  @override
  Future<BackupRestoreInfo> restoreBackup({
    required BackupEntry entry,
    required String instanceId,
    required String rootPath,
    bool prune = false,
    void Function(double? progress)? onProgress,
  }) => throw UnimplementedError('布局测试不应触发恢复');

  @override
  Future<BackupVerifyResult> verifyBackup({
    required BackupEntry entry,
    required String instanceId,
    bool deep = false,
    void Function(double? progress)? onProgress,
  }) => throw UnimplementedError('布局测试不应触发校验');

  @override
  Future<void> deleteBackup({
    required BackupEntry entry,
    required String instanceId,
  }) => throw UnimplementedError('布局测试不应触发删除');

  @override
  Future<int> collectGarbage(String instanceId) async => 0;

  @override
  void cancel() {}
}

BackupRepositoryStatus _emptyStatus() => const BackupRepositoryStatus(
  repoRoot: '/data/backups/abc',
  strategy: 'cas',
  rsyncAvailable: false,
  entries: [],
);

BackupRepositoryStatus _statusWithEntries() => BackupRepositoryStatus(
  repoRoot: '/data/backups/abc',
  strategy: 'rsync-hardlink',
  rsyncAvailable: true,
  rsyncVersion: 'rsync  version 3.2.7  protocol version 31',
  totalLogicalBytes: 30 * 1024 * 1024,
  totalStoredBytes: 6 * 1024 * 1024,
  entries: [
    BackupEntry(
      name: '20260102-030405',
      kind: BackupKind.incremental,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1767225845000),
      strategy: 'rsync-hardlink',
      files: 128,
      bytesTotal: 20 * 1024 * 1024,
      storedBytes: 1024 * 1024,
      durationMs: 4200,
      parent: '20260101-000000',
      filesNew: 4,
      filesModified: 2,
      filesDeleted: 1,
      filesUnchanged: 121,
      bytesAdded: 1024 * 1024,
      bytesReused: 19 * 1024 * 1024,
    ),
    BackupEntry(
      name: '20260101-000000',
      kind: BackupKind.full,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1767139200000),
      strategy: 'zip',
      files: 128,
      bytesTotal: 10 * 1024 * 1024,
      storedBytes: 5 * 1024 * 1024,
      durationMs: 2000,
      compressionLevel: 6,
    ),
  ],
);

void main() {
  Future<void> pumpTab(
    WidgetTester tester,
    BackupOperations operations, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.green,
          useMaterial3: true,
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InstanceBackupTab(
            instanceId: 'abc',
            rootPath: '/data/instances/survival',
            manager: operations,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('主操作区只有全量备份与增量备份两个按钮', (tester) async {
    await pumpTab(tester, _FakeBackupOperations(_emptyStatus()));

    // 两个（且只有两个）主操作按钮
    expect(find.text('全量备份'), findsOneWidget);
    expect(find.text('增量备份'), findsOneWidget);
    expect(find.byType(AppleButton), findsNWidgets(2));
    // 页面级没有其它按钮（历史行不是按钮，空列表时也没有）
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.byType(FloatingActionButton), findsNothing);

    // 仓库信息与空状态提示
    expect(find.textContaining('/data/backups/abc'), findsOneWidget);
    expect(find.textContaining('哈希比对 + 内容寻址存储'), findsOneWidget);
    expect(find.text('还没有备份，点击上方按钮创建第一个备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('备份历史按时间倒序展示，点按行打开详情弹窗', (tester) async {
    await pumpTab(tester, _FakeBackupOperations(_statusWithEntries()));

    expect(find.text('备份历史'), findsOneWidget);
    expect(find.textContaining('2 个备份'), findsOneWidget);
    // 两行历史（每行一个 chevron）
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    // 第一行为最新的增量快照
    expect(find.textContaining('增量'), findsWidgets);
    // 详情弹窗按钮不计入主页按钮
    expect(find.byType(AppleButton), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    expect(find.text('备份详情'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.text('校验'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.textContaining('20260102-030405'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗口下布局不溢出', (tester) async {
    await pumpTab(
      tester,
      _FakeBackupOperations(_statusWithEntries()),
      size: const Size(720, 480),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('全量备份'), findsOneWidget);
    expect(find.text('增量备份'), findsOneWidget);
  });
}
