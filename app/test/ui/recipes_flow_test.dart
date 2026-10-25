import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('recipes: sizes added as simple rows, ingredients picked from Inventory (flour in grams), cost and margin shown, saved', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    final inv = h.container.read(inventoryServiceProvider);
    final flour = await inv.saveItem(name: 'Flour', unit: 'kg', openingMilli: 20000, openingCostMinor: 20000, staffId: owner); // 200 per kg
    await inv.saveItem(name: 'Cheese', unit: 'kg', openingMilli: 5000, openingCostMinor: 100000, staffId: owner);
    await signIn(t, 'Ali', '1234');

    // sizes as rows (no "name, price" lines)
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'add-item');
    await typeInto(t, find.byKey(const ValueKey('item-name')), 'Pizza');
    await typeInto(t, find.byKey(const ValueKey('item-category')), 'Pizza');
    await tapKey(t, 'mode-size');
    await typeInto(t, find.byKey(const ValueKey('size-price-0')), '600');
    await typeInto(t, find.byKey(const ValueKey('size-price-2')), '1100');
    await tapKey(t, 'size-del-3');
    await tapKey(t, 'size-del-1');
    await shot(t, '94_variants_rows');
    await tapKey(t, 'item-save');

    // the Recipes screen: one row per size
    await t.pageBack().catchError((_) {});
    await openTab(t, 'recipes', 'Recipes');
    await shot(t, '95_recipes_list');
    expect(find.byKey(const ValueKey('recipe-Pizza · Small')), findsOneWidget);
    expect(find.byKey(const ValueKey('recipe-Pizza · Large')), findsOneWidget);
    await tapKey(t, 'recipe-edit-Pizza · Large');
    expect(find.byKey(const ValueKey('rc-empty')), findsOneWidget);
    await tapKey(t, 'rc-add');
    await tapKey(t, 'rc-pick-0');
    await t.enterText(find.byKey(const ValueKey('rc-search')), 'flo');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('rc-item-Cheese')), findsNothing);
    await tapKey(t, 'rc-item-Flour');
    await typeInto(t, find.byKey(const ValueKey('rc-qty-0')), '0.4');
    await tapKey(t, 'rc-unit-0'); // kg -> g: 0.4 kg becomes 400 g
    await t.tap(find.text('g').last);
    await t.pumpAndSettle();
    expect((t.widget<TextField>(find.byKey(const ValueKey('rc-qty-0'))).controller!.text), '400');
    expect(find.byKey(const ValueKey('rc-cost')), findsOneWidget);
    await shot(t, '96_recipe_editor');
    // the same ingredient twice is refused
    await tapKey(t, 'rc-add');
    await tapKey(t, 'rc-pick-1');
    await tapKey(t, 'rc-item-Flour');
    await typeInto(t, find.byKey(const ValueKey('rc-qty-1')), '1');
    await tapKey(t, 'rc-save');
    expect(find.byKey(const ValueKey('rc-error')), findsOneWidget);
    await tapKey(t, 'rc-del-1');
    await tapKey(t, 'rc-save');

    final saved = await inv.recipe((await db.customSelect("SELECT id FROM product WHERE name = 'Pizza'").getSingle()).data['id'] as String, variantId: (await db.customSelect("SELECT id FROM product_variant WHERE name = 'Large'").getSingle()).data['id'] as String);
    expect(saved, {flour: 400}, reason: '400 g = 0.4 kg of stock');
    expect(find.byKey(const ValueKey('recipe-margin-Pizza · Large')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
