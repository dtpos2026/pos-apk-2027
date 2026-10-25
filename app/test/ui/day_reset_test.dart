import 'package:dt_food_pos/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('after Close day the dashboard starts again from zero and selling needs Start day', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    await tapKey(t, 'new-sale');
    await tapKey(t, 'open-cart');
    await tapKey(t, 'close-shift');
    await t.pumpAndSettle();
    await tapKey(t, 'day-close');
    await tapKey(t, 'day-close-confirm');
    await t.pageBack();
    await t.pumpAndSettle();
    final d = await h.container.read(dashboardServiceProvider).load();
    expect(d.bills, 0, reason: 'a closed day leaves today at zero');
    expect(d.grossMinor, 0);
    expect(find.byKey(const ValueKey('open-shift')), findsOneWidget, reason: 'the next day needs Start day');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
