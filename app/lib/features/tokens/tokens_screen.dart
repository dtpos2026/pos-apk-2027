import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/receipt_loader.dart';
import '../../data/token_service.dart';
import '../common/dialogs.dart';
import 'token_ui.dart';

/// Today's tokens: who is waiting, hand over food (collected), print or reprint a token, redeem a prepaid coupon.
class TokensScreen extends ConsumerStatefulWidget {
  const TokensScreen({super.key});
  @override
  ConsumerState<TokensScreen> createState() => _TokensScreenState();
}

class _TokensScreenState extends ConsumerState<TokensScreen> {
  String _filter = 'issued';
  String _query = '';
  late Future<List<IssuedToken>> _future = _load();

  Future<List<IssuedToken>> _load() {
    final now = ref.read(clockProvider)();
    return ref.read(tokenServiceProvider).forDate('${now.year}-${two(now.month)}-${two(now.day)}', status: _filter == 'all' ? null : _filter);
  }

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _print(IssuedToken tk) async {
    final t = Strings.of(context);
    final cfg = await ref.read(tokenServiceProvider).config();
    final session = ref.read(sessionProvider)!;
    final again = tk.printCount > 0;
    if (again && cfg.managerReprintOnly && !session.can('settings.manage')) {
      if (mounted) showMessage(context, t['reprint_manager_only']);
      return;
    }
    final print = ref.read(printServiceProvider);
    final jobs = await print.queueTokens(tk.orderId, tokenIds: [tk.id], reprint: again, staffId: session.staffId);
    if (jobs.isNotEmpty) print.processQueue();
    if (!mounted) return;
    showMessage(context, jobs.isEmpty ? t['no_printer'] : t['print_queued']);
    _reload();
  }

  Future<void> _redeem() async {
    final t = Strings.of(context);
    final v = await showFormDialog(context, title: t['redeem_coupon'], okLabel: t['redeem'], fields: [FieldSpec('code', t['coupon_code'])]);
    if (v == null || !mounted) return;
    final r = await ref.read(tokenServiceProvider).redeem(v['code']!, staffId: ref.read(sessionProvider)?.staffId);
    if (!mounted) return;
    final when = r.redeemedAt == null ? '' : ' (${formatDateTime(DateTime.fromMillisecondsSinceEpoch(r.redeemedAt!))})';
    final (icon, color, text) = switch (r.status) {
      RedeemStatus.ok => (Icons.check_circle, Colors.green, '${t['coupon_ok']}: ${r.label} · ${ref.money(r.valueMinor ?? 0)}'),
      RedeemStatus.alreadyRedeemed => (Icons.error, Colors.red, '${t['coupon_used']}$when'),
      RedeemStatus.voided => (Icons.block, Colors.orange, t['coupon_void']),
      RedeemStatus.notFound => (Icons.help_outline, Colors.red, t['coupon_unknown']),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: color, size: 40),
        content: Text(text, key: const ValueKey('redeem-result'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t['ok']))],
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<String>(
              key: const ValueKey('token-filter'),
              showSelectedIcon: false,
              segments: [ButtonSegment(value: 'issued', label: Text(t['token_waiting'])), ButtonSegment(value: 'collected', label: Text(t['token_collected'])), ButtonSegment(value: 'all', label: Text(t['all']))],
              selected: {_filter},
              onSelectionChanged: (s) {
                _filter = s.first;
                _reload();
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(key: const ValueKey('redeem-coupon'), onPressed: _redeem, icon: const Icon(Icons.card_giftcard_outlined), label: Text(t['redeem_coupon'])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(key: const ValueKey('token-search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['token_search'], isDense: true), onChanged: (v) => setState(() => _query = v.trim().toLowerCase())),
      ),
      Expanded(
        child: FutureBuilder<List<IssuedToken>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = [for (final x in snap.data!) if (_query.isEmpty || x.label.toLowerCase().contains(_query) || x.orderNo.toLowerCase().contains(_query) || x.counter.toLowerCase().contains(_query)) x];
            if (list.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t['tokens_none_today'], textAlign: TextAlign.center)));
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final tk = list[i];
                final items = tk.items.map((e) => '${formatQtyShort(e.qtyMilli)} ${e.name}').join(', ');
                final color = switch (tk.status) { 'collected' => Colors.green.shade700, 'void' => Colors.red.shade700, _ => cs.primary };
                return Card(
                  child: ListTile(
                    key: ValueKey('token-${tk.label}-${tk.orderNo}'),
                    leading: Container(
                      constraints: const BoxConstraints(minWidth: 62),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color)),
                      child: Text(tk.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
                    ),
                    title: Text('${kindName(t, tk.kind)}${tk.counter.isEmpty ? '' : ' · ${tk.counter}'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${tk.orderNo}  ·  $items${tk.couponCode == null ? '' : '\n${tk.couponCode}'}${tk.printCount > 0 ? '  ·  ${t['printed_times']} ${tk.printCount}' : ''}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    isThreeLine: tk.couponCode != null,
                    trailing: tk.status == 'void'
                        ? Text(t['token_void'], style: TextStyle(color: color, fontWeight: FontWeight.w700))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(key: ValueKey('token-print-${tk.label}'), tooltip: tk.printCount > 0 ? t['reprint'] : t['print'], icon: const Icon(Icons.print_outlined), onPressed: () => _print(tk)),
                            if (tk.isIssued && tk.couponCode == null)
                              IconButton(
                                key: ValueKey('token-collect-${tk.label}'),
                                tooltip: t['mark_collected'],
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () async {
                                  await ref.read(tokenServiceProvider).markCollected(tk.id);
                                  _reload();
                                },
                              )
                            else if (!tk.isIssued)
                              Icon(Icons.check_circle, color: color),
                          ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

String formatQtyShort(int milli) => milli % 1000 == 0 ? '${milli ~/ 1000}x' : '${(milli / 1000).toStringAsFixed(2)}x';
