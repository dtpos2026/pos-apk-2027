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
        'occupied' => Colors.orange.shade700,
        'reserved' => Colors.blue.shade600,
        'cleaning' => Colors.grey.shade600,
        _ => Colors.green.shade600,
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
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(s['all']), selected: _area == null, onSelected: (_) => setState(() => _area = null))),
            for (final a in areas) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(a.name), selected: _area == a.id, onSelected: (_) => setState(() => _area = a.id))),
            if (canManage) ActionChip(key: const ValueKey('add-area'), avatar: const Icon(Icons.add, size: 18), label: Text(s['add_area']), onPressed: _addArea),
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
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final t = list[i];
                      final c = _color(context, t.status);
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c, width: 2)),
                        child: InkWell(
                          key: ValueKey('table-${t.label}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: t.status == 'free' || t.status == 'occupied' ? () => _open(t) : () => _menu(t),
                          onLongPress: () => _menu(t),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [Expanded(child: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))), Icon(Icons.circle, size: 12, color: c)]),
                              Text('${t.seats} ${s['seats']}', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              const Spacer(),
                              Text(s[t.status], style: TextStyle(color: c, fontWeight: FontWeight.w700)),
                              if (t.orderTotalMinor != null) Text(ref.money(t.orderTotalMinor!), key: ValueKey('table-total-${t.label}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              if (t.waiterName != null) Text(t.waiterName!, style: const TextStyle(fontSize: 12)),
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
