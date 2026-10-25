import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('tables: split a bill onto another table, then merge the bills back (long-press a table)', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await db.customStatement("INSERT INTO area(id,name,updated_at) VALUES ('a','Hall',1)");
    await db.customStatement("INSERT INTO dining_table(id,area_id,label,seats,status,updated_at) VALUES ('t1','a','T1',4,'free',1), ('t2','a','T2',4,'free',1)");
    final zinger = (await db.customSelect("SELECT id FROM product WHERE name = 'Zinger Burger'").getSingle()).data['id'] as String;
    final id = await h.container.read(posServiceProvider).saveDraft(
        DraftOrder(orderType: 'dine_in', tableId: 't1', items: [CartItem(productId: zinger, name: 'Zinger Burger', qtyMilli: 3000, unitPriceMinor: 45000)]),
        staffId: owner);
    await openTab(t, 'tables', 'Tables');
    expect(find.descendant(of: find.byKey(const ValueKey('table-T1')), matching: find.text('Occupied')), findsOneWidget);

    await t.longPress(find.byKey(const ValueKey('table-T1')));
    await t.pumpAndSettle();
    await tapKey(t, 'act-split');
    await shot(t, '91_split_bill');
    await tapKey(t, 'split-ok');
    expect(find.byKey(const ValueKey('split-error')), findsOneWidget, reason: 'nothing picked yet');
    await tapKey(t, 'split-plus-0');
    await tapKey(t, 'split-plus-0');
    await tapKey(t, 'split-dest');
    await t.tap(find.text('New bill on table T2').last);
    await t.pumpAndSettle();
    await tapKey(t, 'split-ok');
    expect(find.byKey(const ValueKey('split-ok')), findsNothing, reason: 'dialog closed');

    var tables = await h.container.read(tableServiceProvider).tables();
    final t1 = tables.firstWhere((x) => x.label == 'T1'), t2 = tables.firstWhere((x) => x.label == 'T2');
    expect(t1.orderTotalMinor, 45000);
    expect(t2.orderTotalMinor, 90000);
    expect(t1.orderId, id);

    await t.longPress(find.byKey(const ValueKey('table-T2')));
    await t.pumpAndSettle();
    await tapKey(t, 'act-merge');
    await tapKey(t, 'merge-into-T1');
    tables = await h.container.read(tableServiceProvider).tables();
    expect(tables.firstWhere((x) => x.label == 'T1').orderTotalMinor, 135000);
    expect(tables.firstWhere((x) => x.label == 'T2').orderId, isNull);
    expect(tables.firstWhere((x) => x.label == 'T2').status, 'free');
  });
}
