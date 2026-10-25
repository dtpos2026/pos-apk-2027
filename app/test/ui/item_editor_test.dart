import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('adding an item asks how it is sold: one price, sizes, by weight or price at the till, all in the same window', (t) async {
    final db = newDb();
    await seedBusiness(db, menu: false);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'menu', 'Menu');

    Future<void> add(String name, String mode, {Map<String, String> fields = const {}}) async {
      await tapKey(t, 'add-item');
      await typeInto(t, find.byKey(const ValueKey('item-name')), name);
      await typeInto(t, find.byKey(const ValueKey('item-category')), 'Menu');
      if (mode != 'fixed') await tapKey(t, 'mode-$mode');
      for (final e in fields.entries) {
        await typeInto(t, find.byKey(ValueKey(e.key)), e.value);
      }
    }

    // sizes: the usual names come ready, a missing price is refused, unwanted rows can go
    await add('Pizza', 'size');
    await shot(t, '98_item_editor_sizes');
    await t.ensureVisible(find.byKey(const ValueKey('item-save')));
    await tapKey(t, 'item-save');
    expect(find.byKey(const ValueKey('item-error')), findsOneWidget, reason: 'sizes need prices');
    await typeInto(t, find.byKey(const ValueKey('size-price-0')), '600');
    await typeInto(t, find.byKey(const ValueKey('size-price-1')), '900');
    await tapKey(t, 'size-del-3');
    await tapKey(t, 'size-del-2');
    await tapKey(t, 'item-save');
    final pizza = (await db.customSelect("SELECT id, base_price_minor b, unit, ask_price a FROM product WHERE name = 'Pizza'").getSingle()).data;
    expect([pizza['b'], pizza['unit'], pizza['a']], [60000, 'pc', 0], reason: 'the lowest size is the "from" price');
    expect((await db.customSelect('SELECT name, price_minor FROM product_variant ORDER BY price_minor').get()).map((r) => '${r.data['name']}:${r.data['price_minor']}'), ['Small:60000', 'Medium:90000']);

    // by weight: a rate per kg, sold as kg
    await add('Karahi', 'weight', fields: {'item-price': '2400'});
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT base_price_minor b, unit FROM product WHERE name = 'Karahi'").getSingle()).data, {'b': 240000, 'unit': 'kg'});

    // price at the till
    await add('Special', 'manual');
    expect(find.byKey(const ValueKey('manual-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-price')), findsNothing, reason: 'no fixed price to type');
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT base_price_minor b, ask_price a FROM product WHERE name = 'Special'").getSingle()).data, {'b': 0, 'a': 1});

    // a plain item, and editing it into sizes later
    await add('Fries', 'fixed', fields: {'item-price': '150'});
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT base_price_minor b FROM product WHERE name = 'Fries'").getSingle()).data['b'], 15000);

    // at the till: sizes show "from", the price item asks for its price, weight asks for kg
    await openTab(t, 'pos', 'POS');
    expect(find.textContaining('from PKR 600'), findsOneWidget);
    expect(find.text('Open price'), findsOneWidget);
    await tapProduct(t, 'Special');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('open-price-input')), '750');
    await tapKey(t, 'open-price-ok');
    final line = h.container.read(cartProvider).items.single;
    expect([line.name, line.unitPriceMinor], ['Special', 75000]);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('an existing item opens in its own mode (sizes show as rows) and a new item can open Add-ons and Recipe right away', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'add-item');
    await typeInto(t, find.byKey(const ValueKey('item-name')), 'Wrap');
    await typeInto(t, find.byKey(const ValueKey('item-price')), '300');
    await typeInto(t, find.byKey(const ValueKey('item-category')), 'Wraps');
    await t.ensureVisible(find.byKey(const ValueKey('edit-addons')));
    await tapKey(t, 'edit-addons'); // saves the new item first, then opens its add-ons
    expect(find.byKey(const ValueKey('new-group')), findsOneWidget);
    await tapKey(t, 'addons-save');
    expect((await db.customSelect("SELECT COUNT(*) n FROM product WHERE name = 'Wrap'").getSingle()).data['n'], 1);
    await t.ensureVisible(find.byKey(const ValueKey('item-save')));
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT COUNT(*) n FROM product WHERE name = 'Wrap'").getSingle()).data['n'], 1, reason: 'Save updates the same item, no copy');

    // switch the item to sizes and back to one price
    await t.tap(find.byKey(const ValueKey('menu-Wrap')));
    await t.pumpAndSettle();
    await tapKey(t, 'mode-size');
    await typeInto(t, find.byKey(const ValueKey('size-price-0')), '250');
    await tapKey(t, 'size-del-3');
    await tapKey(t, 'size-del-2');
    await tapKey(t, 'size-del-1');
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT COUNT(*) n FROM product_variant WHERE deleted_at IS NULL").getSingle()).data['n'], 1);
    await t.tap(find.byKey(const ValueKey('menu-Wrap')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('size-name-0')), findsOneWidget, reason: 'its sizes show as rows');
    await tapKey(t, 'mode-fixed');
    await typeInto(t, find.byKey(const ValueKey('item-price')), '320');
    await tapKey(t, 'item-save');
    expect((await db.customSelect("SELECT COUNT(*) n FROM product_variant WHERE deleted_at IS NULL").getSingle()).data['n'], 0, reason: 'back to one price: no sizes left');
    expect((await db.customSelect("SELECT base_price_minor b FROM product WHERE name = 'Wrap'").getSingle()).data['b'], 32000);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
