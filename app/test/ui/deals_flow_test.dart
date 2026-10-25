import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('deals: make a combo from menu items, see the saving, sell it from the selling screen, bulk-import more', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'open-deals');
    expect(find.textContaining('No deals yet'), findsOneWidget);

    await tapKey(t, 'add-deal');
    await typeInto(t, find.byKey(const ValueKey('deal-name')), 'Family Deal');
    await typeInto(t, find.byKey(const ValueKey('deal-price')), '1000');
    await tapKey(t, 'deal-save');
    expect(find.byKey(const ValueKey('deal-error')), findsOneWidget, reason: 'a deal needs items');
    await tapKey(t, 'deal-add-item');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    await tapKey(t, 'deal-pick-Zinger Burger');
    await tapKey(t, 'deal-plus-0'); // 2 burgers
    await tapKey(t, 'deal-add-item');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    await tapKey(t, 'deal-pick-Fries');
    await shot(t, '92_deal_editor');
    expect(find.byKey(const ValueKey('deal-saving')), findsOneWidget, reason: 'regular 1,050 vs deal 1,000');
    await tapKey(t, 'deal-save');
    expect(find.byKey(const ValueKey('deal-Family Deal')), findsOneWidget);
    await shot(t, '93_deals_list');

    // it is a normal menu item in the Deals category
    final row = (await db.customSelect("SELECT p.base_price_minor AS price, p.kind AS kind, c.name AS cat FROM product p JOIN category c ON c.id = p.category_id WHERE p.name = 'Family Deal'").getSingle()).data;
    expect(row, {'price': 100000, 'kind': 'combo', 'cat': 'Deals'});
    expect((await h.container.read(dealServiceProvider).deals()).single.items, hasLength(2));

    // bulk import: the template names items this menu does not have, so only the deal that fits is imported
    await tapKey(t, 'deal-import');
    await tapKey(t, 'deal-csv-template');
    await tapKey(t, 'deal-csv-check');
    expect(find.byKey(const ValueKey('deal-csv-summary')), findsOneWidget);
    await tapKey(t, 'deal-csv-import');
    expect(find.textContaining('✓'), findsOneWidget);
  });
}
