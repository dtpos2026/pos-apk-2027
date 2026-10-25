import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('dine-in: table and waiter are asked before the order goes to the kitchen or is held; the bill shows in Held', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await db.customStatement("INSERT INTO area(id,name,updated_at) VALUES ('a','Hall',1)");
    await db.customStatement("INSERT INTO dining_table(id,area_id,label,seats,status,updated_at) VALUES ('t1','a','T1',4,'free',1), ('t2','a','T2',4,'free',1)");
    await h.container.read(teamServiceProvider).saveWaiter(name: 'Sara', staffId: owner);

    await tapProduct(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    await t.tap(find.text('Dine-in').last);
    await t.pumpAndSettle();

    // choosing Dine-in opens the table window at once; cancelling keeps the order unheld
    expect(find.byKey(const ValueKey('dinein-table')), findsOneWidget);
    await tapKey(t, 'dinein-cancel');
    await tapKey(t, 'hold');
    expect(find.byKey(const ValueKey('dinein-table')), findsOneWidget);
    await shot(t, '92_dinein_pick');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('dinein-ok'))).onPressed, isNull, reason: 'a table is required');
    await tapKey(t, 'dinein-cancel');
    expect(h.container.read(cartProvider).items, isNotEmpty);

    await tapKey(t, 'hold');
    await tapKey(t, 'dinein-table');
    await t.tap(find.text('T2').last);
    await t.pumpAndSettle();
    await tapKey(t, 'dinein-waiter');
    await t.tap(find.text('Sara').last);
    await t.pumpAndSettle();
    await tapKey(t, 'dinein-ok');

    final held = await h.container.read(posServiceProvider).listHeld();
    expect(held.single.table, 'T2');
    final row = await db.customSelect('SELECT waiter_member_id w, table_id tb, status FROM "order"').getSingle();
    expect(row.data['status'], 'held');
    expect(row.data['tb'], 't2');
    expect(row.data['w'], isNotNull, reason: 'the waiter is on the held bill');
    expect(h.container.read(cartProvider).items, isEmpty, reason: 'the screen is ready for the next customer');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('tables can be edited (name, seats, area) and waiters are added in Staff like riders', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await db.customStatement("INSERT INTO area(id,name,updated_at) VALUES ('a','Hall',1), ('b','Roof',1)");
    await db.customStatement("INSERT INTO dining_table(id,area_id,label,seats,status,updated_at) VALUES ('t1','a','T1',4,'free',1)");
    await openTab(t, 'tables', 'Tables');
    await t.longPress(find.byKey(const ValueKey('table-T1')));
    await t.pumpAndSettle();
    await tapKey(t, 'act-edit');
    await t.enterText(find.byType(TextField).first, 'Window 1');
    await t.enterText(find.byType(TextField).at(1), '6');
    await tapKey(t, 'edit-table-area');
    await t.tap(find.text('Roof').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Save').last);
    await t.pumpAndSettle();
    final r = await db.customSelect("SELECT label, seats, area_id FROM dining_table WHERE id = 't1'").getSingle();
    expect([r.data['label'], r.data['seats'], r.data['area_id']], ['Window 1', 6, 'b']);

    await openTab(t, 'staff', 'Staff');
    await tapKey(t, 'tab-waiters');
    await tapKey(t, 'add-waiter');
    await t.enterText(find.byType(TextField).first, 'Bilal');
    await t.tap(find.text('Save').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('waiter-Bilal')), findsOneWidget);
    expect((await h.container.read(teamServiceProvider).waiters()).single.name, 'Bilal');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
