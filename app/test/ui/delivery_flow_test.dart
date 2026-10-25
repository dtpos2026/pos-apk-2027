import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/receipt_loader.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<Harness> start(WidgetTester t) async {
  final db = newDb();
  await seedBusiness(db);
  final h = await pumpApp(t, db: db);
  await signIn(t, 'Ali', '1234');
  await tapKey(t, 'open-shift');
  await tapKey(t, 'amount-ok');
  return h;
}

Future<int> n(Harness h, String q) async => (await h.db.customSelect(q).getSingle()).data['n'] as int;

void main() {
  testWidgets('delivery: typing a phone finds the saved customer and fills name and address', (t) async {
    final h = await start(t);
    await h.container.read(customerServiceProvider).save(name: 'Ahmed Raza', phone: '0300-1111111', address: 'House 5, Model Town', staffId: 'x');
    await tapProduct(t, 'Zinger Burger');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    expect(find.byKey(const ValueKey('delivery-card')), findsNothing, reason: 'only delivery orders ask for these');
    await t.tap(find.text('Delivery').first);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('delivery-card')), findsOneWidget);
    await typeInto(t, find.byKey(const ValueKey('dlv-phone')), '0300');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    await shot(t, '90_delivery_search');
    await tapKey(t, 'dlv-pick-Ahmed Raza');
    final cart = h.container.read(cartProvider);
    expect(cart.customerId, isNotNull);
    expect(cart.deliveryAddress, 'House 5, Model Town');
    expect(t.widget<TextField>(find.byKey(const ValueKey('dlv-name'))).controller!.text, 'Ahmed Raza');
    expect(t.widget<TextField>(find.byKey(const ValueKey('dlv-address'))).controller!.text, 'House 5, Model Town');
    await h.container.read(cartProvider.notifier).flush();
    expect((await h.db.customSelect('SELECT delivery_address AS a FROM "order"').getSingle()).data['a'], 'House 5, Model Town');
    expect(await n(h, 'SELECT COUNT(*) AS n FROM customer WHERE name = \'Ahmed Raza\''), 1, reason: 'no duplicate customer');
  });

  testWidgets('delivery: a new customer is saved with the order; next time the phone finds them; bill and KOT show who/where', (t) async {
    final h = await start(t);
    await tapProduct(t, 'Zinger Burger');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    await t.tap(find.text('Delivery').first);
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('dlv-phone')), '0311-2222222');
    await typeInto(t, find.byKey(const ValueKey('dlv-name')), 'Bilal');
    await typeInto(t, find.byKey(const ValueKey('dlv-address')), 'Street 9, Block C');
    expect(await n(h, "SELECT COUNT(*) AS n FROM customer WHERE phone = '0311-2222222'"), 0, reason: 'nothing is saved while the cashier is still typing');
    await h.container.read(cartProvider.notifier).finalizeDelivery();
    expect(await n(h, "SELECT COUNT(*) AS n FROM customer WHERE phone = '0311-2222222' AND address = 'Street 9, Block C'"), 1, reason: 'saved for next time');
    final order = (await h.db.customSelect('SELECT id, customer_id, delivery_address FROM "order"').getSingle()).data;
    expect(order['customer_id'], isNotNull);
    expect(order['delivery_address'], 'Street 9, Block C');
    final r = await loadReceipt(h.db, order['id'] as String);
    expect(r.deliveryTo, ['Bilal', 'Tel: 0311-2222222', 'Street 9, Block C']);
    // the same phone again finds the same customer instead of creating a second one
    final cart = h.container.read(cartProvider.notifier);
    cart.setCustomer(null);
    cart.setDelivery(name: 'Bilal', phone: '0311-2222222', address: 'Street 9, Block C');
    await cart.finalizeDelivery();
    expect(await n(h, "SELECT COUNT(*) AS n FROM customer WHERE phone = '0311-2222222'"), 1);
  });
}
