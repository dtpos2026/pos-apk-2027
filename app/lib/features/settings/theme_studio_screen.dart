import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../app/theme_style.dart';
import '../../cloud/access_controller.dart' show adminLockedThemeProvider;
import '../pos/pos_screen.dart' show PriceBadge;
import 'text_editor_screen.dart';

/// Ready-made starting points: professional, matched colour sets. Each one is only a starting point; every value stays editable.
const studioPresets = <(String, ThemeStyle)>[
  ('Restaurant Red', ThemeStyle(main: Color(0xFFC92A2A), accent: Color(0xFFF59F00), background: Color(0xFFFBF5F5))),
  ('Restaurant Red 2', ThemeStyle(main: Color(0xFFC41414), accent: Color(0xFFC41414), background: Color(0xFFFAF7F7), surface: Color(0xFFFFFFFF))),
  ('Red gradient', ThemeStyle(main: Color(0xFFC41414), accent: Color(0xFFF59F00), header: Color(0xFFC41414), header2: Color(0xFF7A0E0E), background: Color(0xFFFAF7F7), shadow: 2)),
  ('Charcoal & Red', ThemeStyle(main: Color(0xFFC41414), accent: Color(0xFFC41414), header: Color(0xFF1F2937), background: Color(0xFFF3F4F6), nav: Color(0xFFFFFFFF), cardBorder: false, shadow: 2)),
  ('Ivory & Gold', ThemeStyle(main: Color(0xFF8A5A00), accent: Color(0xFFB7791F), header: Color(0xFF3B2A12), background: Color(0xFFFBF8F1), shadow: 1)),
  ('Night', ThemeStyle(main: Color(0xFFE5484D), accent: Color(0xFFE5484D), header: Color(0xFF111111), background: Color(0xFF181818), surface: Color(0xFF232323), nav: Color(0xFF111111), text: Color(0xFFF4F4F4), shadow: 0)),
];

const _palette = <Color>[
  Color(0xFFC41414), Color(0xFFC92A2A), Color(0xFFE5484D), Color(0xFF7A0E0E), Color(0xFFFF5A1F), Color(0xFFF59F00), Color(0xFFFFC107), Color(0xFFB7791F),
  Color(0xFF2E9E5B), Color(0xFF2B8A3E), Color(0xFF0F766E), Color(0xFF0B5FA5), Color(0xFF1E2A78), Color(0xFFF08C00), Color(0xFF8E1B1B), Color(0xFFBE185D),
  Color(0xFF111111), Color(0xFF1F2937), Color(0xFF334155), Color(0xFF6B7280), Color(0xFFD1D5DB), Color(0xFFF3F4F6), Color(0xFFFAF7F7), Color(0xFFFFFFFF),
];

/// Theme Studio: change colours, gradient, shadows, borders, buttons, fonts and text size with a live preview, no code needed.
/// Text colours are checked for contrast, so white on white can never be saved.
class ThemeStudioScreen extends ConsumerStatefulWidget {
  const ThemeStudioScreen({super.key});
  @override
  ConsumerState<ThemeStudioScreen> createState() => _ThemeStudioState();
}

class _ThemeStudioState extends ConsumerState<ThemeStudioScreen> {
  ThemeStyle? _d;

  ThemeStyle get d => _d ?? ref.read(themeStyleProvider).value ?? ThemeStyle.defaults;
  void _set(ThemeStyle s) => setState(() => _d = s);

  Future<void> _pick(String label, Color? current, {required ThemeStyle Function(Color?) apply, bool nullable = false}) async {
    final t = Strings.of(context);
    final picked = await showDialog<_Picked>(
      context: context,
      builder: (ctx) {
        final hex = TextEditingController(text: current == null ? '' : (current.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase());
        String? err;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(scrollable: true, 
            title: Text(label),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in _palette)
                    InkWell(
                      key: ValueKey('swatch-${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase()}'),
                      onTap: () => Navigator.pop(ctx, _Picked(c)),
                      child: Container(width: 38, height: 38, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black26, width: current == c ? 3 : 1))),
                    ),
                ]),
                const SizedBox(height: 14),
                TextField(key: const ValueKey('hex-field'), controller: hex, decoration: InputDecoration(labelText: t['studio_hex'], prefixText: '#', errorText: err), onChanged: (_) => setS(() => err = null)),
              ]),
            ),
            actions: [
              if (nullable) TextButton(key: const ValueKey('color-auto'), onPressed: () => Navigator.pop(ctx, const _Picked(null)), child: Text(t['studio_auto'])),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
              FilledButton(
                key: const ValueKey('hex-ok'),
                onPressed: () {
                  final c = parseHexColor(hex.text);
                  if (c == null) {
                    setS(() => err = t['studio_hex_bad']);
                    return;
                  }
                  Navigator.pop(ctx, _Picked(c));
                },
                child: Text(t['ok']),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) _set(apply(picked.color));
  }

  Widget _colorTile(String keyId, String label, Color? value, ThemeStyle Function(Color?) apply, {bool nullable = false, Color? shown}) => ListTile(
        key: ValueKey('studio-$keyId'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Container(width: 34, height: 34, decoration: BoxDecoration(color: value ?? shown ?? Colors.transparent, shape: BoxShape.circle, border: Border.all(color: Colors.black38))),
        subtitle: value == null && nullable ? Text(Strings.of(context)['studio_auto']) : null,
        onTap: () => _pick(label, value, apply: apply, nullable: nullable),
      );

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = d;
    final locked = ref.watch(adminLockedThemeProvider);
    final warnings = s.contrastWarnings();
    Widget group(String title, List<Widget> children) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)), const SizedBox(height: 4), ...children])),
        );
    return Scaffold(
      appBar: DtAppBar(title: Text(t['theme_studio'])),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (locked) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)), child: Text(t['theme_locked_note'])),
        // live preview: a small selling screen drawn with the draft theme
        Container(
          key: const ValueKey('studio-preview'),
          height: 360,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: Theme(data: buildTheme(spec: s.toPreset()), child: const _PreviewPos()),
        ),
        if (warnings.isNotEmpty)
          Container(
            key: const ValueKey('studio-warning'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFDEFD2), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
              const SizedBox(width: 10),
              Expanded(child: Text(t['studio_contrast_warning'], style: const TextStyle(color: Color(0xFF6B4500)))),
              TextButton(key: const ValueKey('studio-fix'), onPressed: () => _set(s.copyWith(clearText: true, clearHeading: true, clearMuted: true)), child: Text(t['studio_fix'])),
            ]),
          ),
        group(t['studio_start'], [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final p in studioPresets) ActionChip(key: ValueKey('preset-${p.$1}'), avatar: CircleAvatar(backgroundColor: p.$2.main, radius: 8), label: Text(p.$1), onPressed: () => _set(p.$2)),
          ]),
        ]),
        group(t['studio_colors'], [
          _colorTile('main', t['studio_main'], s.main, (c) => s.copyWith(main: c)),
          _colorTile('accent', t['studio_accent'], s.accent, (c) => s.copyWith(accent: c)),
          _colorTile('header', t['studio_header'], s.header, (c) => c == null ? s.copyWith(clearHeader: true) : s.copyWith(header: c), nullable: true, shown: s.main),
          _colorTile('header2', t['studio_gradient'], s.header2, (c) => c == null ? s.copyWith(clearHeader2: true) : s.copyWith(header2: c), nullable: true),
          _colorTile('background', t['studio_background'], s.background, (c) => c == null ? s.copyWith(clearBackground: true) : s.copyWith(background: c), nullable: true),
          _colorTile('surface', t['studio_surface'], s.surface, (c) => c == null ? s.copyWith(clearSurface: true) : s.copyWith(surface: c), nullable: true),
          _colorTile('nav', t['studio_nav'], s.nav, (c) => c == null ? s.copyWith(clearNav: true) : s.copyWith(nav: c), nullable: true),
          _colorTile('text', t['studio_text'], s.text, (c) => c == null ? s.copyWith(clearText: true) : s.copyWith(text: c), nullable: true),
          _colorTile('price', t['studio_price'], s.price, (c) => c == null ? s.copyWith(clearPrice: true) : s.copyWith(price: c), nullable: true, shown: s.main),
          _colorTile('heading', t['studio_heading'], s.heading, (c) => c == null ? s.copyWith(clearHeading: true) : s.copyWith(heading: c), nullable: true),
          _colorTile('muted', t['studio_muted'], s.muted, (c) => c == null ? s.copyWith(clearMuted: true) : s.copyWith(muted: c), nullable: true),
          _colorTile('navtext', t['studio_navtext'], s.navText, (c) => c == null ? s.copyWith(clearNavText: true) : s.copyWith(navText: c), nullable: true),
          _colorTile('total', t['studio_total'], s.total, (c) => c == null ? s.copyWith(clearTotal: true) : s.copyWith(total: c), nullable: true),
          _colorTile('icon', t['studio_icon'], s.icon, (c) => c == null ? s.copyWith(clearIcon: true) : s.copyWith(icon: c), nullable: true),
          _colorTile('border', t['studio_border_color'], s.border, (c) => c == null ? s.copyWith(clearBorder: true) : s.copyWith(border: c), nullable: true),
        ]),
        group(t['studio_boxes'], [
          SwitchListTile(key: const ValueKey('studio-card-border'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['studio_show_borders']), value: s.cardBorder, onChanged: (v) => _set(s.copyWith(cardBorder: v))),
          Text(t['studio_shadow']),
          SegmentedButton<int>(
            key: const ValueKey('studio-shadow'),
            showSelectedIcon: false,
            segments: [for (final i in [0, 1, 2, 3]) ButtonSegment(value: i, label: Text(['—', '1', '2', '3'][i]))],
            selected: {s.shadow},
            onSelectionChanged: (v) => _set(s.copyWith(shadow: v.first)),
          ),
          _colorTile('shadow-color', t['studio_shadow_color'], s.shadowColor, (c) => s.copyWith(shadowColor: c)),
          Text('${t['studio_card_radius']}: ${s.cardRadius.round()}'),
          Slider(key: const ValueKey('studio-card-radius'), value: s.cardRadius, min: 0, max: 32, divisions: 16, onChanged: (v) => _set(s.copyWith(cardRadius: v))),
        ]),
        group(t['studio_buttons'], [
          SegmentedButton<String>(
            key: const ValueKey('studio-button-style'),
            showSelectedIcon: false,
            segments: [for (final b in ThemeStyle.buttonStyles) ButtonSegment(value: b, label: Text(t['studio_btn_$b']))],
            selected: {s.buttonStyle},
            onSelectionChanged: (v) => _set(s.copyWith(buttonStyle: v.first)),
          ),
          Text('${t['studio_button_radius']}: ${s.buttonRadius.round()}'),
          Slider(key: const ValueKey('studio-button-radius'), value: s.buttonRadius, min: 0, max: 32, divisions: 16, onChanged: (v) => _set(s.copyWith(buttonRadius: v))),
        ]),
        group(t['studio_text_group'], [
          DropdownButtonFormField<String>(
            key: const ValueKey('studio-font'),
            initialValue: s.fontFamily,
            decoration: InputDecoration(labelText: t['studio_font']),
            items: [for (final f in ThemeStyle.fonts) DropdownMenuItem(value: f, child: Text(t['studio_font_$f']))],
            onChanged: (v) => _set(s.copyWith(fontFamily: v)),
          ),
          Text('${t['studio_font_size']}: ${(s.fontScale * 100).round()}%'),
          Slider(key: const ValueKey('studio-font-scale'), value: s.fontScale, min: 0.85, max: 1.3, divisions: 9, onChanged: (v) => _set(s.copyWith(fontScale: v))),
          ListTile(key: const ValueKey('studio-edit-texts'), contentPadding: EdgeInsets.zero, leading: const Icon(Icons.edit_note), title: Text(t['text_editor']), subtitle: Text(t['text_editor_hint']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TextEditorScreen()))),
        ]),
        Row(children: [
          Expanded(child: OutlinedButton(key: const ValueKey('studio-reset'), onPressed: () => _set(ThemeStyle.defaults), child: Text(t['studio_reset']))),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton(
              key: const ValueKey('studio-save'),
              onPressed: locked
                  ? null
                  : () async {
                      await ref.read(themeStyleProvider.notifier).apply(s);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['studio_saved'])));
                      }
                    },
              child: Text(t['studio_apply']),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _Picked {
  const _Picked(this.color);
  final Color? color;
}

/// A tiny selling screen (top bar, item card with price badge, buttons, bottom bar) that shows the draft theme as it will look.
class _PreviewPos extends StatelessWidget {
  const _PreviewPos();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: DtAppBar(title: const Text('DT Food POS'), actions: const [Icon(Icons.search), SizedBox(width: 12)]),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(height: 56, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), alignment: Alignment.bottomLeft, padding: const EdgeInsets.all(6), child: const PriceBadge(text: 'PKR 450')),
                    const SizedBox(height: 6),
                    const Text('Zinger Burger', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text('Crispy chicken, sauce', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(height: 56, decoration: BoxDecoration(color: context.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), alignment: Alignment.bottomLeft, padding: const EdgeInsets.all(6), child: const PriceBadge(text: 'PKR 250')),
                    const SizedBox(height: 6),
                    const Text('French Fries', style: TextStyle(fontWeight: FontWeight.w700)),
                    const Text('Large', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ]),
          const Spacer(),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Hold'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(onPressed: () {}, child: const Text('Charge  ·  PKR 700'))),
          ]),
        ]),
      ),
      bottomNavigationBar: NavigationBar(selectedIndex: 0, destinations: const [NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'), NavigationDestination(icon: Icon(Icons.table_restaurant_outlined), label: 'Tables'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Bills')]),
    );
  }
}
