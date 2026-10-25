import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/customer_service.dart';
import '../../data/online_order_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../domain/money.dart';
import '../customers/customers_screen.dart' show customersProvider;
import '../../app/format.dart';
import '../../data/menu_service.dart';
import '../pos/options_sheet.dart';
import 'order_sources_screen.dart' show orderSourcesProvider;

/// Typing in an order that came by WhatsApp, the phone, a delivery platform or at the counter: where it came from (optional), who
/// ordered (an existing customer or a new one with address and city), the items (sizes, add-ons and deals as in the POS), a rider,
/// delivery charge and discount. It waits as Pending until it is confirmed.
class NewOnlineOrderScreen extends ConsumerStatefulWidget {
  const NewOnlineOrderScreen({super.key});
  @override
  ConsumerState<NewOnlineOrderScreen> createState() => _NewOnlineOrderState();
}

class _NewOnlineOrderState extends ConsumerState<NewOnlineOrderScreen> {
  String? _sourceId;
  bool _pickup = false;
  CustomerRow? _customer;
  bool _searching = false;
  String? _riderId;
  final _name = TextEditingController(), _phone = TextEditingController(), _address = TextEditingController(), _city = TextEditingController(), _note = TextEditingController(), _search = TextEditingController(), _find = TextEditingController(), _ref = TextEditingController(), _charge = TextEditingController(), _discount = TextEditingController();
  final _lines = <CartItem>[];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _city, _note, _search, _find, _ref, _charge, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  String _key(CartItem i) => '${i.productId}|${i.variantId}|${i.modifiers.map((m) => m.optionId ?? m.name).join(',')}';

  void _addLine(CartItem item) => setState(() {
        final i = _lines.indexWhere((l) => _key(l) == _key(item));
        if (i < 0) {
          _lines.add(item);
        } else {
          final x = _lines[i];
          _lines[i] = CartItem(productId: x.productId, variantId: x.variantId, name: x.name, qtyMilli: x.qtyMilli + item.qtyMilli, unitPriceMinor: x.unitPriceMinor, modifiers: x.modifiers, taxRateBp: x.taxRateBp, taxInclusive: x.taxInclusive, note: x.note, station: x.station);
        }
      });

  void _change(int i, int delta) => setState(() {
        final x = _lines[i];
        final q = x.qtyMilli + delta;
        if (q <= 0) {
          _lines.removeAt(i);
        } else {
          _lines[i] = CartItem(productId: x.productId, variantId: x.variantId, name: x.name, qtyMilli: q, unitPriceMinor: x.unitPriceMinor, modifiers: x.modifiers, taxRateBp: x.taxRateBp, taxInclusive: x.taxInclusive, note: x.note, station: x.station);
        }
      });

  Future<void> _plus(MenuProduct p) async {
    final opts = await ref.read(menuServiceProvider).optionsFor(p.id);
    if (opts.isEmpty) {
      _addLine(CartItem(productId: p.id, name: p.name, qtyMilli: 1000, unitPriceMinor: p.priceMinor, taxRateBp: p.taxBp, taxInclusive: p.taxInclusive, station: p.station));
    } else if (mounted) {
      final item = await showOptionsSheet(context, ref, p, opts);
      if (item != null) _addLine(item);
    }
  }

  void _minus(MenuProduct p) {
    final i = _lines.lastIndexWhere((l) => l.productId == p.id);
    if (i >= 0) _change(i, -1000);
  }

  int get _subtotal => _lines.fold(0, (s, l) => s + (l.unitPriceMinor + l.modifiersMinor) * l.qtyMilli ~/ 1000);
  int _money(TextEditingController c) => parseMinor(c.text.trim().isEmpty ? '0' : c.text.trim(), currency: ref.currency) ?? 0;

  Future<void> _save(List<OrderSource> sources) async {
    final t = Strings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final src = sources.where((s) => s.id == _sourceId).firstOrNull;
      await ref.read(onlineOrderServiceProvider).create(
            sourceId: _sourceId,
            customerId: _customer?.id,
            customerName: _name.text,
            phone: _phone.text,
            address: _address.text,
            city: _city.text,
            items: _lines,
            note: _note.text,
            platformRef: src?.platform == true ? _ref.text : null,
            fulfilment: _pickup ? 'pickup' : 'delivery',
            riderId: _riderId,
            deliveryChargeMinor: _pickup ? 0 : _money(_charge),
            discountMinor: _money(_discount),
            staffId: ref.read(sessionProvider)!.staffId,
          );
      if (mounted) Navigator.pop(context);
    } on PosException catch (e) {
      setState(() => _error = switch (e.code) { 'empty' => t['add_one_item'], 'address_required' => t['dl_need_address'], _ => e.message });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final sources = (ref.watch(orderSourcesProvider).value ?? const <OrderSource>[]).where((s) => s.active).toList();
    _sourceId ??= sources.where((s) => s.name == 'Walk-in / Manual Entry').firstOrNull?.id ?? sources.firstOrNull?.id;
    final source = sources.where((s) => s.id == _sourceId).firstOrNull;
    final products = ref.watch(productsProvider(ProductFilter(search: _search.text))).value ?? const <MenuProduct>[];
    final found = _searching ? (ref.watch(customersProvider(_find.text)).value ?? const <CustomerRow>[]) : const <CustomerRow>[];
    final riders = ref.watch(_ridersProvider).value ?? const [];
    final charge = _pickup ? 0 : _money(_charge), discount = _money(_discount);
    final total = (_subtotal - discount + charge).clamp(0, 1 << 40);
    return Scaffold(
      appBar: DtAppBar(title: Text(t['new_online'])),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('on-source'),
          initialValue: _sourceId,
          isExpanded: true,
          decoration: InputDecoration(labelText: '${t['dl_source']} (${t['optional']})', prefixIcon: Icon(source?.platform == true ? Icons.storefront_outlined : Icons.person_pin_circle_outlined)),
          items: [for (final s in sources) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => setState(() => _sourceId = v),
        ),
        if (source?.platform == true) ...[
          const SizedBox(height: 8),
          TextField(key: const ValueKey('on-ref'), controller: _ref, decoration: InputDecoration(labelText: t['dl_platform_ref'], prefixIcon: const Icon(Icons.tag))),
        ],
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          key: const ValueKey('on-fulfilment'),
          showSelectedIcon: false,
          segments: [ButtonSegment(value: false, label: Text(t['dl_delivery']), icon: const Icon(Icons.two_wheeler_outlined, size: 18)), ButtonSegment(value: true, label: Text(t['dl_pickup']), icon: const Icon(Icons.storefront_outlined, size: 18))],
          selected: {_pickup},
          onSelectionChanged: (s) => setState(() => _pickup = s.first),
        ),
        const SizedBox(height: 12),
        Text(t['customer'], style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (_customer != null)
          Card(
            key: const ValueKey('on-customer'),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([if ((_customer!.phone ?? '').isNotEmpty) _customer!.phone!, if ((_customer!.address ?? '').isNotEmpty) _customer!.address!, if ((_customer!.city ?? '').isNotEmpty) _customer!.city!].join(' · ')),
              trailing: IconButton(key: const ValueKey('on-customer-clear'), icon: const Icon(Icons.close), onPressed: () => setState(() => _customer = null)),
            ),
          )
        else ...[
          TextField(
            key: const ValueKey('on-find'),
            controller: _find,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.person_search_outlined), hintText: t['dl_find_customer'], isDense: true),
            onChanged: (_) => setState(() => _searching = _find.text.trim().isNotEmpty),
          ),
          if (found.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (final c in found.take(5))
                  ListTile(
                    key: ValueKey('on-pick-${c.name}'),
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(c.name),
                    subtitle: Text([if ((c.phone ?? '').isNotEmpty) c.phone!, if ((c.address ?? '').isNotEmpty) c.address!].join(' · ')),
                    onTap: () => setState(() {
                      _customer = c;
                      _find.clear();
                      _searching = false;
                      if ((c.address ?? '').isNotEmpty) _address.text = c.address!;
                      if ((c.city ?? '').isNotEmpty) _city.text = c.city!;
                    }),
                  ),
              ]),
            ),
          const SizedBox(height: 6),
          TextField(key: const ValueKey('on-name'), controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t['name'])),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('on-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t['phone'])),
        ],
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-address'), controller: _address, decoration: InputDecoration(labelText: t['dl_full_address'])),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-city'), controller: _city, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t['city'])),
        const SizedBox(height: 8),
        TextField(key: const ValueKey('on-note'), controller: _note, decoration: InputDecoration(labelText: t['note'])),
        if (!_pickup && riders.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(key: const ValueKey('on-rider'), initialValue: _riderId, isExpanded: true, decoration: InputDecoration(labelText: '${t['rider']} (${t['optional']})', prefixIcon: const Icon(Icons.two_wheeler_outlined)), items: [DropdownMenuItem<String?>(value: null, child: Text(t['dl_no_rider'])), for (final r in riders) DropdownMenuItem<String?>(value: r.id, child: Text(r.name))], onChanged: (v) => setState(() => _riderId = v)),
        ],
        const SizedBox(height: 14),
        Text(t['dl_order_items'], style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        if (_lines.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t['add_one_item'], style: TextStyle(color: cs.onSurfaceVariant))),
        for (var i = 0; i < _lines.length; i++)
          ListTile(
            key: ValueKey('on-line-$i'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_lines[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([ref.money(_lines[i].unitPriceMinor + _lines[i].modifiersMinor), if (_lines[i].modifiers.isNotEmpty) '+ ${_lines[i].modifiers.map((m) => m.name).join(', ')}'].join('  ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: ValueKey('on-line-minus-$i'), visualDensity: VisualDensity.compact, onPressed: () => _change(i, -1000), icon: const Icon(Icons.remove_circle_outline)),
              Text('${_lines[i].qtyMilli ~/ 1000}', key: ValueKey('on-line-qty-$i'), style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(key: ValueKey('on-line-plus-$i'), visualDensity: VisualDensity.compact, onPressed: () => _change(i, 1000), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
        const Divider(),
        TextField(key: const ValueKey('on-search'), controller: _search, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search'], isDense: true), onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        for (final p in products)
          ListTile(
            key: ValueKey('on-item-${p.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(p.name),
            subtitle: Text(ref.money(p.priceMinor)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: ValueKey('on-minus-${p.name}'), onPressed: _lines.any((l) => l.productId == p.id) ? () => _minus(p) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('${_lines.where((l) => l.productId == p.id).fold<int>(0, (s, l) => s + l.qtyMilli) ~/ 1000}', style: const TextStyle(fontWeight: FontWeight.w800)),
              IconButton(key: ValueKey('on-plus-${p.name}'), onPressed: () => _plus(p), icon: const Icon(Icons.add_circle_outline)),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          if (!_pickup) Expanded(child: TextField(key: const ValueKey('on-charge'), controller: _charge, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['delivery_charge']))),
          if (!_pickup) const SizedBox(width: 10),
          Expanded(child: TextField(key: const ValueKey('on-discount'), controller: _discount, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['discount']))),
        ]),
        const SizedBox(height: 90),
      ]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [Text('${t['subtotal']}: ${ref.money(_subtotal)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)), const Spacer(), Text('${t['total']}: ${ref.money(total)}', key: const ValueKey('on-total'), style: const TextStyle(fontWeight: FontWeight.w800))]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(_error!, key: const ValueKey('on-error'), style: TextStyle(color: cs.error))),
          const SizedBox(height: 6),
          FilledButton(key: const ValueKey('on-save'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent, minimumSize: const Size.fromHeight(50)), onPressed: _busy ? null : () => _save(sources), child: Text('${t['save_order']} (${_lines.fold<int>(0, (a, l) => a + l.qtyMilli ~/ 1000)})')),
        ]),
      ),
    );
  }
}

final _ridersProvider = FutureProvider.autoDispose((ref) => ref.watch(teamServiceProvider).riders(activeOnly: true));
