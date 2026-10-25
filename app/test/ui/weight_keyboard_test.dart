import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('weight dialog with the keyboard open: nothing overlaps, the total follows the text and Add stays reachable', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Chicken Karahi (kg)');
    await t.pumpAndSettle();
    t.view.viewInsets = FakeViewPadding(bottom: 320 * t.view.devicePixelRatio); // the on-screen keyboard comes up
    addTearDown(t.view.resetViewInsets);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('weight-input')), '750');
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('weight-price'))).data, 'PKR 1,350.00');
    await shot(t, '110_weight_keyboard');
    await t.ensureVisible(find.byKey(const ValueKey('weight-ok')));
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('weight-ok'))).onPressed, isNotNull);
    final total = t.getRect(find.byKey(const ValueKey('weight-price')));
    final add = t.getRect(find.byKey(const ValueKey('weight-ok')));
    expect(add.top, greaterThanOrEqualTo(total.bottom), reason: 'the Add button sits below the total, not on top of it');
  });
}
