import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/kitchen_service.dart';
import '../../data/receipt_loader.dart' show orderTypeLabels, two;

final _ticketsProvider = FutureProvider.autoDispose<List<KitchenTicket>>((ref) => ref.watch(kitchenServiceProvider).tickets());

/// On-screen kitchen board: New -> Preparing -> Ready. One tap moves a ticket on; "Served" takes it off the board.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});
  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  String _tab = 'new';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // other phones (waiters) send orders too: refresh quietly
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => ref.invalidate(_ticketsProvider));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _advance(String id) async {
    await ref.read(kitchenServiceProvider).advance(id);
    ref.invalidate(_ticketsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_ticketsProvider);
    final all = data.value ?? const <KitchenTicket>[];
    int count(String s) => all.where((k) => k.status == s).length;
    final shown = all.where((k) => k.status == _tab).toList();
    final labels = {'new': t['k_new'], 'preparing': t['k_preparing'], 'ready': t['k_ready']};
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          for (final s in KitchenService.flow)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  key: ValueKey('ktab-$s'),
                  showCheckmark: false,
                  selected: _tab == s,
                  selectedColor: context.accent,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _tab == s ? Colors.white : cs.onSurface),
                  label: SizedBox(width: double.infinity, child: Text('${labels[s]} (${count(s)})', textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                  onSelected: (_) => setState(() => _tab = s),
                ),
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
                  itemBuilder: (_, i) => _TicketCard(ticket: shown[i], onAdvance: () => _advance(shown[i].orderId)),
                ),
        ),
      ),
    ]);
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onAdvance});
  final KitchenTicket ticket;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final k = ticket;
    final where = k.tableLabel ?? (orderTypeLabels[k.orderType] ?? k.orderType);
    final action = switch (k.status) { 'new' => t['k_start'], 'preparing' => t['k_mark_ready'], _ => t['k_serve'] };
    return Card(
      key: ValueKey('kticket-${k.orderId}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${k.label} · $where', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Text((){ final d = DateTime.fromMillisecondsSinceEpoch(k.sentAt); return '${two(d.hour)}:${two(d.minute)}'; }(), style: TextStyle(color: cs.onSurfaceVariant)),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(key: ValueKey('kadvance-${k.orderId}'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)), onPressed: onAdvance, child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700))),
          ),
        ]),
      ),
    );
  }
}
