import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/inventory_service.dart';
import '../../data/pos_service.dart';
import '../../data/queries.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';

final _stockProvider = FutureProvider.autoDispose<List<StockRow>>((ref) => ref.watch(inventoryServiceProvider).list());
final _suppliersProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  final h = ref.watch(dbHelperProvider);
  return h.q('SELECT s.id, s.name, COALESCE((SELECT SUM(amount_minor) FROM supplier_ledger WHERE supplier_id = s.id),0) AS bal FROM supplier s WHERE s.deleted_at IS NULL ORDER BY s.name');
});

String _qty(int milli) => formatQty(milli);
int? _parseQty(String s) {
  final m = parseMinor(s, currency: const Currency('QTY', minorDigits: 3));
  return m;
}

/// Stock items (with low-stock alerts and value), purchases, wastage, stock counts, recipes and suppliers.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _lowOnly = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _staff => ref.read(sessionProvider)!.staffId;
  InventoryService get _svc => ref.read(inventoryServiceProvider);
  void _refresh() {
    ref.invalidate(_stockProvider);
    ref.invalidate(_suppliersProvider);
  }

  Future<void> _addItem() async {
    final s = Strings.of(context);
    var unit = 'kg';
    final v = await showFormDialog(
      context,
      title: s['add_stock_item'],
      fields: [FieldSpec('name', s['name']), FieldSpec('open', s['opening_qty'], number: true, required: false, initial: '0'), FieldSpec('cost', s['cost_per_unit'], number: true, required: false, initial: '0'), FieldSpec('reorder', s['reorder_level'], number: true, required: false, initial: '0')],
      extra: (set) => DropdownButtonFormField<String>(key: const ValueKey('unit'), initialValue: unit, decoration: InputDecoration(labelText: s['unit']), items: [for (final u in ['kg', 'g', 'l', 'ml', 'pc']) DropdownMenuItem(value: u, child: Text(u))], onChanged: (x) => set(() => unit = x ?? unit)),
      validate: (v) async {
        try {
          await _svc.saveItem(name: v['name']!, unit: unit, openingMilli: _parseQty(v['open']!.isEmpty ? '0' : v['open']!) ?? 0, openingCostMinor: parseMinor(v['cost']!.isEmpty ? '0' : v['cost']!, currency: ref.currency) ?? 0, reorderLevelMilli: _parseQty(v['reorder']!.isEmpty ? '0' : v['reorder']!) ?? 0, staffId: _staff);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) _refresh();
  }

  Future<void> _wastage(StockRow r) async {
    final s = Strings.of(context);
    final v = await showFormDialog(context, title: '${s['wastage']}: ${r.name}', fields: [FieldSpec('qty', '${s['qty']} (${r.unit})', number: true), FieldSpec('reason', s['reason'])], validate: (v) async {
      try {
        await _svc.wastage(stockItemId: r.id, qtyMilli: _parseQty(v['qty']!) ?? 0, reason: v['reason']!, staffId: _staff);
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    });
    if (v != null) _refresh();
  }

  Future<void> _count(StockRow r) async {
    final s = Strings.of(context);
    final v = await showFormDialog(context, title: '${s['stock_count']}: ${r.name}', fields: [FieldSpec('qty', '${s['counted']} (${r.unit})', number: true, initial: _qty(r.onHandMilli))], validate: (v) async {
      try {
        await _svc.stockCount(stockItemId: r.id, countedMilli: _parseQty(v['qty']!) ?? -1, staffId: _staff);
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    });
    if (v != null) _refresh();
  }

  Future<void> _purchase(StockRow r) async {
    final s = Strings.of(context);
    final sup = await ref.read(_suppliersProvider.future);
    if (!mounted) return;
    String? supplier;
    final v = await showFormDialog(
      context,
      title: '${s['purchase']}: ${r.name}',
      fields: [FieldSpec('qty', '${s['qty']} (${r.unit})', number: true), FieldSpec('cost', s['cost_per_unit'], number: true), FieldSpec('paid', s['paid_now'], number: true, required: false)],
      extra: (set) => DropdownButtonFormField<String?>(key: const ValueKey('supplier'), initialValue: supplier, decoration: InputDecoration(labelText: s['supplier']), items: [const DropdownMenuItem<String?>(value: null, child: Text('-')), for (final x in sup) DropdownMenuItem<String?>(value: x['id'] as String, child: Text('${x['name']}'))], onChanged: (x) => set(() => supplier = x)),
      validate: (v) async {
        try {
          final qty = _parseQty(v['qty']!) ?? 0;
          final cost = parseMinor(v['cost']!, currency: ref.currency) ?? 0;
          final total = (qty * cost / 1000).round();
          final paid = v['paid']!.isEmpty ? (supplier == null ? total : 0) : (parseMinor(v['paid']!, currency: ref.currency) ?? 0);
          await _svc.purchase(supplierId: supplier, lines: [PurchaseInput(stockItemId: r.id, qtyMilli: qty, unitCostMinor: cost)], paidMinor: paid, staffId: _staff);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) _refresh();
  }

  Future<void> _recipe() async {
    final s = Strings.of(context);
    final products = await loadProducts(ref.read(databaseProvider));
    final stock = await _svc.list();
    if (!mounted || products.isEmpty || stock.isEmpty) return;
    final product = await showDialog<MenuProduct>(context: context, builder: (ctx) => SimpleDialog(title: Text(s['recipe']), children: [for (final p in products) SimpleDialogOption(key: ValueKey('rp-${p.name}'), onPressed: () => Navigator.pop(ctx, p), child: Text(p.name))]));
    if (product == null || !mounted) return;
    final current = await _svc.recipe(product.id);
    final fields = [for (final x in stock) FieldSpec(x.id, '${x.name} (${x.unit})', number: true, required: false, initial: current[x.id] == null ? '' : _qty(current[x.id]!))];
    if (!mounted) return;
    final v = await showFormDialog(context, title: '${s['recipe']}: ${product.name}', fields: fields, validate: (v) async {
      try {
        await _svc.saveRecipe(productId: product.id, ingredientsMilli: {for (final e in v.entries) if (e.value.isNotEmpty && (_parseQty(e.value) ?? 0) > 0) e.key: _parseQty(e.value)!});
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    });
    if (v != null) _refresh();
  }

  Future<void> _addSupplier() async {
    final s = Strings.of(context);
    final v = await showFormDialog(context, title: s['add_supplier'], fields: [FieldSpec('name', s['name']), FieldSpec('phone', s['phone'], required: false)], validate: (v) async {
      try {
        await _svc.saveSupplier(name: v['name']!, phone: v['phone']);
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    });
    if (v != null) _refresh();
  }

  Future<void> _paySupplier(String id, int owed) async {
    final s = Strings.of(context);
    final v = await showFormDialog(context, title: s['pay_supplier'], fields: [FieldSpec('amount', s['amount'], number: true, initial: formatMinor(owed, currency: ref.currency, symbol: false).replaceAll(',', ''))], validate: (v) async {
      try {
        await _svc.paySupplier(supplierId: id, amountMinor: parseMinor(v['amount']!, currency: ref.currency) ?? 0, staffId: _staff);
        return null;
      } on PosException catch (e) {
        return e.message;
      }
    });
    if (v != null) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final stock = ref.watch(_stockProvider).value ?? const [];
    final shown = _lowOnly ? stock.where((r) => r.isLow).toList() : stock;
    final value = stock.fold<int>(0, (a, r) => a + (r.onHandMilli > 0 ? r.valueMinor : 0));
    final suppliers = ref.watch(_suppliersProvider).value ?? const [];
    return Column(children: [
      TabBar(controller: _tabs, tabs: [Tab(text: s['stock_items']), Tab(text: s['suppliers'])]),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-stock'), onPressed: _addItem, icon: const Icon(Icons.add), label: Text(s['add_stock_item'])),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(children: [
                  Expanded(child: Text('${s['valuation']}: ${ref.money(value)}', key: const ValueKey('stock-value'), style: const TextStyle(fontWeight: FontWeight.w800))),
                  IconButton(key: const ValueKey('recipe-btn'), tooltip: s['recipe'], onPressed: _recipe, icon: const Icon(Icons.menu_book_outlined)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  _CountBox(label: s['all'], count: stock.length, color: Theme.of(context).colorScheme.primary, selected: !_lowOnly, onTap: () => setState(() => _lowOnly = false)),
                  const SizedBox(width: 8),
                  _CountBox(label: s['stock_ok'], count: stock.where((r) => !r.isLow).length, color: const Color(0xFF2E9E5B), selected: false, onTap: () => setState(() => _lowOnly = false)),
                  const SizedBox(width: 8),
                  _CountBox(key: const ValueKey('low-filter'), label: s['low_stock'], count: stock.where((r) => r.isLow).length, color: const Color(0xFFD93B3B), selected: _lowOnly, onTap: () => setState(() => _lowOnly = !_lowOnly)),
                ]),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(s['no_stock']))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final r = shown[i];
                          final low = r.isLow;
                          final color = low ? const Color(0xFFD93B3B) : const Color(0xFF2E9E5B);
                          final ratio = r.reorderMilli <= 0 ? 1.0 : (r.onHandMilli / (r.reorderMilli * 2)).clamp(0.04, 1.0).toDouble();
                          return Card(
                            child: ListTile(
                              key: ValueKey('stock-${r.name}'),
                              contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                              title: Row(children: [
                                Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                  child: Text(low ? s['low_stock'] : s['stock_ok'], style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                              ]),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${s['on_hand']}: ${_qty(r.onHandMilli)} ${r.unit}', style: TextStyle(fontWeight: low ? FontWeight.w700 : null, color: low ? color : null)),
                                  const SizedBox(height: 6),
                                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: ratio, minHeight: 6, color: color, backgroundColor: color.withValues(alpha: 0.15))),
                                ]),
                              ),
                              trailing: PopupMenuButton<String>(
                                key: ValueKey('stock-menu-${r.name}'),
                                onSelected: (a) => switch (a) { 'buy' => _purchase(r), 'waste' => _wastage(r), _ => _count(r) },
                                itemBuilder: (_) => [PopupMenuItem(value: 'buy', child: Text(s['purchase'])), PopupMenuItem(value: 'waste', child: Text(s['wastage'])), PopupMenuItem(value: 'count', child: Text(s['stock_count']))],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-supplier'), onPressed: _addSupplier, icon: const Icon(Icons.add), label: Text(s['add_supplier'])),
            body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
              for (final x in suppliers)
                Card(
                  child: ListTile(
                    key: ValueKey('supplier-${x['name']}'),
                    title: Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s['payable']}: ${ref.money(x['bal'] as int)}'),
                    trailing: (x['bal'] as int) > 0 ? FilledButton.tonal(onPressed: () => _paySupplier(x['id'] as String, x['bal'] as int), child: Text(s['pay_supplier'])) : null,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

/// One of the three summary boxes above the stock list (All / OK / Low stock).
class _CountBox extends StatelessWidget {
  const _CountBox({super.key, required this.label, required this.count, required this.color, required this.selected, required this.onTap});
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? color : Theme.of(context).dividerColor),
            ),
            child: Column(children: [
              Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}
