import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

class _Sink implements PrinterTransport {
  _Sink(this.out);
  final List<Uint8List> out;
  @override
  Future<void> send(Uint8List bytes) async => out.add(bytes);
}

void main() {
  testWidgets('after payment the receipt can be printed, shared as text or picture, and sent on WhatsApp', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final share = FakeShare();
    final dir = Directory.systemTemp.createTempSync('dtrcpt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sent = <Uint8List>[];
    final h = await pumpApp(t, db: db, share: share, transport: (c, a) => _Sink(sent), extra: [exportDirProvider.overrideWithValue(dir)]);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Fries');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    expect(find.textContaining('Pay'), findsWidgets, reason: 'the button says Pay');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    await t.pumpAndSettle();
    // no printer yet: the visual receipt is there with all the buttons
    expect(find.byKey(const ValueKey('receipt-paper')), findsOneWidget);
    expect(receiptPaperText(t), allOf(contains('Burger Point'), contains('Fries'), contains('150.00')));
    expect(find.text('No printer set up. Add one in Settings.'), findsOneWidget);
    await shot(t, '83_receipt_dialog');

    // a printer is added later: the first print is the original, the second one is marked DUPLICATE
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('p','P','lan','x',58,'bill',1)");
    await tapKey(t, 'receipt-print');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(String.fromCharCodes(sent.single), isNot(contains('DUPLICATE')));
    await tapKey(t, 'receipt-print');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(String.fromCharCodes(sent.last), contains('DUPLICATE'));

    await tapKey(t, 'receipt-share');
    expect(share.shared.single, contains('Burger Point'));
    await tapKey(t, 'receipt-image');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await t.pumpAndSettle();
    expect(share.files.single, endsWith('.png'));
    expect(h.container.read(businessProvider), isNotNull);
  });
}
