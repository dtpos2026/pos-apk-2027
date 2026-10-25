import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../app/whatsapp.dart';
import '../../data/online_order_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../domain/phone.dart';
import '../common/dialogs.dart';
import '../pos/cart.dart';

final _ordersProvider = FutureProvider.autoDispose<List<OnlineOrder>>((ref) => ref.watch(onlineOrderServiceProvider).orders());

IconData _channelIcon(String c) => switch (c) { 'whatsapp' => Icons.chat_outlined, 'phone' => Icons.call_outlined, 'foodpanda' => Icons.delivery_dining_outlined, _ => Icons.public };

/// WhatsApp / phone / delivery-app orders typed in by staff: accept (goes to the kitchen), reject, then take payment.
class OnlineOrdersScreen extends ConsumerWidget {
  const OnlineOrdersScreen({super.key});

  Future<void> _accept(BuildContext context, WidgetRef ref, OnlineOrder o) async {
    final t = Strings.of(context);
    await ref.read(printServiceProvider).queueKot(o.id, onlyNew: true);
    ref.read(printServiceProvider).processQueue();
    ref.invalidate(_ordersProvider);
    if (!context.mounted) return;
    showMessage(context, t['online_accepted']);
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, OnlineOrder o) async {
    try {
      await ref.read(onlineOrderServiceProvider).reject(o.id);
    } on PosException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
    ref.invalidate(_ordersProvider);
  }

  Future<void> _pay(WidgetRef ref, OnlineOrder o) async {
    await ref.read(cartProvider.notifier).resume(o.id);
    ref.read(shellTabProvider.notifier).go('pos');
  }

  Future<void> _tell(BuildContext context, WidgetRef ref, OnlineOrder o) async {
    final t = Strings.of(context);
    final biz = ref.read(businessProvider).value?.name ?? '';
    await sendViaWhatsApp(ref, o.phone, OnlineOrderService.acceptedText(biz, o, ref.money(o.totalMinor)));
    if (context.mounted) showMessage(context, t['online_accepted']);
  }

  Future<void> _shareMenu(BuildContext context, WidgetRef ref) async {
    final biz = ref.read(businessProvider).value?.name ?? '';
    final cats = await loadCategories(ref.read(databaseProvider));
    final items = await loadProducts(ref.read(databaseProvider), includeUnavailable: false);
    final b = StringBuffer('*$biz*\n');
    for (final c in [...cats, null]) {
      final mine = items.where((p) => p.categoryId == c?.id).toList();
      if (mine.isEmpty) continue;
      if (c != null) b.writeln('\n*${c.name}*');
      for (final p in mine) {
        b.writeln('• ${p.name} — ${ref.money(p.priceMinor)}');
      }
    }
    await ref.read(shareServiceProvider).shareText(b.toString());
  }

  Future<void> _qr(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final biz = ref.read(businessProvider).value;
    final intl = biz?.phone == null ? null : internationalPhone(biz!.phone!, countryCode: callingCodeFor(biz.currency.code));
    if (intl == null) {
      showMessage(context, t['qr_need_phone']);
      return;
    }
    final link = 'https://wa.me/$intl?text=${Uri.encodeComponent('${t['qr_hello']} ${biz!.name}')}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['qr_title']),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 220, height: 220, child: QrImageView(key: const ValueKey('wa-qr'), data: link, backgroundColor: Colors.white)),
          const SizedBox(height: 8),
          Text(t['qr_hint'], textAlign: TextAlign.center),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['ok']))],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final orders = ref.watch(_ordersProvider).value ?? const <OnlineOrder>[];
    final pending = orders.where((o) => o.pending).toList();
    final active = orders.where((o) => !o.pending).toList();
    Widget card(OnlineOrder o) => Card(
          key: ValueKey('online-${o.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_channelIcon(o.channel), size: 20, color: context.accent),
                const SizedBox(width: 8),
                Expanded(child: Text('${o.customerName}${o.phone == null ? '' : ' · ${o.phone}'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Text(ref.money(o.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(o.itemsText),
              if (o.address != null && o.address!.isNotEmpty) Text('📍 ${o.address}', style: TextStyle(color: cs.onSurfaceVariant)),
              if (o.note != null) Text('✎ ${o.note}', style: TextStyle(color: context.accent)),
              const SizedBox(height: 8),
              if (o.pending)
                Row(children: [
                  Expanded(child: OutlinedButton(key: ValueKey('reject-${o.id}'), onPressed: () => _reject(context, ref, o), child: Text(t['reject']))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: FilledButton(key: ValueKey('accept-${o.id}'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent), onPressed: () => _accept(context, ref, o), child: Text(t['accept']))),
                ])
              else
                Row(children: [
                  Text(t['k_${o.status == 'served' ? 'ready' : o.status}'], key: ValueKey('online-status-${o.id}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (o.phone != null) IconButton(key: ValueKey('tell-${o.id}'), tooltip: t['tell_customer'], onPressed: () => _tell(context, ref, o), icon: const Icon(Icons.chat_outlined)),
                  FilledButton.tonal(key: ValueKey('pay-${o.id}'), onPressed: () => _pay(ref, o), child: Text(t['take_payment'])),
                ]),
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('new-online'), onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewOnlineOrderScreen()));
        ref.invalidate(_ordersProvider);
      }, icon: const Icon(Icons.add), label: Text(t['new_online'])),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const ValueKey('share-menu'), onPressed: () => _shareMenu(context, ref), icon: const Icon(Icons.ios_share, size: 18), label: Text(t['share_menu']))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(key: const ValueKey('wa-qr-btn'), onPressed: () => _qr(context, ref), icon: const Icon(Icons.qr_code_2, size: 18), label: Text(t['qr_title']))),
        ]),
        const SizedBox(height: 12),
        if (orders.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(t['online_none']))),
        if (pending.isNotEmpty) ...[Text('${t['waiting']} (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), for (final o in pending) card(o)],
        if (active.isNotEmpty) ...[Text(t['accepted_orders'], style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), for (final o in active) card(o)],
      ]),
    );
  }
}

/// Typing in an order that came by WhatsApp, phone or a delivery app.
class NewOnlineOrderScreen extends ConsumerStatefulWidget {
  const NewOnlineOrderScreen({super.key});
  @override
  ConsumerState<NewOnlineOrderScreen> createState() => _NewOnlineOrderState();
}

class _NewOnlineOrderState extends ConsumerState<NewOnlineOrderScreen> {
  String _channel = 'whatsapp';
  final _name = TextEditingController(), _phone = TextEditingController(), _address = TextEditingController(), _note = TextEditingController(), _search = TextEditingController();
  final _qty = <String, int>{};
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _note, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(List<MenuProduct> products) async {
    final t = Strings.of(context);
    final items = [
      for (final p in products)
        if ((_qty[p.id] ?? 0) > 0) CartItem(productId: p.id, name: p.name, qtyMilli: _qty[p.id]! * 1000, unitPriceMinor: p.priceMinor, taxRateBp: p.taxBp, taxInclusive: p.taxInclusive, station: p.station)
    ];
    try {
      await ref.read(onlineOrderServiceProvider).create(channel: _channel, customerName: _name.text, phone: _phone.text, address: _address.text, items: items, note: _note.text, staffId: ref.read(sessionProvider)!.staffId);
      if (mounted) Navigator.pop(context);
    } on PosException catch (e) {
      setState(() => _error = e.code == 'empty' ? t['add_one_item'] : e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final products = ref.watch(productsProvider(ProductFilter(search: _search.text))).value ?? const <MenuProduct>[];
    final all = ref.watch(productsProvider(const ProductFilter())).value ?? const <MenuProduct>[];
    final count = _qty.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      appBar: DtAppBar(title: Text(t['new_online'])),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Wrap(spacing: 8, children: [
          for (final c in onlineChannels) ChoiceChip(key: ValueKey('ch-$c'), label: Text(t['ch_$c']), avatar: Icon(_channelIcon(c), size: 16), selected: _channel == c, onSelected: (_) => setState(() => _channel = c)),
        ]),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('on-name'), controller: _name, decoration: InputDecoration(labelText: t['name'])),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t['phone'])),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-address'), controller: _address, decoration: InputDecoration(labelText: t['address'])),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-note'), controller: _note, decoration: InputDecoration(labelText: t['note'])),
        const SizedBox(height: 14),
        TextField(key: const ValueKey('on-search'), controller: _search, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search']), onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        for (final p in products)
          ListTile(
            key: ValueKey('on-item-${p.name}'),
            dense: true,
            title: Text(p.name),
            subtitle: Text(ref.money(p.priceMinor)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: ValueKey('on-minus-${p.name}'), onPressed: (_qty[p.id] ?? 0) > 0 ? () => setState(() => _qty[p.id] = _qty[p.id]! - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('${_qty[p.id] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(key: ValueKey('on-plus-${p.name}'), onPressed: () => setState(() => _qty[p.id] = (_qty[p.id] ?? 0) + 1), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
      ]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_error!, key: const ValueKey('on-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton(key: const ValueKey('on-save'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent, minimumSize: const Size.fromHeight(50)), onPressed: () => _save(all), child: Text('${t['save_order']} ($count)')),
        ]),
      ),
    );
  }
}
