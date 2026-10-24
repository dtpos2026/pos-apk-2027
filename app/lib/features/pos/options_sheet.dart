import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/strings.dart';
import '../../data/menu_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';

/// Lets the cashier pick a size and add-ons before an item goes on the order. Returns the configured cart line.
Future<CartItem?> showOptionsSheet(BuildContext context, WidgetRef ref, MenuProduct p, ProductOptions opts) {
  return showModalBottomSheet<CartItem>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => SafeArea(top: false, child: _OptionsSheet(p: p, opts: opts)));
}

class _OptionsSheet extends ConsumerStatefulWidget {
  const _OptionsSheet({required this.p, required this.opts});
  final MenuProduct p;
  final ProductOptions opts;
  @override
  ConsumerState<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends ConsumerState<_OptionsSheet> {
  VariantInfo? _variant;
  final _chosen = <String, Set<String>>{}; // group id -> option ids
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.opts.variants.isNotEmpty) _variant = widget.opts.variants.first;
    for (final g in widget.opts.groups) {
      _chosen[g.id] = {};
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<CartModifier> get _mods => [
        for (final g in widget.opts.groups)
          for (final o in g.options)
            if (_chosen[g.id]!.contains(o.id)) CartModifier(optionId: o.id, name: o.name, priceMinor: o.priceMinor)
      ];

  int get _unit => (_variant?.priceMinor ?? widget.p.priceMinor) + _mods.fold(0, (s, m) => s + m.priceMinor);

  bool get _valid => widget.opts.groups.every((g) => _chosen[g.id]!.length >= g.minSelect && _chosen[g.id]!.length <= g.maxSelect);

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(children: [
        ListTile(title: Text(widget.p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            if (widget.opts.variants.isNotEmpty) ...[
              Text('${t['variants_title']}  ·  ${t['choose_one']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<String>(
                groupValue: _variant?.id,
                onChanged: (id) => setState(() => _variant = widget.opts.variants.firstWhere((v) => v.id == id)),
                child: Column(children: [
                  for (final v in widget.opts.variants)
                    RadioListTile<String>(key: ValueKey('opt-variant-${v.name}'), contentPadding: EdgeInsets.zero, value: v.id, title: Text(v.name), secondary: Text(ref.money(v.priceMinor, symbol: false), style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
              ),
              const Divider(),
            ],
            for (final g in widget.opts.groups) ...[
              Text('${g.name}  ·  ${g.minSelect > 0 ? (g.maxSelect == 1 ? t['choose_one'] : '${t['choose_between']} ${g.minSelect}-${g.maxSelect}') : t['optional']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final o in g.options)
                CheckboxListTile(
                  key: ValueKey('opt-${g.name}-${o.name}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _chosen[g.id]!.contains(o.id),
                  title: Text(o.name),
                  secondary: o.priceMinor > 0 ? Text('+${ref.money(o.priceMinor, symbol: false)}') : null,
                  onChanged: (v) => setState(() {
                    final set = _chosen[g.id]!;
                    if (v == true) {
                      if (g.maxSelect == 1) set.clear(); // single choice behaves like a radio
                      if (set.length < g.maxSelect) set.add(o.id);
                    } else {
                      set.remove(o.id);
                    }
                  }),
                ),
              const Divider(),
            ],
            TextField(key: const ValueKey('opt-note'), controller: _note, decoration: InputDecoration(labelText: t['note'], isDense: true)),
            const SizedBox(height: 16),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('opt-add'),
              style: FilledButton.styleFrom(backgroundColor: scheme.primary),
              onPressed: _valid
                  ? () => Navigator.pop(
                      context,
                      CartItem(
                        productId: widget.p.id,
                        variantId: _variant?.id,
                        name: _variant == null ? widget.p.name : '${widget.p.name} (${_variant!.name})',
                        qtyMilli: 1000,
                        unitPriceMinor: _variant?.priceMinor ?? widget.p.priceMinor,
                        modifiers: _mods,
                        taxRateBp: widget.p.taxBp,
                        taxInclusive: widget.p.taxInclusive,
                        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                        station: widget.p.station,
                      ))
                  : null,
              child: Text('${t['add_to_order']}  ·  ${ref.money(_unit)}'),
            ),
          ),
        ),
      ]),
    );
  }
}
