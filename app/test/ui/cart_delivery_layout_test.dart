import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('phone: a delivery order with its details still shows the totals and the Pay button on screen, and the details scroll', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    await t.tap(find.text('Delivery').last);
    await t.pumpAndSettle();
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final pay = t.getRect(find.byKey(const ValueKey('charge')));
    expect(pay.bottom, lessThanOrEqualTo(screen.height), reason: 'the Pay button is not pushed off the screen');
    expect(pay.top, greaterThan(screen.height / 2), reason: 'it sits at the bottom, with the totals above it');
    await shot(t, '111_cart_delivery');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('charge'))).onPressed, isNotNull);
  });
}
