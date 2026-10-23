import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/text_rasterizer.dart';
import 'package:dt_food_pos/domain/escpos.dart';
import 'package:dt_food_pos/features/settings/receipt_paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

Uint8List logoPng() {
  final i = img.Image(width: 240, height: 120, numChannels: 4)..clear(img.ColorRgba8(255, 255, 255, 255));
  img.fillCircle(i, x: 120, y: 60, radius: 52, color: img.ColorRgba8(0, 0, 0, 255));
  img.fillRect(i, x1: 105, y1: 40, x2: 135, y2: 80, color: img.ColorRgba8(255, 255, 255, 255));
  return Uint8List.fromList(img.encodePng(i));
}

Future<void> openDesigner(WidgetTester t) async {
  await t.tap(find.text('Settings'));
  await t.pumpAndSettle();
  await t.ensureVisible(find.byKey(const ValueKey('receipt-design-tile')));
  await t.tap(find.byKey(const ValueKey('receipt-design-tile')));
  await t.pumpAndSettle();
}

String previewText(WidgetTester t) =>
    t.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.byType(Text))).map((w) => w.data ?? '').join('\n');

Future<void> tapScroll(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> settleImages(WidgetTester t) async {
  await t.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('designer: header details are editable with a live preview; switches hide blocks; save persists', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await openDesigner(t);
    await shot(t, '20_receipt_design');

    var txt = previewText(t);
    expect(txt, contains('Burger Point'));
    expect(txt, contains('Main Bazaar, Burewala'));
    expect(txt, contains('Tel: 0300-0000000'));

    await typeInto(t, find.byKey(const ValueKey('rd-name')), 'Shan Food Corner');
    await typeInto(t, find.byKey(const ValueKey('rd-address')), 'Chowk Azam, Burewala');
    await typeInto(t, find.byKey(const ValueKey('rd-phone')), '0345-1873354');
    await typeInto(t, find.byKey(const ValueKey('rd-header')), 'Since 1999');
    await typeInto(t, find.byKey(const ValueKey('rd-footer')), 'Open 11am to 2am\nFollow us @shanfood');
    txt = previewText(t);
    for (final s in ['Shan Food Corner', 'Chowk Azam, Burewala', 'Tel: 0345-1873354', 'Since 1999', 'Open 11am to 2am', 'Follow us @shanfood']) {
      expect(txt, contains(s));
    }
    expect(txt, isNot(contains('Thank you')));

    await tapScroll(t, 'sw-address');
    expect(previewText(t), isNot(contains('Chowk Azam')));
    await tapScroll(t, 'sw-address');
    expect(previewText(t), contains('Chowk Azam'));

    await tapScroll(t, 'rd-save');
    final biz = (await db.customSelect('SELECT name, address, phone FROM business_profile').getSingle()).data;
    expect(biz, {'name': 'Shan Food Corner', 'address': 'Chowk Azam, Burewala', 'phone': '0345-1873354'});
    final cfg = (await db.customSelect("SELECT config FROM receipt_template WHERE id = 'bill'").getSingle()).data['config'] as String;
    expect(cfg, contains('Since 1999'));
    expect(cfg, contains('Follow us @shanfood'));
  });

  testWidgets('designer: the logo can be chosen, appears centred in the preview, is saved, and can be removed', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final dir = Directory.systemTemp.createTempSync('dtlogo');
    addTearDown(() => dir.deleteSync(recursive: true));
    await pumpApp(t, db: db, tablet: true, logoPicker: FakeLogoPicker(logoPng()), logoDir: dir);
    await signIn(t, 'Ali', '1234');
    await openDesigner(t);

    expect(find.byKey(const ValueKey('logo-preview')), findsNothing);
    await tapScroll(t, 'choose-logo');
    await settleImages(t);
    expect(find.byKey(const ValueKey('logo-preview')), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('logo-preview'))).width, closeTo(ReceiptPaper.textWidthFor(32), 1)); // full paper width: logo is centred inside it
    await shot(t, '21_receipt_design_logo');

    await tapScroll(t, 'rd-save');
    final path = (await db.customSelect('SELECT logo_path FROM business_profile').getSingle()).data['logo_path'] as String;
    expect(File(path).existsSync(), isTrue);

    await tapScroll(t, 'remove-logo');
    expect(find.byKey(const ValueKey('logo-preview')), findsNothing);
    expect((await db.customSelect('SELECT logo_path FROM business_profile').getSingle()).data['logo_path'], isNull);
    expect(File(path).existsSync(), isFalse);
  });

  testWidgets('designer: a picture that is not an image is refused, nothing is stored', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, tablet: true, logoPicker: FakeLogoPicker(Uint8List.fromList([1, 2, 3, 4, 5])));
    await signIn(t, 'Ali', '1234');
    await openDesigner(t);
    await tapScroll(t, 'choose-logo');
    expect(find.text('This file could not be used as a logo'), findsOneWidget);
    expect((await db.customSelect('SELECT logo_path FROM business_profile').getSingle()).data['logo_path'], isNull);
  });

  testWidgets('designer: test print sends the designed bill, including the logo bitmap, to the printer', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final dir = Directory.systemTemp.createTempSync('dtlogo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final server = await t.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    addTearDown(() => server!.close());
    final got = <Uint8List>[];
    server!.listen((c) {
      final b = BytesBuilder();
      c.listen(b.add, onDone: () => got.add(b.toBytes()));
    });
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('p','P','lan','127.0.0.1:${server.port}',58,'bill',1)");

    await pumpApp(t, db: db, tablet: true, logoPicker: FakeLogoPicker(logoPng()), logoDir: dir);
    await signIn(t, 'Ali', '1234');
    await openDesigner(t);
    await tapScroll(t, 'choose-logo');
    await typeInto(t, find.byKey(const ValueKey('rd-name')), 'Shan Food Corner');
    await tapScroll(t, 'print-test');
    for (var i = 0; i < 30 && got.isEmpty; i++) {
      await t.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
    final jobs = (await db.customSelect('SELECT status, last_error FROM print_job').get()).map((r) => r.data).toList();
    expect(got, hasLength(1), reason: 'print jobs: $jobs');
    final bytes = got.single;
    expect(latin1.decode(bytes, allowInvalid: true), contains('Shan Food Corner'));
    expect(latin1.decode(bytes, allowInvalid: true), contains('Powered by Digital Target'));
    final i = _find(bytes, [0x1D, 0x76, 0x30, 0x00]);
    expect(i, isNot(-1)); // the logo bitmap
    expect(bytes[i + 4], 48); // full 384-dot width: centred by padding
  });

  testWidgets('Urdu bill: labels switch language, rows flip right-to-left and the preview shows the Urdu text', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await openDesigner(t);
    final urdu = find.descendant(of: find.byKey(const ValueKey('bill-language')), matching: find.text('اردو'));
    await t.ensureVisible(urdu);
    await t.pumpAndSettle();
    await t.tap(urdu);
    await t.pumpAndSettle();
    final txt = previewText(t);
    expect(txt, contains('بل نمبر'));
    expect(txt, contains('شکریہ'));
    expect(txt, contains('چکن کڑاہی')); // Urdu sample item shows how Urdu item names print
    await shot(t, '22_receipt_design_urdu');
  });

  testWidgets('rasterizer: Urdu text becomes a full-width 1-bit bitmap with ink in it', (t) async {
    await t.runAsync(loadAppFonts);
    final r = await t.runAsync(() => const FlutterTextRasterizer().text('چکن کڑاہی', widthPx: 384, align: PrintAlign.center));
    expect(r!.widthPx, 384);
    expect(r.heightPx, greaterThan(20));
    var ink = 0, left = 0, right = 0;
    for (var y = 0; y < r.heightPx; y++) {
      for (var x = 0; x < r.widthPx; x++) {
        if (r.pixel(x, y)) {
          ink++;
          if (x < 96) left++;
          if (x >= 288) right++;
        }
      }
    }
    expect(ink, greaterThan(150));
    expect(left + right, 0); // centred: nothing in the outer quarters
    final row = await t.runAsync(() => const FlutterTextRasterizer().row('چکن کڑاہی', '1,200.00', widthPx: 384));
    var l = 0, rr = 0;
    for (var y = 0; y < row!.heightPx; y++) {
      for (var x = 0; x < row.widthPx; x++) {
        if (row.pixel(x, y)) {
          if (x < 192) {
            l++;
          } else {
            rr++;
          }
        }
      }
    }
    expect(l, greaterThan(50));
    expect(rr, greaterThan(50)); // name on one side, amount on the other
  });
}

int _find(Uint8List b, List<int> pat) {
  for (var i = 0; i <= b.length - pat.length; i++) {
    var ok = true;
    for (var j = 0; j < pat.length; j++) {
      if (b[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
