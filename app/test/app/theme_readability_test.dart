import 'package:dt_food_pos/app/theme.dart';
import 'package:dt_food_pos/app/theme_style.dart';
import 'package:dt_food_pos/app/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whatever colours the owner picks, text must stay readable: every foreground/background pair the app uses is checked.
void main() {
  Color c(int v) => Color(0xFF000000 | v);
  final schemes = <String, ThemeStyle>{
    'red default': ThemeStyle.defaults,
    'yellow-gold': ThemeStyle(main: c(0xFFC107), accent: c(0xFFD4AF37), header: c(0xFFD4AF37), nav: c(0xFFFFF3C4)),
    'green': ThemeStyle(main: c(0x2E9E57), accent: c(0x1B7F3F), header: c(0x1B7F3F)),
    'purple': ThemeStyle(main: c(0x6A2BD9), accent: c(0x8E5CF0)),
    'pale yellow on white (bad pick)': ThemeStyle(main: c(0xFFF176), accent: c(0xFFF59D), text: c(0xFFFFCC), heading: c(0xFFFF99), muted: c(0xFFFFEE), navText: c(0xFFFFFF), nav: c(0xFFFFFF), total: c(0xFFFFAA)),
    'night': ThemeStyle(main: c(0xE5484D), accent: c(0xE5484D), header: c(0x111111), background: c(0x181818), surface: c(0x232323), nav: c(0x111111), text: c(0xF4F4F4)),
    'gradient bar': ThemeStyle(main: c(0xC92A2A), header: c(0xC92A2A), header2: c(0xFFD54F)),
  };
  for (final e in schemes.entries) {
    test('readable: ${e.key}', () {
      final th = buildTheme(spec: e.value.toPreset());
      final cs = th.colorScheme;
      final b = th.extension<BrandColors>()!;
      expect(contrastRatio(cs.onSurface, cs.surface), greaterThanOrEqualTo(4.5), reason: 'body text on cards');
      expect(contrastRatio(cs.onSurface, th.scaffoldBackgroundColor), greaterThanOrEqualTo(4.0), reason: 'body text on page');
      expect(contrastRatio(cs.onSurfaceVariant, cs.surface), greaterThanOrEqualTo(3), reason: 'labels');
      expect(contrastRatio(th.textTheme.titleLarge!.color!, cs.surface), greaterThanOrEqualTo(4.5), reason: 'headings');
      expect(contrastRatio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5), reason: 'button text');
      expect(contrastRatio(b.onAccent, b.accent), greaterThanOrEqualTo(4.5), reason: 'accent button text');
      expect(contrastRatio(th.appBarTheme.foregroundColor!, th.appBarTheme.backgroundColor!), greaterThanOrEqualTo(3), reason: 'top bar');
      final nav = th.navigationBarTheme;
      expect(contrastRatio(nav.labelTextStyle!.resolve({})!.color!, nav.backgroundColor!), greaterThanOrEqualTo(3), reason: 'bottom bar labels');
      if (b.total != null) expect(contrastRatio(b.total!, cs.surface), greaterThanOrEqualTo(4.5), reason: 'totals');
      final banner = BrandBanner(cs.primary);
      for (final g in banner.colors) {
        expect(contrastRatio(banner.on, g), greaterThanOrEqualTo(3), reason: 'dashboard/drawer banner text');
      }
    });
  }

  test('new per-element colours survive save and load', () {
    final s = ThemeStyle(main: c(0x2E9E57), heading: c(0x112233), muted: c(0x445566), navText: c(0x778899), total: c(0xAA0000), icon: c(0x003300));
    final back = ThemeStyle.decode(s.encode());
    expect(back.heading, s.heading);
    expect(back.muted, s.muted);
    expect(back.navText, s.navText);
    expect(back.total, s.total);
    expect(back.icon, s.icon);
    expect(ThemeStyle.decode('{"heading":"zz"}').heading, isNull);
  });

  test('Restaurant Red is the default; purple looks exist only as extra choices', () {
    bool purple(Color col) {
      final h = HSLColor.fromColor(col);
      return h.saturation > 0.25 && h.lightness > 0.08 && h.lightness < 0.92 && h.hue >= 255 && h.hue <= 305;
    }

    expect(themePresets.first.id, 'red', reason: 'Restaurant Red is the default');
    for (final p in themePresets.where((p) => !const ['dt', 'plum'].contains(p.id))) {
      for (final col in [p.seed, p.accent, p.header, p.nav, p.background, p.surface]) {
        if (col != null) expect(purple(col), isFalse, reason: '${p.id} has a purple colour');
      }
    }
    expect(themePresets.where((p) => purple(p.seed)).map((p) => p.id), containsAll(['dt', 'plum']));
    expect(customPalette.any(purple), isTrue, reason: 'purple can be picked in the colour studio');
  });

  testWidgets('every ready-made theme, purple ones included, is readable', (t) async {
    for (final p in themePresets) {
      final th = buildTheme(spec: p);
      final cs = th.colorScheme;
      expect(contrastRatio(cs.onSurface, cs.surface), greaterThanOrEqualTo(4.5), reason: '${p.id} body text');
      expect(contrastRatio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5), reason: '${p.id} button text');
      expect(contrastRatio(th.appBarTheme.foregroundColor!, th.appBarTheme.backgroundColor!), greaterThanOrEqualTo(3), reason: '${p.id} top bar');
    }
  });

  test('bottom bar: no pill behind the selected item, selected icon and label are brand red', () {
    final th = buildTheme(spec: themePresets.first);
    final nav = th.navigationBarTheme;
    expect(nav.indicatorColor, Colors.transparent);
    final sel = nav.iconTheme!.resolve({WidgetState.selected})!.color!;
    final off = nav.iconTheme!.resolve({})!.color!;
    expect(sel, isNot(off));
    expect(HSLColor.fromColor(sel).hue < 15 || HSLColor.fromColor(sel).hue > 345, isTrue, reason: 'selected is red');
    expect(nav.labelTextStyle!.resolve({WidgetState.selected})!.fontWeight, FontWeight.w800);
  });
}
