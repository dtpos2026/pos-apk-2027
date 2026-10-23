import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/menu_service.dart';
import '../../data/queries.dart';
import 'cart.dart';
import 'options_sheet.dart';
import 'cart_panel.dart';
import 'shift_dialogs.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String? _categoryId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(cartProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final shift = ref.watch(shiftProvider);
    if (shift == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_clock, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(t['shift_required'], style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton.icon(key: const ValueKey('open-shift'), onPressed: () => openShiftDialog(context, ref), icon: const Icon(Icons.play_arrow_rounded), label: Text(t['open_shift'])),
            ]),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final menu = _MenuPanel(
      categoryId: _categoryId,
      search: _search,
      onCategory: (c) => setState(() => _categoryId = c),
      onSearch: (s) => setState(() => _search = s),
    );
    if (wide) {
      return Row(children: [
        Expanded(flex: 62, child: menu),
        const VerticalDivider(width: 1),
        const Expanded(flex: 38, child: CartPanel()),
      ]);
    }
    return Column(children: [
      Expanded(child: menu),
      const _CartBar(),
    ]);
  }
}

class _CartBar extends ConsumerWidget {
  const _CartBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cart = ref.watch(cartProvider);
    final count = cart.items.fold<int>(0, (s, i) => s + (i.qtyMilli / 1000).ceil());
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton(
            key: const ValueKey('open-cart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: CartPanel(inSheet: true)),
            ),
            child: Row(children: [
              Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.shopping_bag_outlined)),
              const SizedBox(width: 12),
              Expanded(child: Text(t['current_order'])),
              Text(ref.money(cart.bill.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends ConsumerWidget {
  const _MenuPanel({required this.categoryId, required this.search, required this.onCategory, required this.onSearch});
  final String? categoryId;
  final String search;
  final void Function(String?) onCategory;
  final void Function(String) onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final products = ref.watch(productsProvider(ProductFilter(categoryId: categoryId, search: search)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(key: const ValueKey('search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search_items'], isDense: true), onChanged: onSearch),
      ),
      SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(t['all']), selected: categoryId == null, onSelected: (_) => onCategory(null))),
          for (final c in cats) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(c.name), selected: categoryId == c.id, onSelected: (_) => onCategory(c.id))),
        ]),
      ),
      Expanded(
        child: products.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) => list.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t['no_items'], textAlign: TextAlign.center)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ProductTile(list[i]),
                ),
        ),
      ),
    ]);
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile(this.p);
  final MenuProduct p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: p.available ? 1 : 0.45,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('product-${p.name}'),
          onTap: p.available
              ? () async {
                  final opts = await ref.read(menuServiceProvider).optionsFor(p.id);
                  if (opts.isEmpty) {
                    ref.read(cartProvider.notifier).add(p);
                  } else if (context.mounted) {
                    final item = await showOptionsSheet(context, ref, p, opts);
                    if (item != null) ref.read(cartProvider.notifier).addConfigured(item);
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(p.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              Wrap(crossAxisAlignment: WrapCrossAlignment.end, children: [
                Text(ref.money(p.priceMinor, symbol: false), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 16)),
                if (p.unit != 'pc') Text(' / ${p.unit}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
