import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../customers/customers_screen.dart';
import 'cart.dart';

/// Delivery details inside the cart: phone, name and address. Typing a phone number or name searches the saved customers;
/// tapping one fills everything in. A new customer is saved automatically with the order, so next time it is one search.
final _activeRidersProvider = FutureProvider.autoDispose((ref) => ref.watch(teamServiceProvider).riders(activeOnly: true));

class DeliveryCard extends ConsumerStatefulWidget {
  const DeliveryCard({super.key});
  @override
  ConsumerState<DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<DeliveryCard> {
  final _phone = TextEditingController(), _name = TextEditingController(), _address = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    final c = ref.read(cartProvider);
    _phone.text = c.deliveryPhone ?? '';
    _name.text = c.deliveryName ?? '';
    _address.text = c.deliveryAddress ?? '';
    if (c.customerId != null && (c.deliveryName == null || c.deliveryPhone == null)) _fill(c.customerId!);
  }

  /// A resumed order knows its customer id only: load the name and phone for the fields.
  Future<void> _fill(String id) async {
    final row = await ref.read(dbHelperProvider).one('SELECT name, phone, address FROM customer WHERE id = ?', [id]);
    if (row == null || !mounted) return;
    setState(() {
      _name.text = row['name'] as String? ?? '';
      _phone.text = row['phone'] as String? ?? '';
      if (_address.text.isEmpty) _address.text = row['address'] as String? ?? '';
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _changed() => ref.read(cartProvider.notifier).setDelivery(name: _name.text, phone: _phone.text, address: _address.text);

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cart = ref.watch(cartProvider);
    final saved = cart.customerId != null;
    final matches = (!saved && _q.trim().length >= 2) ? (ref.watch(customersProvider(_q.trim())).value ?? const []).take(4).toList() : const [];
    return Container(
      key: const ValueKey('delivery-card'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.delivery_dining_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(saved ? t['delivery_saved_customer'] : t['delivery_details'], style: const TextStyle(fontWeight: FontWeight.w700))),
          if (saved)
            TextButton(
              key: const ValueKey('dlv-change'),
              onPressed: () {
                ref.read(cartProvider.notifier).setCustomer(null);
                setState(() => _q = '');
              },
              child: Text(t['change_customer']),
            ),
        ]),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('dlv-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.phone_outlined, size: 18), labelText: t['phone'], suffixIcon: const Icon(Icons.search, size: 18)),
          onChanged: (v) {
            setState(() => _q = v);
            _changed();
          },
        ),
        for (final c in matches)
          ListTile(
            key: ValueKey('dlv-pick-${c.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline, size: 18),
            title: Text(c.name),
            subtitle: Text([c.phone ?? '', c.address ?? ''].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              _name.text = c.name;
              _phone.text = c.phone ?? '';
              _address.text = c.address ?? '';
              ref.read(cartProvider.notifier).useCustomer(c.id, name: c.name, phone: c.phone, address: c.address);
              setState(() => _q = '');
            },
          ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('dlv-name'),
          controller: _name,
          decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.person_outline, size: 18), labelText: t['name']),
          onChanged: (v) {
            if (!saved) setState(() => _q = v);
            _changed();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('dlv-address'),
          controller: _address,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.location_on_outlined, size: 18), labelText: t['address']),
          onChanged: (_) => _changed(),
        ),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final riders = ref.watch(_activeRidersProvider).value ?? const [];
          if (riders.isEmpty) return const SizedBox.shrink();
          return DropdownButtonFormField<String?>(
            key: const ValueKey('dlv-rider'),
            initialValue: riders.any((r) => r.id == cart.riderId) ? cart.riderId : null,
            isExpanded: true,
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.two_wheeler_outlined, size: 18), labelText: t['rider']),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(t['rider_none'])),
              for (final r in riders) DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
            ],
            onChanged: (v) => ref.read(cartProvider.notifier).setRider(v),
          );
        }),
      ]),
    );
  }
}
