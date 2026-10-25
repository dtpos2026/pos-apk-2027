import 'pos_service.dart';
import 'db_helper.dart';

/// One line of a bill and how much of it to move to another bill.
class MovePick {
  const MovePick(this.index, this.qtyMilli);

  /// Position of the line in the bill (as [PosService.loadDraft] lists it).
  final int index;
  final int qtyMilli;
}

/// Merging bills, splitting a bill and moving items between bills, for an order that is not paid yet.
/// Money stays correct: every affected bill is re-priced through the normal bill calculation, nothing is deleted that the
/// kitchen has seen, and each change is written to the audit log.
class BillOps {
  BillOps(this.h, this.pos);
  final DbHelper h;
  final PosService pos;

  static const _open = "('draft','held','new','preparing','ready','served')";

  /// Puts every item of [fromOrderId] on [intoOrderId] and retires the first bill. Equal lines are added together.
  Future<void> merge({required String fromOrderId, required String intoOrderId, required String staffId}) => h.db.transaction(() async {
        if (fromOrderId == intoOrderId) throw PosException('same_bill', 'Pick a different bill to merge with');
        final from = await pos.loadDraft(fromOrderId);
        final into = await pos.loadDraft(intoOrderId);
        if (from == null || into == null) throw PosException('not_editable', 'Only unpaid bills can be merged');
        final merged = _combine([...into.items, ...from.items]);
        await pos.saveDraft(
          DraftOrder(
            id: intoOrderId,
            orderType: into.orderType,
            items: merged,
            config: into.config,
            tableId: into.tableId,
            customerId: into.customerId ?? from.customerId,
            waiterId: into.waiterId,
            guests: into.guests,
            held: into.held,
            deliveryAddress: into.deliveryAddress ?? from.deliveryAddress,
          ),
          staffId: staffId,
        );
        await _retire(fromOrderId, 'Merged into another bill');
        await h.audit('bill.merge', staffId: staffId, entity: 'order', entityId: intoOrderId, before: {'from': fromOrderId}, after: {'items': merged.length});
      });

  /// Moves part (or all) of some lines of [fromOrderId] to another bill: an existing one ([toOrderId]) or a new one, optionally on
  /// [toTableId] (a free table). Returns the id of the bill that received the items.
  Future<String> move({required String fromOrderId, required List<MovePick> picks, String? toOrderId, String? toTableId, required String staffId}) => h.db.transaction(() async {
        if (picks.isEmpty) throw PosException('nothing_picked', 'Pick at least one item to move');
        if (toOrderId != null && toOrderId == fromOrderId) throw PosException('same_bill', 'Pick a different bill');
        final from = await pos.loadDraft(fromOrderId);
        if (from == null) throw PosException('not_editable', 'Only unpaid bills can be split');
        final stay = <CartItem>[];
        final go = <CartItem>[];
        final byIndex = {for (final p in picks) p.index: p.qtyMilli};
        for (var i = 0; i < from.items.length; i++) {
          final it = from.items[i];
          final q = byIndex[i] ?? 0;
          if (q < 0 || q > it.qtyMilli) throw PosException('bad_qty', 'You cannot move more than the bill has');
          if (q == 0) {
            stay.add(it);
          } else if (q == it.qtyMilli) {
            go.add(it);
          } else {
            final rest = it.qtyMilli - q;
            // the discount follows the quantity; the kitchen count stays with the part that was cooked
            final moveDisc = (it.lineDiscountMinor * q / it.qtyMilli).round();
            final keepKot = it.kotSentMilli < rest ? it.kotSentMilli : rest;
            stay.add(_copy(it, qty: rest, discount: it.lineDiscountMinor - moveDisc, kot: keepKot));
            go.add(_copy(it, qty: q, discount: moveDisc, kot: it.kotSentMilli - keepKot));
          }
        }
        if (go.isEmpty) throw PosException('nothing_picked', 'Pick at least one item to move');

        late String target;
        if (toOrderId != null) {
          final to = await pos.loadDraft(toOrderId);
          if (to == null) throw PosException('not_editable', 'Only unpaid bills can receive items');
          target = toOrderId;
          await pos.saveDraft(
            DraftOrder(id: to.id, orderType: to.orderType, items: _combine([...to.items, ...go]), config: to.config, tableId: to.tableId, customerId: to.customerId, waiterId: to.waiterId, guests: to.guests, held: to.held, deliveryAddress: to.deliveryAddress),
            staffId: staffId,
          );
        } else {
          if (toTableId != null) {
            final t = await h.one('SELECT status FROM dining_table WHERE id = ? AND deleted_at IS NULL', [toTableId]);
            if (t == null) throw PosException('not_found', 'Table not found');
            if (t['status'] != 'free' && toTableId != from.tableId) throw PosException('table_busy', 'The table is not free');
          }
          target = await pos.saveDraft(
            DraftOrder(orderType: toTableId != null ? 'dine_in' : from.orderType, items: go, tableId: toTableId, customerId: from.customerId, waiterId: from.waiterId, deliveryAddress: from.deliveryAddress),
            staffId: staffId,
          );
          // items the kitchen already has keep that status on the new bill
          if (go.any((x) => x.kotSentMilli > 0)) {
            final st = await h.one('SELECT status FROM "order" WHERE id = ?', [fromOrderId]);
            final s = st?['status'] as String?;
            if (s != null && const {'new', 'preparing', 'ready', 'served'}.contains(s)) {
              await h.exec('UPDATE "order" SET status=?, updated_at=?, version=version+1 WHERE id=?', [s, h.ts, target]);
            }
          }
        }

        if (stay.isEmpty) {
          await _retire(fromOrderId, 'All items moved to another bill');
        } else {
          await pos.saveDraft(
            DraftOrder(id: fromOrderId, orderType: from.orderType, items: stay, config: from.config, tableId: from.tableId, customerId: from.customerId, waiterId: from.waiterId, guests: from.guests, held: from.held, deliveryAddress: from.deliveryAddress),
            staffId: staffId,
          );
        }
        await h.audit('bill.split', staffId: staffId, entity: 'order', entityId: fromOrderId, before: {'items': from.items.length}, after: {'to': target, 'moved': go.length});
        return target;
      });

  CartItem _copy(CartItem it, {required int qty, required int discount, required int kot}) => CartItem(
        productId: it.productId,
        variantId: it.variantId,
        name: it.name,
        qtyMilli: qty,
        unitPriceMinor: it.unitPriceMinor,
        modifiers: it.modifiers,
        lineDiscountMinor: discount,
        taxRateBp: it.taxRateBp,
        taxInclusive: it.taxInclusive,
        note: it.note,
        station: it.station,
        kotSentMilli: kot,
      );

  /// Equal lines (same item, size, price, modifiers, note, no discount) become one line with the quantities added.
  List<CartItem> _combine(List<CartItem> items) {
    final out = <CartItem>[];
    final index = <String, int>{};
    for (final it in items) {
      if (it.lineDiscountMinor != 0) {
        out.add(it);
        continue;
      }
      final key = [it.productId, it.variantId, it.unitPriceMinor, it.note ?? '', it.station ?? '', it.taxRateBp, it.taxInclusive, for (final m in it.modifiers) '${m.optionId}:${m.name}:${m.priceMinor}'].join('|');
      final at = index[key];
      if (at == null) {
        index[key] = out.length;
        out.add(it);
      } else {
        final a = out[at];
        out[at] = _copy(a, qty: a.qtyMilli + it.qtyMilli, discount: 0, kot: a.kotSentMilli + it.kotSentMilli);
      }
    }
    return out;
  }

  /// A bill whose items were all moved: removed when the kitchen never saw it, otherwise kept as 'cancelled' (never a sale) so the
  /// kitchen history stays complete. Its table is freed when nothing else is open on it.
  Future<void> _retire(String orderId, String note) async {
    final row = await h.one('SELECT table_id FROM "order" WHERE id = ?', [orderId]);
    final seen = await h.one('SELECT 1 AS x FROM kitchen_event WHERE order_id = ? LIMIT 1', [orderId]);
    await h.exec('DELETE FROM order_item_modifier WHERE order_item_id IN (SELECT id FROM order_item WHERE order_id = ?)', [orderId]);
    await h.exec('DELETE FROM order_item WHERE order_id = ?', [orderId]);
    if (seen == null) {
      await h.exec('DELETE FROM "order" WHERE id = ?', [orderId]);
    } else {
      await h.exec("UPDATE \"order\" SET status='cancelled', note=?, subtotal_minor=0, discount_minor=0, service_charge_minor=0, delivery_charge_minor=0, tax_minor=0, tip_minor=0, rounding_minor=0, total_minor=0, updated_at=?, version=version+1 WHERE id=?", [note, h.ts, orderId]);
    }
    final table = row?['table_id'] as String?;
    if (table != null) {
      await h.exec("UPDATE dining_table SET status='free', updated_at=?, version=version+1 WHERE id=? AND NOT EXISTS (SELECT 1 FROM \"order\" WHERE table_id = ? AND status IN $_open)", [h.ts, table, table]);
    }
  }
}
