import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/features/menu/share/menu_doc.dart';
import 'package:dt_food_pos/features/menu/share/menu_pdf.dart';
import 'package:dt_food_pos/features/menu/share/menu_png.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import '../helpers/harness.dart';

int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

void main() {
  testWidgets('the menu becomes PNG pages and a PDF with names, prices, sizes, deals and branding; a long menu takes several pages', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    await t.runAsync(loadAppFonts);
    // a picture for one item, a description, sizes, a deal and many more items
    final dir = Directory.systemTemp.createTempSync('menuimg');
    final jpg = img.encodeJpg(img.Image(width: 300, height: 300)..clear(img.ColorRgb8(200, 60, 60)));
    final f = File('${dir.path}/a.jpg')..writeAsBytesSync(jpg);
    await db.customStatement("UPDATE product SET image_path = ?, description = 'Crispy chicken, spicy mayo' WHERE name = 'Zinger Burger'", [f.path]);
    await db.customStatement("INSERT INTO product_variant(id,product_id,name,price_minor,updated_at) SELECT 'v1', id, 'Large', 60000, 1 FROM product WHERE name = 'Beef Burger'");
    await db.customStatement("INSERT INTO category(id,name,updated_at) VALUES ('deals','Deals',1)");
    await db.customStatement("INSERT INTO product(id,name,category_id,base_price_minor,kind,updated_at) VALUES ('d1','Family Deal','deals',200000,'combo',1)");
    await db.customStatement("INSERT INTO deal_item(id,deal_id,product_id,qty_milli) SELECT 'di1','d1',id,2000 FROM product WHERE name = 'Zinger Burger'");
    for (var i = 0; i < 70; i++) {
      await db.customStatement("INSERT INTO product(id,name,category_id,base_price_minor,updated_at) VALUES ('x$i','Extra item $i with a rather long name to wrap sometimes',(SELECT id FROM category WHERE name = 'Burgers'),${10000 + i},1)");
    }
    await db.customStatement("INSERT INTO product(id,name,category_id,base_price_minor,updated_at) VALUES ('u1','چکن کڑاہی',(SELECT id FROM category WHERE name = 'Burgers'),150000,1)");
    expect(owner, isNotEmpty);

    final doc = (await t.runAsync(() => loadMenuDoc(db, primary: 0xFFC92A2A, accent: 0xFFF59F00)))!;
    expect(doc.name, 'Burger Point');
    expect(doc.sections.map((s) => s.title), contains('Deals'));
    expect(doc.sections.last.deals, isTrue);
    final deal = doc.sections.last.entries.single;
    expect([deal.name, deal.price, deal.inside], ['Family Deal', '2,000', ['2 x Zinger Burger']]);
    final zinger = doc.sections.expand((s) => s.entries).firstWhere((e) => e.name == 'Zinger Burger');
    expect([zinger.description, zinger.image != null, zinger.price], ['Crispy chicken, spicy mayo', true, '450']);
    final beef = doc.sections.expand((s) => s.entries).firstWhere((e) => e.name == 'Beef Burger');
    expect([beef.price, beef.sizes], ['from 600', ['Large  600']]);
    expect(doc.qrLink, startsWith('https://wa.me/'));

    final pages = (await t.runAsync(() => renderMenuPng(doc)))!;
    expect(pages.length, greaterThan(1), reason: '75 items do not fit on one picture');
    for (final p in pages) {
      expect(p.take(8).toList(), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: 'a PNG');
      expect([_u32(p, 16), _u32(p, 20)], [1080, 1528], reason: 'every page has the same size');
    }
    if (Platform.environment['SCREENSHOT_DIR'] != null) {
      for (var i = 0; i < pages.length; i++) {
        File('${Platform.environment['SCREENSHOT_DIR']}/menu_page_${i + 1}.png').writeAsBytesSync(pages[i]);
      }
    }

    final font = pw.Font.ttf(File('assets/fonts/NotoNaskhArabic.ttf').readAsBytesSync().buffer.asByteData());
    final pdf = (await t.runAsync(() => buildMenuPdf(doc, script: font)))!;
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    if (Platform.environment['SCREENSHOT_DIR'] != null) File('${Platform.environment['SCREENSHOT_DIR']}/menu.pdf').writeAsBytesSync(pdf);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length, greaterThan(1));

    // an item with a damaged picture and no logo still makes a menu
    final doc2 = MenuDoc(name: 'X', primary: 0xFFC92A2A, accent: 0xFFF59F00, currencyCode: 'PKR', fingerprint: 'f', sections: [MenuSection(title: 'A', entries: [MenuEntry(name: 'N', price: '1', image: Uint8List.fromList([1, 2, 3]))])]);
    expect((await t.runAsync(() => renderMenuPng(doc2)))!.length, 1);
    expect(String.fromCharCodes((await t.runAsync(() => buildMenuPdf(doc2)))!.take(5)), '%PDF-');

    // the menu follows the data: a changed price or a new item changes the fingerprint (so "menu changed" shows and it is remade)
    await db.customStatement("UPDATE product SET base_price_minor = 49900 WHERE name = 'Zinger Burger'");
    final changed = (await t.runAsync(() => loadMenuDoc(db, primary: 0xFFC92A2A, accent: 0xFFF59F00)))!;
    expect(changed.fingerprint, isNot(doc.fingerprint));
    expect(changed.sections.expand((s) => s.entries).firstWhere((e) => e.name == 'Zinger Burger').price, '499');
    final same = (await t.runAsync(() => loadMenuDoc(db, primary: 0xFFC92A2A, accent: 0xFFF59F00)))!;
    expect(same.fingerprint, changed.fingerprint);
    final recolored = (await t.runAsync(() => loadMenuDoc(db, primary: 0xFF1B7F3B, accent: 0xFFF59F00)))!;
    expect(recolored.fingerprint, isNot(changed.fingerprint));
  });
}
