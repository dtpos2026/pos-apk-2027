import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/features/cloud/cloud_reporter.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/harness.dart';

AccountSnapshot account({String status = 'active', List<String> ok = const [], List<String> requests = const [], String msg = '', DateTime? exp}) => AccountSnapshot(
    status: status, approvedPhones: ok, phoneRequests: requests, adminMessage: msg, businessName: 'Burger Point', expiresAt: exp ?? testNow.add(const Duration(days: 30)), checkedAt: testNow);

/// Lets the fake streams and the controller's async work run.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  testWidgets('signed out → sign in → registration → waiting → approved → app opens, step by step', (t) async {
    final cloud = FakeCloud();
    final h = await pumpApp(t, cloud: cloud);
    await settle(t);
    expect(find.byKey(const Key('cloud_submit')), findsOneWidget);

    // wrong password shows the server's plain message
    await t.enterText(find.byKey(const Key('cloud_email')), 'owner@cafe.pk');
    await t.enterText(find.byKey(const Key('cloud_password')), 'wrongpw');
    await t.tap(find.byKey(const Key('cloud_submit')));
    await settle(t);
    expect(find.text('Wrong email or password.'), findsOneWidget);

    await t.enterText(find.byKey(const Key('cloud_password')), 'secret1');
    await t.tap(find.byKey(const Key('cloud_submit')));
    cloud.serverAccount(null); // the server says: no registration yet
    await settle(t);
    expect(find.byKey(const Key('reg_submit')), findsOneWidget);

    // empty form is refused locally
    await t.tap(find.byKey(const Key('reg_submit')));
    await t.pump();
    expect(find.byKey(const Key('reg_error')), findsOneWidget);

    await t.enterText(find.byKey(const Key('reg_name')), 'Burger Point');
    await t.enterText(find.byKey(const Key('reg_owner')), 'Ali');
    await t.enterText(find.byKey(const Key('reg_phone')), '0300-1111111');
    await t.tap(find.byKey(const Key('reg_submit')));
    await settle(t);
    expect(cloud.registered.single.businessName, 'Burger Point');
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.byKey(const Key('check_again')), findsOneWidget);

    // the admin approves from the panel: the phone id the app registered is now approved
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    expect(find.text('Set up your business'), findsOneWidget, reason: 'continues to the normal first-run setup');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('suspending from the panel stops a running app and shows the admin message, activating restores it', (t) async {
    final cloud = FakeCloud()..signedIn = true;
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget, reason: 'PIN screen of the local app');

    cloud.serverAccount(account(status: 'suspended', ok: [phoneId], msg: 'Pay the March fee'));
    await settle(t);
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Pay the March fee'), findsOneWidget);
    expect(find.text('Your restaurant data is safe on this phone.'), findsOneWidget);

    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('a phone that is not approved asks for approval once', (t) async {
    final cloud = FakeCloud();
    final h = await pumpApp(t, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    cloud.serverAccount(account(ok: ['some-other-phone']));
    await settle(t);
    expect(find.text('New phone needs approval'), findsOneWidget);
    final id = await h.container.read(accessProvider.notifier).phoneId();
    expect(cloud.requestedPhones, [id]);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('expiry in a few days shows a banner after sign-in', (t) async {
    final cloud = FakeCloud()..control = const AppControl(notice: 'Eid holidays: support closed Friday');
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId], exp: testNow.add(const Duration(days: 3))));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    expect(find.byKey(const Key('access_banner')), findsOneWidget);
    expect(find.textContaining('ends in 4 days'), findsOneWidget);
    expect(find.textContaining('Eid holidays'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('only totals are sent to the cloud: bills, net sales, customers', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.devices.last.phoneId, phoneId);
    expect(cloud.sales.last.bills, 0);
    expect(cloud.sales.last.date, '2026-01-12');
    expect(cloud.sales.last.currency, 'PKR');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('support chat sends and shows replies', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'support');
    await t.enterText(find.byKey(const Key('support_text')), 'My printer is offline');
    await t.tap(find.byKey(const Key('support_send')));
    await settle(t);
    expect(find.text('My printer is offline'), findsOneWidget);
    cloud.adminReplies('Check the Wi-Fi');
    await settle(t);
    expect(find.text('Check the Wi-Fi'), findsOneWidget);
    expect(cloud.support.first.fromAdmin, isFalse);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('days spent offline are re-sent later, and the app bar shows offline/synced', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    final owner = await seedBusiness(db);
    // a sale two days ago, while the phone was offline
    final past = PosService(db, now: () => testNow.subtract(const Duration(days: 2)));
    final pid = (await db.customSelect("SELECT id FROM product WHERE sku = 'BRG-1'").getSingle()).data['id'] as String;
    final cash = (await db.customSelect("SELECT id FROM payment_method WHERE kind = 'cash'").getSingle()).data['id'] as String;
    final o = await past.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: pid, name: 'Zinger', qtyMilli: 1000, unitPriceMinor: 45000)]), staffId: owner);
    await past.settleOrder(orderId: o, payments: [SettlePayment(methodId: cash, amountMinor: 45000)], staffId: owner);

    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    cloud.offline = true;
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    await t.pump();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(cloud.pastDays, isEmpty);

    cloud.offline = false;
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    await t.pump();
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    final d = cloud.pastDays.singleWhere((x) => x.date == '2026-01-10');
    expect(d.bills, 1);
    expect(d.netMinor, greaterThanOrEqualTo(45000));
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
