import 'dart:io';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/backup_service.dart';
import 'package:dt_food_pos/data/restore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<void> _openBackup(WidgetTester t) async {
  await openTab(t, 'settings', 'Settings');
  await t.scrollUntilVisible(find.byKey(const ValueKey('restore')), 300, scrollable: verticalScroll);
  await t.drag(verticalScroll, const Offset(0, -160));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('backup is made and offered to share; restore checks the passphrase and prepares the data for the next start', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final docs = Directory.systemTemp.createTempSync('docs');
    final backups = Directory('${docs.path}/backups');
    final file = (await t.runAsync(() => BackupService(db, iterations: 2000).createBackup(passphrase: 'secret123', dir: backups)))!;
    final share = FakeShare();
    await pumpApp(t, db: db, share: share, backupDir: backups, extra: [
      docsDirProvider.overrideWithValue(docs),
      backupFilePickerProvider.overrideWithValue(FakeImportPicker(file.path.split('/').last, file.readAsBytesSync())),
    ]);
    await signIn(t, 'Ali', '1234');
    await _openBackup(t);

    // wrong passphrase: refused, nothing prepared
    await tapKey(t, 'restore');
    await t.enterText(find.byKey(const ValueKey('restore-pass')), 'wrong-pass');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('restore-go')));
      for (var i = 0; i < 60 && find.textContaining('Wrong passphrase').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    expect(find.textContaining('Wrong passphrase'), findsOneWidget);
    expect(pendingRestoreDir(docs).existsSync(), isFalse);

    // right passphrase: ready, the app asks to be reopened
    await t.enterText(find.byKey(const ValueKey('restore-pass')), 'secret123');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('restore-go')));
      for (var i = 0; i < 60 && find.byKey(const ValueKey('restore-close-app')).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    expect(find.text('Backup is ready'), findsOneWidget);
    expect(File('${pendingRestoreDir(docs).path}/$dbFileName').existsSync(), isTrue);
  });
}
