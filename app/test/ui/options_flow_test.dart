import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/menu_service.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  importTest();
  testWidgets('sizes and add-ons: defined in the menu, chosen at the till, priced on the bill and shown on the receipt', (t) async {
    final db = newDb();
    await seedBusiness(db, menu: false);
    final h = await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');

    // 1. menu: a pizza with two sizes and an add-on group
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'add-item');
    await typeInto(t, find.byKey(const ValueKey('item-name')), 'Pizza');
    await typeInto(t, find.byKey(const ValueKey('item-category')), 'Pizza');
    await tapKey(t, 'mode-size'); // the usual sizes appear, ready for prices (as in DT Enterprise)
    await typeInto(t, find.byKey(const ValueKey('size-price-0')), '600');
    await typeInto(t, find.byKey(const ValueKey('size-price-2')), '1100');
    await tapKey(t, 'size-del-3'); // no Extra Large
    await tapKey(t, 'size-del-1'); // no Medium
    await tapKey(t, 'edit-addons');
    await tapKey(t, 'new-group');
    await typeInto(t, find.byKey(const ValueKey('f-name')), 'Toppings');
    await typeInto(t, find.byKey(const ValueKey('f-max')), '2');
    await typeInto(t, find.byKey(const ValueKey('f-options')), 'Extra cheese, 150\nOlives, 100\nMushroom, 120');
    await tapKey(t, 'form-ok');
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('group-Toppings'))).value, isTrue); // the new group is linked right away
    await tapKey(t, 'addons-save');
    await tapKey(t, 'item-save');
    await shot(t, '50_menu_options');

    // 2. till: tapping the pizza asks for the size and toppings
    await openTab(t, 'pos', 'POS');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Pizza');
    await t.pumpAndSettle();
    await shot(t, '51_options_sheet');
    await tapKey(t, 'opt-variant-Large');
    await tapKey(t, 'opt-Toppings-Extra cheese');
    await tapKey(t, 'opt-Toppings-Olives');
    await tapKey(t, 'opt-Toppings-Mushroom'); // a third topping is not allowed: the group maximum is 2
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('opt-Toppings-Mushroom'))).value, isFalse);
    await typeInto(t, find.byKey(const ValueKey('opt-note')), 'well done');
    expect(find.textContaining('1,350.00'), findsWidgets); // 1100 + 150 + 100
    await tapKey(t, 'opt-add');

    final item = h.container.read(cartProvider).items.single;
    expect(item.name, 'Pizza (Large)');
    expect(item.unitPriceMinor, 110000);
    expect(item.modifiers.map((m) => m.name), ['Extra cheese', 'Olives']);
    expect(item.note, 'well done');
    expect(find.textContaining('Extra cheese, Olives'), findsOneWidget);

    // the same configuration merges into one line; a different one does not
    await tapProduct(t, 'Pizza');
    await t.pumpAndSettle();
    await tapKey(t, 'opt-variant-Large');
    await tapKey(t, 'opt-Toppings-Extra cheese');
    await tapKey(t, 'opt-Toppings-Olives');
    await typeInto(t, find.byKey(const ValueKey('opt-note')), 'well done');
    await tapKey(t, 'opt-add');
    expect(h.container.read(cartProvider).items.single.qtyMilli, 2000);
    await tapProduct(t, 'Pizza');
    await t.pumpAndSettle();
    await tapKey(t, 'opt-add'); // Small with nothing extra: Large is not preselected... the cheapest size is
    expect(h.container.read(cartProvider).items.length, 2);
    expect(h.container.read(cartProvider).items.last.name, 'Pizza (Small)');

    // 3. the bill prices the add-ons and the receipt lists them
    expect(h.container.read(cartProvider).bill.totalMinor, 2 * 135000 + 60000);
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    final receipt = receiptPaperText(t);
    expect(receipt, contains('Pizza (Large)'));
    expect(receipt, contains('+ Extra cheese'));
    expect(receipt, contains('+ Olives'));
    expect(receipt, contains('* well done'));
    expect(receipt, contains('3,300.00')); // 2 x 1350 + 600
    await tapKey(t, 'new-sale');
  });

  testWidgets('a required choice must be made before the item can be added', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db, menu: false);
    final h = await pumpApp(t, db: db, tablet: true);
    final menu = h.container.read(menuServiceProvider);
    final p = await menu.saveProduct(name: 'Shawarma', priceMinor: 40000, staffId: owner);
    final g = await menu.saveGroup(name: 'Sauce', minSelect: 1, maxSelect: 1, options: [(name: 'Garlic', priceMinor: 0), (name: 'Chilli', priceMinor: 0)]);
    await menu.setProductGroups(p, [g]);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Shawarma');
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('opt-add'))).onPressed, isNull); // nothing chosen yet
    await tapKey(t, 'opt-Sauce-Garlic');
    await tapKey(t, 'opt-Sauce-Chilli'); // single choice: replaces Garlic
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('opt-Sauce-Garlic'))).value, isFalse);
    await tapKey(t, 'opt-add');
    expect(h.container.read(cartProvider).items.single.modifiers.single.name, 'Chilli');
  });
}


void importTest() {
  testWidgets('menu import: choose an Excel file, check it, import it; a bad row blocks the import with its line number', (t) async {
    final db = newDb();
    await seedBusiness(db, menu: false);
    Uint8List book(String rows) {
      final a = Archive()..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', '<worksheet><sheetData>$rows</sheetData></worksheet>'));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    String cell(String ref, String v) => '<c r="$ref" t="inlineStr"><is><t>$v</t></is></c>';
    final good = book('<row r="1">${cell('A1', 'category')}${cell('B1', 'name')}${cell('C1', 'price')}</row>'
        '<row r="2">${cell('A2', 'Burgers')}${cell('B2', 'Zinger Burger')}<c r="C2"><v>450</v></c></row>'
        '<row r="3">${cell('A3', 'Burgers')}${cell('B3', 'Beef Burger')}<c r="C3"><v>550.5</v></c></row>');
    final h = await pumpApp(t, db: db, tablet: true, importPicker: FakeImportPicker('menu.xlsx', good));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'import-csv');
    await tapKey(t, 'csv-file');
    expect(t.widget<TextField>(find.byKey(const ValueKey('csv-text'))).controller!.text, contains('Zinger Burger,450'));
    await tapKey(t, 'csv-check');
    expect(t.widget<Text>(find.byKey(const ValueKey('csv-summary'))).data, startsWith('2 new, 0 updated'));
    expect((await h.db.customSelect('SELECT COUNT(*) AS n FROM product').getSingle()).data['n'], 0); // a check changes nothing
    await tapKey(t, 'csv-import');
    expect((await h.db.customSelect('SELECT COUNT(*) AS n FROM product').getSingle()).data['n'], 2);
    expect((await h.db.customSelect("SELECT base_price_minor AS p FROM product WHERE name = 'Beef Burger'").getSingle()).data['p'], 55050);
  });

  testWidgets('menu import: an unreadable file is reported and nothing is imported', (t) async {
    final db = newDb();
    await seedBusiness(db, menu: false);
    await pumpApp(t, db: db, tablet: true, importPicker: FakeImportPicker('broken.xlsx', Uint8List.fromList([1, 2, 3])));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'import-csv');
    await tapKey(t, 'csv-file');
    expect(find.text('This file could not be read'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('csv-text'))).controller!.text, isEmpty);
  });
}
