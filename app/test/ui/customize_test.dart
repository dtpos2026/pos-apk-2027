import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/app/theme.dart';
import 'package:dt_food_pos/app/themes.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<void> _settings(WidgetTester t) async {
  await openTab(t, 'settings', 'Settings');
}

void main() {
  test('custom theme ids keep both colours; unknown ids fall back to Digital Target', () {
    final id = customThemeId(const Color(0xFF1E2A78), const Color(0xFFFF5A1F));
    expect(id, 'custom:1E2A78,FF5A1F,,,outline,14');
    expect(presetById('custom:1E2A78,FF5A1F').accent.toARGB32(), 0xFFFF5A1F, reason: 'older 2-colour ids still load');
    expect(presetById('forest').id, 'green', reason: 'renamed themes keep working');
    final p = presetById(id);
    expect(p.seed.toARGB32(), 0xFF1E2A78);
    expect(p.accent.toARGB32(), 0xFFFF5A1F);
    expect(presetById('nope').id, 'dt');
    expect(presetById('dt').accent.toARGB32(), 0xFFFF5A1F);
  });

  testWidgets('owner builds a custom theme (main + button colour); it is saved and applied', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await _settings(t);
    await showThemeCard(t, 'theme-custom');
    await tapKey(t, 'theme-custom');
    await tapKey(t, 'main-ff1e2a78');
    await tapKey(t, 'accent-ff2b8a3e');
    await tapKey(t, 'custom-theme-save');
    final ctx = t.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).colorScheme.primary.toARGB32(), 0xFF1E2A78);
    expect(ctx.accent.toARGB32(), 0xFF2B8A3E);
    expect(await t.runAsync(() => getSetting(db, 'theme')), startsWith('custom:1E2A78,2B8A3E'));
    expect(h.container.read(themeIdProvider), startsWith('custom:'));
  });

  testWidgets('compact selling layout shows more items without pictures and is remembered', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await _settings(t);
    await t.ensureVisible(find.byKey(const ValueKey('pos-layout')));
    await t.pumpAndSettle();
    await t.tap(find.text('Compact (faster)'));
    await t.pumpAndSettle();
    expect(await t.runAsync(() => getSetting(db, 'pos_layout')), 'compact');
    await openTab(t, 'pos', 'POS');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    expect(find.byKey(const ValueKey('add-Zinger Burger')), findsNothing, reason: 'compact tiles have no Add button, tap the tile');
    expect(find.byKey(const ValueKey('product-Zinger Burger')), findsOneWidget, reason: 'all five items fit on one screen');
  });
}
