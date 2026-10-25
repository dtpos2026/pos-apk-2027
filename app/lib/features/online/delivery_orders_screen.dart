import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../app/whatsapp.dart';
import '../../data/online_order_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../data/receipt_loader.dart' show formatDateTime, two;
import '../../domain/csv.dart';
import '../../domain/delivery_messages.dart';
import '../common/dialogs.dart';
import '../menu/share/menu_share_screen.dart';
import '../pos/cart.dart';
import 'new_delivery_order_screen.dart';
import 'order_sources_screen.dart';

final _activeProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) => ref.watch(onlineOrderServiceProvider).list(openOnly: true));
final deliveryRidersProvider = FutureProvider.autoDispose((ref) => ref.watch(teamServiceProvider).riders(activeOnly: true));

/// The text the owner wrote for customers about how to pay (below the bank details in WhatsApp messages).
const payInstructionsKey = 'delivery.pay_instructions';
final payInstructionsProvider = FutureProvider.autoDispose<String>((ref) async => await getSetting(ref.watch(databaseProvider), payInstructionsKey) ?? '');

String statusLabel(Strings t, String status) => t['dl_st_$status'];

Color statusColor(BuildContext context, String s) => switch (s) {
      'pending' => const Color(0xFFB7791F),
      'confirmed' => const Color(0xFF2563EB),
      'preparing' => const Color(0xFFD9480F),
      'ready' => const Color(0xFF0C8599),
      'dispatched' => const Color(0xFF1864AB),
      'delivered' => const Color(0xFF2B8A3E),
      _ => Theme.of(context).colorScheme.error,
    };

/// Delivery orders: those typed in from WhatsApp, the phone or a delivery platform, and those taken in the POS as Delivery.
/// Confirm (goes to the kitchen), prepare, ready, dispatch with a rider, deliver, take payment, tell the customer, and a history/report.
class OnlineOrdersScreen extends ConsumerStatefulWidget {
  const OnlineOrdersScreen({super.key});
  @override
  ConsumerState<OnlineOrdersScreen> createState() => _DeliveryState();
}

class _DeliveryState extends ConsumerState<OnlineOrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _staff => ref.read(sessionProvider)!.staffId;
  OnlineOrderService get _svc => ref.read(onlineOrderServiceProvider);

  void _refresh() {
    ref.invalidate(_activeProvider);
    ref.invalidate(_reportProvider);
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } on PosException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    _refresh();
  }

  Future<void> _accept(OnlineOrder o) => _guard(() async {
        final t = Strings.of(context);
        await ref.read(printServiceProvider).queueKot(o.id, onlyNew: true);
        ref.read(printServiceProvider).processQueue();
        await _svc.setStatus(o.id, 'confirmed', staffId: _staff);
        if (mounted) showMessage(context, t['online_accepted']);
      });

  Future<void> _reject(OnlineOrder o) => _guard(() => _svc.reject(o.id, staffId: _staff));

  Future<String?> _pickRider(OnlineOrder o) async {
    final t = Strings.of(context);
    final riders = await ref.read(teamServiceProvider).riders(activeOnly: true);
    if (!mounted) return null;
    if (riders.isEmpty) {
      showMessage(context, t['dl_no_riders']);
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t['dl_pick_rider']),
        children: [for (final r in riders) SimpleDialogOption(key: ValueKey('rider-pick-${r.name}'), onPressed: () => Navigator.pop(ctx, r.id), child: Text('${r.name}${(r.phone ?? '').isEmpty ? '' : '  ·  ${r.phone}'}', style: TextStyle(fontWeight: r.id == o.riderId ? FontWeight.w800 : FontWeight.w500)))],
      ),
    );
  }

  Future<void> _move(OnlineOrder o, String status) => _guard(() async {
        String? rider;
        if (status == 'dispatched') {
          rider = o.riderId ?? await _pickRider(o);
          if (rider == null) return;
        }
        if (status == 'confirmed') return _accept(o);
        await _svc.setStatus(o.id, status, riderId: rider, staffId: _staff);
      });

  Future<void> _pay(OnlineOrder o) async {
    await ref.read(cartProvider.notifier).resume(o.id);
    ref.read(shellTabProvider.notifier).go('pos');
  }

  Future<void> _history(OnlineOrder o) async {
    final t = Strings.of(context);
    final steps = await _svc.history(o.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['dl_history']),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final s in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [Icon(Icons.circle, size: 10, color: statusColor(ctx, s.status)), const SizedBox(width: 10), Expanded(child: Text(statusLabel(t, s.status), style: const TextStyle(fontWeight: FontWeight.w700))), Text('${formatDateTime(DateTime.fromMillisecondsSinceEpoch(s.at))}${s.staff == null ? '' : '  ·  ${s.staff}'}', style: const TextStyle(fontSize: 12))]),
              ),
            if (steps.isEmpty) Text(t['dl_no_history']),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['ok']))],
      ),
    );
  }

  // ---- WhatsApp messages ----

  Future<void> _tell(OnlineOrder o, DeliveryMessageKind kind) async {
    final t = Strings.of(context);
    final biz = ref.read(businessProvider).value;
    final methods = await ref.read(paymentMethodServiceProvider).all();
    final instructions = await ref.read(payInstructionsProvider.future);
    String m(int v) => ref.money(v);
    final accounts = [
      for (final x in methods)
        if (x.enabled && (x.kind == 'bank' || x.kind == 'wallet') && ((x.accountNo ?? '').isNotEmpty || (x.holder ?? '').isNotEmpty)) PayAccount(name: x.name, number: x.accountNo, holder: x.holder, provider: x.provider, qrPath: x.imagePath),
    ];
    final text = buildDeliveryMessage(
      kind,
      business: biz?.name ?? '',
      accounts: accounts,
      instructions: instructions,
      t: (k) => t[k],
      order: MessageOrder(
        customerName: o.customerName,
        items: [for (final s in o.itemsText.split(', ')) if (s.isNotEmpty) s],
        subtotal: m(o.subtotalMinor),
        discount: o.discountMinor > 0 ? m(o.discountMinor) : '',
        delivery: o.deliveryChargeMinor > 0 ? m(o.deliveryChargeMinor) : '',
        total: m(o.totalMinor),
        due: m(o.dueMinor),
        ref: o.invoiceNo ?? o.platformRef,
        address: o.address,
        city: o.city,
        rider: o.riderName,
        riderPhone: o.riderPhone,
        platform: o.platform ? o.sourceName : null,
      ),
    );
    final qrs = [
      if (kind != DeliveryMessageKind.delivered && kind != DeliveryMessageKind.dispatch)
        for (final a in accounts)
          if (a.qrPath != null && File(a.qrPath!).existsSync()) a.qrPath!
    ];
    if (qrs.isNotEmpty) {
      // the payment QR pictures go with the message: the share list is the way to attach pictures (choose WhatsApp there)
      await ref.read(shareServiceProvider).shareFiles(qrs, text: text, mimeType: 'image/jpeg');
    } else {
      await sendViaWhatsApp(ref, o.phone, text);
    }
  }

  Future<void> _kindMenu(OnlineOrder o) async {
    final t = Strings.of(context);
    final kind = await showModalBottomSheet<DeliveryMessageKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final k in DeliveryMessageKind.values) ListTile(key: ValueKey('msg-${k.name}'), leading: Icon(_kindIcon(k)), title: Text(t['dl_msg_${k.name}']), onTap: () => Navigator.pop(ctx, k)),
        ]),
      ),
    );
    if (kind != null) await _tell(o, kind);
  }

  IconData _kindIcon(DeliveryMessageKind k) => switch (k) { DeliveryMessageKind.confirmation => Icons.check_circle_outline, DeliveryMessageKind.bill => Icons.receipt_long_outlined, DeliveryMessageKind.dispatch => Icons.two_wheeler_outlined, DeliveryMessageKind.delivered => Icons.home_outlined, DeliveryMessageKind.paymentReminder => Icons.payments_outlined };

  // ---- the QR / menu ----

  Future<void> _qr() async {
    final t = Strings.of(context);
    final d = await currentMenuDoc(context, ref);
    if (!mounted) return;
    if (d.qrLink == null) {
      showMessage(context, t['qr_need_phone']);
      return;
    }
    if (!mounted) return;
    await showQrCardDialog(context, ref, d, menuLabels(t));
  }

  // ---- cards ----

  Widget _sourceChip(OnlineOrder o) {
    final cs = Theme.of(context).colorScheme;
    final name = o.sourceName.isEmpty ? Strings.of(context)['dl_direct'] : o.sourceName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: o.platform ? context.accent : cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: o.platform ? null : Border.all(color: cs.primary.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(o.platform ? Icons.storefront_outlined : Icons.person_pin_circle_outlined, size: 14, color: o.platform ? context.onAccent : cs.primary), const SizedBox(width: 4), Text(name, key: ValueKey('src-${o.id}'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: o.platform ? context.onAccent : cs.primary))]),
    );
  }

  Widget _pill(String text, Color color, {Key? key}) => Container(key: key, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)), child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)));

  Widget _card(OnlineOrder o, {bool actions = true}) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final steps = OnlineOrderService.nextSteps(o.deliveryStatus, fulfilment: o.fulfilment).where((s) => s != 'cancelled').toList();
    final next = steps.isEmpty ? null : steps.first;
    final payColor = o.paymentStatus == 'paid' ? const Color(0xFF2B8A3E) : (o.paymentStatus == 'partial' ? const Color(0xFFB7791F) : cs.error);
    return Card(
      key: ValueKey('online-${o.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [_sourceChip(o), if (o.fulfilment == 'pickup') _pill(t['dl_pickup'], cs.primary), if ((o.platformRef ?? '').isNotEmpty) _pill('#${o.platformRef}', cs.onSurfaceVariant, key: ValueKey('ref-${o.id}'))])),
            Text(ref.money(o.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Text('${o.customerName}${o.phone == null ? '' : ' · ${o.phone}'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(o.itemsText),
          if ((o.address ?? '').isNotEmpty || (o.city ?? '').isNotEmpty) Text('📍 ${[if ((o.address ?? '').isNotEmpty) o.address!, if ((o.city ?? '').isNotEmpty) o.city!].join(', ')}', style: TextStyle(color: cs.onSurfaceVariant)),
          if (o.note != null) Text('✎ ${o.note}', style: TextStyle(color: context.accent)),
          if (o.deliveryChargeMinor > 0 || o.discountMinor > 0) Text([if (o.deliveryChargeMinor > 0) '${t['delivery_charge']}: ${ref.money(o.deliveryChargeMinor)}', if (o.discountMinor > 0) '${t['discount']}: -${ref.money(o.discountMinor)}'].join('   '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _pill(statusLabel(t, o.deliveryStatus), statusColor(context, o.deliveryStatus), key: ValueKey('online-status-${o.id}')),
            _pill(t['dl_pay_${o.paymentStatus}'], payColor, key: ValueKey('paystate-${o.id}')),
            if ((o.riderName ?? '').isNotEmpty) _pill('🛵 ${o.riderName}', cs.onSurfaceVariant, key: ValueKey('rider-${o.id}')),
          ]),
          if (actions) ...[
            const SizedBox(height: 8),
            if (o.pending)
              Row(children: [
                Expanded(child: OutlinedButton(key: ValueKey('reject-${o.id}'), onPressed: () => _reject(o), child: Text(t['reject']))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: FilledButton(key: ValueKey('accept-${o.id}'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent), onPressed: () => _accept(o), child: Text(t['accept']))),
              ])
            else
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (next != null) FilledButton(key: ValueKey('next-${o.id}'), onPressed: () => _move(o, next), child: Text('${t['dl_mark']} ${statusLabel(t, next)}', textAlign: TextAlign.center)),
                const SizedBox(height: 6),
                Row(children: [
                if (o.paymentStatus != 'paid' && !o.closed) Expanded(child: FilledButton.tonal(key: ValueKey('pay-${o.id}'), onPressed: () => _pay(o), child: Text(t['take_payment']))) else const Spacer(),
                if (o.phone != null) IconButton(key: ValueKey('tell-${o.id}'), tooltip: t['tell_customer'], onPressed: () => _kindMenu(o), icon: const Icon(Icons.chat_outlined)),
                PopupMenuButton<String>(
                  key: ValueKey('more-${o.id}'),
                  onSelected: (v) async {
                    if (v == 'history') return _history(o);
                    if (v == 'rider') {
                      final r = await _pickRider(o);
                      if (r != null) await _guard(() => _svc.assignRider(o.id, r, staffId: _staff));
                      return;
                    }
                    await _move(o, v);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(key: ValueKey('hist-${o.id}'), value: 'history', child: Text(t['dl_history'])),
                    if (o.fulfilment == 'delivery') PopupMenuItem(value: 'rider', child: Text(t['dl_pick_rider'])),
                    for (final s in steps.skip(1)) PopupMenuItem(value: s, child: Text('${t['dl_mark']} ${statusLabel(t, s)}')),
                    if (OnlineOrderService.nextSteps(o.deliveryStatus, fulfilment: o.fulfilment).contains('cancelled')) PopupMenuItem(key: ValueKey('cancel-${o.id}'), value: 'cancelled', child: Text(t['dl_cancel_order'])),
                  ],
                ),
                ]),
              ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final orders = ref.watch(_activeProvider).value ?? const <OnlineOrder>[];
    final pending = orders.where((o) => o.pending).toList();
    final active = orders.where((o) => !o.pending).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              key: const ValueKey('new-online'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewOnlineOrderScreen()));
                _refresh();
              },
              icon: const Icon(Icons.add),
              label: Text(t['new_online']))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(key: const ValueKey('share-menu'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MenuShareScreen())), icon: const Icon(Icons.ios_share, size: 18), label: Text(t['share_menu']))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(key: const ValueKey('wa-qr-btn'), onPressed: _qr, icon: const Icon(Icons.qr_code_2, size: 18), label: Text(t['qr_title']))),
            IconButton(key: const ValueKey('open-sources'), tooltip: t['dl_sources'], onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OrderSourcesScreen())), icon: const Icon(Icons.tune)),
          ]),
        ),
        TabBar(controller: _tabs, onTap: (_) => setState(() {}), tabs: [Tab(key: const ValueKey('tab-active'), text: t['dl_tab_active']), Tab(key: const ValueKey('tab-report'), text: t['dl_tab_report'])]),
        Expanded(
          child: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
            ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), children: [
              if (orders.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(t['online_none']))),
              if (pending.isNotEmpty) ...[Text('${t['waiting']} (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), for (final o in pending) _card(o)],
              if (active.isNotEmpty) ...[Text(t['accepted_orders'], style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), for (final o in active) _card(o)],
            ]),
            _ReportTab(card: _card),
          ]),
        ),
      ]),
    );
  }
}

// ---- history & report ----

class _ReportArgs {
  const _ReportArgs(this.from, this.to);
  final String from;
  final String to;
  @override
  bool operator ==(Object o) => o is _ReportArgs && o.from == from && o.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

final _reportProvider = FutureProvider.autoDispose.family<({List<OnlineOrder> orders, ({List<SourceTotal> bySource, SourceTotal direct, SourceTotal platforms}) totals}), _ReportArgs>((ref, a) async {
  final s = ref.watch(onlineOrderServiceProvider);
  return (orders: await s.list(from: a.from, to: a.to), totals: await s.totals(a.from, a.to));
});

class _ReportTab extends ConsumerStatefulWidget {
  const _ReportTab({required this.card});
  final Widget Function(OnlineOrder, {bool actions}) card;
  @override
  ConsumerState<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends ConsumerState<_ReportTab> {
  late DateTime _from = ref.read(clockProvider)().subtract(const Duration(days: 6));
  late DateTime _to = ref.read(clockProvider)();
  String _group = 'all'; // all | direct | platform | <source id>
  String _payment = 'all';
  String _status = 'all';

  String _key(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  Future<void> _range() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (r != null) {
      setState(() {
        _from = r.start;
        _to = r.end;
      });
    }
  }

  Future<void> _export(List<OnlineOrder> list) async {
    final t = Strings.of(context);
    String n(int v) => (v / 100).toStringAsFixed(2);
    final b = StringBuffer('Date,Invoice,Customer,Phone,City,Source,Type,Reference,Status,Payment,Rider,Subtotal,Discount,Delivery,Total,Paid\n');
    for (final o in list) {
      b.writeln([
        formatDateTime(DateTime.fromMillisecondsSinceEpoch(o.createdAt)), o.invoiceNo ?? '', o.customerName, o.phone ?? '', o.city ?? '', o.sourceName, o.platform ? 'Platform' : 'Direct', o.platformRef ?? '',
        statusLabel(t, o.deliveryStatus), o.paymentStatus, o.riderName ?? '', n(o.subtotalMinor), n(o.discountMinor), n(o.deliveryChargeMinor), n(o.totalMinor), n(o.paidMinor),
      ].map(csvEscape).join(','));
    }
    final f = File('${ref.read(exportDirProvider).path}/delivery-orders-${_key(_from)}_${_key(_to)}.csv')..writeAsStringSync('\u{FEFF}$b');
    await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'text/csv', subject: 'delivery-orders');
    if (mounted) showMessage(context, t['exported']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_reportProvider(_ReportArgs(_key(_from), _key(_to)))).value;
    final sources = ref.watch(_sourcesProvider).value ?? const <OrderSource>[];
    final all = data?.orders ?? const <OnlineOrder>[];
    final list = all.where((o) {
      if (_group == 'direct' && o.platform) return false;
      if (_group == 'platform' && !o.platform) return false;
      if (_group != 'all' && _group != 'direct' && _group != 'platform' && o.sourceId != _group) return false;
      if (_payment != 'all' && o.paymentStatus != _payment) return false;
      if (_status != 'all' && o.deliveryStatus != _status) return false;
      return true;
    }).toList();
    Widget totalCard(String key, String title, SourceTotal x, {bool strong = false}) => Card(
          key: ValueKey(key),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 16 : 14.5))), Text(ref.money(x.salesMinor), key: ValueKey('$key-sales'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 17 : 15, color: cs.primary))]),
              const SizedBox(height: 4),
              Wrap(spacing: 14, children: [
                Text('${t['dl_orders']}: ${x.orders}', style: const TextStyle(fontSize: 12.5)),
                Text('${t['dl_st_delivered']}: ${x.delivered}', style: const TextStyle(fontSize: 12.5)),
                Text('${t['dl_st_cancelled']}: ${x.cancelled}', style: const TextStyle(fontSize: 12.5)),
                Text('${t['dl_pay_paid']}: ${ref.money(x.paidMinor)}', style: const TextStyle(fontSize: 12.5)),
                Text('${t['dl_due']}: ${ref.money(x.dueMinor)}', style: TextStyle(fontSize: 12.5, color: x.dueMinor > 0 ? cs.error : null)),
              ]),
            ]),
          ),
        );
    DropdownButton<String> drop(String key, String value, List<(String, String)> items, void Function(String) on) => DropdownButton<String>(key: ValueKey(key), value: value, isDense: true, underline: const SizedBox.shrink(), items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2))], onChanged: (v) => on(v ?? value));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const ValueKey('report-range'), onPressed: _range, icon: const Icon(Icons.date_range, size: 18), label: Text(_key(_from) == _key(_to) ? _key(_from) : '${_key(_from)}  →  ${_key(_to)}'))),
        IconButton(key: const ValueKey('report-export'), tooltip: t['export_csv'], onPressed: list.isEmpty ? null : () => _export(list), icon: const Icon(Icons.table_view_outlined)),
      ]),
      Wrap(spacing: 14, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
        drop('flt-source', _group, [('all', t['dl_all_sources']), ('direct', t['dl_direct_only']), ('platform', t['dl_platforms_only']), for (final s in sources) (s.id, s.name)], (v) => setState(() => _group = v)),
        drop('flt-payment', _payment, [('all', t['dl_any_payment']), ('paid', t['dl_pay_paid']), ('unpaid', t['dl_pay_unpaid']), ('partial', t['dl_pay_partial'])], (v) => setState(() => _payment = v)),
        drop('flt-status', _status, [('all', t['dl_any_status']), for (final s in [...deliveryStatuses, 'cancelled']) (s, statusLabel(t, s))], (v) => setState(() => _status = v)),
      ]),
      const SizedBox(height: 6),
      if (data != null) ...[
        totalCard('tot-direct', t['dl_direct'], data.totals.direct, strong: true),
        totalCard('tot-platforms', t['dl_platforms'], data.totals.platforms, strong: true),
        if (data.totals.bySource.length > 1 || (data.totals.bySource.length == 1 && data.totals.bySource.first.name != 'POS'))
          for (final s in data.totals.bySource) totalCard('tot-${s.name}', '${s.platform ? '🛵 ' : ''}${s.name}', s),
      ],
      const SizedBox(height: 8),
      Text('${t['dl_orders']}: ${list.length}', key: const ValueKey('report-count'), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      for (final o in list) widget.card(o, actions: false),
      if (list.isEmpty) Padding(padding: const EdgeInsets.all(28), child: Center(child: Text(t['online_none']))),
    ]);
  }
}

final _sourcesProvider = FutureProvider.autoDispose<List<OrderSource>>((ref) => ref.watch(onlineOrderServiceProvider).sources());
