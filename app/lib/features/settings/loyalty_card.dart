import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/loyalty.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';

/// Settings > Loyalty points: on/off, how many points a bill earns and what a point is worth when spent.
class LoyaltyCard extends ConsumerStatefulWidget {
  const LoyaltyCard({super.key});
  @override
  ConsumerState<LoyaltyCard> createState() => _LoyaltyCardState();
}

class _LoyaltyCardState extends ConsumerState<LoyaltyCard> {
  final _spend = TextEditingController(), _per = TextEditingController(), _value = TextEditingController(), _min = TextEditingController();
  bool _on = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(loyaltyServiceProvider).config().then((c) {
      if (!mounted) return;
      final cur = ref.read(businessProvider).value?.currency ?? Currency.pkr;
      setState(() {
        _on = c.enabled;
        _spend.text = formatMinor(c.spendStepMinor, currency: cur, symbol: false).replaceAll(',', '');
        _per.text = '${c.pointsPerStep}';
        _value.text = formatMinor(c.pointValueMinor, currency: cur, symbol: false).replaceAll(',', '');
        _min.text = '${c.minRedeem}';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_spend, _per, _value, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = Strings.of(context);
    final cur = ref.read(businessProvider).value?.currency ?? Currency.pkr;
    final spend = parseMinor(_spend.text.trim().isEmpty ? '0' : _spend.text.trim(), currency: cur) ?? 0;
    final value = parseMinor(_value.text.trim().isEmpty ? '0' : _value.text.trim(), currency: cur) ?? 0;
    final per = int.tryParse(_per.text.trim()) ?? 0;
    if (_on && (spend <= 0 || per <= 0 || value <= 0)) {
      showMessage(context, t['loyalty_invalid']);
      return;
    }
    await ref.read(loyaltyServiceProvider).save(LoyaltyConfig(enabled: _on, spendStepMinor: spend, pointsPerStep: per, pointValueMinor: value, minRedeem: int.tryParse(_min.text.trim()) ?? 0));
    if (mounted) showMessage(context, t['saved']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    if (!_loaded) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
    InputDecoration dec(String label, {String? suffix}) => InputDecoration(labelText: label, suffixText: suffix, isDense: true);
    const num = TextInputType.numberWithOptions(decimal: true);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t['loyalty_hint'], style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      SwitchListTile(key: const ValueKey('loyalty-on'), contentPadding: EdgeInsets.zero, title: Text(t['loyalty_on']), value: _on, onChanged: (v) => setState(() => _on = v)),
      if (_on) ...[
        Row(children: [
          Expanded(child: TextField(key: const ValueKey('loyalty-spend'), controller: _spend, keyboardType: num, decoration: dec(t['loyalty_spend'], suffix: ref.currency.code))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const ValueKey('loyalty-per'), controller: _per, keyboardType: TextInputType.number, decoration: dec(t['loyalty_points_per']))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(key: const ValueKey('loyalty-value'), controller: _value, keyboardType: num, decoration: dec(t['loyalty_value'], suffix: ref.currency.code))),
          const SizedBox(width: 10),
          Expanded(child: TextField(key: const ValueKey('loyalty-min'), controller: _min, keyboardType: TextInputType.number, decoration: dec(t['loyalty_min']))),
        ]),
      ],
      const SizedBox(height: 8),
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.tonal(key: const ValueKey('loyalty-save'), onPressed: _save, child: Text(t['save']))),
    ]);
  }
}
