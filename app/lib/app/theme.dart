import 'package:flutter/material.dart';

import 'theme_style.dart';
import 'themes.dart';

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
  const BrandColors({required this.accent, required this.onAccent, this.price, this.headerGradient});
  final Color accent;
  final Color onAccent;

  /// Fill of the price badges (null = the main colour).
  final Color? price;

  /// Two colours = the top bar is a gradient (see [DtAppBar]).
  final List<Color>? headerGradient;
  @override
  BrandColors copyWith({Color? accent, Color? onAccent, Color? price, List<Color>? headerGradient}) => BrandColors(accent: accent ?? this.accent, onAccent: onAccent ?? this.onAccent, price: price ?? this.price, headerGradient: headerGradient ?? this.headerGradient);
  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) =>
      other is BrandColors ? BrandColors(accent: Color.lerp(accent, other.accent, t)!, onAccent: Color.lerp(onAccent, other.onAccent, t)!, price: Color.lerp(price, other.price, t), headerGradient: t < 0.5 ? headerGradient : other.headerGradient) : this;
}

extension BrandColorsX on BuildContext {
  Color get accent => Theme.of(this).extension<BrandColors>()?.accent ?? brandOrange;
  Color get onAccent => Theme.of(this).extension<BrandColors>()?.onAccent ?? Colors.white;

  /// Price badge fill: the owner's price colour, else the main colour.
  Color get priceColor => Theme.of(this).extension<BrandColors>()?.price ?? Theme.of(this).colorScheme.primary;
}

double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + 0.05 : l2 + 0.05) / (l1 > l2 ? l2 + 0.05 : l1 + 0.05);
}

/// A darker shade of [c] that reads on [bg] (contrast >= 4.5), keeping its hue.
Color readableShade(Color c, Color bg) {
  var h = HSLColor.fromColor(c);
  var out = c;
  for (var i = 0; i < 20 && contrastRatio(out, bg) < 4.5; i++) {
    h = h.withLightness((h.lightness - 0.04).clamp(0.0, 1.0));
    out = h.toColor();
  }
  return out;
}

/// Builds the whole Material theme from a theme spec ([spec]) or just a main and accent colour.
ThemeData buildTheme({Brightness brightness = Brightness.light, Color seed = brandPurple, Color accent = brandOrange, ThemePreset? spec}) {
  final p = spec ?? ThemePreset('_', seed, '', accent: accent);
  final st = p.style is ThemeStyle ? p.style as ThemeStyle : null;
  final b = p.dark ? Brightness.dark : brightness;
  final light = b == Brightness.light;
  var scheme = ColorScheme.fromSeed(seedColor: p.seed, brightness: b, dynamicSchemeVariant: DynamicSchemeVariant.fidelity);
  final surface = (light || p.dark) ? (p.surface ?? (light ? Colors.white : scheme.surface)) : scheme.surface;
  // bright brand colours (yellow, gold) are used as fills; text and outlines get a darker shade that stays readable
  final fill = (light || p.dark) ? p.seed : scheme.primary;
  final textPrimary = contrastRatio(fill, surface) >= 4.5 ? fill : (light ? readableShade(fill, surface) : fill);
  scheme = scheme.copyWith(
    primary: textPrimary,
    onPrimary: _readableOn(textPrimary),
    primaryContainer: light ? Color.alphaBlend(fill.withValues(alpha: 0.16), Colors.white) : scheme.primaryContainer,
    secondary: p.secondary ?? scheme.secondary,
    surface: surface,
    onSurface: st != null ? st.effectiveText(surface) : (_readableOn(surface) == Colors.white ? const Color(0xFFF1F1F1) : const Color(0xFF1B1B1F)),
  );
  final background = light ? (p.background ?? Color.alphaBlend(p.seed.withValues(alpha: 0.04), const Color(0xFFF8F8FA))) : (p.dark ? (p.background ?? scheme.surface) : scheme.surface);
  final header = light || p.dark ? p.headerColor : scheme.surfaceContainerHigh;
  // with a gradient the bar text must read on both ends
  final header2 = st?.header2;
  final onHeader = header2 == null ? _readableOn(header) : _readableOn(Color.lerp(header, header2, 0.5)!);
  final nav = p.nav ?? (light ? surface : scheme.surfaceContainer);
  final r = p.radius;
  final cardRadius = st?.cardRadius ?? (r + 2);
  final showBorder = st != null ? st.cardBorder : p.cardStyle == 'outline';
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(cardRadius),
    side: showBorder ? BorderSide(color: st?.border ?? scheme.outlineVariant) : BorderSide.none,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: st == null ? 'Inter' : (st.fontFamily == 'system' ? null : st.fontFamily),
    fontFamilyFallback: const ['NotoNaskhArabic'],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
  final pill = st?.buttonStyle == 'pill';
  final outlinedButtons = st?.buttonStyle == 'outlined';
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(pill ? 999 : r));
  final themed = base.copyWith(
    extensions: [BrandColors(accent: p.accent, onAccent: _readableOn(p.accent), price: st?.price, headerGradient: header2 == null ? null : [header, header2])],
    // smooth page changes without heavy animations on low-end phones
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()}),
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: header,
      foregroundColor: onHeader,
      elevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 18, color: onHeader),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: nav,
      indicatorColor: fill.withValues(alpha: light ? 0.22 : 0.35),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: _readableOn(nav) == Colors.white ? Colors.white : const Color(0xFF2A2A2E))),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _readableOn(nav) == Colors.white ? Colors.white : const Color(0xFF2A2A2E))),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: nav,
      indicatorColor: fill.withValues(alpha: light ? 0.22 : 0.35),
      selectedIconTheme: IconThemeData(color: _readableOn(nav) == Colors.white ? Colors.white : const Color(0xFF2A2A2E)),
      unselectedIconTheme: IconThemeData(color: _readableOn(nav) == Colors.white ? Colors.white70 : const Color(0xFF55555C)),
      selectedLabelTextStyle: TextStyle(fontWeight: FontWeight.w700, color: _readableOn(nav) == Colors.white ? Colors.white : const Color(0xFF2A2A2E)),
      unselectedLabelTextStyle: TextStyle(color: _readableOn(nav) == Colors.white ? Colors.white70 : const Color(0xFF55555C)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: fill, foregroundColor: _readableOn(fill), shape: buttonShape),
    cardTheme: CardThemeData(
      elevation: st != null ? st.elevation : (p.cardStyle == 'shadow' ? 2 : 0),
      shadowColor: st != null ? st.shadowColor.withValues(alpha: 0.55) : Colors.black26,
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
    ),
    dialogTheme: DialogThemeData(backgroundColor: surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 6))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: outlinedButtons ? Colors.transparent : fill,
        foregroundColor: outlinedButtons ? textPrimary : _readableOn(fill),
        side: outlinedButtons ? BorderSide(color: textPrimary, width: 1.5) : null,
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: buttonShape)),
    inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular((r - 2).clamp(4, 30).toDouble())), filled: true, fillColor: surface),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 6))),
  );
  if (st == null) return themed;
  // text colour for the whole app (text SIZE is applied in the app builder, on top of the phone's own text-size setting)
  return themed.copyWith(textTheme: themed.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface));
}


/// The app's top bar: a normal AppBar, or a gradient bar when the theme has one (Theme Studio). Use it instead of AppBar.
class DtAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DtAppBar({super.key, this.title, this.actions, this.leading, this.bottom});
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final g = Theme.of(context).extension<BrandColors>()?.headerGradient;
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      flexibleSpace: g == null ? null : DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: g))),
      backgroundColor: g == null ? null : Colors.transparent,
    );
  }
}
