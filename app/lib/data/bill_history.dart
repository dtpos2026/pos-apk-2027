import 'db_helper.dart';

class BillRow {
  const BillRow({this.kitchenSent = false, required this.id, required this.invoiceNo, required this.status, required this.totalMinor, required this.paidMinor, required this.refundedMinor, required this.settledAt, required this.orderType, this.customer, this.table});
  final String id;
  final String invoiceNo;

  /// paid | void | refunded | held | new | preparing | ready | served  (the last five = unpaid, running)
  final String status;

  /// The order was sent to the kitchen (its kitchen ticket and this bill are the same order).
  final bool kitchenSent;
  bool get running => const {'held', 'new', 'preparing', 'ready', 'served'}.contains(status);
  final int totalMinor;
  final int paidMinor;
  final int refundedMinor;
  final int settledAt;
  final String orderType;
  final String? customer;
  final String? table;
  int get netMinor => totalMinor - refundedMinor;
  bool get canRefund => status == 'paid' && refundedMinor < paidMinor;
}

/// Past bills for a business date, for looking up, reprinting and refunding.
class BillHistory {
  BillHistory(this.h);
  final DbHelper h;

  /// [tab]: all | paid | running | kitchen | cancelled. Unpaid running orders (held or sent to the kitchen) are always listed
  /// whatever their date, because they are still open; settled bills belong to their business date.
  Future<List<BillRow>> forDate(String date, {String search = '', String tab = 'all'}) async {
    final like = '%${search.trim()}%';
    const running = "('held','new','preparing','ready','served')";
    final where = switch (tab) {
      'paid' => "o.business_date = ? AND o.status = 'paid'",
      'cancelled' => "o.business_date = ? AND o.status IN ('void','refunded','cancelled')",
      'running' => '(o.status IN $running AND ? IS NOT NULL)',
      'kitchen' => "((o.business_date = ? AND o.status IN ('paid','void','refunded','cancelled')) OR o.status IN $running) AND EXISTS (SELECT 1 FROM order_item k WHERE k.order_id = o.id AND k.kot_sent_at IS NOT NULL)",
      _ => "((o.business_date = ? AND o.status IN ('paid','void','refunded','cancelled')) OR o.status IN $running)",
    };
    final rows = await h.q(
        'SELECT o.id, o.invoice_no, o.status, o.total_minor, o.paid_minor, o.settled_at, o.updated_at, o.order_type, c.name AS cust, t.label AS tbl, '
        '(SELECT COUNT(*) FROM order_item k WHERE k.order_id = o.id AND k.kot_sent_at IS NOT NULL) AS ksent, '
        'COALESCE((SELECT SUM(amount_minor) FROM refund WHERE order_id = o.id),0) AS refunded '
        'FROM "order" o LEFT JOIN customer c ON c.id = o.customer_id LEFT JOIN dining_table t ON t.id = o.table_id '
        'WHERE $where AND (COALESCE(o.invoice_no, o.id) LIKE ? OR c.name LIKE ?) AND EXISTS (SELECT 1 FROM order_item i WHERE i.order_id = o.id) '
        'ORDER BY COALESCE(o.settled_at, o.updated_at) DESC, o.rowid DESC',
        [date, like, like]);
    return [
      for (final r in rows)
        BillRow(
            id: r['id'] as String,
            invoiceNo: (r['invoice_no'] as String?) ?? '#${(r['id'] as String).substring(0, 4).toUpperCase()}',
            status: r['status'] as String,
            kitchenSent: (r['ksent'] as int) > 0,
            totalMinor: r['total_minor'] as int,
            paidMinor: r['paid_minor'] as int,
            refundedMinor: r['refunded'] as int,
            settledAt: (r['settled_at'] as int?) ?? (r['updated_at'] as int),
            orderType: r['order_type'] as String,
            customer: r['cust'] as String?,
            table: r['tbl'] as String?)
    ];
  }
}
