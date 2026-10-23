import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/expense_service.dart';
import '../../data/pos_service.dart';
import '../../data/receipt_loader.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';

final _expensesProvider = FutureProvider.autoDispose.family<List<ExpenseRow>, String>((ref, d) => ref.watch(expenseServiceProvider).forDate(d));

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late DateTime _day = ref.read(clockProvider)();
  String get _key => '${_day.year}-${two(_day.month)}-${two(_day.day)}';

  Future<void> _add() async {
    final s = Strings.of(context);
    final methods = (await ref.read(paymentMethodsProvider.future)).where((m) => m.kind != 'credit').toList();
    if (!mounted) return;
    var method = methods.first.id;
    final v = await showFormDialog(
      context,
      title: s['add_expense'],
      fields: [FieldSpec('amount', s['amount'], number: true), FieldSpec('category', s['category']), FieldSpec('note', s['note'], required: false)],
      extra: (set) => DropdownButtonFormField<String>(key: const ValueKey('exp-method'), initialValue: method, items: [for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name))], onChanged: (x) => set(() => method = x ?? method)),
      validate: (v) async {
        try {
          await ref.read(expenseServiceProvider).add(amountMinor: parseMinor(v['amount']!, currency: ref.currency) ?? 0, category: v['category']!, methodId: method, note: v['note'], staffId: ref.read(sessionProvider)!.staffId);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) ref.invalidate(_expensesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final list = ref.watch(_expensesProvider(_key));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-expense'), onPressed: _add, icon: const Icon(Icons.add), label: Text(s['add_expense'])),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            IconButton(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_key, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              final total = rows.fold<int>(0, (a, e) => a + e.amountMinor);
              return Column(children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [Text(s['today_total']), const Spacer(), Text(ref.money(total), key: const ValueKey('exp-total'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))])),
                Expanded(
                  child: rows.isEmpty
                      ? Center(child: Text(s['no_expenses']))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          itemCount: rows.length,
                          itemBuilder: (_, i) => Card(child: ListTile(title: Text(rows[i].category ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text([rows[i].method, rows[i].note].whereType<String>().join(' · ')), trailing: Text(ref.money(rows[i].amountMinor), style: const TextStyle(fontWeight: FontWeight.w800)))),
                        ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
