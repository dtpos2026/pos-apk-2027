import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/bill_ops.dart';
import '../../data/pos_service.dart';
import '../../data/table_service.dart';
import '../../domain/money.dart';
import '../common/dialogs.dart';
import '../pos/cart.dart';

/// Merge this table's bill into another table's bill. Returns true when something changed.
Future<bool> showMergeBill(BuildContext context, WidgetRef ref, TableInfo from) async {
  final t = Strings.of(context);
  final others = (await ref.read(tableServiceProvider).tables()).where((x) => x.orderId != null && x.orderId != from.orderId).toList();
  if (!context.mounted) return false;
  if (others.isEmpty) {
    showMessage(context, t['merge_none']);
    return false;
  }
  final into = await showDialog<TableInfo>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${t['merge_bill']}: ${from.label}'),
      content: SizedBox(
        width: 320,
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t['merge_into'])),
          for (final o in others)
            ListTile(
              key: ValueKey('merge-into-${o.label}'),
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(o.label),
              trailing: o.orderTotalMinor == null ? null : Text(ref.money(o.orderTotalMinor!), style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, o),
            ),
        ]),
      ),
      actions: [DialogActions([TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel']))])],
    ),
  );
  if (into == null || !context.mounted) return false;
  try {
    await ref.read(billOpsProvider).merge(fromOrderId: from.orderId!, intoOrderId: into.orderId!, staffId: ref.read(sessionProvider)!.staffId);
    await ref.read(cartProvider.notifier).reloadAfterBillChange();
    if (context.mounted) showMessage(context, t['bill_merged']);
    return true;
  } on PosException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Split this table's bill: pick items (and how many) and where they go. Returns true when something changed.
Future<bool> showSplitBill(BuildContext context, WidgetRef ref, TableInfo from) async {
  final t = Strings.of(context);
  final draft = await ref.read(posServiceProvider).loadDraft(from.orderId!);
  final tables = await ref.read(tableServiceProvider).tables();
  if (draft == null || !context.mounted) return false;
  final result = await showDialog<bool>(context: context, builder: (_) => _SplitDialog(from: from, draft: draft, tables: tables));
  if (result == true && context.mounted) showMessage(context, t['bill_split_done']);
  return result == true;
}

class _SplitDialog extends ConsumerStatefulWidget {
  const _SplitDialog({required this.from, required this.draft, required this.tables});
  final TableInfo from;
  final DraftOrder draft;
  final List<TableInfo> tables;
  @override
  ConsumerState<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends ConsumerState<_SplitDialog> {
  late final List<int> _move = List.filled(widget.draft.items.length, 0);
  String _dest = 'same';
  bool _busy = false;
  String? _error;

  bool _whole(CartItem i) => i.qtyMilli % 1000 != 0; // kg / weight lines: all or nothing
  int _step(CartItem i) => _whole(i) ? i.qtyMilli : 1000;

  Future<void> _go() async {
    final t = Strings.of(context);
    final picks = [for (var i = 0; i < _move.length; i++) if (_move[i] > 0) MovePick(i, _move[i])];
    if (picks.isEmpty) {
      setState(() => _error = t['split_pick_items']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(billOpsProvider).move(
            fromOrderId: widget.from.orderId!,
            picks: picks,
            toOrderId: _dest.startsWith('bill:') ? _dest.substring(5) : null,
            toTableId: _dest == 'same' ? widget.from.id : (_dest.startsWith('table:') ? _dest.substring(6) : null),
            staffId: ref.read(sessionProvider)!.staffId,
          );
      await ref.read(cartProvider.notifier).reloadAfterBillChange();
      if (mounted) Navigator.pop(context, true);
    } on PosException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final items = widget.draft.items;
    final free = widget.tables.where((x) => x.status == 'free').toList();
    final bills = widget.tables.where((x) => x.orderId != null && x.orderId != widget.from.orderId).toList();
    return AlertDialog(
      title: Text('${t['split_bill']}: ${widget.from.label}'),
      scrollable: true,
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t['split_pick_hint'], style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text('${formatQty(items[i].qtyMilli)} x ${items[i].name}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(key: ValueKey('split-minus-$i'), visualDensity: VisualDensity.compact, onPressed: _move[i] <= 0 ? null : () => setState(() => _move[i] = (_move[i] - _step(items[i])).clamp(0, items[i].qtyMilli)), icon: const Icon(Icons.remove_circle_outline)),
                SizedBox(width: 38, child: Text(formatQty(_move[i]), key: ValueKey('split-qty-$i'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton(key: ValueKey('split-plus-$i'), visualDensity: VisualDensity.compact, onPressed: _move[i] >= items[i].qtyMilli ? null : () => setState(() => _move[i] = (_move[i] + _step(items[i])).clamp(0, items[i].qtyMilli)), icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
          const Divider(height: 20),
          Text(t['move_to'], style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const ValueKey('split-dest'),
            initialValue: _dest,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              DropdownMenuItem(value: 'same', child: Text('${t['new_bill_same_table']} (${widget.from.label})')),
              for (final f in free) DropdownMenuItem(value: 'table:${f.id}', child: Text('${t['new_bill_on']} ${f.label}')),
              for (final b in bills) DropdownMenuItem(value: 'bill:${b.orderId}', child: Text('${t['existing_bill']} ${b.label}')),
            ],
            onChanged: (v) => setState(() => _dest = v ?? 'same'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const ValueKey('split-error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
      actions: [
        DialogActions([
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t['cancel'])),
          FilledButton(key: const ValueKey('split-ok'), onPressed: _busy ? null : _go, child: Text(t['split_bill'])),
        ]),
      ],
    );
  }
}
