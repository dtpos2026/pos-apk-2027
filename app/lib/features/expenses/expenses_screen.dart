import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/expense_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart' show PaymentMethodInfo;
import '../../data/receipt_loader.dart';
import '../../domain/money.dart';

final _expensesProvider = FutureProvider.autoDispose.family<List<ExpenseRow>, String>((ref, d) => ref.watch(expenseServiceProvider).forDate(d));
final _categoriesProvider = FutureProvider.autoDispose((ref) => ref.watch(expenseServiceProvider).categories());

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late DateTime _day = ref.read(clockProvider)();
  String get _key => '${_day.year}-${two(_day.month)}-${two(_day.day)}';

  Future<void> _add() async {
    final methods = (await ref.read(paymentMethodsProvider.future)).where((m) => m.kind != 'credit').toList();
    final cats = await ref.read(expenseServiceProvider).categories();
    if (!mounted) return;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExpenseSheet(methods: methods, categories: cats),
    );
    if (done == true) {
      ref.invalidate(_expensesProvider);
      ref.invalidate(_categoriesProvider);
    }
  }

  Future<void> _confirmDelete(ExpenseRow e) async {
    final s = Strings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['expense_delete_title']),
        content: Text('${e.category ?? s['no_category']}  ·  ${ref.money(e.amountMinor)}\n\n${s['expense_delete_body']}'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])), FilledButton(key: const ValueKey('exp-delete-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(s['delete']))],
      ),
    );
    if (ok != true) return;
    await ref.read(expenseServiceProvider).delete(e.id, staffId: ref.read(sessionProvider)!.staffId);
    ref.invalidate(_expensesProvider);
  }

  Future<void> _manageCategories() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const _CategorySheet());
    ref.invalidate(_categoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = ref.watch(_expensesProvider(_key));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-expense'), onPressed: _add, icon: const Icon(Icons.add), label: Text(s['add_expense'])),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            IconButton(onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_key, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
            IconButton(key: const ValueKey('manage-categories'), tooltip: s['expense_categories'], onPressed: _manageCategories, icon: const Icon(Icons.category_outlined)),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              final total = rows.fold<int>(0, (a, e) => a + e.amountMinor);
              return Column(children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.primary.withValues(alpha: 0.35))),
                  child: Row(children: [
                    Icon(Icons.payments_outlined, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(s['today_total'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(ref.money(total), key: const ValueKey('exp-total'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: cs.primary)),
                  ]),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(child: Text(s['no_expenses'], style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final e = rows[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant)),
                              child: Row(children: [
                                CircleAvatar(radius: 20, backgroundColor: cs.primary.withValues(alpha: 0.1), child: Icon(Icons.receipt_outlined, color: cs.primary, size: 20)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.category ?? s['no_category'], style: TextStyle(fontWeight: FontWeight.w700, color: e.category == null ? cs.onSurfaceVariant : null)),
                                    if ([e.method, e.note].whereType<String>().isNotEmpty) Text([e.method, e.note].whereType<String>().join(' · '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                                  ]),
                                ),
                                Text(ref.money(e.amountMinor), style: TextStyle(fontWeight: FontWeight.w800, color: cs.error)),
                                IconButton(key: ValueKey('exp-delete-$i'), tooltip: s['delete'], visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant), onPressed: () => _confirmDelete(e)),
                              ]),
                            );
                          },
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

/// Add an expense with as few taps as possible: the amount and how it was paid are all that is needed. A category (tap one of
/// the saved ones, or type a new one) and a note are optional.
class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet({required this.methods, required this.categories});
  final List<PaymentMethodInfo> methods;
  final List<({String id, String name})> categories;
  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  late String _method = widget.methods.first.id;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_amount, _category, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(expenseServiceProvider).add(amountMinor: parseMinor(_amount.text, currency: ref.currency) ?? 0, category: _category.text, methodId: _method, note: _note.text, staffId: ref.read(sessionProvider)!.staffId);
      if (mounted) Navigator.pop(context, true);
    } on PosException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s['add_expense'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('f-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: s['amount'], prefixIcon: const Icon(Icons.payments_outlined)),
          ),
          const SizedBox(height: 14),
          Text(s['pay_with'], style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in widget.methods)
              ChoiceChip(key: ValueKey('exp-method-${m.name}'), label: Text(m.name), selected: _method == m.id, showCheckmark: false, onSelected: (_) => setState(() => _method = m.id)),
          ]),
          const SizedBox(height: 14),
          Text('${s['category']} (${s['optional']})', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (widget.categories.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final c in widget.categories)
                ChoiceChip(key: ValueKey('exp-cat-${c.name}'), label: Text(c.name), selected: _category.text.trim().toLowerCase() == c.name.toLowerCase(), showCheckmark: false, onSelected: (on) => setState(() => _category.text = on ? c.name : '')),
            ]),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('f-category'), controller: _category, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: s['new_category'], prefixIcon: const Icon(Icons.label_outline))),
          const SizedBox(height: 10),
          TextField(key: const ValueKey('f-note'), controller: _note, decoration: InputDecoration(labelText: '${s['note']} (${s['optional']})', prefixIcon: const Icon(Icons.notes))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, key: const ValueKey('form-error'), style: TextStyle(color: cs.error))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('form-ok'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: _busy ? null : _save, child: Text(s['save']))),
        ]),
      ),
    );
  }
}

/// The saved categories, each with a delete button. Deleting only removes it from the quick list: old expenses keep their name.
class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet();
  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late Future<List<({String id, String name})>> _cats = ref.read(expenseServiceProvider).categories();

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return SafeArea(
      child: FutureBuilder<List<({String id, String name})>>(
        future: _cats,
        builder: (context, snap) {
          final cats = snap.data ?? const [];
          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(s['expense_categories'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.done && cats.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(s['no_categories'])),
            for (final c in cats)
              ListTile(
                key: ValueKey('cat-${c.name}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline),
                title: Text(c.name),
                trailing: IconButton(
                  key: ValueKey('cat-delete-${c.name}'),
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    await ref.read(expenseServiceProvider).deleteCategory(c.id);
                    setState(() {
                      _cats = ref.read(expenseServiceProvider).categories();
                    });
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
