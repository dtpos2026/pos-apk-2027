import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('dashboard shows today\'s real numbers after a sale, links to other screens', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'dashboard', 'Dashboard');
    String kpi(String key) => t.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).map((w) => w.data ?? '').join('|');
    expect(kpi('dash-sales'), contains('PKR 0.00'));
    expect(find.text('No sales yet today.'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-greeting')), findsOneWidget);

    // a real sale (2 burgers + fries, cash) through the POS
    await tapKey(t, 'dash-new-sale');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    await tapProduct(t, 'Zinger Burger');
    await tapProduct(t, 'Fries');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    await tapKey(t, 'confirm-payment');
    await t.pumpAndSettle();
    await tapKey(t, 'new-sale');
    await openTab(t, 'dashboard', 'Dashboard');
    await t.pumpAndSettle();
    expect(kpi('dash-sales'), allOf(contains('PKR 1,050.00'), contains('1 bills')));
    expect(kpi('dash-cash'), contains('PKR 1,050.00'));
    expect(kpi('dash-udhaar'), contains('PKR 0.00'));
    await t.ensureVisible(find.text('Top items today'));
    expect(find.text('Zinger Burger'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-2026-01-12')), findsOneWidget);
    await shot(t, '84_dashboard');
    await Scrollable.ensureVisible(t.element(find.byKey(const ValueKey('qa-bills'))), alignment: 0.5);
    await t.pumpAndSettle();
    await tapKey(t, 'qa-bills');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('bill-INV-20260112-0001')), findsOneWidget);
  });
}
