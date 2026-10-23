import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('first run: setup form validates, then lands on the app', (t) async {
    final h = await pumpApp(t);
    expect(find.text('Set up your business'), findsOneWidget);
    expect(find.byKey(const ValueKey('btype-fastfood')), findsOneWidget);
    await shot(t, '01_setup');
    await t.scrollUntilVisible(find.text('Powered by Digital Target'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Powered by Digital Target'), findsOneWidget);

    await t.ensureVisible(find.text('Finish setup'));
    await t.tap(find.text('Finish setup'));
    await t.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));
    expect(find.text('PIN must be 4 to 8 digits'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await typeInto(t, fields.at(0), 'Burger Point');
    await typeInto(t, fields.at(1), 'Ali');
    await typeInto(t, fields.at(2), '1234');
    await t.ensureVisible(find.text('Finish setup'));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish setup'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-shift')), findsOneWidget); // signed in as the owner, shift required
    expect((await h.db.customSelect('SELECT COUNT(*) AS n FROM staff').getSingle()).data['n'], 1);
  });

  testWidgets('login: wrong PIN is rejected, right PIN opens the app, 5 wrong PINs lock', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    expect(find.text('Choose your name'), findsOneWidget);
    await shot(t, '02_login_users');

    await signIn(t, 'Ali', '9999');
    expect(find.text('Wrong PIN'), findsOneWidget);
    await shot(t, '03_login_wrong_pin');
    for (var i = 0; i < 4; i++) {
      for (final d in '0000'.split('')) {
        await tapKey(t, 'key-$d');
      }
      await tapKey(t, 'key-ok');
    }
    expect(find.textContaining('Too many attempts'), findsOneWidget);
    for (final d in '1234'.split('')) {
      await tapKey(t, 'key-$d');
    }
    await tapKey(t, 'key-ok');
    expect(find.byKey(const ValueKey('open-shift')), findsNothing); // right PIN refused while locked
  });

  testWidgets('full sale on a phone: shift, add items, discount, split payment, receipt, report', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    expect(find.text('Open a shift to start selling'), findsOneWidget);
    await shot(t, '04_shift_required');

    await tapKey(t, 'open-shift');
    await typeInto(t, find.byKey(const ValueKey('amount-field')), '5000');
    await tapKey(t, 'amount-ok');
    expect(find.text('Beef Burger'), findsOneWidget);
    await shot(t, '05_pos_phone');

    await tapProduct(t, 'Zinger Burger');
    await tapProduct(t, 'Zinger Burger');
    await tapProduct(t, 'Cola 500ml');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    expect(find.byKey(const ValueKey('qty-0')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('qty-0'))).data, '2');
    expect(t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'PKR 1,000.00'); // 2 x 450 + 100
    await shot(t, '06_cart');

    await tapKey(t, 'discount');
    await typeInto(t, find.byKey(const ValueKey('discount-field')), '10');
    await tapKey(t, 'discount-ok');
    expect(t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'PKR 900.00');

    await tapKey(t, 'charge');
    expect(t.widget<Text>(find.byKey(const ValueKey('checkout-total'))).data, 'PKR 900.00');
    await tapKey(t, 'method-Card');
    await typeInto(t, find.byKey(const ValueKey('pay-0')), '400');
    await tapKey(t, 'method-Cash');
    await shot(t, '07_checkout_split');
    expect(t.widget<Text>(find.byKey(const ValueKey('remaining'))).data, 'PKR 0.00'); // cash line prefilled with the rest
    await typeInto(t, find.byKey(const ValueKey('pay-1')), '1000');
    expect(t.widget<Text>(find.byKey(const ValueKey('change'))).data, 'PKR 500.00');
    await tapKey(t, 'confirm-payment');

    expect(find.byKey(const ValueKey('invoice-no')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('invoice-no'))).data, 'INV-20260112-0001');
    final receipt = t.widget<Text>(find.byKey(const ValueKey('receipt-text'))).data!;
    expect(receipt, contains('Burger Point'));
    expect(receipt, contains('2 x Zinger Burger'));
    expect(receipt, contains('Change'));
    expect(receipt, contains('Powered by Digital Target'));
    expect(find.text('No printer set up. Add one in Settings.'), findsOneWidget);
    await shot(t, '08_receipt');
    await tapKey(t, 'new-sale');

    // the sale is really in the database, and the cart/draft is gone
    final o = (await h.db.customSelect("SELECT status, total_minor, paid_minor FROM \"order\"").getSingle()).data;
    expect(o, {'status': 'paid', 'total_minor': 90000, 'paid_minor': 90000});
    expect((await h.db.customSelect('SELECT COUNT(*) AS n FROM payment').getSingle()).data['n'], 2);
    expect((await h.db.customSelect("SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'draft'").getSingle()).data['n'], 0);
    expect(h.container.read(cartProvider).isEmpty, isTrue);

    // report
    await openTab(t, 'reports', 'Reports');
    expect(t.widget<Text>(find.byKey(const ValueKey('stat-gross'))).data, 'PKR 900.00');
    expect(t.widget<Text>(find.byKey(const ValueKey('stat-bills'))).data, '1');
    await shot(t, '09_report');
  });

  testWidgets('crash recovery: the cart comes back after the app is restarted', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Fries');
    await tapProduct(t, 'Fries');
    await t.pumpAndSettle();
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'draft'").getSingle()).data['n'], 1);

    // "kill" the app: a brand new widget tree and providers over the same database file
    await t.pumpWidget(const SizedBox());
    final h2 = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await t.pumpAndSettle();
    expect(h2.container.read(cartProvider).items.single.name, 'Fries');
    expect(h2.container.read(cartProvider).items.single.qtyMilli, 2000);
  });

  testWidgets('tablet layout shows menu and order side by side; weight items step by 0.5 kg', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    expect(find.byKey(const ValueKey('charge')), findsOneWidget); // cart panel is visible without opening a sheet
    await tapProduct(t, 'Chicken Karahi (kg)');
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('qty-0'))).data, '0.5');
    await tapKey(t, 'inc-0');
    expect(t.widget<Text>(find.byKey(const ValueKey('qty-0'))).data, '1');
    await tapProduct(t, 'Zinger Burger');
    await t.pumpAndSettle();
    await shot(t, '10_pos_tablet');
  });

  testWidgets('cashier sees only Sell and cannot discount', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final role = (await db.customSelect("SELECT id FROM role WHERE name = 'Cashier'").getSingle()).data['id'] as String;
    final h = await pumpApp(t, db: db);
    await h.container.read(authServiceProvider).createStaff(name: 'Sara', roleId: role, pin: '5555');
    h.container.invalidate(staffListProvider);
    await t.pumpAndSettle();
    await signIn(t, 'Sara', '5555');
    for (final hidden in ['Menu', 'Settings', 'Reports', 'Inventory', 'Staff']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(hidden)), findsNothing, reason: hidden);
    }
    expect(find.byKey(const ValueKey('nav-more')), findsNothing); // exactly five destinations fit on the bar
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Fries');
    await t.pumpAndSettle();
    await tapKey(t, 'open-cart');
    expect(find.byKey(const ValueKey('discount')), findsNothing);
  });

  testWidgets('Urdu switches the whole UI to right-to-left', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, locale: const Locale('ur'));
    expect(find.text('اپنا نام منتخب کریں'), findsOneWidget);
    expect(Directionality.of(t.element(find.text('اپنا نام منتخب کریں'))), TextDirection.rtl);
    await shot(t, '11_login_urdu');
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await shot(t, '12_pos_urdu');
    expect(find.text('سب'), findsOneWidget);
  });
}
