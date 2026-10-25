import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

void main() {
  testWidgets('a customer gets a photo (camera or gallery), it shows in the list, and it can be removed', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final jpg = Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 48)));
    final dir = Directory.systemTemp.createTempSync('dtcust');
    addTearDown(() => dir.deleteSync(recursive: true));
    final h = await pumpApp(t, db: db, logoPicker: FakeLogoPicker(jpg), extra: [menuImageDirProvider.overrideWithValue(dir)]);
    await h.container.read(customerServiceProvider).save(name: 'Ahmed Raza', phone: '0300-1111111', staffId: owner);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'customers', 'Customers');
    await tapKey(t, 'customer-Ahmed Raza');
    await tapKey(t, 'cust-photo-camera');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    final path = (await db.customSelect("SELECT image_path AS p FROM customer WHERE name = 'Ahmed Raza'").getSingle()).data['p'] as String?;
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(find.byKey(const ValueKey('cust-photo-remove')), findsOneWidget);
    await shot(t, '95_customer_photo');
    await tapKey(t, 'cust-photo-remove');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect((await db.customSelect("SELECT image_path AS p FROM customer WHERE name = 'Ahmed Raza'").getSingle()).data['p'], isNull);
    expect(File(path).existsSync(), isFalse, reason: 'the old file is deleted too');
  });
}
