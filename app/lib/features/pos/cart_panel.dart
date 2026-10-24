import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../../data/pos_service.dart';
import '../../domain/bill.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';
import '../customers/customers_screen.dart';
import 'cart.dart';
import 'checkout_sheet.dart';
import 'shift_dialogs.dart';

final heldOrdersProvider = FutureProvider.autoDispose<List<HeldOrder>>((ref) => ref.watch(posServiceProvider).listHeld());
final _customerNameProvider = FutureProvider.autoDispose.family<String?, String?>((ref, id) async {
  if (id == null) return null;
  return (await ref.watch(dbHelperProvider).one('SELECT name FROM customer WHERE id = ?', [id]))?['name'] as String?;
});
final _tableLabelProvider = FutureProvider.autoDispose.family<String?, String?>((ref, id) async {
  if (id == null) return null;
  return (await ref.watch(dbHelperProvider).one('SELECT label FROM dining_table WHERE id = ?', [id]))?['label'] as String?;
});

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, this.inSheet = false});
  final bool inSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final session = ref.watch(sessionProvider)!;
    final bill = cart.bill;
    final scheme = Theme.of(context).colorScheme;

    final totals = <Widget>[
      _TotalRow(t['subtotal'], ref.money(bill.subtotalMinor)),
      if (bill.discountMinor > 0) _TotalRow(t['discount'], '-${ref.money(bill.discountMinor)}', color: Colors.green.shade700),
      if (bill.serviceChargeMinor > 0) _TotalRow(t['service_charge'], ref.money(bill.serviceChargeMinor)),
      if (bill.taxMinor > 0) _TotalRow(t['tax'], ref.money(bill.taxMinor)),
      const Divider(height: 18),
      Row(children: [
        Text(t['total'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: FittedBox(fit: BoxFit.scaleDown, child: Text(ref.money(bill.totalMinor), key: const ValueKey('cart-total'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.primary))))),
      ]),
    ];

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(child: Text(t['current_order'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              OutlinedButton.icon(key: const ValueKey('close-shift'), onPressed: () => closeShiftDialog(context, ref), icon: const Icon(Icons.lock_outline, size: 18), label: Text(t['close_shift'])),
              if (inSheet) IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
              segments: [for (final k in ['dine_in', 'takeaway', 'delivery', 'counter']) ButtonSegment(value: k, label: Text(t[k], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))],
              selected: {cart.orderType},
              onSelectionChanged: (s) => notifier.setOrderType(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(children: [
              Expanded(
                child: ActionChip(
                  key: const ValueKey('pick-customer'),
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(ref.watch(_customerNameProvider(cart.customerId)).value ?? t['walk_in'], overflow: TextOverflow.ellipsis),
                  onPressed: () async {
                    final id = await pickCustomer(context, ref);
                    if (id != null) notifier.setCustomer(id.isEmpty ? null : id);
                  },
                ),
              ),
              if (cart.orderType == 'dine_in') ...[
                const SizedBox(width: 8),
                ActionChip(
                  key: const ValueKey('pick-table'),
                  avatar: const Icon(Icons.table_restaurant_outlined, size: 18),
                  label: Text(ref.watch(_tableLabelProvider(cart.tableId)).value ?? t['table']),
                  onPressed: () async {
                    final free = (await ref.read(tableServiceProvider).tables()).where((x) => x.status == 'free' || x.id == cart.tableId).toList();
                    if (!context.mounted) return;
                    final picked = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(title: Text(t['tables']), children: [for (final x in free) SimpleDialogOption(key: ValueKey('cart-table-${x.label}'), onPressed: () => Navigator.pop(ctx, x.id), child: Text(x.label))]));
                    if (picked != null) notifier.setTable(picked);
                  },
                ),
              ],
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: cart.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t['empty_cart'], textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant))))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = cart.items[i];
                      final line = bill.lines[i];
                      final step = it.qtyMilli % 1000 != 0 ? 500 : 1000;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text([ref.money(it.unitPriceMinor + it.modifiersMinor, symbol: false), if (it.modifiers.isNotEmpty) '+ ${it.modifiers.map((m) => m.name).join(', ')}', if (it.note != null) '* ${it.note}'].join('  '), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ])),
                          IconButton(key: ValueKey('dec-$i'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => notifier.changeQty(i, -step)),
                          SizedBox(width: 34, child: Text(formatQty(it.qtyMilli), key: ValueKey('qty-$i'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                          IconButton(key: ValueKey('inc-$i'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () => notifier.changeQty(i, step)),
                          SizedBox(width: 84, child: Text(ref.money(line.grossMinor - line.discountMinor, symbol: false), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
                        ]),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
            child: Column(children: [
              ...totals,
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                OutlinedButton(key: const ValueKey('clear-cart'), onPressed: cart.isEmpty ? null : notifier.clear, child: Text(t['clear'])),
                if (session.can('discount.apply')) OutlinedButton(key: const ValueKey('discount'), onPressed: cart.isEmpty ? null : () => _discountDialog(context, ref), child: Text(t['discount'])),
                OutlinedButton(
                  key: const ValueKey('hold'),
                  onPressed: cart.isEmpty ? null : () async {
                    await notifier.hold();
                    ref.invalidate(heldOrdersProvider);
                  },
                  child: Text(t['hold']),
                ),
                Badge(
                  isLabelVisible: (ref.watch(heldOrdersProvider).value?.length ?? 0) > 0,
                  label: Text('${ref.watch(heldOrdersProvider).value?.length ?? 0}'),
                  child: OutlinedButton(key: const ValueKey('held'), onPressed: () => _heldSheet(context, ref), child: Text(t['held_orders'])),
                ),
                if (ref.watch(activeModulesProvider).contains('kitchen'))
                  OutlinedButton.icon(
                    key: const ValueKey('send-kitchen'),
                    onPressed: cart.isEmpty ? null : () async {
                      final r = await notifier.sendToKitchen(ref.read(printServiceProvider));
                      ref.invalidate(heldOrdersProvider);
                      if (!context.mounted) return;
                      switch (r) {
                        case KitchenSend.sent:
                          showMessage(context, t['kitchen_sent']);
                          if (inSheet) Navigator.of(context).maybePop();
                        case KitchenSend.nothingNew:
                          showMessage(context, t['kitchen_nothing_new']);
                        case KitchenSend.failed:
                          showMessage(context, t['kitchen_failed']);
                        case KitchenSend.busy:
                          break;
                      }
                    },
                    icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                    label: Text(t['send_kitchen']),
                  ),
              ]),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('charge'), onPressed: cart.isEmpty ? null : () => showCheckout(context, ref, closeParent: inSheet), child: Text('${t['charge']}  ·  ${ref.money(bill.totalMinor)}'))),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _heldSheet(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final held = await ref.read(posServiceProvider).listHeld();
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: held.isEmpty
            ? Padding(padding: const EdgeInsets.all(28), child: Text(t['no_held'], textAlign: TextAlign.center))
            : ListView(shrinkWrap: true, children: [
                ListTile(title: Text(t['held_orders'], style: const TextStyle(fontWeight: FontWeight.w700))),
                for (final h in held)
                  ListTile(key: ValueKey('held-${h.id}'), leading: const Icon(Icons.pause_circle_outline), title: Text(ref.money(h.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${h.itemCount} · ${t[h.orderType]}${h.table != null ? ' ${h.table}' : ''}'), trailing: Text(t['resume']), onTap: () => Navigator.pop(ctx, h.id)),
              ]),
      ),
    );
    if (picked != null) {
      await ref.read(cartProvider.notifier).resume(picked);
      ref.invalidate(heldOrdersProvider);
    }
  }

  Future<void> _discountDialog(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final c = TextEditingController();
    var percent = true;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t['discount']),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(showSelectedIcon: false, segments: [const ButtonSegment(value: true, label: Text('%')), ButtonSegment(value: false, label: Text(ref.currency.code))], selected: {percent}, onSelectionChanged: (s) => setState(() => percent = s.first)),
            const SizedBox(height: 12),
            TextField(key: const ValueKey('discount-field'), controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: InputDecoration(errorText: error)),
          ]),
          actions: [
            TextButton(
                onPressed: () {
                  final n = ref.read(cartProvider.notifier);
                  final cfg = ref.read(cartProvider).config;
                  n.setConfig(BillConfig(serviceChargeBp: cfg.serviceChargeBp, serviceChargeTaxBp: cfg.serviceChargeTaxBp, deliveryChargeMinor: cfg.deliveryChargeMinor, tipMinor: cfg.tipMinor, rounding: cfg.rounding));
                  Navigator.pop(ctx);
                },
                child: Text(t['clear'])),
            FilledButton(
              key: const ValueKey('discount-ok'),
              onPressed: () {
                final v = parseMinor(c.text, currency: ref.currency);
                if (v == null || v <= 0) {
                  setState(() => error = t['required']);
                  return;
                }
                final cfg = ref.read(cartProvider).config;
                final next = BillConfig(billDiscount: percent ? Discount.percent(v) : Discount.fixed(v), serviceChargeBp: cfg.serviceChargeBp, serviceChargeTaxBp: cfg.serviceChargeTaxBp, deliveryChargeMinor: cfg.deliveryChargeMinor, tipMinor: cfg.tipMinor, rounding: cfg.rounding);
                try {
                  calculateBill([for (final i in ref.read(cartProvider).items) BillLineInput(id: i.productId, unitPriceMinor: i.unitPriceMinor, qtyMilli: i.qtyMilli, modifiersMinor: i.modifiersMinor, lineDiscountMinor: i.lineDiscountMinor, taxRateBp: i.taxRateBp, taxInclusive: i.taxInclusive)], next);
                } on ArgumentError catch (e) {
                  setState(() => error = '${e.message}');
                  return;
                }
                ref.read(cartProvider.notifier).setConfig(next);
                Navigator.pop(ctx);
              },
              child: Text(t['save']),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Text(label), const Spacer(), Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color))]),
      );
}
