import 'dart:io';
import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/cloud/cloud_gateway.dart' show Branding;
import 'package:dt_food_pos/app/device_channel.dart';
import 'package:dt_food_pos/cloud/location_consent.dart';
import 'package:dt_food_pos/app/providers.dart' show authServiceProvider;
import 'package:dt_food_pos/data/auth_service.dart' show PinResult;
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/queries.dart' show getSetting;
import 'package:dt_food_pos/features/cloud/cloud_reporter.dart';
import 'package:dt_food_pos/features/cloud/notices.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
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
    await shot(t, '60_cloud_signin');

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
    await shot(t, '61_cloud_register');

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
    await shot(t, '62_cloud_waiting');
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
    await shot(t, '63_cloud_suspended');
    expect(find.text('Your restaurant data is safe on this phone.'), findsOneWidget);

    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('a PIN reset from the panel shows on the sign-in screen at once, the new PIN works, data stays, and it is applied only once', (t) async {
    final cloud = FakeCloud()..signedIn = true;
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-reset-banner')), findsNothing);

    // "Forgot PIN?" explains what to do, and closes itself when the reset arrives
    await t.tap(find.byKey(const ValueKey('forgot-pin')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('forgot-pin-body')), findsOneWidget);
    await shot(t, '64_forgot_pin');

    // the owner is locked out after wrong tries, then Digital Target resets the PIN from the panel
    final before = await db.customSelect('SELECT COUNT(*) c FROM product').getSingle();
    cloud.serverPinReset(account(ok: [phoneId]), 'r1', '4821');
    await settle(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('forgot-pin-body')), findsNothing, reason: 'dialog closed itself');
    expect(find.byKey(const ValueKey('pin-reset-banner')), findsOneWidget);
    expect(cloud.finishedResets, ['r1'], reason: 'the PIN was removed from the cloud copy');
    await shot(t, '65_pin_reset_banner');

    await signIn(t, 'Ali', '1234');
    expect(find.byKey(const ValueKey('pin-error')), findsOneWidget);
    expect((t.widget<Text>(find.byKey(const ValueKey('pin-error')))).data, 'Wrong PIN');
    for (final d in '4821'.split('')) {
      await tapKey(t, 'key-$d');
    }
    await tapKey(t, 'key-ok');
    expect(find.byKey(const ValueKey('staff-Ali')), findsNothing, reason: 'signed in with the new PIN');
    expect((await db.customSelect('SELECT COUNT(*) c FROM product').getSingle()).data['c'], before.data['c'], reason: 'no data was cleared');

    // the same reset arriving again (reconnect) is not applied twice
    cloud.serverPinReset(account(ok: [phoneId]), 'r1', '9999');
    await settle(t);
    expect(await h.container.read(authServiceProvider).verifyPin((await db.customSelect('SELECT id FROM staff').getSingle()).read<String>('id'), '4821'), PinResult.ok);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('with free phone slots a new phone opens at once and is still listed for the panel', (t) async {
    final cloud = FakeCloud()..signedIn = true;
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    cloud.serverAccount(AccountSnapshot(status: 'active', approvedPhones: const ['other-1'], maxPhones: 15, businessName: 'Burger Point', expiresAt: testNow.add(const Duration(days: 30)), checkedAt: testNow));
    await settle(t);
    expect(find.text('New phone needs approval'), findsNothing);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget);
    expect(cloud.requestedPhones, [await h.container.read(accessProvider.notifier).phoneId()]);
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

  testWidgets('the restaurant\'s data never leaves the phone: only account state, device info and daily totals are reported', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await t.runAsync(() => h.db.customStatement("INSERT INTO outbox(idempotency_key, entity, entity_id, op, payload, created_at) VALUES ('customer:c1:v1','customer','c1','upsert','{\"name\":\"Secret\"}',1)"));
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.devices, isNotEmpty);
    expect((await h.db.customSelect("SELECT COUNT(*) AS n FROM outbox WHERE acked_at IS NOT NULL").getSingle()).data['n'], 0, reason: 'nothing from the local change log was uploaded');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('the restaurant logo goes to the panel as a tiny picture (once, again only when the logo changes) for the map pin', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final dir = Directory.systemTemp.createTempSync('dtlogo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final logo = File('${dir.path}/logo.png')..writeAsBytesSync(img.encodePng(img.Image(width: 300, height: 200)));
    await db.customStatement("UPDATE business_profile SET logo_path = ?", [logo.path]);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.profiles, isNotEmpty, reason: 'the restaurant name and address go to the panel');
    expect(cloud.logos, hasLength(1));
    expect(cloud.logos.single, startsWith('data:image/jpeg;base64,'));
    expect(cloud.logos.single.length, lessThan(20000), reason: 'a pin picture, not the full logo');
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.logos, hasLength(1), reason: 'unchanged: not sent again');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('support chat sends and shows replies', (t) async {
    final cloud = FakeCloud()..brand = const Branding(whatsapp: '0300-1234567');
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
    expect(cloud.supportNames.single, 'Burger Point', reason: 'support sees the restaurant name, not the owner\'s');
    expect(find.byKey(const ValueKey('support-whatsapp')), findsOneWidget, reason: 'the WhatsApp number comes from the panel');
    cloud.adminReplies('Check the Wi-Fi');
    await settle(t);
    expect(find.text('Check the Wi-Fi'), findsOneWidget);
    expect(cloud.support.first.fromAdmin, isFalse);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('notifications: a notice sent from the panel reaches the open app at once, the bell counts it, opening it marks it read (and it stays read)', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    expect(find.byKey(const ValueKey('bell')), findsOneWidget);
    expect(find.byType(Badge).evaluate().where((e) => (e.widget as Badge).isLabelVisible), isEmpty, reason: 'nothing yet');

    cloud.pushNotice('Subscription payment due', 'Please pay on time.', kind: 'payment');
    cloud.pushNotice('New version available', 'Please update.', kind: 'update');
    await settle(t);
    expect(find.text('2'), findsOneWidget, reason: 'two unread on the bell');
    await shot(t, '100_bell');

    await tapKey(t, 'bell');
    await settle(t);
    expect(find.text('Subscription payment due'), findsOneWidget);
    expect(find.text('New version available'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('2'), findsNothing, reason: 'read now');
    expect(h.container.read(noticeSeenProvider).value, greaterThan(0));

    cloud.pushNotice('Short maintenance', 'Tonight.', kind: 'warning');
    await settle(t);
    expect(find.text('1'), findsOneWidget, reason: 'only the new one is unread');
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

  testWidgets('reinstalling the app on an approved phone does not ask for approval again (stable phone id)', (t) async {
    final cloud = FakeCloud();
    final db = newDb(); // a fresh install: nothing stored locally
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud, platformPhoneId: 'a1b2c3d4e5f6a7b8c9d0');
    await cloud.signInDirect('owner@cafe.pk');
    cloud.serverAccount(account(ok: ['a1b2c3d4e5f6a7b8c9d0']));
    await settle(t);
    expect(await h.container.read(accessProvider.notifier).phoneId(), 'a1b2c3d4e5f6a7b8c9d0');
    expect(find.text('New phone needs approval'), findsNothing);
    expect(cloud.requestedPhones, isEmpty);
    expect(find.byKey(const ValueKey('staff-Ali')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('location: asked once after sign-in; shared only when allowed; can be switched off', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    var permissionAsked = 0;
    final h = await pumpApp(t, db: db, cloud: cloud, extra: [
      locationSourceProvider.overrideWithValue(() async => PhoneLocation(31.52, 74.35, 12, testNow)),
      locationPermissionProvider.overrideWithValue(() async { permissionAsked++; return true; }),
    ]);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await settle(t);
    expect(find.text('Share location?'), findsOneWidget);
    await t.tap(find.byKey(const Key('location-yes')));
    await settle(t);
    expect(permissionAsked, 1);
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.devices.last.locationAllowed, isTrue);
    expect(cloud.devices.last.lat, 31.52);

    await t.runAsync(() => h.container.read(locationConsentProvider.notifier).set(false));
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.devices.last.locationAllowed, isFalse);
    expect(cloud.devices.last.lat, isNull);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('location: "Not now" shares nothing and does not ask again', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud, extra: [
      locationSourceProvider.overrideWithValue(() async => PhoneLocation(1, 2, 3, testNow)),
    ]);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(account(ok: [phoneId]));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await settle(t);
    await t.tap(find.byKey(const Key('location-no')));
    await settle(t);
    await t.runAsync(() => h.container.read(cloudReporterProvider).reportNow());
    expect(cloud.devices.last.locationAllowed, isFalse);
    expect(cloud.devices.last.lat, isNull);
    expect(await t.runAsync(() => getSetting(db, LocationConsentNotifier.key)), '0');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
