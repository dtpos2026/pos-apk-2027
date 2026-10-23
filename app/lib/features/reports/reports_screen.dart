import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/receipt_loader.dart';
import '../../data/report_service.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';

String _key(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

final reportProvider = FutureProvider.family<SalesReport, String>((ref, date) => ref.watch(posServiceProvider).salesReport(date));
final _rangeProvider = FutureProvider.autoDispose.family<_RangeData, (String, String)>((ref, r) async {
  final s = ref.watch(reportServiceProvider);
  return _RangeData(await s.itemWise(r.$1, r.$2), await s.categoryWise(r.$1, r.$2), await s.cashierWise(r.$1, r.$2), await s.totals(r.$1, r.$2));
});

class _RangeData {
  const _RangeData(this.items, this.categories, this.cashiers, this.totals);
  final List<ReportLine> items;
  final List<ReportLine> categories;
  final List<ReportLine> cashiers;
  final ({int sales, int refunds, int expenses, int tax}) totals;
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late DateTime _from = ref.read(clockProvider)();
  late DateTime _to = _from;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r == null) return;
    setState(() {
      _from = r.start;
      _to = r.end;
    });
  }

  Future<void> _export(List<ReportLine> lines, String header, String name, {bool withQty = true}) async {
    final csv = reportCsv(lines, labelHeader: header, withQty: withQty);
    final f = File('${ref.read(exportDirProvider).path}/$name-${_key(_from)}_${_key(_to)}.csv')..writeAsStringSync('﻿$csv'); // BOM so Excel reads Urdu names correctly
    await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'text/csv', subject: name);
    if (mounted) showMessage(context, Strings.of(context)['exported']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final range = ref.watch(_rangeProvider((_key(_from), _key(_to))));
    final single = _key(_from) == _key(_to);
    return Column(children: [
      ListTile(
        dense: true,
        leading: IconButton(onPressed: single ? () => setState(() {
          _from = _from.subtract(const Duration(days: 1));
          _to = _from;
        }) : null, icon: const Icon(Icons.chevron_left)),
        title: InkWell(key: const ValueKey('range-pick'), onTap: _pickRange, child: Text(single ? _key(_from) : '${_key(_from)}  →  ${_key(_to)}', key: const ValueKey('report-date'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        trailing: IconButton(onPressed: single ? () => setState(() {
          _from = _from.add(const Duration(days: 1));
          _to = _from;
        }) : null, icon: const Icon(Icons.chevron_right)),
      ),
      TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: t['summary']), Tab(text: t['items_report']), Tab(text: t['categories_report']), Tab(text: t['cashiers_report'])]),
      Expanded(
        child: range.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (d) => TabBarView(controller: _tabs, children: [
            _Summary(from: _key(_from), to: _key(_to), totals: d.totals),
            _Breakdown(lines: d.items, header: t['items_report'], withQty: true, onExport: () => _export(d.items, 'Item', 'items')),
            _Breakdown(lines: d.categories, header: t['categories_report'], withQty: true, onExport: () => _export(d.categories, 'Category', 'categories')),
            _Breakdown(lines: d.cashiers, header: t['cashiers_report'], withQty: false, onExport: () => _export(d.cashiers, 'Cashier', 'cashiers', withQty: false)),
          ]),
        ),
      ),
    ]);
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.from, required this.to, required this.totals});
  final String from;
  final String to;
  final ({int sales, int refunds, int expenses, int tax}) totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final single = from == to;
    final report = single ? ref.watch(reportProvider(from)) : null;
    final net = totals.sales - totals.refunds;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        if (report?.value != null) _Stat(t['bills'], '${report!.value!.bills}', scheme.secondary, id: 'stat-bills'),
        _Stat(t['gross_sales'], ref.money(totals.sales), scheme.primary, id: 'stat-gross'),
        _Stat(t['refunds'], ref.money(totals.refunds), scheme.error, id: 'stat-refunds'),
        _Stat(t['net_sales'], ref.money(net), Colors.green.shade700, id: 'stat-net'),
        _Stat(t['tax'], ref.money(totals.tax), scheme.tertiary, id: 'stat-tax'),
        _Stat(t['expenses_total'], ref.money(totals.expenses), scheme.error, id: 'stat-expenses'),
        _Stat(t['result'], ref.money(net - totals.expenses), net - totals.expenses >= 0 ? Colors.green.shade700 : scheme.error, id: 'stat-result'),
      ]),
      const SizedBox(height: 6),
      Text(t['profit_note'], style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      if (report?.value != null) ...[
        const SizedBox(height: 20),
        Text(t['by_method'], style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Card(
          child: Column(children: [
            if (report!.value!.byMethod.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('-')),
            for (final e in report.value!.byMethod.entries) ListTile(dense: true, title: Text(e.key), trailing: Text(ref.money(e.value), style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      ],
    ]);
  }
}

class _Breakdown extends ConsumerWidget {
  const _Breakdown({required this.lines, required this.header, required this.withQty, required this.onExport});
  final List<ReportLine> lines;
  final String header;
  final bool withQty;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [Expanded(child: Text(header, style: const TextStyle(fontWeight: FontWeight.w700))), OutlinedButton.icon(key: ValueKey('export-$header'), onPressed: lines.isEmpty ? null : onExport, icon: const Icon(Icons.ios_share, size: 18), label: Text(t['export_csv']))]),
      ),
      Expanded(
        child: lines.isEmpty
            ? const Center(child: Text('-'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: lines.length,
                itemBuilder: (_, i) {
                  final l = lines[i];
                  return Card(child: ListTile(dense: true, title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text([if (withQty) '${t['quantity_short']}: ${formatQty(l.qtyMilli)}', '${t['bills']}: ${l.bills}'].join('   ')), trailing: Text(ref.money(l.amountMinor), style: const TextStyle(fontWeight: FontWeight.w800))));
                },
              ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, {required this.id});
  final String label;
  final String value;
  final Color color;
  final String id;
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
