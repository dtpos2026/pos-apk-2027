import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('Share menu: preview of the pages, PNG and PDF shared with the message, saved to the phone, QR card, and a "menu changed" warning after an edit', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final share = FakeShare();
    final saver = FakeSaver();
    final h = await pumpApp(t, db: db, share: share, saver: saver);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'online', 'Delivery Orders');
    await t.tap(find.byKey(const ValueKey('share-menu')));
    await t.pump();
    for (var i = 0; i < 40 && find.byKey(const ValueKey('menu-pages')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('menu-pages')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-page-count')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-changed')), findsNothing);
    final message = (t.widget<TextField>(find.byKey(const ValueKey('menu-message'))).controller!.text);
    expect(message, allOf(contains('Burger Point'), contains('0300-0000000')));
    await shot(t, '101_menu_share');

    Future<void> tapAsync(String key) async {
      await t.ensureVisible(find.byKey(ValueKey(key)));
      await t.tap(find.byKey(ValueKey(key)));
      for (var i = 0; i < 30; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    await tapAsync('menu-share-png');
    expect(share.multi.single.paths.every((p) => p.endsWith('.png')), isTrue);
    expect(share.multi.single.text, message);
    await tapAsync('menu-share-pdf');
    expect(share.multi.last.paths.single, endsWith('menu.pdf'));
    await tapAsync('menu-save-pdf');
    expect(saver.saved.last.mime, 'application/pdf');
    await tapAsync('menu-save-png');
    expect(saver.saved.where((s) => s.mime == 'image/png' && s.gallery), isNotEmpty);
    await tapAsync('menu-qr');
    for (var i = 0; i < 40 && find.byKey(const ValueKey('wa-qr-card')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('wa-qr-card')), findsOneWidget);
    // the customer's message can be chosen: one QR per message, or all on one poster
    for (final k in ['qr-pick-qr_msg_menu', 'qr-pick-all']) {
      await t.tap(find.byKey(ValueKey(k)));
      for (var i = 0; i < 15; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('wa-qr-card')), findsOneWidget);
    }
    await tapKey(t, 'qr-share');
    expect(share.multi.last.paths.single, endsWith('whatsapp-order-qr.png'));
    await t.tap(find.text('Save pictures').last);
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5)); // close the dialog
    await t.pumpAndSettle();

    // a price changes: opening the screen again says the shared menu is out of date, and the new price is in the new preview
    await db.customStatement("UPDATE product SET base_price_minor = 49900 WHERE name = 'Zinger Burger'");
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-menu')));
    await t.pump();
    for (var i = 0; i < 40 && find.byKey(const ValueKey('menu-pages')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('menu-changed')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
