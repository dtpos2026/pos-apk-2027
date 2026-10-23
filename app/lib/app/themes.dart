import 'package:flutter/material.dart';

import 'theme.dart';

class ThemePreset {
  const ThemePreset(this.id, this.seed, this.nameKey, {this.accent = brandOrange});
  final String id;
  final Color seed;

  /// Second colour for "Add" buttons, the selected category and other calls to action.
  final Color accent;

  /// Key in [Strings] for the display name.
  final String nameKey;
}

/// The default is the Digital Target logo purple. Every preset keeps its seed colour exactly as the main colour,
/// so buttons and the app bar match the chosen brand colour.
const themePresets = <ThemePreset>[
  ThemePreset('dt', brandPurple, 'theme_dt'),
  ThemePreset('orange', Color(0xFFE8590C), 'theme_orange', accent: Color(0xFF1E2A78)),
  ThemePreset('ocean', Color(0xFF0B5FA5), 'theme_ocean', accent: Color(0xFFF59F00)),
  ThemePreset('navy', Color(0xFF1E2A78), 'theme_navy', accent: Color(0xFFF26A21)),
  ThemePreset('forest', Color(0xFF1B6B3A), 'theme_forest', accent: Color(0xFFF26A21)),
  ThemePreset('red', Color(0xFFC92A2A), 'theme_red', accent: Color(0xFFF59F00)),
  ThemePreset('sunset', Color(0xFFC2410C), 'theme_sunset', accent: Color(0xFF5F3DC4)),
  ThemePreset('rose', Color(0xFFBE185D), 'theme_rose', accent: Color(0xFF0F766E)),
  ThemePreset('slate', Color(0xFF334155), 'theme_slate', accent: Color(0xFFF26A21)),
  ThemePreset('gold', Color(0xFF8A5A00), 'theme_gold', accent: Color(0xFF3C096C)),
  ThemePreset('teal', Color(0xFF0F766E), 'theme_teal', accent: Color(0xFFF26A21)),
];

/// Colours offered for a custom theme (main and accent).
const customPalette = <Color>[
  Color(0xFF3C096C), Color(0xFF5F3DC4), Color(0xFF1E2A78), Color(0xFF0B5FA5), Color(0xFF0F766E), Color(0xFF1B6B3A),
  Color(0xFF2B8A3E), Color(0xFF8A5A00), Color(0xFFF59F00), Color(0xFFF26A21), Color(0xFFE8590C), Color(0xFFC2410C),
  Color(0xFFC92A2A), Color(0xFFBE185D), Color(0xFF862E9C), Color(0xFF334155), Color(0xFF212529), Color(0xFF5C3D2E),
];

/// 'custom:RRGGBB,RRGGBB' = a theme the owner put together; anything else is a preset id.
ThemePreset presetById(String? id) {
  if (id != null && id.startsWith('custom:')) {
    final parts = id.substring(7).split(',');
    final main = parts.isNotEmpty ? int.tryParse(parts[0], radix: 16) : null;
    final accent = parts.length > 1 ? int.tryParse(parts[1], radix: 16) : null;
    if (main != null) return ThemePreset(id, Color(0xFF000000 | main), 'theme_custom', accent: accent == null ? brandOrange : Color(0xFF000000 | accent));
  }
  return themePresets.firstWhere((p) => p.id == id, orElse: () => themePresets.first);
}

String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
String customThemeId(Color main, Color accent) => 'custom:${_hex(main)},${_hex(accent)}';

/// 'system' | 'light' | 'dark'
ThemeMode modeFromId(String? id) => switch (id) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
String modeId(ThemeMode m) => switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' };
