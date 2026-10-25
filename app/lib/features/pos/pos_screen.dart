import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart' show BrandColorsX, contrastRatio;
import '../common/menu_image.dart';
import '../../data/menu_service.dart';
import '../../data/queries.dart';
import 'cart.dart';
import 'options_sheet.dart';
import 'weight_dialog.dart';
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
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: FilledButton(
            key: const ValueKey('open-cart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const FractionallySizedBox(heightFactor: 0.92, child: SafeArea(top: false, child: CartPanel(inSheet: true))),
            ),
            child: Row(children: [
              Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.shopping_bag_outlined)),
              const SizedBox(width: 12),
              Expanded(child: Text('${t['view_cart']} ($count)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text(ref.money(cart.bill.totalMinor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(width: 8),
              const Icon(Icons.shopping_cart_outlined),
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
    final compact = ref.watch(posLayoutProvider) == 'compact';
    final products = ref.watch(productsProvider(ProductFilter(categoryId: categoryId, search: search)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(key: const ValueKey('search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search_items'], isDense: true), onChanged: onSearch),
      ),
      SizedBox(
        height: 96,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), children: [
          _CategoryTile(key: const ValueKey('cat-all'), label: t['all'], icon: Icons.grid_view_rounded, selected: categoryId == null, onTap: () => onCategory(null)),
          for (final c in cats)
            _CategoryTile(key: ValueKey('cat-${c.name}'), label: c.name, imagePath: c.imagePath, selected: categoryId == c.id, onTap: () => onCategory(c.id)),
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
                  gridDelegate: compact
                      ? const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 130)
                      : const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 220),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ProductTile(list[i], compact: compact),
                ),
        ),
      ),
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({super.key, required this.label, required this.selected, required this.onTap, this.imagePath, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? imagePath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: selected ? context.accent : scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? context.accent : scheme.outlineVariant),
              ),
              child: icon != null
                  ? Icon(icon, color: selected ? context.onAccent : scheme.primary, size: 28)
                  : MenuImage(path: imagePath, name: label, radius: 13, iconSize: 26),
            ),
            const SizedBox(height: 5),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? context.accent : null)),
          ]),
        ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile(this.p, {this.compact = false});
  final MenuProduct p;

  /// Text-only tile: more items on screen and faster on old phones.
  final bool compact;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final opts = await ref.read(menuServiceProvider).optionsFor(p.id);
    if (opts.isEmpty) {
      if (const {'kg', 'g', 'l', 'ml'}.contains(p.unit)) {
        // sold by weight: ask for it (grams or kg) instead of guessing
        if (!context.mounted) return;
        final q = await showWeightDialog(context, ref, name: p.name, unit: p.unit, unitPriceMinor: p.priceMinor);
        if (q != null) ref.read(cartProvider.notifier).addWeighed(p, q);
        return;
      }
      ref.read(cartProvider.notifier).add(p);
    } else if (context.mounted) {
      final item = await showOptionsSheet(context, ref, p, opts);
      if (item != null) ref.read(cartProvider.notifier).addConfigured(item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final inCartMilli = ref.watch(cartProvider.select((c) => c.items.where((i) => i.productId == p.id).fold<int>(0, (s, i) => s + i.qtyMilli)));
    final inCart = inCartMilli == 0 ? null : (inCartMilli % 1000 == 0 ? '${inCartMilli ~/ 1000}' : (inCartMilli / 1000).toStringAsFixed(2));
    return Opacity(
      opacity: p.available ? 1 : 0.45,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: inCart != null ? scheme.primary : scheme.outlineVariant, width: inCart != null ? 2 : 1)),
        child: InkWell(
          key: ValueKey('product-${p.name}'),
          onTap: p.available ? () => _add(context, ref) : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: compact
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(width: 44, height: 44, child: MenuImage(path: p.imagePath ?? p.categoryImagePath, name: '${p.name} ${p.categoryName ?? ''}', radius: 10, iconSize: 22)),
                      const Spacer(),
                      if (inCart != null)
                        Container(
                          key: ValueKey('in-cart-${p.name}'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text('× $inCart', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2))),
                    Align(alignment: AlignmentDirectional.centerStart, child: PriceBadge(text: ref.money(p.priceMinor), suffix: p.unit == 'pc' ? null : '/ ${p.unit}')),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  MenuImage(path: p.imagePath ?? p.categoryImagePath, name: p.categoryName == null ? p.name : '${p.name} ${p.categoryName}', radius: 12, iconSize: 40),
                  if (inCart != null)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: Container(
                        key: ValueKey('in-cart-${p.name}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                        child: Text('× $inCart', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ),
                  PositionedDirectional(bottom: 6, start: 6, child: PriceBadge(text: ref.money(p.priceMinor), suffix: p.unit == 'pc' ? null : '/ ${p.unit}')),
                  if (!p.available)
                    Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), color: Colors.black54, child: Text(Strings.of(context)['unavailable'], style: const TextStyle(color: Colors.white, fontSize: 12)))),
                ]),
              ),
              const SizedBox(height: 8),
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: FilledButton.icon(
                  key: ValueKey('add-${p.name}'),
                  style: FilledButton.styleFrom(backgroundColor: context.accent, foregroundColor: context.onAccent, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: p.available ? () => _add(context, ref) : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(Strings.of(context)['add'], style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The price of an item as a compact red badge with white bold text and a thin white outline: readable at a glance on
/// a picture or a plain tile, and it shrinks instead of overflowing on a narrow tile.
class PriceBadge extends StatelessWidget {
  const PriceBadge({super.key, required this.text, this.suffix});
  final String text;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('price-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: context.priceColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(suffix == null ? text : '$text $suffix', maxLines: 1, style: TextStyle(color: contrastRatio(context.priceColor, Colors.white) >= contrastRatio(context.priceColor, Colors.black) ? Colors.white : Colors.black, fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.15)),
      ),
    );
  }
}
