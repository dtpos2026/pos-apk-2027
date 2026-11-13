import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/queries.dart';
import '../../domain/happy_hour.dart';
import '../common/dialogs.dart';

/// Settings > Happy hour: a percentage off that a new bill gets by itself on the chosen days and hours.
class HappyHourCard extends ConsumerStatefulWidget {
  const HappyHourCard({super.key});
  @override
  ConsumerState<HappyHourCard> createState() => _HappyHourCardState();
}

class _HappyHourCardState extends ConsumerState<HappyHourCard> {
  HappyHour? _hh;
  final _pct = TextEditingController();

  @override
  void initState() {
    super.initState();
    ref.read(happyHourProvider.future).then((h) {
      if (!mounted) return;
      setState(() {
        _hh = h;
        _pct.text = (h.percentBp / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
      });
    });
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  String _time(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  Future<void> _pick(bool from) async {
    final h = _hh!;
    final m = from ? h.fromMinute : h.toMinute;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null) return;
    setState(() => _hh = from ? h.copyWith(fromMinute: t.hour * 60 + t.minute) : h.copyWith(toMinute: t.hour * 60 + t.minute));
  }

  Future<void> _save() async {
    final t = Strings.of(context);
    final bp = ((double.tryParse(_pct.text.trim().replaceAll(',', '.')) ?? 0) * 100).round().clamp(0, 10000);
    final h = _hh!.copyWith(percentBp: bp);
    if (h.enabled && (bp <= 0 || h.days.isEmpty || h.fromMinute == h.toMinute)) {
      showMessage(context, t['happy_invalid']);
      return;
    }
    await setSetting(ref.read(databaseProvider), happyHourSettingKey, h.encode(), ref.read(clockProvider)().millisecondsSinceEpoch);
    ref.invalidate(happyHourProvider);
    setState(() => _hh = h);
    if (mounted) showMessage(context, t['saved']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final h = _hh;
    if (h == null) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t['happy_hint'], style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      SwitchListTile(key: const ValueKey('happy-on'), contentPadding: EdgeInsets.zero, title: Text(t['happy_on']), value: h.enabled, onChanged: (v) => setState(() => _hh = h.copyWith(enabled: v))),
      if (h.enabled) ...[
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const ValueKey('happy-from'), onPressed: () => _pick(true), icon: const Icon(Icons.schedule, size: 18), label: Text('${t['happy_from']} ${_time(h.fromMinute)}'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(key: const ValueKey('happy-to'), onPressed: () => _pick(false), icon: const Icon(Icons.schedule, size: 18), label: Text('${t['happy_to']} ${_time(h.toMinute)}'))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              key: ValueKey('happy-day-$d'),
              label: Text(names[d - 1]),
              selected: h.days.contains(d),
              onSelected: (on) => setState(() => _hh = h.copyWith(days: on ? {...h.days, d} : ({...h.days}..remove(d)))),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('happy-pct'), controller: _pct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t['happy_pct'], suffixText: '%', isDense: true)),
      ],
      const SizedBox(height: 8),
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.tonal(key: const ValueKey('happy-save'), onPressed: _save, child: Text(t['save']))),
    ]);
  }
}
