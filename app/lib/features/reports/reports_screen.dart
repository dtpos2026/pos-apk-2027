import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/receipt_loader.dart';

String _dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

final reportProvider = FutureProvider.family<SalesReport, String>((ref, date) => ref.watch(posServiceProvider).salesReport(date));

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _day = ref.read(clockProvider)();

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final key = _dateKey(_day);
    final report = ref.watch(reportProvider(key));
    final scheme = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(key, key: const ValueKey('report-date'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 8),
      report.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
        error: (e, _) => Text('$e'),
        data: (r) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Stat(t['bills'], '${r.bills}', scheme.secondary, id: 'stat-bills'),
            _Stat(t['gross_sales'], ref.money(r.grossMinor), scheme.primary, id: 'stat-gross'),
            _Stat(t['refunds'], ref.money(r.refundsMinor), scheme.error, id: 'stat-refunds'),
            _Stat(t['net_sales'], ref.money(r.netMinor), Colors.green.shade700, id: 'stat-net'),
            _Stat(t['tax'], ref.money(r.taxMinor), scheme.tertiary, id: 'stat-tax'),
          ]),
          const SizedBox(height: 20),
          Text(t['by_method'], style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Card(
            child: Column(children: [
              if (r.byMethod.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('—')),
              for (final e in r.byMethod.entries) ListTile(dense: true, title: Text(e.key), trailing: Text(ref.money(e.value), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, {required this.id});
  final String id;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(value, key: ValueKey(id), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color))),
            ]),
          ),
        ),
      );
}
