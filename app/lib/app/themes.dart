import 'package:flutter/material.dart';

import 'theme.dart';

/// One complete look for the app: every screen reads these tokens through the Material theme, so changing the
/// theme recolours the whole app at once. Themes only change the interface, never prices or data.
class ThemePreset {
  const ThemePreset(
    this.id,
    this.seed,
    this.nameKey, {
    this.accent = brandOrange,
    this.secondary,
    this.background,
    this.surface,
    this.header,
    this.nav,
    this.dark = false,
    this.cardStyle = 'outline',
    this.radius = 14,
    this.style,
  });
  final String id;

  /// Main colour (buttons, selected items, prices).
  final Color seed;

  /// Key in [Strings] for the display name.
  final String nameKey;

  /// "Add" buttons, the selected category and other calls to action.
  final Color accent;
  final Color? secondary;

  /// Page background and card colour (light themes); null = derived from the main colour.
  final Color? background;
  final Color? surface;

  /// Top bar colour; null = main colour.
  final Color? header;

  /// Bottom navigation / side rail colour; null = surface.
  final Color? nav;

  /// Always dark (e.g. black & gold), whatever the light/dark setting says.
  final bool dark;

  /// 'outline' (thin border), 'shadow' (soft shadow) or 'flat'.
  final String cardStyle;

  /// Corner roundness of buttons and cards.
  final double radius;

  /// The extra settings of an owner-made Theme Studio theme (fonts, gradient, shadows...); null for the ready-made themes.
  final Object? style;

  Color get headerColor => header ?? seed;
}

/// The default is Restaurant Red (red / white with gold and black accents). "Digital Target" is the purple brand theme, available as a choice.
const themePresets = <ThemePreset>[
  // The DT Food POS identity: red and white. Restaurant Red is the default; Restaurant Red 2 uses #C41414.
  ThemePreset('red', Color(0xFFC92A2A), 'theme_red', accent: Color(0xFFF59F00), background: Color(0xFFFBF5F5)),
  ThemePreset('red2', Color(0xFFC41414), 'theme_red2', accent: Color(0xFFC41414), background: Color(0xFFFAF7F7), surface: Color(0xFFFFFFFF), nav: Color(0xFFFFFFFF)),
  // Digital Target's own colours: royal purple with amber. An extra choice; the app stays Restaurant Red by default.
  ThemePreset('dt', Color(0xFF3C096C), 'theme_dt', accent: brandAmber, background: Color(0xFFF8F5FC)),
  ThemePreset('green', Color(0xFF2B8A3E), 'theme_green', accent: Color(0xFFF08C00), background: Color(0xFFF3F8F4)),
  ThemePreset('golden', Color(0xFFB7791F), 'theme_golden', accent: Color(0xFF1F2937), background: Color(0xFFFBF8F1)),
  ThemePreset('yellow', Color(0xFFFFC107), 'theme_yellow', accent: Color(0xFFD9480F), background: Color(0xFFFFFBEB), cardStyle: 'shadow'),
  ThemePreset('coffee', Color(0xFF6F4E37), 'theme_coffee', accent: Color(0xFFC8A27A), background: Color(0xFFF7F1EA), surface: Color(0xFFFFFCF8)),
  ThemePreset('ocean', Color(0xFF0B5FA5), 'theme_ocean', accent: Color(0xFFF59F00), background: Color(0xFFF2F6FB)),
  ThemePreset('blackgold', Color(0xFFD4AF37), 'theme_blackgold', accent: Color(0xFFD4AF37), dark: true, header: Color(0xFF0E0E0E), nav: Color(0xFF0E0E0E), background: Color(0xFF121212), surface: Color(0xFF1C1C1C)),
  ThemePreset('orange', Color(0xFFE8590C), 'theme_orange', accent: Color(0xFF1E2A78), background: Color(0xFFFFF8F3)),
  ThemePreset('navy', Color(0xFF1E2A78), 'theme_navy', accent: Color(0xFFFF5A1F)),
  ThemePreset('teal', Color(0xFF0F766E), 'theme_teal', accent: Color(0xFFFF5A1F)),
  ThemePreset('rose', Color(0xFFBE185D), 'theme_rose', accent: Color(0xFF0F766E)),
  // Luxury look: rose gold.
  ThemePreset('rosegold', Color(0xFF9A4B5E), 'theme_rosegold', accent: Color(0xFFA56E43), background: Color(0xFFFDF5F6), header: Color(0xFF7A2F42), cardStyle: 'shadow', radius: 18),
  ThemePreset('slate', Color(0xFF334155), 'theme_slate', accent: Color(0xFFFF5A1F)),
];

/// Colours offered for a custom theme.
const customPalette = <Color>[
  Color(0xFFC92A2A), Color(0xFFC41414), Color(0xFF1E2A78), Color(0xFF0B5FA5), Color(0xFF0F766E), Color(0xFF1B6B3A),
  Color(0xFF2B8A3E), Color(0xFFB7791F), Color(0xFFD4AF37), Color(0xFFFFC107), Color(0xFFF59F00), Color(0xFFFF5A1F),
  Color(0xFFE8590C), Color(0xFF8E1B1B), Color(0xFFBE185D), Color(0xFF6F4E37), Color(0xFF334155), Color(0xFF111111),
];

/// Background colours offered for a custom theme (light and dark).
const backgroundPalette = <Color>[
  Color(0xFFFFF8F0), Color(0xFFFFFFFF), Color(0xFFF3F8F4), Color(0xFFFFFBEB), Color(0xFFF7F1EA), Color(0xFFF2F6FB), Color(0xFFFBF5F5), Color(0xFF121212),
];

// Old saved ids keep working.
const _aliases = {'forest': 'green', 'sunset': 'orange', 'gold': 'golden'};

String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
Color? _color(String? s) {
  final v = s == null || s.isEmpty ? null : int.tryParse(s, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// 'custom:main,accent[,header,background,cardStyle,radius]' = a theme the owner put together.
String customThemeId(Color main, Color accent, {Color? header, Color? background, String cardStyle = 'outline', double radius = 14}) =>
    'custom:${_hex(main)},${_hex(accent)},${header == null ? '' : _hex(header)},${background == null ? '' : _hex(background)},$cardStyle,${radius.round()}';

ThemePreset presetById(String? id) {
  if (id != null && id.startsWith('custom:')) {
    final p = id.substring(7).split(',');
    final main = _color(p.isNotEmpty ? p[0] : null);
    if (main != null) {
      final bg = _color(p.length > 3 ? p[3] : null);
      final darkBg = bg != null && bg.computeLuminance() < 0.1;
      return ThemePreset(
        id,
        main,
        'theme_custom',
        accent: _color(p.length > 1 ? p[1] : null) ?? brandOrange,
        header: _color(p.length > 2 ? p[2] : null),
        background: bg,
        dark: darkBg,
        surface: darkBg ? const Color(0xFF1C1C1C) : null,
        nav: darkBg ? const Color(0xFF0E0E0E) : null,
        cardStyle: p.length > 4 && const ['outline', 'shadow', 'flat'].contains(p[4]) ? p[4] : 'outline',
        radius: (p.length > 5 ? double.tryParse(p[5]) : null)?.clamp(4, 28).toDouble() ?? 14,
      );
    }
  }
  final real = _aliases[id] ?? id;
  return themePresets.firstWhere((p) => p.id == real, orElse: () => themePresets.first);
}

/// 'system' | 'light' | 'dark'
ThemeMode modeFromId(String? id) => switch (id) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
String modeId(ThemeMode m) => switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' };
