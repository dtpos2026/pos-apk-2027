import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../data/receipt_loader.dart';
import '../../domain/money.dart';
import '../../domain/payments.dart';
import '../../domain/receipt.dart';
import 'cart.dart';

/// [closeParent]: when the cart is shown in a bottom sheet (phones), close it once the sale is done so the
/// receipt appears over the menu and the next customer can be served straight away.
Future<void> showCheckout(BuildContext context, WidgetRef ref, {bool closeParent = false}) async {
  final methods = await ref.read(paymentMethodsProvider.future);
  if (!context.mounted) return;
  final done = await showModalBottomSheet<SettledOrder>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CheckoutSheet(totalMinor: ref.read(cartProvider).bill.totalMinor, methods: methods),
  );
  if (done != null && context.mounted) {
    final root = Navigator.of(context, rootNavigator: true).context;
    if (closeParent) Navigator.pop(context);
    if (root.mounted) await showReceipt(root, ref, done);
  }
}

class _Line {
  _Line(this.method, this.controller);
  final PaymentMethodInfo method;
  final TextEditingController controller;
}

class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key, required this.totalMinor, required this.methods});
  final int totalMinor;
  final List<PaymentMethodInfo> methods;
  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  final _lines = <_Line>[];
  String? _error;
  bool _busy = false;

  Currency get _cur => ref.currency;

  List<PaymentInput>? get _inputs {
    final out = <PaymentInput>[];
    for (final l in _lines) {
      final v = parseMinor(l.controller.text.isEmpty ? '0' : l.controller.text, currency: _cur);
      if (v == null || v <= 0) return null;
      out.add(PaymentInput(PaymentKind.values.firstWhere((k) => k.name == l.method.kind, orElse: () => PaymentKind.other), v));
    }
    return out;
  }

  SettlementResult? get _result {
    final inputs = _inputs;
    if (inputs == null) return null;
    try {
      return settle(widget.totalMinor, inputs);
    } on ArgumentError {
      return null;
    }
  }

  int get _enteredTotal => _inputs?.fold<int>(0, (s, p) => s + p.amountMinor) ?? 0;

  void _add(PaymentMethodInfo m) {
    final alreadyPaid = _lines.fold<int>(0, (s, l) => s + (parseMinor(l.controller.text, currency: _cur) ?? 0));
    final remaining = (widget.totalMinor - alreadyPaid).clamp(0, widget.totalMinor);
    setState(() => _lines.add(_Line(m, TextEditingController(text: remaining == 0 ? '' : formatMinor(remaining, currency: _cur, symbol: false).replaceAll(',', '')))));
  }

  Future<void> _confirm() async {
    final t = Strings.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payments = [
        for (final l in _lines) SettlePayment(methodId: l.method.id, amountMinor: parseMinor(l.controller.text, currency: _cur)!),
      ];
      final settled = await ref.read(cartProvider.notifier).checkout(payments);
      if (mounted) Navigator.pop(context, settled);
    } on PosException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '${t['payment']}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<int> _quickAmounts(int remaining) {
    final f = _cur.factor;
    final out = <int>{remaining};
    for (final step in [500, 1000, 5000]) {
      final s = step * f;
      final up = ((remaining + s - 1) ~/ s) * s;
      if (up > 0) out.add(up);
    }
    return out.toList()..sort();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final cartHasCustomer = ref.watch(cartProvider).customerId != null;
    final methods = widget.methods.where((m) => m.kind != 'credit' || cartHasCustomer).toList();
    final remainingForQuick = (widget.totalMinor - _lines.where((l) => l.method.kind != 'cash').fold<int>(0, (s, l) => s + (parseMinor(l.controller.text, currency: _cur) ?? 0))).clamp(0, widget.totalMinor);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(t['payment'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: FittedBox(fit: BoxFit.scaleDown, child: Text(ref.money(widget.totalMinor), key: const ValueKey('checkout-total'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary))))),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final m in methods) ActionChip(key: ValueKey('method-${m.name}'), avatar: Icon(_iconFor(m.kind), size: 18), label: Text(m.kind == 'cash' ? t['cash'] : (m.kind == 'card' ? t['card'] : m.name)), onPressed: () => _add(m))]),
          const SizedBox(height: 10),
          for (var i = 0; i < _lines.length; i++) ...[
            Row(children: [
              SizedBox(width: 92, child: Text(_lines[i].method.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: TextField(key: ValueKey('pay-$i'), controller: _lines[i].controller, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(isDense: true))),
              IconButton(onPressed: () => setState(() => _lines.removeAt(i).controller.dispose()), icon: const Icon(Icons.close)),
            ]),
            if (_lines[i].method.kind == 'cash')
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(spacing: 6, children: [
                  for (final a in _quickAmounts(remainingForQuick))
                    ActionChip(key: ValueKey('quick-$a'), label: Text(a == remainingForQuick ? t['exact'] : formatMinor(a, currency: _cur, symbol: false)), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _lines[i].controller.text = formatMinor(a, currency: _cur, symbol: false).replaceAll(',', ''))),
                ]),
              ),
          ],
          const Divider(height: 24),
          _row(t['paid'], ref.money(result?.paidMinor ?? 0)),
          _row(t['remaining'], ref.money(result?.dueMinor ?? (widget.totalMinor - _enteredTotal).clamp(0, widget.totalMinor)), key: const ValueKey('remaining')),
          _row(t['change'], ref.money(result?.changeMinor ?? 0), key: const ValueKey('change'), strong: (result?.changeMinor ?? 0) > 0),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const ValueKey('checkout-error'), style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600))),
          const SizedBox(height: 14),
          FilledButton(key: const ValueKey('confirm-payment'), onPressed: (result != null && result.isSettled && !_busy) ? _confirm : null, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t['confirm_payment'])),
        ]),
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) { 'cash' => Icons.payments_outlined, 'card' => Icons.credit_card, 'wallet' => Icons.account_balance_wallet_outlined, 'bank' => Icons.account_balance_outlined, 'credit' => Icons.menu_book_outlined, _ => Icons.payment };

  Widget _row(String label, String value, {Key? key, bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Text(label), const Spacer(), Text(value, key: key, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: strong ? 20 : 15))]),
      );
}

/// Receipt preview (exactly the text the printer gets) with print status. Queues the bill for every bill printer.
Future<void> showReceipt(BuildContext context, WidgetRef ref, SettledOrder order) async {
  final db = ref.read(databaseProvider);
  final data = await loadReceipt(db, order.orderId);
  final printSvc = ref.read(printServiceProvider);
  final jobs = await printSvc.queueBill(order.orderId);
  if (jobs.isNotEmpty) {
    printSvc.processQueue(); // fire and forget: a missing/offline printer never blocks the sale
    printSvc.queueKot(order.orderId).then((_) => printSvc.processQueue());
  }
  if (!context.mounted) return;
  final t = Strings.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [const Icon(Icons.check_circle, color: Colors.green), const SizedBox(width: 8), Text(order.invoiceNo, key: const ValueKey('invoice-no'), style: const TextStyle(fontSize: 18))]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
            child: Text(previewBill(data), key: const ValueKey('receipt-text'), style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5, height: 1.25, color: Colors.black87)),
          ),
          const SizedBox(height: 10),
          Text(jobs.isEmpty ? t['no_printer'] : t['print_queued'], style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12.5)),
        ]),
      ),
      actions: [FilledButton(key: const ValueKey('new-sale'), onPressed: () => Navigator.pop(ctx), child: Text(t['new_sale']))],
    ),
  );
}
