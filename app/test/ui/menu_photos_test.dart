import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/data/menu_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

Uint8List photo(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 80, 20))));

void main() {
  test('pictures are cut square and shrunk to a small JPEG; non-pictures are refused', () {
    final out = img.decodeJpg(MenuImageStore.normalize(photo(1200, 800)))!;
    expect([out.width, out.height], [480, 480]);
    expect(() => MenuImageStore.normalize(Uint8List.fromList([1, 2, 3])), throwsA(isA<MenuImageException>()));
  });

  testWidgets('owner adds a photo to an item and a category; the selling screen shows them; removing works', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final picker = FakeLogoPicker(photo(900, 900));
    final dir = Directory.systemTemp.createTempSync('menuimg');
    await pumpApp(t, db: db, logoPicker: picker, extra: [menuImageDirOverride(dir)]);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'menu', 'Menu');
    await t.tap(find.byKey(const ValueKey('menu-Zinger Burger')));
    await t.pumpAndSettle();
    await tapKey(t, 'item-photo');
    expect(find.byKey(const ValueKey('item-photo-remove')), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('item-save')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await t.pump();
      }
    });
    await t.pumpAndSettle();
    final path = (await db.customSelect("SELECT image_path FROM product WHERE name = 'Zinger Burger'").getSingle()).data['image_path'] as String?;
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(File(path).readAsBytesSync().take(2), [0xFF, 0xD8]); // JPEG

    // category picture
    await tapKey(t, 'categories');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('category-photo-Drinks')));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await t.pump();
      }
    });
    await t.pumpAndSettle();
    expect((await db.customSelect("SELECT image_path FROM category WHERE name = 'Drinks'").getSingle()).data['image_path'], isNotNull);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();

    // the selling screen shows the item's own picture
    await openTab(t, 'pos', 'Sell');
    if (find.byKey(const ValueKey('open-shift')).evaluate().isNotEmpty) {
      await tapKey(t, 'open-shift');
      await tapKey(t, 'amount-ok');
    }
    await t.scrollUntilVisible(find.byKey(const ValueKey('product-Zinger Burger')), 150, scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first);
    expect(find.descendant(of: find.byKey(const ValueKey('product-Zinger Burger')), matching: find.byType(Image)), findsOneWidget);
    await shot(t, '53_pos_with_photos');

    // remove the item photo again: the file is deleted
    await openTab(t, 'menu', 'Menu');
    await t.tap(find.byKey(const ValueKey('menu-Zinger Burger')));
    await t.pumpAndSettle();
    await tapKey(t, 'item-photo-remove');
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT image_path FROM product WHERE name = 'Zinger Burger'").getSingle()).data['image_path'], isNull);
    expect(File(path).existsSync(), isFalse);
  });
}
