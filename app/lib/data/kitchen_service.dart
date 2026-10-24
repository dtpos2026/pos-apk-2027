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
  const KitchenTicket({required this.orderId, required this.label, required this.status, required this.sentAt, required this.lines, this.tableLabel, this.orderType = 'counter', this.token});
  final String orderId;
  final String label;

  /// new | preparing | ready
  final String status;
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

  Future<List<KitchenTicket>> tickets() async {
    final orders = await h.q('''SELECT * FROM (SELECT o.id, o.invoice_no, o.status, o.order_type, t.label AS table_label,
        (SELECT MIN(kot_sent_at) FROM order_item i WHERE i.order_id = o.id AND i.kot_sent_at IS NOT NULL) AS sent
      FROM "order" o LEFT JOIN dining_table t ON t.id = o.table_id
      WHERE o.status IN ('new','preparing','ready')) WHERE sent IS NOT NULL ORDER BY sent''');
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
        label: (o['invoice_no'] as String?) ?? '#${id.substring(0, 4)}',
        status: o['status'] as String,
        sentAt: o['sent'] as int,
        tableLabel: o['table_label'] as String?,
        orderType: o['order_type'] as String,
        lines: lines,
      ));
    }
    return out;
  }

  /// new -> preparing -> ready -> served (served leaves the board; the bill is still open for payment).
  Future<void> advance(String orderId) async {
    final r = await h.one('SELECT status FROM "order" WHERE id = ?', [orderId]);
    if (r == null) throw PosException('not_found', 'Order not found');
    final i = flow.indexOf(r['status'] as String);
    if (i < 0) throw PosException('not_in_kitchen', 'The order is not in the kitchen');
    final next = i + 1 < flow.length ? flow[i + 1] : 'served';
    await h.exec('UPDATE "order" SET status = ?, updated_at = ?, version = version + 1 WHERE id = ?', [next, h.ts, orderId]);
  }
}
