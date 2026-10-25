import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('staff: the owner chooses exactly which screens a new person can open; they sign in and see only those', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'staff', 'Staff');
    await tapKey(t, 'add-staff');
    await typeInto(t, find.byKey(const ValueKey('f-name')), 'Mia');
    await typeInto(t, find.byKey(const ValueKey('f-pin')), '4321');
    await tapKey(t, 'staff-custom');
    await tapKey(t, 'form-ok');
    // the access list starts from what a cashier opens today; take away what Mia should not see
    expect(find.byKey(const ValueKey('acc-screen-pos')), findsOneWidget);
    for (final k in ['tables', 'kitchen', 'online', 'customers', 'expenses']) {
      await t.ensureVisible(find.byKey(ValueKey('acc-screen-$k')));
      await tapKey(t, 'acc-screen-$k');
    }
    await shot(t, '97_staff_access');
    await t.ensureVisible(find.byKey(const ValueKey('acc-act-discount.apply')));
    await tapKey(t, 'acc-act-discount.apply');
    await t.ensureVisible(find.byKey(const ValueKey('access-save')));
    await tapKey(t, 'access-save');

    await tapKey(t, 'sign-out');
    h.container.invalidate(staffListProvider);
    await t.pumpAndSettle();
    await signIn(t, 'Mia', '4321');
    final bar = find.byType(NavigationBar);
    expect(find.descendant(of: bar, matching: find.text('POS')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Tables')), findsNothing);
    expect(find.descendant(of: bar, matching: find.text('Kitchen')), findsNothing);
    expect(find.descendant(of: bar, matching: find.text('Staff')), findsNothing);
  });
}
