import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/harness.dart';

Future<void> openDrawer(WidgetTester t) async {
  await t.tap(find.byTooltip('Open navigation menu'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the three-line menu shows the restaurant, opens the profile; edits are saved and shown everywhere', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openDrawer(t);
    expect(t.widget<Text>(find.byKey(const ValueKey('drawer-name'))).data, 'Burger Point');
    await shot(t, '80_drawer');
    await tapKey(t, 'drawer-profile');
    expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
    await typeInto(t, find.byKey(const ValueKey('profile-name')), 'Shan Food Corner');
    await typeInto(t, find.byKey(const ValueKey('profile-owner')), 'Ali Khan');
    await typeInto(t, find.byKey(const ValueKey('profile-address')), 'Chowk Azam, Burewala');
    await typeInto(t, find.byKey(const ValueKey('profile-tax')), '1234567-8');
    await t.ensureVisible(find.byKey(const ValueKey('profile-save')));
    await tapKey(t, 'profile-save');
    final row = (await t.runAsync(() => db.customSelect('SELECT name, owner_name, address, tax_number FROM business_profile').getSingle()))!.data;
    expect(row, {'name': 'Shan Food Corner', 'owner_name': 'Ali Khan', 'address': 'Chowk Azam, Burewala', 'tax_number': '1234567-8'});
    await t.pageBack();
    await t.pumpAndSettle();
    await openDrawer(t);
    expect(t.widget<Text>(find.byKey(const ValueKey('drawer-name'))).data, 'Shan Food Corner');
  });

  testWidgets('the account page shows the licence details kept from Digital Target', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(AccountSnapshot(status: 'active', plan: 'yearly', customerId: 'DTC-0007', approvedPhones: [phoneId], expiresAt: testNow.add(const Duration(days: 90)), checkedAt: testNow));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await signIn(t, 'Ali', '1234');
    await openDrawer(t);
    await tapKey(t, 'drawer-account');
    expect(find.byKey(const ValueKey('account-status')), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('account-customer-id'))).data, 'DTC-0007');
    expect(t.widget<Text>(find.byKey(const ValueKey('account-expiry'))).data, '2026-04-12');
    await shot(t, '81_account');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
