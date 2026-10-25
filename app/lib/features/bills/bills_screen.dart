import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/whatsapp.dart';
import '../../app/strings.dart';
import '../../data/bill_history.dart';
import '../../data/pos_service.dart';
import '../../data/receipt_loader.dart';
import '../../domain/money.dart';
import '../../domain/receipt.dart';
import '../common/dialogs.dart';
import '../pos/cart.dart';

final _billsProvider = FutureProvider.autoDispose.family<List<BillRow>, (String, String, String)>((ref, k) => ref.watch(billHistoryProvider).forDate(k.$1, search: k.$2, tab: k.$3));

/// Past bills: look up, reprint (marked DUPLICATE), share, refund or void.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});
  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  late DateTime _day = ref.read(clockProvider)();
  String _search = '';
  String _tab = 'all';

  String get _key => '${_day.year}-${two(_day.month)}-${two(_day.day)}';

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final bills = ref.watch(_billsProvider((_key, _search, _tab)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_key, key: const ValueKey('bills-date'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          IconButton(onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: TextField(key: const ValueKey('bill-search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s['search_bill'], isDense: true), onChanged: (v) => setState(() => _search = v))),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final k in const ['all', 'paid', 'running', 'kitchen', 'cancelled'])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(key: ValueKey('billtab-$k'), label: Text(s['bills_tab_$k']), selected: _tab == k, showCheckmark: false, onSelected: (_) => setState(() => _tab = k)),
            ),
        ]),
      ),
      Expanded(
        child: bills.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) => list.isEmpty
              ? Center(child: Text(s['no_bills']))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final b = list[i];
                    final color = switch (b.status) { 'void' => Colors.red.shade700, 'refunded' => Colors.orange.shade800, 'paid' => Colors.green.shade700, 'cancelled' => Colors.grey.shade700, _ => Colors.blue.shade700 };
                    final time = DateTime.fromMillisecondsSinceEpoch(b.settledAt);
                    return Card(
                      child: ListTile(
                        key: ValueKey('bill-${b.invoiceNo}'),
                        title: Text(b.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${two(time.hour)}:${two(time.minute)}  ·  ${s[_typeKey(b.orderType)]}${b.table != null ? ' ${b.table}' : ''}${b.customer != null ? '  ·  ${b.customer}' : ''}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(ref.money(b.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(b.running ? s['bill_running_${b.status}'] : s['${b.status}_status'], key: ValueKey('bill-status-${b.invoiceNo}'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                        onTap: () async {
                          await showDialog<void>(context: context, builder: (_) => b.running || b.status == 'cancelled' ? _RunningBillDialog(b) : _BillDialog(b));
                          ref.invalidate(_billsProvider);
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }

  String _typeKey(String t) => switch (t) { 'dine_in' => 'dine_in', 'takeaway' => 'takeaway', 'delivery' => 'delivery', _ => 'counter' };
}

/// An unpaid bill (held, or sent to the kitchen): look at it, continue it in Sell, take payment, or cancel it.
class _RunningBillDialog extends ConsumerStatefulWidget {
  const _RunningBillDialog(this.bill);
  final BillRow bill;
  @override
  ConsumerState<_RunningBillDialog> createState() => _RunningBillDialogState();
}

class _RunningBillDialogState extends ConsumerState<_RunningBillDialog> {
  List<Map<String, Object?>> _items = const [];

  @override
  void initState() {
    super.initState();
    ref.read(dbHelperProvider).q("SELECT name, qty_milli, line_total_minor FROM order_item WHERE order_id = ? AND status = 'active' ORDER BY rowid", [widget.bill.id]).then((r) {
      if (mounted) setState(() => _items = r);
    });
  }

  Future<void> _resume({required bool pay}) async {
    await ref.read(cartProvider.notifier).resume(widget.bill.id);
    ref.read(shellTabProvider.notifier).go('pos');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    final s = Strings.of(context);
    final ok = await confirmDialog(context, s['cancel_order_confirm'], okLabel: s['cancel_order']);
    if (!ok) return;
    try {
      await ref.read(posServiceProvider).cancelOrder(widget.bill.id, staffId: ref.read(sessionProvider)!.staffId);
      if (mounted) Navigator.pop(context);
    } on PosException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final b = widget.bill;
    final session = ref.watch(sessionProvider)!;
    return AlertDialog(
      title: Text('${b.invoiceNo} · ${b.running ? s['bill_running_${b.status}'] : s['cancelled_status']}'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (b.table != null) Text('${s['table']}: ${b.table}'),
          const SizedBox(height: 6),
          for (final i in _items) Text('${formatQty(i['qty_milli'] as int)} x ${i['name']}   ${ref.money(i['line_total_minor'] as int)}'),
          const Divider(),
          Text('${s['total']}: ${ref.money(b.totalMinor)}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      actions: [DialogActions([
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
        if (b.kitchenSent && (ref.watch(printSettingsProvider).value?.kotEnabled ?? true))
          TextButton.icon(key: const ValueKey('running-print-kot'), onPressed: () => _printKot(context, ref, b.id), icon: const Icon(Icons.soup_kitchen_outlined, size: 18), label: Text(s['print_kot'])),
        if (b.running && session.can('bill.void')) TextButton(key: const ValueKey('running-cancel'), onPressed: _cancel, child: Text(s['cancel_order'])),
        if (b.running) FilledButton.tonal(key: const ValueKey('running-resume'), onPressed: () => _resume(pay: false), child: Text(s['resume_bill'])),
        if (b.running) FilledButton(key: const ValueKey('running-pay'), onPressed: () => _resume(pay: true), child: Text(s['take_payment'])),
      ])],
    );
  }
}

class _BillDialog extends ConsumerStatefulWidget {
  const _BillDialog(this.bill);
  final BillRow bill;
  @override
  ConsumerState<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends ConsumerState<_BillDialog> {
  String? _preview;
  String? _customerPhone;
  bool _hasTokens = false;
  final _paperKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final design = await ref.read(receiptTemplateStoreProvider).load();
    final data = await loadReceipt(ref.read(databaseProvider), widget.bill.id);
    final tokens = (await ref.read(tokenServiceProvider).forOrder(widget.bill.id)).any((x) => x.status != 'void');
    final phone = await ref.read(databaseProvider).customSelect('SELECT c.phone AS p FROM "order" o JOIN customer c ON c.id = o.customer_id WHERE o.id = ?', variables: [Variable.withString(widget.bill.id)]).get();
    if (mounted) {
      setState(() {
        _preview = previewBill(data, template: design);
        _customerPhone = phone.isEmpty ? null : phone.first.data['p'] as String?;
        _hasTokens = tokens;
      });
    }
  }

  Future<void> _whatsApp() async {
    final s = Strings.of(context);
    final phone = await askPhone(context, initial: _customerPhone, title: s['send_whatsapp'], label: s['customer_phone'], ok: s['send'], cancel: s['cancel']);
    if (phone == null || !mounted) return;
    await sendViaWhatsApp(ref, phone, _preview!);
  }

  /// The receipt as a PNG picture (what is on screen), shared through the share sheet (e.g. WhatsApp).
  Future<void> _shareImage() async {
    final boundary = _paperKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    final f = File('${ref.read(exportDirProvider).path}/${widget.bill.invoiceNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.png')..writeAsBytesSync(png.buffer.asUint8List());
    await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'image/png', subject: widget.bill.invoiceNo);
  }

  Future<void> _refund({required bool full}) async {
    final s = Strings.of(context);
    final b = widget.bill;
    final session = ref.read(sessionProvider)!;
    final remaining = b.paidMinor - b.refundedMinor;
    final v = await showFormDialog(
      context,
      title: full ? s['void_bill'] : s['refund'],
      fields: [
        if (!full) FieldSpec('amount', s['refund_amount'], number: true, initial: formatMinor(remaining, currency: ref.currency, symbol: false).replaceAll(',', '')),
        FieldSpec('reason', s['reason'], lines: 2),
      ],
      validate: (v) async {
        try {
          final methods = await ref.read(paymentMethodsProvider.future);
          final cash = methods.firstWhere((m) => m.kind == 'cash', orElse: () => methods.first);
          await ref.read(posServiceProvider).refundOrder(
                orderId: b.id,
                staffId: session.staffId,
                reason: v['reason']!,
                amountMinor: full ? null : parseMinor(v['amount']!, currency: ref.currency),
                methodId: cash.id,
                shiftId: ref.read(shiftProvider),
              );
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null && mounted) {
      showMessage(context, s['refund_done']);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final session = ref.watch(sessionProvider)!;
    final b = widget.bill;
    return AlertDialog(
      title: Text(b.invoiceNo),
      content: SingleChildScrollView(
        child: RepaintBoundary(
          key: _paperKey,
          child: Container(
          width: 340,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
          child: _preview == null ? const Center(child: CircularProgressIndicator()) : Text(_preview!, key: const ValueKey('bill-preview'), style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, height: 1.25, color: Colors.black87)),
        ),
        ),
      ),
      actionsOverflowButtonSpacing: 6,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [DialogActions([
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-share'), onPressed: () => ref.read(shareServiceProvider).shareText(_preview!, subject: b.invoiceNo), icon: const Icon(Icons.share_outlined, size: 18), label: Text(s['share'])),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-whatsapp'), onPressed: _whatsApp, icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('WhatsApp')),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-image'), onPressed: _shareImage, icon: const Icon(Icons.image_outlined, size: 18), label: Text(s['share_image'])),
        if (b.kitchenSent && (ref.watch(printSettingsProvider).value?.kotEnabled ?? true))
          TextButton.icon(key: const ValueKey('bill-print-kot'), onPressed: () => _printKot(context, ref, b.id), icon: const Icon(Icons.soup_kitchen_outlined, size: 18), label: Text(s['print_kot'])),
        if (_hasTokens && (ref.watch(printSettingsProvider).value?.tokenEnabled ?? true))
          TextButton.icon(
            key: const ValueKey('bill-reprint-tokens'),
            onPressed: () async {
              final cfg = await ref.read(tokenServiceProvider).config();
              if (cfg.managerReprintOnly && !session.can('settings.manage')) {
                if (context.mounted) showMessage(context, s['reprint_manager_only']);
                return;
              }
              final jobs = await ref.read(printServiceProvider).queueTokens(b.id, reprint: true, staffId: session.staffId);
              if (jobs.isNotEmpty) ref.read(printServiceProvider).processQueue();
              if (context.mounted) showMessage(context, jobs.isEmpty ? s['no_printer'] : s['print_queued']);
            },
            icon: const Icon(Icons.confirmation_number_outlined, size: 18),
            label: Text(s['print_tokens']),
          ),
        if (ref.watch(printSettingsProvider).value?.billEnabled ?? true)
        TextButton.icon(
          key: const ValueKey('bill-reprint'),
          onPressed: () async {
            final cfg = await ref.read(tokenServiceProvider).config();
            if (cfg.managerReprintOnly && !session.can('settings.manage')) {
              if (context.mounted) showMessage(context, s['reprint_manager_only']);
              return;
            }
            final jobs = await ref.read(printServiceProvider).queueBill(b.id, duplicate: true, staffId: session.staffId);
            if (jobs.isNotEmpty) ref.read(printServiceProvider).processQueue();
            if (context.mounted) showMessage(context, jobs.isEmpty ? s['no_printer'] : s['print_queued']);
          },
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(s['reprint']),
        ),
        if (b.canRefund && session.can('bill.refund')) TextButton(key: const ValueKey('bill-refund'), onPressed: () => _refund(full: false), child: Text(s['refund'])),
        if (b.canRefund && b.refundedMinor == 0 && session.can('bill.void')) FilledButton(key: const ValueKey('bill-void'), style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => _refund(full: true), child: Text(s['void_bill'])),
      ])],
    );
  }
}

/// Prints the kitchen ticket of an existing order again (marked REPRINT). It never creates a new order or a second kitchen entry.
Future<void> _printKot(BuildContext context, WidgetRef ref, String orderId) async {
  final s = Strings.of(context);
  final svc = ref.read(printServiceProvider);
  final jobs = await svc.queueKot(orderId, reprint: true);
  if (jobs.isNotEmpty) svc.processQueue();
  if (context.mounted) showMessage(context, jobs.isEmpty ? s['no_printer'] : s['print_queued']);
}
