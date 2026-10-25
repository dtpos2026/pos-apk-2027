import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/queries.dart' show getSetting, setSetting;
import 'providers.dart';
import 'theme.dart';
import 'theme_style.dart';

/// How the side menu (the drawer behind the three lines) looks: dark (the colour of the theme, white words) or light (white / soft tint,
/// dark words), and optionally the words' colour and the header colour chosen by the owner. Words are checked for contrast before they are used.
class SideMenuStyle {
  const SideMenuStyle({this.light = false, this.text, this.bg});
  final bool light;
  final Color? text;
  final Color? bg;
}

/// What the header and list of the menu really use, worked out from the theme colour and [SideMenuStyle].
class MenuColors {
  MenuColors(Color primary, SideMenuStyle s) {
    if (s.light) {
      final base = s.bg ?? Color.alphaBlend(primary.withValues(alpha: 0.10), Colors.white);
      headerColors = [base, Color.alphaBlend(primary.withValues(alpha: 0.04), Colors.white)];
      body = Colors.white;
      on = ThemeStyle.guard(s.text, base, readableShade(primary, base));
    } else {
      final banner = BrandBanner(primary, darken: 0.45);
      final base = s.bg ?? primary;
      headerColors = s.bg == null ? banner.colors : BrandBanner(base, darken: 0.45).colors;
      body = null;
      on = ThemeStyle.guard(s.text, headerColors.first, BrandBanner(base).on);
    }
    soft = on.withValues(alpha: 0.72);
    chip = on.withValues(alpha: 0.16);
    listText = s.text;
  }
  late final List<Color> headerColors;
  late final Color on, soft, chip;

  /// Drawer body colour (null = the theme's).
  late final Color? body;

  /// Colour the owner chose for the list words (null = the theme's).
  late final Color? listText;
  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: headerColors);
}

class SideMenuStyleNotifier extends AsyncNotifier<SideMenuStyle> {
  static const lightKey = 'ui.menu_light', textKey = 'ui.menu_text', bgKey = 'ui.menu_bg';

  @override
  Future<SideMenuStyle> build() async {
    final db = ref.read(databaseProvider);
    return SideMenuStyle(light: (await getSetting(db, lightKey)) == '1', text: _c(await getSetting(db, textKey)), bg: _c(await getSetting(db, bgKey)));
  }

  static Color? _c(String? s) => s == null || s.isEmpty ? null : parseHexColor(s);
  static String _h(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  Future<void> _save(String key, String value, SideMenuStyle next) async {
    await setSetting(ref.read(databaseProvider), key, value, ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(next);
  }

  Future<void> setLight(bool v) async {
    final s = state.value ?? const SideMenuStyle();
    await _save(lightKey, v ? '1' : '0', SideMenuStyle(light: v, text: s.text, bg: s.bg));
  }

  /// null = automatic.
  Future<void> setText(Color? c) async {
    final s = state.value ?? const SideMenuStyle();
    await _save(textKey, c == null ? '' : _h(c), SideMenuStyle(light: s.light, text: c, bg: s.bg));
  }

  Future<void> setBg(Color? c) async {
    final s = state.value ?? const SideMenuStyle();
    await _save(bgKey, c == null ? '' : _h(c), SideMenuStyle(light: s.light, text: s.text, bg: c));
  }
}

final menuStyleProvider = AsyncNotifierProvider<SideMenuStyleNotifier, SideMenuStyle>(SideMenuStyleNotifier.new);
