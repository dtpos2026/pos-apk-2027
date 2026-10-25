import 'dart:io';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/app/whatsapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('promotion: pick customers, WhatsApp opens for each with the personal message; the list exports to CSV in Downloads', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final sent = <(String, String)>[];
    final saver = FakeSaver();
    final share = FakeShare();
    final dir = Directory.systemTemp.createTempSync('dtpromo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final h = await pumpApp(t, db: db, saver: saver, share: share, extra: [
      exportDirProvider.overrideWithValue(dir),
      whatsAppOpenerProvider.overrideWithValue((phone, text) async {
        sent.add((phone, text));
        return true;
      }),
    ]);
    final svc = h.container.read(customerServiceProvider);
    await svc.save(name: 'Ahmed', phone: '0300-1111111', staffId: owner);
    await svc.save(name: 'Bilal', phone: '0311-2222222', staffId: owner);
    await svc.save(name: 'NoPhone', staffId: owner);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'customers', 'Customers');
    await tapKey(t, 'promo-open-screen');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('promo-c-NoPhone')), findsNothing, reason: 'only customers with a phone number');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('promo-start'))).onPressed, isNull, reason: 'nobody picked yet');
    await tapKey(t, 'promo_t_thanks');
    await tapKey(t, 'promo-all');
    await shot(t, '96_promo');
    await tapKey(t, 'promo-start');
    expect(find.byKey(const ValueKey('promo-progress')), findsOneWidget);
    expect(find.textContaining('Burger Point'), findsWidgets);
    await tapKey(t, 'promo-open');
    await tapKey(t, 'promo-skip');
    expect(find.byKey(const ValueKey('promo-done')), findsOneWidget);
    expect(sent, hasLength(1), reason: 'one opened, one skipped');
    expect(sent.single.$2, contains('Ahmed'));
    expect(sent.single.$2, contains('Burger Point'));
    expect(sent.single.$1, startsWith('92'), reason: 'international number for WhatsApp');
    await tapKey(t, 'promo-close');

    await t.ensureVisible(find.byKey(const ValueKey('customers-csv')));
    await t.pumpAndSettle();
    await tapKey(t, 'customers-csv');
    for (var k = 0; k < 20 && (saver.saved.isEmpty || share.files.isEmpty); k++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(saver.saved.single.mime, 'text/csv');
    expect(saver.saved.single.name, 'customers.csv');
    expect(share.files.single, endsWith('customers.csv'));
    expect(File(share.files.single).readAsStringSync(), contains('Ahmed,0300-1111111'));
  });
}
