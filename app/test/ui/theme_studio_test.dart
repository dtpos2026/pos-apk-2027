import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/app/strings.dart';
import 'package:dt_food_pos/app/theme.dart';
import 'package:dt_food_pos/app/theme_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Future<void> _see(WidgetTester t, String key) async {
  await t.scrollUntilVisible(find.byKey(ValueKey(key)), 250, scrollable: verticalScroll);
  await Scrollable.ensureVisible(t.element(find.byKey(ValueKey(key))), alignment: 0.4);
  await t.pumpAndSettle();
}

Future<void> _openStudio(WidgetTester t) async {
  await openTab(t, 'settings', 'Settings');
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byKey(const ValueKey('theme-studio-tile')), 200, scrollable: verticalScroll);
  await Scrollable.ensureVisible(t.element(find.byKey(const ValueKey('theme-studio-tile'))), alignment: 0.4);
  await t.pumpAndSettle();
  await tapKey(t, 'theme-studio-tile');
}

void main() {
  test('ThemeStyle: saved as data and read back; damaged data gives the defaults; values stay in range', () {
    const s = ThemeStyle(main: Color(0xFFC41414), header: Color(0xFFC41414), header2: Color(0xFF7A0E0E), shadow: 2, buttonStyle: 'pill', fontScale: 1.2, cardBorder: false);
    final back = ThemeStyle.decode(s.encode());
    expect([back.main.toARGB32(), back.header2!.toARGB32(), back.shadow, back.buttonStyle, back.fontScale, back.cardBorder], [0xFFC41414, 0xFF7A0E0E, 2, 'pill', 1.2, false]);
    expect(ThemeStyle.decode('{{ nope').main.toARGB32(), ThemeStyle.defaults.main.toARGB32());
    final wild = ThemeStyle.decode('{"shadow": 99, "fontScale": 9, "cardRadius": -5, "buttonStyle": "weird", "fontFamily": "Comic"}');
    expect([wild.shadow, wild.fontScale, wild.cardRadius, wild.buttonStyle, wild.fontFamily], [3, 1.3, 0.0, 'filled', 'Inter']);
    expect(parseHexColor('#c41414')!.toARGB32(), 0xFFC41414);
    expect(parseHexColor('zzz'), isNull);
  });

  test('contrast guard: white text on a white page is replaced by a readable colour; a good choice is kept', () {
    const bad = ThemeStyle(text: Color(0xFFFFFFFF));
    expect(bad.contrastWarnings(), contains('text'));
    final used = bad.effectiveText(const Color(0xFFFFFFFF));
    expect(contrastRatio(used, const Color(0xFFFFFFFF)), greaterThanOrEqualTo(4.5));
    const good = ThemeStyle(text: Color(0xFF222222));
    expect(good.effectiveText(const Color(0xFFFFFFFF)), const Color(0xFF222222));
    // and a dark page gets light text
    expect(contrastRatio(const ThemeStyle().effectiveText(const Color(0xFF111111)), const Color(0xFF111111)), greaterThanOrEqualTo(4.5));
  });

  test('the theme is built from the style: gradient bar, price colour, font size, button shape, card shadow', () {
    const s = ThemeStyle(header: Color(0xFFC41414), header2: Color(0xFF7A0E0E), price: Color(0xFF111111), fontScale: 1.2, buttonStyle: 'pill', shadow: 3, cardBorder: false, fontFamily: 'JetBrainsMono');
    final th = buildTheme(spec: s.toPreset());
    final brand = th.extension<BrandColors>()!;
    expect(brand.headerGradient, [const Color(0xFFC41414), const Color(0xFF7A0E0E)]);
    expect(brand.price, const Color(0xFF111111));
    expect(th.cardTheme.elevation, 9.0);
    expect(th.textTheme.bodyMedium!.fontFamily, 'JetBrainsMono');
    final shape = th.filledButtonTheme.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect((shape.borderRadius as BorderRadius).topLeft.x, 999);
  });

  testWidgets('Theme Studio: pick a ready-made set, change a colour by code, see it live, save; the app uses it and remembers it', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await _openStudio(t);
    expect(find.byKey(const ValueKey('studio-preview')), findsOneWidget);
    await _see(t, 'preset-Red gradient');
    await tapKey(t, 'preset-Red gradient');
    await _see(t, 'studio-main');
    await tapKey(t, 'studio-main');
    await t.enterText(find.byKey(const ValueKey('hex-field')), 'zz'); // not a colour: refused with a message
    await tapKey(t, 'hex-ok');
    expect(find.text('Enter 6 letters/digits, for example C41414'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('hex-field')), '0B5FA5');
    await tapKey(t, 'hex-ok');
    await _see(t, 'studio-save');
    await tapKey(t, 'studio-save');
    expect(h.container.read(themeIdProvider), 'studio');
    final st = h.container.read(themeStyleProvider).value!;
    expect([st.main.toARGB32(), st.header2!.toARGB32()], [0xFF0B5FA5, 0xFF7A0E0E]);
    final saved = await t.runAsync(() => h.db.customSelect("SELECT setting_value AS v FROM setting WHERE setting_key = 'theme.style'").getSingle());
    expect(saved!.data['v'], contains('0B5FA5'));
    expect(Theme.of(t.element(find.byKey(const ValueKey('studio-save')))).extension<BrandColors>()?.headerGradient, isNotNull, reason: 'the app itself now has the gradient bar');
  });

  testWidgets('a white text colour on a white page is flagged and "automatic" fixes it', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await _openStudio(t);
    await _see(t, 'studio-text');
    await tapKey(t, 'studio-text');
    await t.enterText(find.byKey(const ValueKey('hex-field')), 'FFFFFF');
    await tapKey(t, 'hex-ok');
    await t.drag(verticalScroll, const Offset(0, 4000)); // back to the top, where the warning shows
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('studio-warning')), findsOneWidget);
    await tapKey(t, 'studio-fix');
    expect(find.byKey(const ValueKey('studio-warning')), findsNothing);
  });

  testWidgets('Edit app texts: rename a label, it changes everywhere at once and survives; reset brings the original back', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Dashboard')), findsOneWidget);
    await t.runAsync(() => h.container.read(textOverridesProvider.notifier).setText('en', 'dashboard', 'Home'));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')), findsOneWidget, reason: 'the bottom bar shows the new name without restarting');
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Dashboard')), findsNothing);
    final saved = await t.runAsync(() => h.db.customSelect("SELECT setting_value AS v FROM setting WHERE setting_key = 'text.overrides'").getSingle());
    expect(saved!.data['v'], contains('Home'));
    await t.runAsync(() => h.container.read(textOverridesProvider.notifier).resetAll());
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Dashboard')), findsOneWidget);
    expect(Strings.overrides, isEmpty);
  });
}
