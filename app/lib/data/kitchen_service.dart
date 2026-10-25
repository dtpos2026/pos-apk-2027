import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class KitchenLine {
  const KitchenLine(this.name, this.qtyMilli, this.note, this.modifiers);
  final String name;
  final int qtyMilli;
  final String? note;
  final List<String> modifiers;
}

class KitchenTicket {
  const KitchenTicket({this.paid = false, this.sentBy, required this.orderId, required this.label, required this.status, required this.sentAt, required this.lines, this.tableLabel, this.orderType = 'counter', this.token});
  final String orderId;
  final String label;

  /// new | preparing | ready | served
  final String status;

  /// The bill is already paid (the kitchen still has to prepare it, or it is done and kept as history).
  final bool paid;
  final String? sentBy;
  final int sentAt;
  final String? tableLabel;
  final String orderType;
  final String? token;
  final List<KitchenLine> lines;
}

/// The on-screen kitchen board: orders that were sent to the kitchen and are not paid yet.
class KitchenService {
  KitchenService(this.h);
  final DbHelper h;

  static const flow = ['new', 'preparing', 'ready'];

  /// The kitchen state of every order is its latest row in the append-only kitchen history, so it does not depend on
  /// whether the bill was paid, voided or cancelled in the meantime. [status] is one of new / preparing / ready / served.
  /// Orders called off (cancelled / void / refunded) leave the board.
  Future<List<KitchenTicket>> tickets({String status = 'new'}) async {
    final startOfDay = DateTime.fromMillisecondsSinceEpoch(h.ts);
    final since = status == 'served' ? DateTime(startOfDay.year, startOfDay.month, startOfDay.day).millisecondsSinceEpoch : 0;
    final orders = await h.q('''SELECT o.id, o.invoice_no, o.status AS ostatus, o.order_type, t.label AS table_label, e.at AS since,
        (SELECT MIN(kot_sent_at) FROM order_item i WHERE i.order_id = o.id AND i.kot_sent_at IS NOT NULL) AS sent
      FROM kitchen_event e JOIN "order" o ON o.id = e.order_id LEFT JOIN dining_table t ON t.id = o.table_id
      WHERE e.id = (SELECT k.id FROM kitchen_event k WHERE k.order_id = e.order_id ORDER BY k.at DESC, k.rowid DESC LIMIT 1)
        AND e.status = ? AND e.at >= ? AND o.status NOT IN ('cancelled','void','refunded','draft')
      ORDER BY e.at''', [status, since]);
    final out = <KitchenTicket>[];
    for (final o in orders) {
      final items = await h.q("SELECT id, name, qty_milli, note FROM order_item WHERE order_id = ? AND status = 'active' AND kot_sent_at IS NOT NULL ORDER BY rowid", [o['id']]);
      final lines = <KitchenLine>[];
      for (final i in items) {
        final mods = await h.q('SELECT name FROM order_item_modifier WHERE order_item_id = ?', [i['id']]);
        lines.add(KitchenLine(i['name'] as String, i['qty_milli'] as int, i['note'] as String?, [for (final m in mods) m['name'] as String]));
      }
      final id = o['id'] as String;
      out.add(KitchenTicket(
        orderId: id,
        label: (o['invoice_no'] as String?) ?? '#${id.substring(0, 4).toUpperCase()}',
        status: status,
        paid: o['ostatus'] == 'paid',
        sentAt: (o['since'] as int?) ?? (o['sent'] as int? ?? 0),
        tableLabel: o['table_label'] as String?,
        orderType: o['order_type'] as String,
        lines: lines,
      ));
    }
    return out;
  }

  /// How many orders are waiting in each state (for the tab counters and the "ready" badge).
  Future<Map<String, int>> counts() async {
    final out = {for (final s in [...flow, 'served']) s: 0};
    for (final s in out.keys.toList()) {
      out[s] = (await tickets(status: s)).length;
    }
    return out;
  }

  /// new -> preparing -> ready -> served (completed). Each step is recorded in the kitchen history; the bill's own status is
  /// only touched while it is still unpaid.
  Future<void> advance(String orderId, {String? staffId}) async {
    final r = await h.one('SELECT status FROM kitchen_event WHERE order_id = ? ORDER BY at DESC, rowid DESC LIMIT 1', [orderId]);
    if (r == null) throw PosException('not_in_kitchen', 'The order is not in the kitchen');
    final i = flow.indexOf(r['status'] as String);
    if (i < 0) throw PosException('already_served', 'This order is already completed');
    final next = i + 1 < flow.length ? flow[i + 1] : 'served';
    await h.db.transaction(() async {
      await h.exec('INSERT INTO kitchen_event(id, order_id, status, at, staff_id) VALUES (?,?,?,?,?)', [h.id, orderId, next, h.ts, staffId]);
      await h.exec("UPDATE \"order\" SET status = ?, updated_at = ?, version = version + 1 WHERE id = ? AND status IN ('new','preparing','ready','served')", [next, h.ts, orderId]);
      await _followInDelivery(orderId, next, staffId);
    });
  }

  /// A delivery / online order follows its kitchen ticket: Preparing and Ready in the kitchen move the delivery status the same way, so the
  /// cashier never has to tap the same step twice. It only ever moves forward, and never past Ready (the rider / hand-over steps stay manual).
  Future<void> _followInDelivery(String orderId, String kitchenStatus, String? staffId) async {
    const order = ['pending', 'confirmed', 'preparing', 'ready'];
    final target = switch (kitchenStatus) { 'preparing' => 'preparing', 'ready' => 'ready', _ => null };
    if (target == null) return;
    final d = await h.one('SELECT status FROM delivery_info WHERE order_id = ?', [orderId]);
    if (d == null) return;
    final now = d['status'] as String;
    final at = order.indexOf(now);
    if (at < 0 || at >= order.indexOf(target)) return;
    await h.exec('UPDATE delivery_info SET status = ?, updated_at = ? WHERE order_id = ?', [target, h.ts, orderId]);
    await h.exec('INSERT INTO delivery_status_log(id, order_id, status, staff_id, created_at) VALUES (?,?,?,?,?)', [h.id, orderId, target, staffId, h.ts]);
  }
}
