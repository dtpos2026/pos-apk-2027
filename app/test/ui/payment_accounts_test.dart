import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<void> _openSettingsAt(WidgetTester t, String key) async {
  await openTab(t, 'settings', 'Settings');
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byKey(ValueKey(key)), 300, scrollable: verticalScroll);
  await t.drag(verticalScroll, const Offset(0, -160)); // clear of the bottom navigation bar
  await t.pumpAndSettle();
}

void main() {
  testWidgets('owner adds a JazzCash account, it appears at checkout; switching it off hides it; cash cannot be switched off', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await _openSettingsAt(t, 'add-payment-method');
    await tapKey(t, 'add-payment-method');
    await t.enterText(find.byKey(const ValueKey('pm-name')), 'JazzCash 0300-1234567');
    await tapKey(t, 'pm-save');
    expect(find.text('JazzCash 0300-1234567'), findsOneWidget);
    var names = (await t.runAsync(() => h.container.read(paymentMethodsProvider.future)))!.map((m) => m.name);
    expect(names, contains('JazzCash 0300-1234567'));

    // duplicate name is refused with a message
    await tapKey(t, 'add-payment-method');
    await t.enterText(find.byKey(const ValueKey('pm-name')), 'jazzcash 0300-1234567');
    await tapKey(t, 'pm-save');
    expect(find.text('A payment method with this name already exists'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    await t.scrollUntilVisible(find.byKey(const ValueKey('pm-switch-JazzCash 0300-1234567')), 200, scrollable: verticalScroll);
    await tapKey(t, 'pm-switch-JazzCash 0300-1234567');
    h.container.invalidate(paymentMethodsProvider);
    names = (await t.runAsync(() => h.container.read(paymentMethodsProvider.future)))!.map((m) => m.name);
    expect(names, isNot(contains('JazzCash 0300-1234567')));
    expect(t.widget<Switch>(find.byKey(const ValueKey('pm-switch-Cash'))).onChanged, isNull);
  });
}
