import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('expenses: a category can be saved on its own, an expense can be edited, and the cash drawer follows', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'expenses', 'Expenses');
    await t.pump(const Duration(milliseconds: 300));

    // save usual categories first
    await tapKey(t, 'manage-categories');
    for (final c in ['Gas', 'Rent']) {
      await t.enterText(find.byKey(const ValueKey('new-cat-field')), c);
      await t.tap(find.byKey(const ValueKey('new-cat-add')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('cat-Gas')), findsOneWidget);
    expect(find.byKey(const ValueKey('cat-Rent')), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    // add one with a saved category (one tap), then correct it
    await tapKey(t, 'add-expense');
    await t.enterText(find.byKey(const ValueKey('f-amount')), '500');
    await tapKey(t, 'exp-cat-Gas');
    await tapKey(t, 'form-ok');
    expect(t.widget<Text>(find.byKey(const ValueKey('exp-total'))).data, 'PKR 500.00');
    await tapKey(t, 'exp-edit-0');
    expect(t.widget<TextField>(find.byKey(const ValueKey('f-amount'))).controller!.text, '500');
    expect(t.widget<TextField>(find.byKey(const ValueKey('f-category'))).controller!.text, 'Gas');
    await t.enterText(find.byKey(const ValueKey('f-amount')), '650');
    await tapKey(t, 'exp-cat-Rent');
    await tapKey(t, 'form-ok');
    expect(t.widget<Text>(find.byKey(const ValueKey('exp-total'))).data, 'PKR 650.00');
    expect(find.text('Rent'), findsWidgets);
    final cash = await db.customSelect("SELECT COALESCE(SUM(CASE direction WHEN 'out' THEN -amount_minor ELSE amount_minor END),0) AS s FROM cash_movement").getSingle();
    expect(cash.data['s'], -65000, reason: 'the drawer lost 650 in the end: 500 out, 500 back, 650 out');
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM audit_log WHERE event = 'expense.update'").getSingle()).data['n'], 1);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
