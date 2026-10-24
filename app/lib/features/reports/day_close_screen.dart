import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../data/receipt_loader.dart';
import '../../data/shift_service.dart';
import '../../domain/day_close_doc.dart';
import '../../domain/money.dart';
import '../../domain/receipt_doc.dart';
import '../common/dialogs.dart';
import '../common/slip_screen.dart';

final zReportProvider = FutureProvider.autoDispose.family<ZReport, String>((ref, date) => ref.watch(shiftServiceProvider).zReport(date));

/// End of day: the Z report for one date, closing the day (once), printing the slip and sharing it.
class DayCloseScreen extends ConsumerWidget {
  const DayCloseScreen({super.key, required this.date});
  final String date;

  Future<ReceiptDoc Function(int)> _doc(WidgetRef ref, ZReport z) async {
    final biz = await loadBusiness(ref.read(databaseProvider));
    final at = formatDateTime(ref.read(clockProvider)());
    return (int _) => buildZReportDoc(z, businessName: biz?.name ?? '', currency: biz?.currency ?? Currency.pkr, printedAt: at);
  }

  Future<void> _close(BuildContext context, WidgetRef ref, ZReport z) async {
    final t = Strings.of(context);
    final openShifts = z.shifts.where((x) => x.closedAt == null).toList();
    final counts = {for (final s in openShifts) s.id: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t['close_day_btn']),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['day_close_confirm'].replaceAll('{d}', date)),
            if (z.openOrders > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text(t['day_open_orders_note'].replaceAll('{n}', '${z.openOrders}'), key: const ValueKey('day-open-orders'), style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))),
            if (openShifts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t['day_close_shifts_note'], key: const ValueKey('day-shifts-note'), style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final s in openShifts)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(key: ValueKey('count-${s.staff}'), controller: counts[s.id], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '${s.staff}: ${t['counted_cash']} (${t['optional']})')),
                ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t['cancel'])),
          FilledButton(key: const ValueKey('day-close-confirm'), onPressed: () => Navigator.pop(c, true), child: Text(t['close_day_btn'])),
        ],
      ),
    );
    final entered = {for (final e in counts.entries) if (e.value.text.trim().isNotEmpty) e.key: parseMinor(e.value.text, currency: ref.currency) ?? -1};
    for (final c in counts.values) {
      c.dispose();
    }
    if (ok != true) return;
    try {
      await ref.read(shiftServiceProvider).closeDay(date, staffId: ref.read(sessionProvider)!.staffId, countedByShift: entered);
      ref.invalidate(zReportProvider(date));
      // the signed-in user's own shift was closed with the day: the next sale asks for a new opening cash
      await ref.read(shiftProvider.notifier).refresh();
      if (context.mounted) showMessage(context, t['day_closed_ok']);
    } on PosException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final z = ref.watch(zReportProvider(date));
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('${t['day_close']} · $date')),
      body: z.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (z) {
          Widget row(String k, int v, {bool strong = false, Color? color}) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(k, style: strong ? const TextStyle(fontWeight: FontWeight.w700) : null)),
                  Text(ref.money(v), style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, color: color)),
                ]),
              );
          Widget card(String title, List<Widget> children) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                    const SizedBox(height: 6),
                    ...children,
                  ]),
                ),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              key: const ValueKey('day-status'),
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: z.closedAt != null ? const Color(0xFFDCF2E2) : const Color(0xFFFDEFD2), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(z.closedAt != null ? Icons.lock_outline : Icons.lock_open_outlined, color: z.closedAt != null ? const Color(0xFF1E7B3A) : const Color(0xFF8A5A00)),
                const SizedBox(width: 10),
                Expanded(child: Text(style: TextStyle(color: z.closedAt != null ? const Color(0xFF1E7B3A) : const Color(0xFF6B4500), fontWeight: FontWeight.w600), z.closedAt != null ? t['day_already_closed'].replaceAll('{t}', formatDateTime(DateTime.fromMillisecondsSinceEpoch(z.closedAt!))) : (z.problems.isNotEmpty ? t['day_problems'] : (z.anyShiftOpen ? t['day_open_shifts_info'] : t['day_open'])))),
              ]),
            ),
            if (z.closedAt == null && z.problems.isNotEmpty)
              Container(
                key: const ValueKey('day-problems'),
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final p in z.problems) Text('• $p', style: TextStyle(color: scheme.onErrorContainer))]),
              ),
            card(t['summary'], [
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(t['bills'])), Text('${z.bills}', style: const TextStyle(fontWeight: FontWeight.w600))])),
              row(t['gross_sales'], z.grossMinor),
              row(t['discounts_given'], z.discountMinor),
              row(t['refunds'], z.refundsMinor, color: scheme.error),
              const Divider(),
              row(t['net_sales'], z.netMinor, strong: true, color: Colors.green.shade700),
              row(t['tax'], z.taxMinor),
            ]),
            card(t['by_method'], [
              if (z.byMethod.isEmpty) const Text('-'),
              for (final e in z.byMethod.entries) row(e.key, e.value),
            ]),
            card(t['udhaar_and_expenses'], [
              row(t['udhaar_given'], z.creditGivenMinor),
              row(t['udhaar_recovered'], z.creditRecoveredMinor),
              row(t['expenses_total'], z.expensesMinor, color: scheme.error),
            ]),
            card(t['cash_drawer'], [
              if (z.shifts.isEmpty) Text(t['no_shift']),
              for (final s in z.shifts) ...[
                Text('${s.staff} · ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(s.openedAt)).substring(11)}–${s.closedAt == null ? t['open_now'] : formatDateTime(DateTime.fromMillisecondsSinceEpoch(s.closedAt!)).substring(11)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                row(t['opening_cash'], s.openingMinor),
                if (s.expectedMinor != null) row(t['expected_cash'], s.expectedMinor!),
                if (s.countedMinor != null) row(t['counted_cash'], s.countedMinor!),
                if (s.closedAt != null && s.countedMinor == null) Text(t['cash_not_counted'], key: ValueKey('not-counted-${s.staff}'), style: TextStyle(color: scheme.onSurfaceVariant)),
                if (s.varianceMinor != null) row(t['short_over'], s.varianceMinor!, strong: true, color: s.varianceMinor! < 0 ? scheme.error : Colors.green.shade700),
                const SizedBox(height: 6),
              ],
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (z.closedAt == null && (session?.can('day.close') ?? false))
                FilledButton.icon(key: const ValueKey('day-close'), onPressed: z.problems.isNotEmpty ? null : () => _close(context, ref, z), icon: const Icon(Icons.lock_outline), label: Text(t['close_day_btn'])),
              OutlinedButton.icon(
                key: const ValueKey('day-preview'),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(t['preview']),
                onPressed: () async {
                  final build = await _doc(ref, z);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SlipScreen(title: '${t['day_close']} $date', fileName: 'day-close-$date', build: build)));
                },
              ),
              OutlinedButton.icon(
                key: const ValueKey('day-print'),
                icon: const Icon(Icons.print_outlined),
                label: Text(t['print_slip']),
                onPressed: () async {
                  final jobs = await ref.read(printServiceProvider).queueDocument('report', await _doc(ref, z));
                  if (!context.mounted) return;
                  if (jobs.isEmpty) {
                    showMessage(context, t['no_printer']);
                  } else {
                    showMessage(context, t['sent_to_printer']);
                    ref.read(printServiceProvider).processQueue();
                  }
                },
              ),
              OutlinedButton.icon(
                key: const ValueKey('day-share'),
                icon: const Icon(Icons.share_outlined),
                label: Text(t['share_report']),
                onPressed: () async {
                  final text = docToText((await _doc(ref, z))(58), 58);
                  await ref.read(shareServiceProvider).shareText(text, subject: '${t['day_close']} $date');
                },
              ),
            ]),
          ]);
        },
      ),
    );
  }
}
