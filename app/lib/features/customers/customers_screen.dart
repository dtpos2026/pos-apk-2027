import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/whatsapp.dart';
import '../../app/strings.dart';
import '../../data/customer_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart' show loadBusiness;
import '../../data/receipt_loader.dart' show formatDateTime;
import '../../domain/statement_doc.dart';
import '../common/slip_screen.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';
import 'customer_tools.dart';
import 'promo_screen.dart';
import '../../data/menu_images.dart';
import 'dart:io';

final customersProvider = FutureProvider.autoDispose.family<List<CustomerRow>, String>((ref, q) => ref.watch(customerServiceProvider).list(search: q));

Future<String?> addCustomerDialog(BuildContext context, WidgetRef ref, {CustomerRow? existing}) async {
  final s = Strings.of(context);
  String? id;
  final v = await showFormDialog(
    context,
    title: existing == null ? s['add_customer'] : s['edit'],
    fields: [
      FieldSpec('name', s['name'], initial: existing?.name ?? ''),
      FieldSpec('phone', s['phone'], initial: existing?.phone ?? '', required: false),
      FieldSpec('address', s['address'], initial: existing?.address ?? '', required: false),
      FieldSpec('limit', s['credit_limit'], initial: existing == null ? '0' : formatMinor(existing.creditLimitMinor, currency: ref.currency, symbol: false).replaceAll(',', ''), number: true, required: false),
    ],
    validate: (v) async {
      try {
        id = await ref.read(customerServiceProvider).save(
            id: existing?.id, name: v['name']!, phone: v['phone'], address: v['address'], creditLimitMinor: parseMinor(v['limit']!.isEmpty ? '0' : v['limit']!, currency: ref.currency) ?? 0, staffId: ref.read(sessionProvider)!.staffId);
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    },
  );
  if (v == null) return null;
  ref.invalidate(customersProvider);
  return id;
}

/// Round customer picture (or the first letter of the name) with a white ring, so lists look the same everywhere.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar(this.c, {super.key, this.radius = 22});
  final CustomerRow c;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final has = c.imagePath != null && File(c.imagePath!).existsSync();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 1.5)),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.primary,
        backgroundImage: has ? FileImage(File(c.imagePath!)) : null,
        child: has ? null : Text(c.name.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

final _outstandingProvider = FutureProvider.autoDispose((ref) => ref.watch(customerServiceProvider).outstanding());

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _q = '';
  bool _owingOnly = false;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final list = ref.watch(customersProvider(_q));
    final owed = ref.watch(_outstandingProvider).value;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-customer'), onPressed: () => addCustomerDialog(context, ref), icon: const Icon(Icons.person_add_alt_1), label: Text(s['add_customer'])),
      body: Column(children: [
        if (owed != null && owed.customers > 0)
          Container(
            key: const ValueKey('udhaar-summary'),
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35))),
            child: Row(children: [
              Icon(Icons.menu_book_outlined, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 10),
              Expanded(child: Text('${s['udhaar_due']} · ${owed.customers}', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(ref.money(owed.totalMinor), key: const ValueKey('udhaar-total'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s['search_items'], isDense: true), onChanged: (v) => setState(() => _q = v))),
            const SizedBox(width: 8),
            FilterChip(key: const ValueKey('owing-only'), label: Text(s['owing_only']), selected: _owingOnly, showCheckmark: false, onSelected: (v) => setState(() => _owingOnly = v)),
          ]),
        ),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            ActionChip(key: const ValueKey('promo-open-screen'), avatar: const Icon(Icons.campaign_outlined, size: 18), label: Text(s['promo_title']), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PromoScreen()))),
            const SizedBox(width: 8),
            ActionChip(key: const ValueKey('customers-csv'), avatar: const Icon(Icons.table_chart_outlined, size: 18), label: Text(s['export_csv']), onPressed: () => exportCustomers(context, ref, pdf: false, search: _q)),
            const SizedBox(width: 8),
            ActionChip(key: const ValueKey('customers-pdf'), avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: Text(s['export_customers_pdf']), onPressed: () => exportCustomers(context, ref, pdf: true, search: _q)),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (all) {
              final rows = _owingOnly ? all.where((c) => c.balanceMinor > 0).toList() : all;
              return rows.isEmpty
                ? Center(child: Text(s['no_customers']))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final c = rows[i];
                      return Card(
                        child: ListTile(
                          key: ValueKey('customer-${c.name}'),
                          leading: CustomerAvatar(c, radius: 22),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(c.phone ?? ''),
                          trailing: c.balanceMinor > 0
                              ? Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(s['owes'], style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)), Text(ref.money(c.balanceMinor), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.error))])
                              : null,
                          onTap: () async {
                            await showDialog<void>(context: context, builder: (_) => _CustomerDialog(c.id));
                            ref.invalidate(customersProvider);
                          },
                        ),
                      );
                    },
                  );
            },
          ),
        ),
      ]),
    );
  }
}

class _CustomerDialog extends ConsumerStatefulWidget {
  const _CustomerDialog(this.id);
  final String id;
  @override
  ConsumerState<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends ConsumerState<_CustomerDialog> {
  CustomerRow? _c;
  List<LedgerEntry> _ledger = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(customerServiceProvider);
    final all = await svc.list();
    final led = await svc.ledger(widget.id);
    if (!mounted) return;
    setState(() {
      _c = all.firstWhere((c) => c.id == widget.id);
      _ledger = led;
    });
  }

  Future<void> _openStatement(CustomerRow c) async {
    final biz = await loadBusiness(ref.read(databaseProvider));
    final cur = biz?.currency ?? Currency.pkr;
    final lines = [
      for (final e in _ledger.reversed)
        StatementLine(at: DateTime.fromMillisecondsSinceEpoch(e.at), description: e.kind == 'sale_credit' ? (e.invoiceNo ?? 'Credit sale') : (e.kind == 'recovery' ? 'Payment received' : e.kind), amountMinor: e.amountMinor, balanceMinor: e.balanceAfterMinor),
    ];
    final printedAt = formatDateTime(ref.read(clockProvider)());
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SlipScreen(
        title: '${Strings.of(context)['statement']} · ${c.name}',
        fileName: 'statement-${c.name}',
        build: (_) => buildStatementDoc(businessName: biz?.name ?? '', customerName: c.name, phone: c.phone, lines: lines, balanceMinor: c.balanceMinor, currency: cur, printedAt: printedAt),
        csv: () => statementCsv(lines, currency: cur),
      ),
    ));
  }

  Future<void> _photo({required bool camera}) async {
    final picker = ref.read(logoPickerProvider);
    final b = camera ? await picker.capture() : await picker.pick();
    if (b == null) return;
    try {
      await ref.read(menuImageStoreProvider).setCustomer(widget.id, b);
      ref.invalidate(customersProvider);
      await _load();
    } on MenuImageException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _receive() async {
    final s = Strings.of(context);
    final methods = (await ref.read(paymentMethodsProvider.future)).where((m) => m.kind != 'credit').toList();
    if (!mounted) return;
    var method = methods.first.id;
    final v = await showFormDialog(
      context,
      title: s['receive_payment'],
      fields: [FieldSpec('amount', s['amount'], number: true, initial: formatMinor(_c!.balanceMinor, currency: ref.currency, symbol: false).replaceAll(',', ''))],
      extra: (set) => DropdownButtonFormField<String>(key: const ValueKey('recv-method'), initialValue: method, items: [for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name))], onChanged: (x) => set(() => method = x ?? method)),
      validate: (v) async {
        try {
          await ref.read(customerServiceProvider).receivePayment(customerId: widget.id, amountMinor: parseMinor(v['amount']!, currency: ref.currency) ?? 0, methodId: method, staffId: ref.read(sessionProvider)!.staffId);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final c = _c;
    return AlertDialog(
      title: c == null
          ? const Text('')
          : Row(children: [
              CustomerAvatar(c, radius: 26),
              const SizedBox(width: 12),
              Expanded(child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
      content: SizedBox(
        width: 380,
        child: c == null
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, children: [
                  ActionChip(key: const ValueKey('cust-photo-camera'), avatar: const Icon(Icons.photo_camera_outlined, size: 18), label: Text(s['take_photo']), onPressed: () => _photo(camera: true)),
                  ActionChip(key: const ValueKey('cust-photo-gallery'), avatar: const Icon(Icons.photo_library_outlined, size: 18), label: Text(s['choose_photo']), onPressed: () => _photo(camera: false)),
                  if (c.imagePath != null) ActionChip(key: const ValueKey('cust-photo-remove'), avatar: const Icon(Icons.delete_outline, size: 18), label: Text(s['remove_photo']), onPressed: () async {
                        await ref.read(menuImageStoreProvider).removeCustomer(c.id);
                        await _load();
                      }),
                ]),
                const SizedBox(height: 8),
                Text('${s['balance']}: ${ref.money(c.balanceMinor)}', key: const ValueKey('cust-balance'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text('${s['credit_limit']}: ${ref.money(c.creditLimitMinor)}'),
                const Divider(),
                Flexible(
                  child: _ledger.isEmpty
                      ? Padding(padding: const EdgeInsets.all(8), child: Text(s['no_ledger']))
                      : ListView(shrinkWrap: true, children: [
                          for (final e in _ledger)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.kind == 'sale_credit' ? '${s['owes']}${e.invoiceNo == null ? '' : ' · ${e.invoiceNo}'}' : (e.kind == 'recovery' ? s['receive_payment'] : e.kind)),
                              subtitle: Text('${DateTime.fromMillisecondsSinceEpoch(e.at).toString().substring(0, 16)}  ·  ${s['balance']}: ${ref.money(e.balanceAfterMinor)}'),
                              trailing: Text(ref.money(e.amountMinor), style: TextStyle(fontWeight: FontWeight.w700, color: e.amountMinor < 0 ? Colors.green.shade700 : null)),
                            ),
                        ]),
                ),
              ]),
      ),
      actions: [DialogActions([
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s['close'])),
        TextButton(onPressed: c == null ? null : () async {
          if (await addCustomerDialog(context, ref, existing: c) != null) _load();
        }, child: Text(s['edit'])),
        if (c != null && _ledger.isNotEmpty)
          TextButton.icon(
            key: const ValueKey('customer-statement'),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text(s['statement']),
            onPressed: () => _openStatement(c),
          ),
        if (c != null && c.balanceMinor > 0)
          TextButton.icon(
            key: const ValueKey('udhaar-reminder'),
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: Text(s['reminder']),
            onPressed: () async {
              final biz = ref.read(businessProvider).value?.name ?? '';
              final text = s['udhaar_reminder_text'].replaceAll('{name}', c.name).replaceAll('{business}', biz).replaceAll('{amount}', ref.money(c.balanceMinor));
              final phone = c.phone ?? await askPhone(context, title: s['reminder'], label: s['customer_phone'], ok: s['send'], cancel: s['cancel']);
              if (phone == null || !context.mounted) return;
              await sendViaWhatsApp(ref, phone, text);
            },
          ),
        if (c != null && c.balanceMinor > 0) FilledButton(key: const ValueKey('receive-payment'), onPressed: _receive, child: Text(s['receive_payment'])),
      ])],
    );
  }
}

/// Bottom sheet used by the cart to attach a customer to the order (needed for credit sales).
Future<String?> pickCustomer(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<String>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const SafeArea(top: false, child: _CustomerPicker()));
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final list = ref.watch(customersProvider(_q)).value ?? const [];
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Column(children: [
        ListTile(title: Text(s['select_customer'], style: const TextStyle(fontWeight: FontWeight.w700)), trailing: IconButton(key: const ValueKey('picker-add'), icon: const Icon(Icons.person_add_alt_1), onPressed: () async {
          final id = await addCustomerDialog(context, ref);
          if (id != null && context.mounted) Navigator.pop(context, id);
        })),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s['search_items'], isDense: true), onChanged: (v) => setState(() => _q = v))),
        ListTile(key: const ValueKey('pick-walkin'), leading: const Icon(Icons.person_outline), title: Text(s['walk_in']), onTap: () => Navigator.pop(context, '')),
        Expanded(child: ListView(children: [for (final c in list) ListTile(key: ValueKey('pick-${c.name}'), leading: CircleAvatar(child: Text(c.name.characters.first.toUpperCase())), title: Text(c.name), subtitle: Text(c.phone ?? ''), trailing: c.balanceMinor > 0 ? Text(ref.money(c.balanceMinor)) : null, onTap: () => Navigator.pop(context, c.id))])),
      ]),
    );
  }
}
