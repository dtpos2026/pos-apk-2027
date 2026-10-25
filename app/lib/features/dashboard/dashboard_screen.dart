import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../cloud/access_controller.dart';
import '../../data/dashboard_service.dart';
import '../../data/receipt_loader.dart' show two;
import '../reports/day_close_screen.dart';

final dashboardServiceProvider = Provider<DashboardService>((ref) => DashboardService(ref.watch(dbHelperProvider)));

/// Refreshes after every sale/refund because the shell rebuilds it with a new key when the tab is opened.
final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) => ref.watch(dashboardServiceProvider).load());

/// The business at a glance: today's sales, cash, udhaar, tables, the last 7 days and the best sellers. All numbers come from the
/// phone's own records.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onGo});

  /// Opens another main screen ('pos', 'tables', 'bills', 'customers', 'expenses'...).
  final void Function(String key) onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final session = ref.watch(sessionProvider)!;
    final biz = ref.watch(businessProvider).value;
    final data = ref.watch(dashboardProvider);
    final modules = ref.watch(activeModulesProvider);
    final now = ref.watch(clockProvider)();
    final hour = now.hour;
    final greeting = hour < 12 ? t['good_morning'] : (hour < 17 ? t['good_afternoon'] : t['good_evening']);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: BrandBanner(cs.primary).gradient,
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$greeting, ${session.name}', key: const ValueKey('dash-greeting'), style: TextStyle(color: BrandBanner(cs.primary).on, fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${biz?.name ?? ''}  ·  ${now.year}-${two(now.month)}-${two(now.day)}', style: TextStyle(color: BrandBanner(cs.primary).soft)),
              ]),
            ),
            FilledButton.icon(
              key: const ValueKey('dash-new-sale'),
              style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent),
              onPressed: () => onGo('pos'),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text(t['new_sale']),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        data.when(
          loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: Text('$e')),
          data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Kpis(items: [
              _Kpi('dash-sales', Icons.payments_outlined, t['todays_sales'], ref.money(d.netMinor), '${d.bills} ${t['orders_word']} · ${t['avg']} ${ref.money(d.avgBillMinor)}', primary: true, deltaPct: d.vsYesterdayPct, onTap: () => onGo('bills')),
              _Kpi('dash-cash', Icons.account_balance_wallet_outlined, t['cash'], ref.money(d.cashMinor), null),
              _Kpi('dash-other', Icons.credit_card, t['card_other'], ref.money(d.otherMinor), null),
              _Kpi('dash-udhaar', Icons.menu_book_outlined, t['udhaar_due'], ref.money(d.udhaarDueMinor), '${d.udhaarCustomers} ${t['customers']}', warn: d.udhaarDueMinor > 0, onTap: modules.contains('customers') ? () => onGo('customers') : null),
              _Kpi('dash-expenses', Icons.receipt_long_outlined, t['expenses'], ref.money(d.expensesMinor), null, onTap: modules.contains('expenses') ? () => onGo('expenses') : null),
              _Kpi('dash-discounts', Icons.percent, t['discounts_given'], ref.money(d.discountMinor), null),
              if (modules.contains('tables')) _Kpi('dash-tables', Icons.table_restaurant_outlined, t['tables_occupied'], '${d.tablesOccupied} / ${d.tablesTotal}', null, onTap: () => onGo('tables')),
              _Kpi('dash-open', Icons.pending_actions_outlined, t['running_orders'], '${d.openOrders}', null),
              if (modules.contains('inventory') && d.lowStock > 0) _Kpi('dash-low', Icons.warning_amber_outlined, t['low_stock'], '${d.lowStock}', null, warn: true, onTap: () => onGo('inventory')),
            ]),
            const SizedBox(height: 12),
            _Card(title: t['last_7_days'], child: _Bars(points: d.last7, money: ref.money)),
            const SizedBox(height: 12),
            if (d.byType.isNotEmpty) ...[_Card(title: t['sales_by_type'], child: _TypeBars(byType: d.byType, total: d.byType.values.fold(0, (a, b) => a + b), t: t, money: ref.money)), const SizedBox(height: 12)],
            _Card(
              title: t['top_items_today'],
              child: d.top.isEmpty
                  ? Padding(padding: const EdgeInsets.all(8), child: Text(t['no_sales_yet']))
                  : Column(children: [
                      for (final i in d.top)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Expanded(child: Text(i.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text('× ${i.qtyMilli % 1000 == 0 ? i.qtyMilli ~/ 1000 : (i.qtyMilli / 1000).toStringAsFixed(2)}', style: TextStyle(color: cs.onSurfaceVariant)),
                            const SizedBox(width: 12),
                            Text(ref.money(i.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ]),
                        ),
                    ]),
            ),
            const SizedBox(height: 12),
            _Card(title: t['quick_actions'], child: Wrap(spacing: 8, runSpacing: 8, children: [
              _Action('qa-pos', Icons.point_of_sale, t['pos'], () => onGo('pos')),
              if (modules.contains('tables')) _Action('qa-tables', Icons.table_restaurant_outlined, t['tables'], () => onGo('tables')),
              _Action('qa-bills', Icons.receipt_long_outlined, t['bills_title'], () => onGo('bills')),
              if (modules.contains('customers')) _Action('qa-customers', Icons.people_alt_outlined, t['customers'], () => onGo('customers')),
              if (modules.contains('expenses')) _Action('qa-expenses', Icons.payments_outlined, t['expenses'], () => onGo('expenses')),
              if (session.can('reports.view')) _Action('qa-reports', Icons.bar_chart_rounded, t['reports'], () => onGo('reports')),
              if (session.can('day.close')) _Action('qa-dayclose', Icons.lock_clock_outlined, t['close_day_btn'], () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DayCloseScreen(date: d.date)))),
            ])),
          ]),
        ),
      ]),
    );
  }
}

class _Kpi {
  const _Kpi(this.key, this.icon, this.label, this.value, this.sub, {this.primary = false, this.warn = false, this.onTap, this.deltaPct});
  final String key;
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final bool primary;
  final bool warn;
  final VoidCallback? onTap;

  /// Change against yesterday in percent (null = nothing to compare).
  final int? deltaPct;
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.items});
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final k in items)
          SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              color: k.primary ? cs.primary : cs.surface,
              child: InkWell(
                key: ValueKey(k.key),
                borderRadius: BorderRadius.circular(14),
                onTap: k.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: (k.primary ? readableOn(cs.primary) : (k.warn ? Colors.orange : cs.primary)).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: Icon(k.icon, size: 18, color: k.primary ? readableOn(cs.primary) : (k.warn ? Colors.orange.shade800 : cs.primary)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(k.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: k.primary ? readableOn(cs.primary).withValues(alpha: 0.72) : cs.onSurfaceVariant))),
                    ]),
                    const SizedBox(height: 8),
                    FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(k.value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: k.primary ? readableOn(cs.primary) : cs.onSurface))),
                    if (k.deltaPct != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${k.deltaPct! >= 0 ? '▲' : '▼'} ${k.deltaPct!.abs()}% ${Strings.of(context)['vs_yesterday']}',
                          key: ValueKey('${k.key}-delta'),
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: k.primary ? readableOn(cs.primary) : (k.deltaPct! >= 0 ? const Color(0xFF2E9E5B) : const Color(0xFFD93B3B))),
                        ),
                      ),
                    if (k.sub != null) Text(k.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: k.primary ? readableOn(cs.primary).withValues(alpha: 0.72) : cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 10), child])),
      );
}

class _Action extends StatelessWidget {
  const _Action(this.k, this.icon, this.label, this.onTap);
  final String k;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(key: ValueKey(k), avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);
}

/// Seven bars, one per day, newest on the right; the tallest is the best day.
class _Bars extends StatelessWidget {
  const _Bars({required this.points, required this.money});
  final List<DayPoint> points;
  final String Function(int, {bool symbol}) money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final max = points.fold<int>(0, (m, p) => p.netMinor > m ? p.netMinor : m);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final p in points)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (p.netMinor > 0) FittedBox(fit: BoxFit.scaleDown, child: Text(money(p.netMinor, symbol: false), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))),
                const SizedBox(height: 3),
                Container(
                  key: ValueKey('bar-${p.date}'),
                  height: max == 0 ? 3 : (3 + 95 * p.netMinor / max),
                  decoration: BoxDecoration(color: p.date == points.last.date ? cs.primary : cs.primary.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(5)),
                ),
                const SizedBox(height: 4),
                Text(p.date.substring(8), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _TypeBars extends StatelessWidget {
  const _TypeBars({required this.byType, required this.total, required this.t, required this.money});
  final Map<String, int> byType;
  final int total;
  final Strings t;
  final String Function(int, {bool symbol}) money;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(children: [
            Row(children: [Expanded(child: Text(t[e.key == 'dine_in' ? 'dine_in' : e.key], style: const TextStyle(fontWeight: FontWeight.w600))), Text(money(e.value), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 8), SizedBox(width: 38, child: Text('${total == 0 ? 0 : (100 * e.value / total).round()}%', textAlign: TextAlign.end, style: TextStyle(color: cs.onSurfaceVariant)))]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(minHeight: 7, value: total == 0 ? 0 : e.value / total, backgroundColor: cs.primary.withValues(alpha: 0.1))),
          ]),
        ),
    ]);
  }
}
