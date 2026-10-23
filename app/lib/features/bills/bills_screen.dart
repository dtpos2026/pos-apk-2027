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

final _billsProvider = FutureProvider.autoDispose.family<List<BillRow>, (String, String)>((ref, k) => ref.watch(billHistoryProvider).forDate(k.$1, search: k.$2));

/// Past bills: look up, reprint (marked DUPLICATE), share, refund or void.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});
  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  late DateTime _day = ref.read(clockProvider)();
  String _search = '';

  String get _key => '${_day.year}-${two(_day.month)}-${two(_day.day)}';

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final bills = ref.watch(_billsProvider((_key, _search)));
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
                    final color = switch (b.status) { 'void' => Colors.red.shade700, 'refunded' => Colors.orange.shade800, _ => Colors.green.shade700 };
                    final time = DateTime.fromMillisecondsSinceEpoch(b.settledAt);
                    return Card(
                      child: ListTile(
                        key: ValueKey('bill-${b.invoiceNo}'),
                        title: Text(b.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${two(time.hour)}:${two(time.minute)}  ·  ${s[_typeKey(b.orderType)]}${b.table != null ? ' ${b.table}' : ''}${b.customer != null ? '  ·  ${b.customer}' : ''}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(ref.money(b.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(s['${b.status}_status'], style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                        onTap: () async {
                          await showDialog<void>(context: context, builder: (_) => _BillDialog(b));
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

class _BillDialog extends ConsumerStatefulWidget {
  const _BillDialog(this.bill);
  final BillRow bill;
  @override
  ConsumerState<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends ConsumerState<_BillDialog> {
  String? _preview;
  String? _customerPhone;
  final _paperKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final design = await ref.read(receiptTemplateStoreProvider).load();
    final data = await loadReceipt(ref.read(databaseProvider), widget.bill.id);
    final phone = await ref.read(databaseProvider).customSelect('SELECT c.phone AS p FROM "order" o JOIN customer c ON c.id = o.customer_id WHERE o.id = ?', variables: [Variable.withString(widget.bill.id)]).get();
    if (mounted) {
      setState(() {
        _preview = previewBill(data, template: design);
        _customerPhone = phone.isEmpty ? null : phone.first.data['p'] as String?;
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-share'), onPressed: () => ref.read(shareServiceProvider).shareText(_preview!, subject: b.invoiceNo), icon: const Icon(Icons.share_outlined, size: 18), label: Text(s['share'])),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-whatsapp'), onPressed: _whatsApp, icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('WhatsApp')),
        if (_preview != null)
          TextButton.icon(key: const ValueKey('bill-image'), onPressed: _shareImage, icon: const Icon(Icons.image_outlined, size: 18), label: Text(s['share_image'])),
        TextButton.icon(
          key: const ValueKey('bill-reprint'),
          onPressed: () async {
            final jobs = await ref.read(printServiceProvider).queueBill(b.id, duplicate: true, staffId: session.staffId);
            if (jobs.isNotEmpty) ref.read(printServiceProvider).processQueue();
            if (context.mounted) showMessage(context, jobs.isEmpty ? s['no_printer'] : s['print_queued']);
          },
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(s['reprint']),
        ),
        if (b.canRefund && session.can('bill.refund')) TextButton(key: const ValueKey('bill-refund'), onPressed: () => _refund(full: false), child: Text(s['refund'])),
        if (b.canRefund && b.refundedMinor == 0 && session.can('bill.void')) FilledButton(key: const ValueKey('bill-void'), style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => _refund(full: true), child: Text(s['void_bill'])),
      ],
    );
  }
}
