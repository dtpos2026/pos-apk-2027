import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/strings.dart';

/// Quantity of a product sold by weight or volume, from what the cashier entered.
/// [productUnit] is the unit the price is per (kg, g, l, ml); [value] is typed in grams / millilitres, or in kg / litres when [big].
/// Result is the quantity in thousandths of the product unit (750 g of a per-kg item = 750).
int weightToMilli(String productUnit, double value, {required bool big}) {
  final productBig = productUnit == 'kg' || productUnit == 'l';
  final inProductUnit = productBig ? (big ? value : value / 1000) : (big ? value * 1000 : value);
  return (inProductUnit * 1000).round();
}

/// The same quantity as the cashier would say it: "750 g", "1.25 kg", "300 ml".
String weightLabel(String productUnit, int qtyMilli) {
  final productBig = productUnit == 'kg' || productUnit == 'l';
  final small = productUnit == 'l' || productUnit == 'ml' ? 'ml' : 'g';
  final big = small == 'ml' ? 'l' : 'kg';
  final smallAmount = productBig ? qtyMilli : qtyMilli / 1000; // grams (or ml)
  return smallAmount >= 1000 ? '${_trim(smallAmount / 1000)} $big' : '${_trim(smallAmount)} $small';
}

String _trim(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// Asks for the weight (grams, or kilograms) or volume of an item sold by weight and shows the price as it is typed.
/// Returns the quantity in thousandths of the product unit, or null when cancelled.
Future<int?> showWeightDialog(BuildContext context, WidgetRef ref, {required String name, required String unit, required int unitPriceMinor, int? initialMilli}) {
  return showDialog<int>(context: context, builder: (_) => _WeightDialog(name: name, unit: unit, unitPriceMinor: unitPriceMinor, initialMilli: initialMilli));
}

class _WeightDialog extends ConsumerStatefulWidget {
  const _WeightDialog({required this.name, required this.unit, required this.unitPriceMinor, this.initialMilli});
  final String name;
  final String unit;
  final int unitPriceMinor;
  final int? initialMilli;
  @override
  ConsumerState<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends ConsumerState<_WeightDialog> {
  late final TextEditingController _c;
  bool _big = false;

  bool get _liquid => widget.unit == 'l' || widget.unit == 'ml';
  String get _small => _liquid ? 'ml' : 'g';
  String get _bigName => _liquid ? 'l' : 'kg';

  @override
  void initState() {
    super.initState();
    final productBig = widget.unit == 'kg' || widget.unit == 'l';
    final start = widget.initialMilli;
    // show an existing quantity in the unit that reads best
    final smallAmount = start == null ? null : (productBig ? start.toDouble() : start / 1000);
    if (smallAmount != null && smallAmount >= 1000) {
      _big = true;
      _c = TextEditingController(text: _trim(smallAmount / 1000));
    } else {
      _c = TextEditingController(text: smallAmount == null ? '' : _trim(smallAmount));
    }
  }

  int? get _milli {
    final v = double.tryParse(_c.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return weightToMilli(widget.unit, v, big: _big);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final milli = _milli;
    final price = milli == null ? 0 : widget.unitPriceMinor * milli ~/ 1000;
    return AlertDialog(
      title: Text(widget.name),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${ref.money(widget.unitPriceMinor)} / ${widget.unit}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('weight-input'),
                controller: _c,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _big ? _bigName : _small, hintText: _big ? '1.5' : '750'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<bool>(
              key: const ValueKey('weight-unit'),
              showSelectedIcon: false,
              segments: [ButtonSegment(value: false, label: Text(_small)), ButtonSegment(value: true, label: Text(_bigName))],
              selected: {_big},
              onSelectionChanged: (s) => setState(() => _big = s.first),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final p in const [(250.0, false), (500.0, false), (750.0, false), (1.0, true), (2.0, true)])
              ActionChip(
                key: ValueKey('weight-preset-${p.$1.round()}${p.$2 ? 'big' : 'small'}'),
                label: Text('${_trim(p.$1)} ${p.$2 ? _bigName : _small}'),
                onPressed: () => setState(() {
                  _big = p.$2;
                  _c.text = _trim(p.$1);
                }),
              ),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text(t['total']),
              const Spacer(),
              Text(ref.money(price), key: const ValueKey('weight-price'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel'])),
        FilledButton(key: const ValueKey('weight-ok'), onPressed: milli == null ? null : () => Navigator.pop(context, milli), child: Text(t['add'])),
      ],
    );
  }
}
