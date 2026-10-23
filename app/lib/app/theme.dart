import 'package:flutter/material.dart';

/// Digital Target brand purple, measured from the supplied logo.
const brandPurple = Color(0xFF3C096C);
const brandAmber = Color(0xFFFFB547);

/// Accent for "Add" actions on the selling screen (from the approved POS design references).
const brandOrange = Color(0xFFFF5A1F);

Color _readableOn(Color bg) {
  double ratio(Color a, Color b) {
    final l1 = a.computeLuminance(), l2 = b.computeLuminance();
    return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
  }

  return ratio(bg, Colors.white) >= ratio(bg, Colors.black) ? Colors.white : Colors.black;
}

/// The theme's second colour, available everywhere as `context.accent`.
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({required this.accent, required this.onAccent});
  final Color accent;
  final Color onAccent;
  @override
  BrandColors copyWith({Color? accent, Color? onAccent}) => BrandColors(accent: accent ?? this.accent, onAccent: onAccent ?? this.onAccent);
  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) =>
      other is BrandColors ? BrandColors(accent: Color.lerp(accent, other.accent, t)!, onAccent: Color.lerp(onAccent, other.onAccent, t)!) : this;
}

extension BrandColorsX on BuildContext {
  Color get accent => Theme.of(this).extension<BrandColors>()?.accent ?? brandOrange;
  Color get onAccent => Theme.of(this).extension<BrandColors>()?.onAccent ?? Colors.white;
}

ThemeData buildTheme({Brightness brightness = Brightness.light, Color seed = brandPurple, Color accent = brandOrange}) {
  // fidelity keeps the seed (the logo purple) as the exact primary colour instead of a muted tonal variant
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.fidelity);
  if (brightness == Brightness.light) {
    // the brand colour itself (not a tonal variant of it) is the main colour, so the app matches the logo exactly
    scheme = scheme.copyWith(primary: seed, onPrimary: _readableOn(seed));
  }
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['NotoNaskhArabic'],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  return base.copyWith(
    extensions: [BrandColors(accent: accent, onAccent: _readableOn(accent))],
    // smooth page changes without heavy animations on low-end phones
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()}),
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF6F3FA) : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 18, color: scheme.onPrimary),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
    cardTheme: CardThemeData(elevation: 0, color: scheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: scheme.surface),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}
