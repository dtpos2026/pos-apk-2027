import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('owner closes the day from Reports, the Z report is shared and the day is locked', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final share = FakeShare();
    await pumpApp(t, db: db, share: share);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'reports', 'Reports');
    await t.ensureVisible(find.byKey(const ValueKey('open-day-close')));
    await tapKey(t, 'open-day-close');
    expect(find.text('Day is open. Close it after the last bill.'), findsOneWidget);
    await shot(t, '70_day_close');
    await tapKey(t, 'day-close');
    await tapKey(t, 'day-close-confirm');
    expect(find.textContaining('This report is final'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-close')), findsNothing);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM day_close').getSingle()).data['n'], 1);
    await t.ensureVisible(find.byKey(const ValueKey('day-share')));
    await tapKey(t, 'day-share');
    expect(share.shared.single, contains('DAY CLOSE (Z REPORT)'));
    expect(share.shared.single, contains('Burger Point'));
  });

  testWidgets('REGRESSION: a cash shift that was never closed by hand no longer blocks Day Close; sales -> close -> saved Z report -> next business day', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final share = FakeShare();
    final h = await pumpApp(t, db: db, share: share);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift'); // the cashier opened the drawer (as in the owner's phone) and never closed the shift
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    await tapKey(t, 'new-sale');
    expect(await _n(db, 'SELECT COUNT(*) AS n FROM shift WHERE closed_at IS NULL'), 1, reason: 'the stale shift is open');

    await openTab(t, 'reports', 'Reports');
    await t.ensureVisible(find.byKey(const ValueKey('open-day-close')));
    await tapKey(t, 'open-day-close');
    expect(find.text('A cash shift is still open. Close all shifts first.'), findsNothing, reason: 'the old blocking message is gone');
    expect(find.byKey(const ValueKey('day-problems')), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('day-close')));
    await tapKey(t, 'day-close');
    expect(find.byKey(const ValueKey('day-shifts-note')), findsOneWidget, reason: 'the dialog explains the open shift is closed with the day');
    await tapKey(t, 'day-close-confirm');

    expect(find.textContaining('This report is final'), findsOneWidget);
    expect(await _n(db, 'SELECT COUNT(*) AS n FROM day_close'), 1, reason: 'the Z report is saved');
    expect(await _n(db, 'SELECT COUNT(*) AS n FROM shift WHERE closed_at IS NULL'), 0, reason: 'the shift was closed with the day');
    expect(find.byKey(const ValueKey('day-close')), findsNothing, reason: 'cannot be closed twice');
    expect(h.container.read(shiftProvider), isNull, reason: 'the signed-in cashier must open a new shift for the next business day');
  });

  testWidgets('a report slip can be previewed, printed, shared or saved as a PNG picture', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('p','P','lan','main',58,'bill',1)");
    final sent = <List<int>>[];
    final share = FakeShare();
    final saver = FakeSaver();
    final dir = Directory.systemTemp.createTempSync('dtslip');
    addTearDown(() => dir.deleteSync(recursive: true));
    await pumpApp(t, db: db, share: share, saver: saver, transport: (c, a) => _Sink(sent), extra: [exportDirProvider.overrideWithValue(dir)]);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'reports', 'Reports');
    await t.ensureVisible(find.byKey(const ValueKey('open-day-close')));
    await tapKey(t, 'open-day-close');
    await t.ensureVisible(find.byKey(const ValueKey('day-preview')));
    await tapKey(t, 'day-preview');
    expect(find.byKey(const ValueKey('receipt-paper')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.text('Burger Point')), findsOneWidget);
    await shot(t, '82_slip_preview');
    await t.tap(find.descendant(of: find.byKey(const ValueKey('slip-paper')), matching: find.text('80 mm')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-paper')), findsOneWidget);

    await t.runAsync(() async {});
    await t.ensureVisible(find.byKey(const ValueKey('slip-print')));
    await t.pumpAndSettle();
    await tapKey(t, 'slip-print');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pumpAndSettle();
    expect(sent, isNotEmpty);

    await t.ensureVisible(find.byKey(const ValueKey('slip-share-png')));
    await t.pumpAndSettle();
    await tapKey(t, 'slip-share-png');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(share.files.single, endsWith('.png'));
    expect(File(share.files.single).lengthSync(), greaterThan(1000));

    await t.ensureVisible(find.byKey(const ValueKey('slip-save-png')));
    await t.pumpAndSettle();
    for (final e in find.byType(ScaffoldMessenger).evaluate()) {
      ((e as StatefulElement).state as ScaffoldMessengerState).clearSnackBars(); // earlier messages queue up
    }
    await t.pumpAndSettle();
    await tapKey(t, 'slip-save-png');
    for (var k = 0; k < 10 && find.textContaining('Saved in').evaluate().isEmpty; k++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Saved in'), findsOneWidget);
    expect(find.textContaining('Pictures/DT Food POS'), findsOneWidget, reason: 'the PNG goes to the gallery folder, not a hidden app folder');
    expect(saver.saved.single.gallery, isTrue);
    expect(saver.saved.single.mime, 'image/png');
    await t.ensureVisible(find.byKey(const ValueKey('slip-share-text')));
    await t.pumpAndSettle();
    await tapKey(t, 'slip-share-text');
    expect(share.shared.single, contains('DAY CLOSE (Z REPORT)'));
  });
}

class _Sink implements PrinterTransport {
  _Sink(this.out);
  final List<List<int>> out;
  @override
  Future<void> send(Uint8List bytes) async => out.add(bytes);
}

Future<int> _n(dynamic db, String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;
