import 'dart:convert';

import 'package:flutter/material.dart';

import 'theme.dart';
import 'themes.dart';

/// Everything the owner can change in the Theme Studio. All of it is data (saved as JSON in the settings table), so a theme
/// can be edited without touching the code. A null colour means "use the base theme's colour".
class ThemeStyle {
  const ThemeStyle({
    this.main = const Color(0xFFC92A2A),
    this.accent = const Color(0xFFF59F00),
    this.header,
    this.header2,
    this.background,
    this.surface,
    this.nav,
    this.text,
    this.price,
    this.border,
    this.heading,
    this.muted,
    this.navText,
    this.total,
    this.icon,
    this.shadowColor = const Color(0xFF000000),
    this.shadow = 1,
    this.cardBorder = true,
    this.cardRadius = 16,
    this.buttonRadius = 14,
    this.buttonStyle = 'filled',
    this.fontFamily = 'Inter',
    this.fontScale = 1.0,
  });

  /// Main colour (buttons, selected items, price badges unless [price] is set) and the second "Add" colour.
  final Color main;
  final Color accent;

  /// Top bar colour; with [header2] the bar is a gradient from [header] (or [main]) to [header2].
  final Color? header;
  final Color? header2;
  final Color? background;
  final Color? surface;
  final Color? nav;

  /// Body text colour (null = automatic black/white for the background). Checked for contrast before it is used.
  final Color? text;

  /// Price badge fill (null = main colour).
  final Color? price;

  /// Card / box border colour (null = automatic).
  final Color? border;

  /// Headings / titles, labels and descriptions (muted), bottom-bar labels, grand totals, icons. null = automatic.
  final Color? heading;
  final Color? muted;
  final Color? navText;
  final Color? total;
  final Color? icon;
  final Color shadowColor;

  /// 0 = none, 1 = subtle, 2 = medium, 3 = strong.
  final int shadow;
  final bool cardBorder;
  final double cardRadius;
  final double buttonRadius;

  /// 'filled' (square-ish, radius as set), 'pill' (fully round), 'outlined' (border only).
  final String buttonStyle;

  /// One of [fonts].
  final String fontFamily;

  /// 0.85 ... 1.3
  final double fontScale;

  static const fonts = ['Inter', 'JetBrainsMono', 'NotoNaskhArabic', 'system'];
  static const buttonStyles = ['filled', 'pill', 'outlined'];
  static const defaults = ThemeStyle();

  ThemeStyle copyWith({
    Color? main, Color? accent, Color? header, Color? header2, Color? background, Color? surface, Color? nav, Color? text, Color? price, Color? border, Color? heading, Color? muted, Color? navText, Color? total, Color? icon, Color? shadowColor,
    bool clearHeading = false, bool clearMuted = false, bool clearNavText = false, bool clearTotal = false, bool clearIcon = false,
    bool clearHeader2 = false, bool clearText = false, bool clearPrice = false, bool clearBorder = false, bool clearHeader = false, bool clearBackground = false, bool clearSurface = false, bool clearNav = false,
    int? shadow, bool? cardBorder, double? cardRadius, double? buttonRadius, String? buttonStyle, String? fontFamily, double? fontScale,
  }) =>
      ThemeStyle(
        main: main ?? this.main,
        accent: accent ?? this.accent,
        header: clearHeader ? null : (header ?? this.header),
        header2: clearHeader2 ? null : (header2 ?? this.header2),
        background: clearBackground ? null : (background ?? this.background),
        surface: clearSurface ? null : (surface ?? this.surface),
        nav: clearNav ? null : (nav ?? this.nav),
        text: clearText ? null : (text ?? this.text),
        price: clearPrice ? null : (price ?? this.price),
        border: clearBorder ? null : (border ?? this.border),
        heading: clearHeading ? null : (heading ?? this.heading),
        muted: clearMuted ? null : (muted ?? this.muted),
        navText: clearNavText ? null : (navText ?? this.navText),
        total: clearTotal ? null : (total ?? this.total),
        icon: clearIcon ? null : (icon ?? this.icon),
        shadowColor: shadowColor ?? this.shadowColor,
        shadow: (shadow ?? this.shadow).clamp(0, 3),
        cardBorder: cardBorder ?? this.cardBorder,
        cardRadius: (cardRadius ?? this.cardRadius).clamp(0, 32).toDouble(),
        buttonRadius: (buttonRadius ?? this.buttonRadius).clamp(0, 32).toDouble(),
        buttonStyle: buttonStyles.contains(buttonStyle) ? buttonStyle! : this.buttonStyle,
        fontFamily: fonts.contains(fontFamily) ? fontFamily! : this.fontFamily,
        fontScale: (fontScale ?? this.fontScale).clamp(0.85, 1.3).toDouble(),
      );

  /// Elevation for the card shadow level.
  double get elevation => const [0.0, 1.5, 4.0, 9.0][shadow];

  /// The colour text really gets: the chosen one when it reads on the background (contrast 4.5), otherwise black or white.
  Color effectiveText(Color background) {
    final t = text;
    if (t != null && contrastRatio(t, background) >= 4.5) return t;
    return contrastRatio(background, Colors.white) >= contrastRatio(background, Colors.black) ? Colors.white : const Color(0xFF111111);
  }

  /// [chosen] when it reads on [bg] (contrast >= [min]), otherwise [fallback]. Every owner-picked text colour goes through this.
  static Color guard(Color? chosen, Color bg, Color fallback, {double min = 4.5}) => chosen != null && contrastRatio(chosen, bg) >= min ? chosen : fallback;

  /// Contrast problems to show next to the controls (empty = all fine).
  List<String> contrastWarnings() {
    final out = <String>[];
    final bg = background ?? const Color(0xFFFAF7F7);
    if (text != null && contrastRatio(text!, bg) < 4.5) out.add('text');
    if (heading != null && contrastRatio(heading!, bg) < 4.5) out.add('heading');
    if (muted != null && contrastRatio(muted!, bg) < 3) out.add('muted');
    final h = header ?? main;
    if (contrastRatio(h, Colors.white) < 3 && contrastRatio(h, Colors.black) < 3) out.add('header');
    return out;
  }

  /// Turns the studio settings into a theme the app can build ([ThemePreset] plus these extras).
  ThemePreset toPreset([String id = 'studio']) => ThemePreset(
        id,
        main,
        'theme_studio',
        accent: accent,
        background: background,
        surface: surface,
        header: header,
        nav: nav,
        cardStyle: shadow > 0 ? 'shadow' : (cardBorder ? 'outline' : 'flat'),
        radius: buttonRadius,
        style: this,
        dark: ((background ?? surface)?.computeLuminance() ?? 1) < 0.12,
      );

  Map<String, Object?> toJson() => {
        'main': _hex(main), 'accent': _hex(accent), 'header': _hexN(header), 'header2': _hexN(header2), 'background': _hexN(background), 'surface': _hexN(surface), 'nav': _hexN(nav),
        'text': _hexN(text), 'price': _hexN(price), 'border': _hexN(border), 'heading': _hexN(heading), 'muted': _hexN(muted), 'navText': _hexN(navText), 'total': _hexN(total), 'icon': _hexN(icon), 'shadowColor': _hex(shadowColor), 'shadow': shadow, 'cardBorder': cardBorder, 'cardRadius': cardRadius,
        'buttonRadius': buttonRadius, 'buttonStyle': buttonStyle, 'fontFamily': fontFamily, 'fontScale': fontScale,
      };

  String encode() => jsonEncode(toJson());

  /// Damaged data gives the defaults; every value is range-checked.
  static ThemeStyle decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return defaults;
      return defaults.copyWith(
        main: _color(j['main']), accent: _color(j['accent']), header: _color(j['header']), header2: _color(j['header2']), background: _color(j['background']), surface: _color(j['surface']), nav: _color(j['nav']),
        text: _color(j['text']), price: _color(j['price']), border: _color(j['border']), heading: _color(j['heading']), muted: _color(j['muted']), navText: _color(j['navText']), total: _color(j['total']), icon: _color(j['icon']), shadowColor: _color(j['shadowColor']),
        shadow: (j['shadow'] as num?)?.toInt(), cardBorder: j['cardBorder'] as bool?, cardRadius: (j['cardRadius'] as num?)?.toDouble(), buttonRadius: (j['buttonRadius'] as num?)?.toDouble(),
        buttonStyle: j['buttonStyle'] as String?, fontFamily: j['fontFamily'] as String?, fontScale: (j['fontScale'] as num?)?.toDouble(),
      );
    } catch (_) {
      return defaults;
    }
  }

  static String _hex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  static String? _hexN(Color? c) => c == null ? null : _hex(c);
  static Color? _color(Object? s) {
    final v = s is String ? int.tryParse(s, radix: 16) : null;
    return v == null ? null : Color(0xFF000000 | v);
  }
}

/// "#RRGGBB" / "RRGGBB" typed by the owner -> a colour, or null when it is not a valid colour.
Color? parseHexColor(String input) {
  final h = input.trim().replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
