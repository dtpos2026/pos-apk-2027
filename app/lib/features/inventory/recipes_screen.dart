import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/inventory_service.dart';
import '../../data/pos_service.dart' show PosException;
import '../../data/recipe_service.dart';

class _SearchText extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final _recipeSearchProvider = NotifierProvider.autoDispose<_SearchText, String>(_SearchText.new);
final recipeRowsProvider = FutureProvider.autoDispose<List<RecipeRow>>((ref) => ref.watch(recipeServiceProvider).rows(search: ref.watch(_recipeSearchProvider)));

/// Recipes & food cost: every menu item (and each of its sizes) with what one portion costs and the margin, as in DT Enterprise.
/// "Build" opens the ingredient list; a sale then takes exactly those ingredients out of Inventory.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final rows = ref.watch(recipeRowsProvider);
    final stock = ref.watch(inventoryServiceProvider);
    final withRecipe = rows.value?.where((r) => r.hasRecipe).length ?? 0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Icon(Icons.menu_book_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(t['recipes_title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            Text('$withRecipe / ${rows.value?.length ?? 0}', key: const ValueKey('recipes-count'), style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(key: const ValueKey('recipe-search'), onChanged: (v) => ref.read(_recipeSearchProvider.notifier).set(v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['recipes_search'])),
        ),
        FutureBuilder<List<StockRow>>(
          future: stock.list(),
          builder: (c, s) => (s.hasData && s.data!.isEmpty)
              ? Container(key: const ValueKey('recipes-need-stock'), margin: const EdgeInsets.fromLTRB(12, 0, 12, 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)), child: Text(t['recipes_need_stock'], style: TextStyle(color: cs.onTertiaryContainer)))
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: rows.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(child: Text(t['recipes_none'], textAlign: TextAlign.center))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _RecipeCard(row: list[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _RecipeCard extends ConsumerWidget {
  const _RecipeCard({required this.row});
  final RecipeRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final m = row.marginPct;
    final marginColor = m == null ? cs.onSurfaceVariant : (m < 30 ? cs.error : (m < 50 ? const Color(0xFFB7791F) : Colors.green.shade700));
    return Card(
      key: ValueKey('recipe-${row.label}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              if (row.variantName != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(row.variantName!, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700))),
              const SizedBox(height: 4),
              Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(row.hasRecipe ? '${row.ingredients} ${t['recipe_ingredients']}' : t['no_recipe'], style: TextStyle(fontSize: 12.5, color: row.hasRecipe ? Colors.green.shade700 : cs.onSurfaceVariant)),
                Text('${t['sale_price']}: ${ref.money(row.priceMinor)}', style: const TextStyle(fontSize: 12.5)),
                if (row.hasRecipe) Text('${t['food_cost']}: ${ref.money(row.costMinor)}', key: ValueKey('recipe-cost-${row.label}'), style: const TextStyle(fontSize: 12.5)),
                if (m != null) Text('$m%', key: ValueKey('recipe-margin-${row.label}'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: marginColor)),
              ]),
            ]),
          ),
          OutlinedButton.icon(
            key: ValueKey('recipe-edit-${row.label}'),
            onPressed: () async {
              final ok = await showRecipeEditor(context, ref, row);
              if (ok == true) ref.invalidate(recipeRowsProvider);
            },
            icon: Icon(row.hasRecipe ? Icons.edit_outlined : Icons.add, size: 18),
            label: Text(row.hasRecipe ? t['edit'] : t['recipe_build']),
          ),
        ]),
      ),
    );
  }
}

/// The ingredient list of one menu item (or size). true = saved.
Future<bool?> showRecipeEditor(BuildContext context, WidgetRef ref, RecipeRow row) async {
  final stock = await ref.read(inventoryServiceProvider).list();
  final current = await ref.read(recipeServiceProvider).ingredients(row.productId, row.variantId);
  if (!context.mounted) return null;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecipeEditor(row: row, stock: stock, current: current),
  );
}

class _Line {
  _Line(this.item, this.unit, String qty) : qty = TextEditingController(text: qty);
  StockRow? item;
  String unit;
  final TextEditingController qty;

  int? get milli {
    final v = double.tryParse(qty.text.trim().replaceAll(',', '.'));
    final it = item;
    if (v == null || v <= 0 || it == null) return null;
    final per = recipeUnits(it.unit).firstWhere((u) => u.unit == unit, orElse: () => (unit: it.unit, perStockUnit: 1)).perStockUnit;
    return (v * 1000 / per).round();
  }

  int get costMinor {
    final m = milli, it = item;
    return m == null || it == null ? 0 : (m * it.avgCostMinor / 1000).round();
  }
}

String _plain(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

class _RecipeEditor extends ConsumerStatefulWidget {
  const _RecipeEditor({required this.row, required this.stock, required this.current});
  final RecipeRow row;
  final List<StockRow> stock;
  final List<RecipeIngredient> current;
  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  late final List<_Line> _lines = [
    for (final c in widget.current)
      _Line(widget.stock.where((s) => s.id == c.stockItemId).firstOrNull, c.unit, _plain(c.qtyMilli / 1000)),
  ];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(_Line l) async {
    final t = Strings.of(context);
    final picked = await showDialog<StockRow>(
      context: context,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, set) {
            final list = widget.stock.where((s) => s.name.toLowerCase().contains(q.toLowerCase())).toList();
            return AlertDialog(
              title: Text(t['recipe_pick']),
              content: SizedBox(
                width: 360,
                height: 380,
                child: Column(children: [
                  TextField(key: const ValueKey('rc-search'), autofocus: true, onChanged: (v) => set(() => q = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search'])),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(children: [
                      for (final s in list)
                        ListTile(
                          key: ValueKey('rc-item-${s.name}'),
                          dense: true,
                          title: Text(s.name),
                          subtitle: Text('${ref.money(s.avgCostMinor)} / ${s.unit}'),
                          onTap: () => Navigator.pop(ctx, s),
                        ),
                    ]),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    setState(() {
      l.item = picked;
      l.unit = picked.unit;
    });
  }

  void _changeUnit(_Line l, String unit) {
    final it = l.item;
    if (it == null) return;
    final units = recipeUnits(it.unit);
    double per(String u) => units.firstWhere((x) => x.unit == u).perStockUnit.toDouble();
    final v = double.tryParse(l.qty.text.trim().replaceAll(',', '.'));
    setState(() {
      if (v != null) l.qty.text = _plain(v * per(unit) / per(l.unit));
      l.unit = unit;
    });
  }

  int get _total => _lines.fold(0, (s, l) => s + l.costMinor);

  Future<void> _save() async {
    final t = Strings.of(context);
    final map = <String, int>{};
    for (final l in _lines) {
      final empty = l.item == null && l.qty.text.trim().isEmpty;
      if (empty) continue;
      final m = l.milli;
      if (l.item == null) return setState(() => _error = t['recipe_pick_first']);
      if (m == null) return setState(() => _error = t['recipe_qty_bad']);
      if (map.containsKey(l.item!.id)) return setState(() => _error = t['recipe_twice']);
      map[l.item!.id] = m;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(inventoryServiceProvider).saveRecipe(productId: widget.row.productId, variantId: widget.row.variantId, ingredientsMilli: map);
      if (mounted) Navigator.pop(context, true);
    } on PosException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final sale = widget.row.priceMinor;
    final margin = sale > 0 && _total > 0 ? ((sale - _total) * 100 / sale).round() : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t['recipe']}: ${widget.row.label}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(t['recipe_hint'], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Flexible(
          child: SingleChildScrollView(
            child: Column(children: [
              if (_lines.isEmpty) Padding(padding: const EdgeInsets.all(18), child: Text(t['recipe_empty'], key: const ValueKey('rc-empty'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))),
              for (var i = 0; i < _lines.length; i++) _lineRow(context, i),
            ]),
          ),
        ),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('rc-add'), onPressed: () => setState(() => _lines.add(_Line(null, 'pc', ''))), icon: const Icon(Icons.add), label: Text(t['recipe_add']))),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.primary.withValues(alpha: 0.35))),
          child: Row(children: [
            Expanded(child: Text(t['food_cost'], style: const TextStyle(fontWeight: FontWeight.w600))),
            if (margin != null) Padding(padding: const EdgeInsets.only(right: 12), child: Text('$margin%', key: const ValueKey('rc-margin'), style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(ref.money(_total), key: const ValueKey('rc-cost'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.primary)),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const ValueKey('rc-error'), style: TextStyle(color: cs.error))),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('rc-save'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: _busy ? null : _save, child: Text(t['save']))),
      ]),
    );
  }

  Widget _lineRow(BuildContext context, int i) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final l = _lines[i];
    final units = l.item == null ? const <({String unit, int perStockUnit})>[] : recipeUnits(l.item!.unit);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: InkWell(
            key: ValueKey('rc-pick-$i'),
            onTap: () => _pick(l),
            child: InputDecorator(
              decoration: InputDecoration(isDense: true, labelText: t['ingredient']),
              child: Text(l.item?.name ?? t['recipe_pick'], overflow: TextOverflow.ellipsis, style: TextStyle(color: l.item == null ? cs.onSurfaceVariant : null)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            key: ValueKey('rc-qty-$i'),
            controller: l.qty,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(isDense: true, labelText: t['qty']),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 52,
          child: units.length > 1
              ? DropdownButton<String>(key: ValueKey('rc-unit-$i'), value: l.unit, isDense: true, underline: const SizedBox.shrink(), items: [for (final u in units) DropdownMenuItem(value: u.unit, child: Text(u.unit))], onChanged: (v) => _changeUnit(l, v ?? l.unit))
              : Text(l.item?.unit ?? '', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        SizedBox(width: 62, child: Text(ref.money(l.costMinor, symbol: false), key: ValueKey('rc-line-$i'), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        IconButton(key: ValueKey('rc-del-$i'), visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, color: cs.error), onPressed: () => setState(() => _lines.removeAt(i).qty.dispose())),
      ]),
    );
  }
}
