import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/app/theme.dart';
import 'package:dt_food_pos/app/themes.dart';
import 'package:dt_food_pos/data/receipt_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

Color primary(WidgetTester t) => Theme.of(t.element(find.byType(Scaffold).first)).colorScheme.primary;

void main() {
  testWidgets('the default theme is the Digital Target logo purple, exactly', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    expect(primary(t).toARGB32(), brandPurple.toARGB32());
    expect(themePresets.first.id, 'dt');
  });

  testWidgets('choosing a theme recolours the whole app and is remembered after a restart', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.ensureVisible(find.byKey(const ValueKey('theme-ocean')));
    await t.tap(find.byKey(const ValueKey('theme-ocean')));
    await t.pumpAndSettle();
    expect(primary(t).toARGB32(), 0xFF0B5FA5);
    await shot(t, '30_theme_ocean');
    expect((await db.customSelect("SELECT setting_value FROM setting WHERE setting_key = 'theme'").getSingle()).data['setting_value'], 'ocean');

    // restart: a fresh app over the same database restores the theme
    await t.pumpWidget(const SizedBox());
    final h2 = await pumpApp(t, db: db);
    await t.runAsync(() => h2.container.read(themeIdProvider.notifier).restore());
    await t.pumpAndSettle();
    expect(primary(t).toARGB32(), 0xFF0B5FA5);
  });

  testWidgets('all themes build a readable scheme (text on primary has enough contrast)', (t) async {
    for (final p in themePresets) {
      for (final b in Brightness.values) {
        final s = buildTheme(seed: p.seed, brightness: b).colorScheme;
        double lum(Color c) => c.computeLuminance();
        double ratio(Color a, Color c) {
          final l1 = lum(a), l2 = lum(c);
          return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
        }

        expect(ratio(s.primary, s.onPrimary), greaterThan(4.5), reason: '${p.id} $b primary');
        expect(ratio(s.surface, s.onSurface), greaterThan(7), reason: '${p.id} $b surface');
      }
    }
  });

  testWidgets('dark mode switches the whole app to a dark scheme', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.ensureVisible(find.byKey(const ValueKey('theme-mode')));
    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    await shot(t, '31_dark');
  });

  testWidgets('sign-in screen shows the business logo, name, address and phone centred', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final dir = Directory.systemTemp.createTempSync('dtlogo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final i = img.Image(width: 200, height: 100, numChannels: 4)..clear(img.ColorRgba8(61, 9, 109, 255));
    await LogoStore(db, dir).save(Uint8List.fromList(img.encodePng(i)));
    await pumpApp(t, db: db, logoDir: dir);
    expect(find.byKey(const ValueKey('login-logo')), findsOneWidget);
    expect(find.text('Burger Point'), findsOneWidget);
    expect(find.text('Main Bazaar, Burewala'), findsOneWidget);
    expect(find.text('0300-0000000'), findsOneWidget);
    final screenCentre = t.getCenter(find.byType(Scaffold).first).dx;
    for (final f in [find.byKey(const ValueKey('login-logo')), find.text('Burger Point'), find.text('Main Bazaar, Burewala'), find.text('0300-0000000')]) {
      expect(t.getCenter(f).dx, closeTo(screenCentre, 1.5));
    }
    await shot(t, '32_login_brand');
  });
}
