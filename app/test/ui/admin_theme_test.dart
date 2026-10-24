import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/harness.dart';

Future<Harness> start(WidgetTester t, {required String themeId, required bool locked, bool ownerChose = false}) async {
  final cloud = FakeCloud();
  final db = newDb();
  await seedBusiness(db);
  final h = await pumpApp(t, db: db, cloud: cloud);
  if (ownerChose) await h.container.read(themeIdProvider.notifier).set('ocean');
  await cloud.signInDirect('owner@cafe.pk');
  final phoneId = await h.container.read(accessProvider.notifier).phoneId();
  cloud.serverAccount(AccountSnapshot(status: 'active', approvedPhones: [phoneId], expiresAt: testNow.add(const Duration(days: 30)), themeId: themeId, themeLocked: locked, checkedAt: testNow));
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
  return h;
}

void main() {
  testWidgets('a theme assigned by Digital Target is the default until the owner picks one', (t) async {
    final h = await start(t, themeId: 'green', locked: false);
    expect(h.container.read(effectiveThemeIdProvider), 'green');
    await signIn(t, 'Ali', '1234');
    expect(Theme.of(t.element(find.byType(Scaffold).first)).appBarTheme.backgroundColor, const Color(0xFF2B8A3E));
    await h.container.read(themeIdProvider.notifier).set('red');
    await t.pumpAndSettle();
    expect(h.container.read(effectiveThemeIdProvider), 'red', reason: 'the owner may change an unlocked theme');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('a locked theme wins over the owner\'s choice and Settings cannot change it', (t) async {
    final h = await start(t, themeId: 'custom:0B5FA5,F59F00,,,shadow,20', locked: true, ownerChose: true);
    expect(h.container.read(effectiveThemeIdProvider), 'custom:0B5FA5,F59F00,,,shadow,20');
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-locked-note')), findsOneWidget);
    await showThemeCard(t, 'theme-green');
    await t.tap(find.byKey(const ValueKey('theme-green')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(h.container.read(effectiveThemeIdProvider), 'custom:0B5FA5,F59F00,,,shadow,20');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  testWidgets('an unknown assigned theme is ignored; nothing assigned changes nothing', (t) async {
    final h = await start(t, themeId: 'does-not-exist', locked: true);
    expect(h.container.read(effectiveThemeIdProvider), 'red');
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });

  test('the theme survives the offline cache', () {
    final a = AccountSnapshot(status: 'active', themeId: 'coffee', themeLocked: true, checkedAt: DateTime(2026));
    final back = AccountSnapshot.tryParse(a.toJson())!;
    expect([back.themeId, back.themeLocked], ['coffee', true]);
    expect(AccountSnapshot.tryParse(AccountSnapshot(status: 'active', checkedAt: DateTime(2026)).toJson())!.themeId, '');
  });
}
