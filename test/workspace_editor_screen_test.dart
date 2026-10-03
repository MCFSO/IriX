import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irix/screens/workspace_editor_screen.dart';

void main() {
  testWidgets('opens and saves a local text file', (tester) async {
    final dir = Directory.systemTemp.createTempSync('irix-editor-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}server.properties');
    file.writeAsStringSync('motd=Hello\r\n');

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceEditorScreen(rootPath: dir.path)),
    );
    await tester.pump();

    expect(find.text('server.properties'), findsWidgets);
    await tester.runAsync(() async {
      await tester.tap(find.text('server.properties').first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 20 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'motd=World\r\n');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      for (
        var i = 0;
        i < 20 && file.readAsStringSync() != 'motd=World\r\n';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(file.readAsStringSync(), 'motd=World\r\n');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow layout switches between explorer and editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final dir = Directory.systemTemp.createTempSync('irix-editor-compact-');
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceEditorScreen(rootPath: dir.path)),
    );
    expect(find.text('资源管理器'), findsOneWidget);
    await tester.tap(find.byTooltip('显示编辑器'));
    await tester.pump();
    expect(find.text('从左侧选择文件开始编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
