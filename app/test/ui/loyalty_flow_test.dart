import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/domain/loyalty.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('loyalty: the customer pays part of the bill with points at checkout; points go down and new ones are earned', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO customer(id,name,phone,updated_at) VALUES ('c1','Sara','03001234567',1)");
    final h = await pumpApp(t, db: db);
    await t.runAsync(() async {
      await h.container.read(loyaltyServiceProvider).save(const LoyaltyConfig(enabled: true)); // 1 point per 100, 1 point = 1
      await db.customStatement("INSERT INTO loyalty_ledger(id, customer_id, kind, points, created_at) VALUES ('l1','c1','adjust',50,1)");
    });
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    h.container.read(cartProvider.notifier).setCustomer('c1');
    await t.runAsync(() => h.container.read(cartProvider.notifier).flush());
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    for (var i = 0; i < 20 && find.byKey(const ValueKey('use-points')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.textContaining('Pay with points (50'), findsOneWidget);
    await tapKey(t, 'use-points');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    final rows = (await t.runAsync(() => db.customSelect("SELECT kind, points FROM loyalty_ledger WHERE order_id IS NOT NULL ORDER BY kind").get()))!.map((r) => (r.data['kind'], r.data['points'])).toList();
    expect(rows.first, ('earn', 4), reason: '450 bill - 50 in points = 400 cash -> 4 points');
    expect(rows.last, ('redeem', -50));
  });
}
