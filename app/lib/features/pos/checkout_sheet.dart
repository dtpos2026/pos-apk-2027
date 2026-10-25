import '../tokens/token_ui.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../common/dialogs.dart';
import '../../app/theme.dart';
import '../../cloud/access_controller.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../data/receipt_loader.dart';
import '../../domain/money.dart';
import '../../domain/payments.dart';
import '../../domain/receipt.dart';
import '../customers/customers_screen.dart' show pickCustomer;
import 'cart.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../../app/whatsapp.dart';
import '../../data/token_service.dart' show IssuedToken;
import '../../domain/receipt_doc.dart';
import '../../domain/receipt_template.dart';
import '../settings/receipt_paper.dart';

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

  /// Credit with no customer: never lost and never silent. Asks for the customer, or the fixed "Walk-in credit" account.
  /// Returns false when the cashier backed out.
  Future<bool> _askCreditCustomer() async {
    final t = Strings.of(context);
    final hasCredit = _lines.any((l) => l.method.kind == 'credit' && (parseMinor(l.controller.text, currency: _cur) ?? 0) > 0);
    if (!hasCredit || ref.read(cartProvider).customerId != null) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['walkin_credit_title']),
        content: Text(t['walkin_credit_body']),
        actions: [DialogActions([
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
          OutlinedButton(key: const ValueKey('credit-choose'), onPressed: () => Navigator.pop(ctx, 'choose'), child: Text(t['walkin_credit_choose'])),
          FilledButton(key: const ValueKey('credit-walkin'), onPressed: () => Navigator.pop(ctx, 'walkin'), child: Text(t['walkin_credit_use'])),
        ])],
      ),
    );
    if (choice == null || !mounted) return false;
    String? id;
    if (choice == 'walkin') {
      id = await ref.read(customerServiceProvider).walkInCreditId(staffId: ref.read(sessionProvider)!.staffId);
    } else {
      id = await pickCustomer(context, ref);
      if (id == null || id.isEmpty) return false;
    }
    ref.read(cartProvider.notifier).setCustomer(id);
    await ref.read(cartProvider.notifier).flush();
    return true;
  }

  Future<void> _confirm() async {
    final t = Strings.of(context);
    if (!await _askCreditCustomer()) return;
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
    final methods = widget.methods;
    final remainingForQuick = (widget.totalMinor - _lines.where((l) => l.method.kind != 'cash').fold<int>(0, (s, l) => s + (parseMinor(l.controller.text, currency: _cur) ?? 0))).clamp(0, widget.totalMinor);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        // keep the last button above the phone's navigation bar (bottom sheets ignore it by themselves)
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewPaddingOf(context).bottom),
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
          FilledButton(key: const ValueKey('confirm-payment'), style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: (result != null && result.isSettled && !_busy) ? _confirm : null, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t['complete_order'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
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
  final tokenCfg = await ref.read(tokenServiceProvider).config();
  final cfg = await printSvc.printSettings();
  final orderType = (await db.customSelect('SELECT order_type FROM "order" WHERE id = ?', variables: [Variable.withString(order.orderId)]).getSingle()).data['order_type'] as String;
  // what prints by itself follows the print settings: bill, token and KOT are separate switches (and per order type)
  final billJobs = tokenCfg.printBill && cfg.autoBillFor(orderType) ? await printSvc.queueBill(order.orderId) : <String>[];
  final tokenJobs = cfg.autoTokenFor(orderType) ? await printSvc.queueTokens(order.orderId, autoOnly: true) : <String>[];
  final jobs = [...billJobs, ...tokenJobs];
  final issued = (await ref.read(tokenServiceProvider).forOrder(order.orderId)).where((x) => x.status != 'void').toList();
  // the kitchen board gets the order when it is paid (if it was not sent before); the ticket prints only when KOT is automatic
  if (ref.read(activeModulesProvider).contains('kitchen') || cfg.autoKotFor(orderType)) {
    printSvc.sendToKitchen(order.orderId, printKot: cfg.autoKotFor(orderType)).then((_) => printSvc.processQueue());
  }
  if (jobs.isNotEmpty) printSvc.processQueue(); // fire and forget: a missing/offline printer never blocks the sale
  if (!context.mounted) return;
  final design = await ref.read(receiptTemplateStoreProvider).load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _ReceiptDialog(order: order, data: data, design: design, issued: issued, printed: billJobs.isNotEmpty, queued: jobs.isNotEmpty),
  );
}

/// After payment: the receipt as it prints (logo, saved design), with Print, Share, picture and WhatsApp.
class _ReceiptDialog extends ConsumerStatefulWidget {
  const _ReceiptDialog({required this.order, required this.data, required this.design, required this.issued, required this.printed, required this.queued});
  final SettledOrder order;
  final ReceiptData data;
  final BillDesign design;
  final List<IssuedToken> issued;

  /// The bill already went to a printer when the sale was saved (a second print is then marked DUPLICATE).
  final bool printed;
  final bool queued;

  @override
  ConsumerState<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<_ReceiptDialog> {
  final _paperKey = GlobalKey();
  late bool _printed = widget.printed;
  String? _note;

  String get _text => docToText(buildBillDoc(widget.data, template: widget.design), 58);

  Future<void> _print() async {
    final t = Strings.of(context);
    final svc = ref.read(printServiceProvider);
    final jobs = await svc.queueBill(widget.order.orderId, duplicate: _printed, staffId: ref.read(sessionProvider)?.staffId);
    if (jobs.isNotEmpty) {
      _printed = true;
      svc.processQueue();
    }
    if (mounted) setState(() => _note = jobs.isEmpty ? t['no_printer'] : t['print_queued']);
  }

  Future<void> _image() async {
    final boundary = _paperKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final dir = ref.read(exportDirProvider)..createSync(recursive: true);
    final f = File('${dir.path}/${widget.order.invoiceNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.png')..writeAsBytesSync(png.buffer.asUint8List());
    await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'image/png', subject: widget.order.invoiceNo);
  }

  Future<void> _whatsApp() async {
    final t = Strings.of(context);
    final phone = await askPhone(context, title: t['send_whatsapp'], label: t['customer_phone'], ok: t['send'], cancel: t['cancel']);
    if (phone == null || !mounted) return;
    await sendViaWhatsApp(ref, phone, _text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final doc = buildBillDoc(widget.data, template: widget.design);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      title: Row(children: [const Icon(Icons.check_circle, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text(widget.order.invoiceNo, key: const ValueKey('invoice-no'), style: const TextStyle(fontSize: 18)))]),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            RepaintBoundary(key: _paperKey, child: ReceiptPaper(doc: doc, paperMm: 58)),
            if (widget.issued.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                key: const ValueKey('receipt-tokens'),
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [for (final x in widget.issued) Chip(avatar: Icon(kindIcon(x.kind), size: 16), label: Text('${x.label}${x.counter.isEmpty ? '' : ' · ${x.counter}'}', style: const TextStyle(fontWeight: FontWeight.w800)))],
              ),
            ],
            const SizedBox(height: 10),
            Text(_note ?? (widget.queued ? t['print_queued'] : t['no_printer']), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
              FilledButton.tonalIcon(key: const ValueKey('receipt-print'), onPressed: _print, icon: const Icon(Icons.print_outlined, size: 18), label: Text(t['print'])),
              OutlinedButton.icon(key: const ValueKey('receipt-share'), onPressed: () => ref.read(shareServiceProvider).shareText(_text, subject: widget.order.invoiceNo), icon: const Icon(Icons.share_outlined, size: 18), label: Text(t['share'])),
              OutlinedButton.icon(key: const ValueKey('receipt-image'), onPressed: _image, icon: const Icon(Icons.image_outlined, size: 18), label: Text(t['share_image'])),
              OutlinedButton.icon(key: const ValueKey('receipt-whatsapp'), onPressed: _whatsApp, icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('WhatsApp')),
            ]),
          ]),
        ),
      ),
      actions: [FilledButton(key: const ValueKey('new-sale'), onPressed: () => Navigator.pop(context), child: Text(t['new_sale']))],
    );
  }
}
