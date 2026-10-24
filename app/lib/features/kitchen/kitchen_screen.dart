import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../cloud/access_controller.dart';
import '../../data/kitchen_service.dart';
import '../../data/receipt_loader.dart' show orderTypeLabels, two;

final kitchenTicketsProvider = FutureProvider.autoDispose.family<List<KitchenTicket>, String>((ref, status) => ref.watch(kitchenServiceProvider).tickets(status: status));
final kitchenCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) => ref.watch(kitchenServiceProvider).counts());

/// The kitchen board: New -> Preparing -> Ready -> Completed. One tap moves a ticket on. Completed orders stay as history
/// (also after the bill is paid). Each ticket shows the order number, type, items, notes and how long it has waited.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});
  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  String _tab = 'new';
  Timer? _poll;

  void _refresh() {
    ref.invalidate(kitchenTicketsProvider);
    ref.invalidate(kitchenCountsProvider);
  }

  @override
  void initState() {
    super.initState();
    // other phones (waiters) send orders too: refresh quietly; also keeps "waiting for N minutes" current
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _advance(String id) async {
    await ref.read(kitchenServiceProvider).advance(id, staffId: ref.read(sessionProvider)?.staffId);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final counts = ref.watch(kitchenCountsProvider).value ?? const <String, int>{};
    final data = ref.watch(kitchenTicketsProvider(_tab));
    final shown = data.value ?? const <KitchenTicket>[];
    const tabs = ['new', 'preparing', 'ready', 'served'];
    final labels = {'new': t['k_new'], 'preparing': t['k_preparing'], 'ready': t['k_ready'], 'served': t['k_completed']};
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(10, 10, 10, 4), children: [
          for (final s in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                key: ValueKey('ktab-$s'),
                showCheckmark: false,
                selected: _tab == s,
                selectedColor: context.accent,
                labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _tab == s ? Colors.white : cs.onSurface),
                label: Text('${labels[s]} (${counts[s] ?? 0})'),
                onSelected: (_) => setState(() => _tab = s),
              ),
            ),
        ]),
      ),
      Expanded(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (_) => shown.isEmpty
              ? Center(child: Text(t['k_empty'], style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _TicketCard(ticket: shown[i], now: ref.watch(clockProvider)(), onAdvance: () => _advance(shown[i].orderId)),
                ),
        ),
      ),
    ]);
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.now, required this.onAdvance});
  final KitchenTicket ticket;
  final DateTime now;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final k = ticket;
    final where = k.tableLabel ?? (orderTypeLabels[k.orderType] ?? k.orderType);
    final action = switch (k.status) { 'new' => t['k_start'], 'preparing' => t['k_mark_ready'], 'ready' => t['k_serve'], _ => '' };
    final waited = now.difference(DateTime.fromMillisecondsSinceEpoch(k.sentAt)).inMinutes.clamp(0, 9999);
    final late = k.status != 'served' && waited >= 15;
    final at = DateTime.fromMillisecondsSinceEpoch(k.sentAt);
    return Card(
      key: ValueKey('kticket-${k.orderId}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${k.label} · $where', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (k.paid) Container(margin: const EdgeInsetsDirectional.only(end: 8), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF2E9E5B).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)), child: Text(t['paid_status'], style: const TextStyle(color: Color(0xFF2E9E5B), fontWeight: FontWeight.w700, fontSize: 12))),
            Text(k.status == 'served' ? '${two(at.hour)}:${two(at.minute)}' : '$waited ${t['min']}', key: ValueKey('kwait-${k.orderId}'), style: TextStyle(fontWeight: FontWeight.w700, color: late ? cs.error : cs.onSurfaceVariant)),
          ]),
          const Divider(height: 18),
          for (final l in k.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(l.qtyMilli / 1000).toStringAsFixed(l.qtyMilli % 1000 == 0 ? 0 : 1)} × ${l.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                for (final m in l.modifiers) Text('  + $m', style: TextStyle(color: cs.onSurfaceVariant)),
                if (l.note != null && l.note!.isNotEmpty) Text('  ✎ ${l.note}', style: TextStyle(color: context.accent)),
              ]),
            ),
          if (action.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(key: ValueKey('kadvance-${k.orderId}'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)), onPressed: onAdvance, child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700))),
            ),
          ],
        ]),
      ),
    );
  }
}


/// How many orders are Ready and waiting to be served (shown as a badge on the Kitchen tab).
class KitchenReadyCount extends Notifier<int> {
  @override
  int build() => 0;
  void set(int n) => state = n;
}

final kitchenReadyCountProvider = NotifierProvider<KitchenReadyCount, int>(KitchenReadyCount.new);

/// Invisible: while the app is open it checks the kitchen every few seconds, keeps the Ready badge up to date and tells the
/// cashier or waiter when a new order becomes Ready. Needs the Kitchen module; costs nothing when it is off.
class KitchenReadyWatcher extends ConsumerStatefulWidget {
  const KitchenReadyWatcher({super.key, this.every = const Duration(seconds: 15)});
  final Duration every;
  @override
  ConsumerState<KitchenReadyWatcher> createState() => _KitchenReadyWatcherState();
}

class _KitchenReadyWatcherState extends ConsumerState<KitchenReadyWatcher> {
  Timer? _timer;
  Set<String>? _seen;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(widget.every, (_) => _check());
  }

  Future<void> _check() async {
    if (!ref.read(activeModulesProvider).contains('kitchen')) return;
    try {
      final ready = await ref.read(kitchenServiceProvider).tickets(status: 'ready');
      if (!mounted) return;
      final ids = {for (final k in ready) k.orderId};
      ref.read(kitchenReadyCountProvider.notifier).set(ids.length);
      final fresh = _seen == null ? const <KitchenTicket>[] : ready.where((k) => !_seen!.contains(k.orderId)).toList();
      _seen = ids;
      if (fresh.isNotEmpty && mounted) {
        final t = Strings.of(context);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(key: const ValueKey('ready-alert'), content: Text(t['kitchen_ready_alert'].replaceAll('{n}', fresh.map((k) => k.label).join(', ')))));
      }
    } catch (_) {
      // a failed check is retried on the next round
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
