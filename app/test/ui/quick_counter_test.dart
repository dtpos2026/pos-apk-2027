import 'package:dt_food_pos/app/business_mode.dart';
import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('food point: applying the type from Settings sets features and printing; selling shows only Counter and Takeaway; paying prints and returns to the next sale', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');

    // Settings: apply "Food point"
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('set-btype-foodpoint')), 200, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('set-btype-foodpoint')));
    await t.tap(find.byKey(const ValueKey('set-btype-foodpoint')));
    await t.pumpAndSettle();
    await shot(t, '97_apply_foodpoint');
    await tapKey(t, 'btype-apply');
    expect(h.container.read(quickCounterProvider).value, isTrue);
    expect(h.container.read(modulesProvider), {'tokens', 'inventory', 'customers', 'expenses'});
    final cfg = await h.container.read(printSettingsProvider.future);
    expect([cfg.autoBill, cfg.autoKot, cfg.autoToken], [true, false, true]);

    await openTab(t, 'pos', 'POS');
    await tapProduct(t, 'Fries');
    await tapKey(t, 'open-cart');
    expect(find.text('Dine-in'), findsNothing);
    expect(find.text('Delivery'), findsNothing);
    expect(find.text('Counter'), findsOneWidget);
    expect(find.text('Takeaway'), findsOneWidget);
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    expect(find.byKey(const ValueKey('pay-print-bill')), findsOneWidget, reason: 'the cashier can switch the bill off for this sale');
    await tapKey(t, 'confirm-payment');
    expect(find.byKey(const ValueKey('new-sale')), findsNothing, reason: 'no receipt window in quick counter mode');
    expect(h.container.read(cartProvider).items, isEmpty);
    expect((await db.customSelect("SELECT COUNT(*) n FROM \"order\" WHERE status = 'paid'").getSingle()).data['n'], 1);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
