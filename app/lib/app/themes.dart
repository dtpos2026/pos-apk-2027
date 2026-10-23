import 'package:flutter/material.dart';

import 'theme.dart';

class ThemePreset {
  const ThemePreset(this.id, this.seed, this.nameKey);
  final String id;
  final Color seed;

  /// Key in [Strings] for the display name.
  final String nameKey;
}

/// The default is the Digital Target logo purple. Every preset keeps its seed colour exactly as the main colour,
/// so buttons and the app bar match the chosen brand colour.
const themePresets = <ThemePreset>[
  ThemePreset('dt', brandPurple, 'theme_dt'),
  ThemePreset('ocean', Color(0xFF0B5FA5), 'theme_ocean'),
  ThemePreset('forest', Color(0xFF1B6B3A), 'theme_forest'),
  ThemePreset('sunset', Color(0xFFC2410C), 'theme_sunset'),
  ThemePreset('rose', Color(0xFFBE185D), 'theme_rose'),
  ThemePreset('slate', Color(0xFF334155), 'theme_slate'),
  ThemePreset('gold', Color(0xFF8A5A00), 'theme_gold'),
  ThemePreset('teal', Color(0xFF0F766E), 'theme_teal'),
];

ThemePreset presetById(String? id) => themePresets.firstWhere((p) => p.id == id, orElse: () => themePresets.first);

/// 'system' | 'light' | 'dark'
ThemeMode modeFromId(String? id) => switch (id) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
String modeId(ThemeMode m) => switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' };
