import 'db_helper.dart';

class BillRow {
  const BillRow({required this.id, required this.invoiceNo, required this.status, required this.totalMinor, required this.paidMinor, required this.refundedMinor, required this.settledAt, required this.orderType, this.customer, this.table});
  final String id;
  final String invoiceNo;

  /// paid | void | refunded
  final String status;
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

  Future<List<BillRow>> forDate(String date, {String search = ''}) async {
    final like = '%${search.trim()}%';
    final rows = await h.q(
        'SELECT o.id, o.invoice_no, o.status, o.total_minor, o.paid_minor, o.settled_at, o.order_type, c.name AS cust, t.label AS tbl, '
        'COALESCE((SELECT SUM(amount_minor) FROM refund WHERE order_id = o.id),0) AS refunded '
        'FROM "order" o LEFT JOIN customer c ON c.id = o.customer_id LEFT JOIN dining_table t ON t.id = o.table_id '
        "WHERE o.business_date = ? AND o.status IN ('paid','void','refunded') AND (o.invoice_no LIKE ? OR c.name LIKE ?) ORDER BY o.settled_at DESC, o.rowid DESC",
        [date, like, like]);
    return [
      for (final r in rows)
        BillRow(
            id: r['id'] as String,
            invoiceNo: r['invoice_no'] as String,
            status: r['status'] as String,
            totalMinor: r['total_minor'] as int,
            paidMinor: r['paid_minor'] as int,
            refundedMinor: r['refunded'] as int,
            settledAt: (r['settled_at'] as int?) ?? 0,
            orderType: r['order_type'] as String,
            customer: r['cust'] as String?,
            table: r['tbl'] as String?)
    ];
  }
}
