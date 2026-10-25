import 'package:dt_food_pos/app/feedback.dart';
import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/fake_feedback.dart';
import '../helpers/harness.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

void main() {
  testWidgets('every tap clicks and vibrates, a paid bill plays the success tone; sound and vibration can each be switched off', (t) async {
    final fb = FakeFeedback();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, extra: [feedbackPlayerProvider.overrideWithValue(fb)]);
    await signIn(t, 'Ali', '1234');
    expect(fb.clicks, greaterThan(0), reason: 'taps made sounds');
    expect(fb.vibrations, greaterThan(0));

    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Cash');
    expect(fb.tones, isEmpty);
    await tapKey(t, 'confirm-payment');
    expect(fb.tones, ['success']);
    expect(fb.strongVibrations, 1);

    // switched off: silence (and no buzz)
    await h.container.read(feedbackPrefsProvider.notifier).setSound(false);
    await h.container.read(feedbackPrefsProvider.notifier).setVibrate(false);
    final c = fb.clicks, v = fb.vibrations;
    await tapKey(t, 'new-sale');
    expect(fb.clicks, c);
    expect(fb.vibrations, v);
    await h.container.read(appFeedbackProvider).success();
    expect(fb.tones, ['success'], reason: 'no second tone');

    // the choice is remembered
    expect((await h.container.read(feedbackPrefsProvider.future)).sound, isFalse);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('a scroll is not a tap: no sound', (t) async {
    final fb = FakeFeedback();
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, extra: [feedbackPlayerProvider.overrideWithValue(fb)]);
    final before = fb.clicks;
    await t.dragFrom(const Offset(200, 500), const Offset(0, -200));
    await t.pump();
    expect(fb.clicks, before);
  });

  testWidgets('notices: asks permission once, shows new ones in the status bar, respects the switch, Clear all empties the list', (t) async {
    final fb = FakeFeedback();
    final cloud = FakeCloud()..signedIn = true;
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud, extra: [feedbackPlayerProvider.overrideWithValue(fb)]);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(AccountSnapshot(status: 'active', approvedPhones: [phoneId], businessName: 'Burger Point', expiresAt: testNow.add(const Duration(days: 30)), checkedAt: testNow));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await settle(t);
    expect(find.text('Allow notifications?'), findsOneWidget);
    await tapKey(t, 'notices-yes');
    expect((await h.container.read(feedbackPrefsProvider.future)).notices, isTrue);

    cloud.pushNotice('Payment due', 'Please pay the fee');
    await settle(t);
    await settle(t);
    expect(fb.shown, ['Payment due']);
    cloud.pushNotice('Update ready', 'New version');
    await settle(t);
    await settle(t);
    expect(fb.shown, ['Payment due', 'Update ready'], reason: 'each notice once');

    await h.container.read(feedbackPrefsProvider.notifier).setNotices(false);
    cloud.pushNotice('Quiet one', 'x');
    await settle(t);
    await settle(t);
    expect(fb.shown.length, 2, reason: 'switched off: nothing in the status bar');

    // the bell list, then Clear
    await t.tap(find.byKey(const ValueKey('bell')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('notice-Quiet one')), findsOneWidget);
    await tapKey(t, 'notices-clear');
    expect(find.byKey(const ValueKey('notices-empty')), findsOneWidget);
    expect(fb.cleared, 1, reason: 'the status-bar notices were removed too');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('declining Android permission leaves the notices switch off', (t) async {
    final fb = FakeFeedback(permission: false);
    final cloud = FakeCloud()..signedIn = true;
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud, extra: [feedbackPlayerProvider.overrideWithValue(fb)]);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(AccountSnapshot(status: 'active', approvedPhones: [phoneId], businessName: 'Burger Point', expiresAt: testNow.add(const Duration(days: 30)), checkedAt: testNow));
    await settle(t);
    await signIn(t, 'Ali', '1234');
    await settle(t);
    await tapKey(t, 'notices-yes');
    expect((await h.container.read(feedbackPrefsProvider.future)).notices, isFalse);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
