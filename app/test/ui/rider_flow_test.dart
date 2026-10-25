import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/receipt_loader.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('riders: add a rider in Staff, give a delivery order to them, see it on the bill and in the rider\'s count', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'staff', 'Staff');
    await tapKey(t, 'tab-riders');
    expect(find.textContaining('No riders yet'), findsOneWidget);
    await tapKey(t, 'add-rider');
    await typeInto(t, find.byKey(const ValueKey('f-name')), 'Kamran');
    await typeInto(t, find.byKey(const ValueKey('f-phone')), '0301-5555555');
    await typeInto(t, find.byKey(const ValueKey('f-bike')), 'LEA-1234');
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('rider-Kamran')), findsOneWidget);
    await shot(t, '98_riders');

    await openTab(t, 'pos', 'POS');
    await tapProduct(t, 'Zinger Burger');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    await t.tap(find.text('Delivery').first);
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('dlv-address')), 'Street 9');
    await t.ensureVisible(find.byKey(const ValueKey('dlv-rider')));
    await tapKey(t, 'dlv-rider');
    await t.tap(find.text('Kamran').last);
    await t.pumpAndSettle();
    await h.container.read(cartProvider.notifier).finalizeDelivery();
    final order = (await db.customSelect('SELECT id, rider_id FROM "order"').getSingle()).data;
    final kamran = (await db.customSelect("SELECT id FROM team_member WHERE name = 'Kamran'").getSingle()).data['id'];
    expect(order['rider_id'], kamran);
    final r = await loadReceipt(db, order['id'] as String);
    expect(r.deliveryTo, contains('Rider: Kamran'));

    final riders = await h.container.read(teamServiceProvider).riders(day: (await db.customSelect('SELECT business_date AS d FROM "order"').getSingle()).data['d'] as String);
    expect(riders.single.deliveries, 1);
    expect(riders.single.totalMinor, greaterThan(0));
  });
}
