import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/pos_service.dart';
import '../../data/table_service.dart';
import '../common/dialogs.dart';
import '../pos/cart.dart';

final _areasProvider = FutureProvider.autoDispose<List<AreaRow>>((ref) => ref.watch(tableServiceProvider).areas());
final _tablesProvider = FutureProvider.autoDispose.family<List<TableInfo>, String?>((ref, area) => ref.watch(tableServiceProvider).tables(areaId: area));

/// Dine-in floor plan: pick a table to start or continue its order; managers can edit the floor.
class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});
  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  String? _area;

  void _refresh() {
    ref.invalidate(_areasProvider);
    ref.invalidate(_tablesProvider);
  }

  Color _color(BuildContext c, String status) => switch (status) {
        'occupied' => const Color(0xFFE8590C),
        'reserved' => const Color(0xFF5B3CC4),
        'cleaning' => const Color(0xFFC28A00),
        _ => const Color(0xFF2B8A3E),
      };

  Future<void> _open(TableInfo t) async {
    final shift = ref.read(shiftProvider);
    await ref.read(cartProvider.notifier).openTable(t.id, orderId: t.orderId);
    if (shift == null && mounted) showMessage(context, Strings.of(context)['shift_required']);
    ref.read(shellTabProvider.notifier).go('pos');
  }

  Future<void> _menu(TableInfo t) async {
    final s = Strings.of(context);
    final canManage = ref.read(sessionProvider)!.can('menu.manage');
    final svc = ref.read(tableServiceProvider);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (t.orderId == null) ListTile(key: const ValueKey('act-free'), leading: const Icon(Icons.check_circle_outline), title: Text(s['mark_free']), onTap: () => Navigator.pop(ctx, 'free')),
          if (t.orderId == null) ListTile(key: const ValueKey('act-reserve'), leading: const Icon(Icons.bookmark_outline), title: Text(s['mark_reserved']), onTap: () => Navigator.pop(ctx, 'reserved')),
          if (t.orderId == null) ListTile(leading: const Icon(Icons.cleaning_services_outlined), title: Text(s['mark_cleaning']), onTap: () => Navigator.pop(ctx, 'cleaning')),
          if (t.orderId != null) ListTile(key: const ValueKey('act-transfer'), leading: const Icon(Icons.swap_horiz), title: Text(s['transfer']), onTap: () => Navigator.pop(ctx, 'transfer')),
          if (canManage && t.orderId == null) ListTile(key: const ValueKey('act-delete'), leading: const Icon(Icons.delete_outline), title: Text(s['delete']), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'delete') {
        await svc.deleteTable(t.id);
      } else if (choice == 'transfer') {
        final free = (await svc.tables()).where((x) => x.status == 'free').toList();
        if (!mounted) return;
        final to = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(title: Text(s['transfer']), children: [for (final f in free) SimpleDialogOption(key: ValueKey('to-${f.label}'), onPressed: () => Navigator.pop(ctx, f.id), child: Text(f.label))]),
        );
        if (to != null) {
          await svc.transfer(orderId: t.orderId!, toTableId: to, staffId: ref.read(sessionProvider)!.staffId);
          if (ref.read(cartProvider).draftId == t.orderId) ref.read(cartProvider.notifier).setTable(to);
        }
      } else {
        await svc.setStatus(t.id, choice);
      }
    } on PosException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
    _refresh();
  }

  Future<void> _addArea() async {
    final s = Strings.of(context);
    final v = await showFormDialog(context, title: s['add_area'], fields: [FieldSpec('name', s['area_name'])]);
    if (v == null) return;
    await ref.read(tableServiceProvider).saveArea(name: v['name']!);
    _refresh();
  }

  Future<void> _addTable() async {
    final s = Strings.of(context);
    final areas = await ref.read(tableServiceProvider).areas();
    if (areas.isEmpty) {
      await _addArea();
      return;
    }
    if (!mounted) return;
    var area = _area ?? areas.first.id;
    final v = await showFormDialog(
      context,
      title: s['add_table'],
      fields: [FieldSpec('label', s['table_label']), FieldSpec('seats', s['seats'], initial: '4', number: true)],
      extra: (set) => DropdownButtonFormField<String>(initialValue: area, items: [for (final a in areas) DropdownMenuItem(value: a.id, child: Text(a.name))], onChanged: (x) => set(() => area = x ?? area)),
      validate: (v) async {
        try {
          await ref.read(tableServiceProvider).saveTable(areaId: area, label: v['label']!, seats: int.tryParse(v['seats']!) ?? 4);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final canManage = ref.watch(sessionProvider)!.can('menu.manage');
    final areas = ref.watch(_areasProvider).value ?? const [];
    final tables = ref.watch(_tablesProvider(_area));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage ? FloatingActionButton.extended(key: const ValueKey('add-table'), onPressed: _addTable, icon: const Icon(Icons.add), label: Text(s['add_table'])) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _AreaTab(label: s['all'], selected: _area == null, onTap: () => setState(() => _area = null)),
              for (final a in areas) _AreaTab(label: a.name, selected: _area == a.id, onTap: () => setState(() => _area = a.id)),
              if (canManage) Padding(padding: const EdgeInsets.only(left: 4), child: ActionChip(key: const ValueKey('add-area'), avatar: const Icon(Icons.add, size: 16), label: Text(s['add_area']), onPressed: _addArea, visualDensity: VisualDensity.compact)),
            ]),
          ),
        ),
        if (tables.value != null && tables.value!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Row(children: [
              for (final st in const ['occupied', 'free', 'cleaning', 'reserved'])
                Expanded(
                  child: Container(
                    key: ValueKey('count-$st'),
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: _color(context, st).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      Text('${tables.value!.where((x) => x.status == st).length}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _color(context, st))),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.circle, size: 8, color: _color(context, st)),
                        const SizedBox(width: 4),
                        Flexible(child: Text(s[st], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: tables.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s['no_tables'], textAlign: TextAlign.center)))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 142),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final t = list[i];
                      final c = _color(context, t.status);
                      return Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.withValues(alpha: 0.55), width: 1.4)),
                        child: InkWell(
                          key: ValueKey('table-${t.label}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: t.status == 'free' || t.status == 'occupied' ? () => _open(t) : () => _menu(t),
                          onLongPress: () => _menu(t),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                            child: Column(children: [
                              SizedBox(width: 74, height: 56, child: CustomPaint(painter: TableSeatsPainter(seats: t.seats, color: c))),
                              const SizedBox(height: 4),
                              Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                              Text(t.orderTotalMinor != null ? ref.money(t.orderTotalMinor!) : '${t.seats} ${s['seats']}', key: t.orderTotalMinor != null ? ValueKey('table-total-${t.label}') : null, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: t.orderTotalMinor != null ? FontWeight.w800 : FontWeight.w500, color: t.orderTotalMinor != null ? c : Theme.of(context).colorScheme.onSurfaceVariant)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                child: Text(t.waiterName != null && t.status == 'occupied' ? t.waiterName! : s[t.status], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11.5)),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class _AreaTab extends StatelessWidget {
  const _AreaTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? cs.onPrimary : cs.onSurfaceVariant)),
      ),
    );
  }
}

/// A table seen from above with its chairs (2, 4, 6 or more seats), coloured by status, like a restaurant floor plan.
class TableSeatsPainter extends CustomPainter {
  const TableSeatsPainter({required this.seats, required this.color});
  final int seats;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final chair = Paint()..color = color.withValues(alpha: 0.55);
    final w = size.width, h = size.height;
    final table = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.24, w * 0.72, h * 0.52), const Radius.circular(8));
    final n = seats.clamp(1, 12);
    final top = (n + 1) ~/ 2, bottom = n - top;
    void row(int count, double y) {
      for (var i = 0; i < count; i++) {
        final cx = w * (0.14 + 0.72 * (i + 0.5) / (count == 0 ? 1 : count));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, y), width: (w * 0.72 / (count < 3 ? 3 : count)) * 0.8, height: h * 0.16), const Radius.circular(4)), chair);
      }
    }

    row(top, h * 0.1);
    row(bottom, h * 0.9);
    canvas.drawRRect(table, fill);
  }

  @override
  bool shouldRepaint(TableSeatsPainter old) => old.seats != seats || old.color != color;
}
