import 'db_helper.dart';

class DayPoint {
  const DayPoint(this.date, this.netMinor, this.bills);
  final String date;
  final int netMinor;
  final int bills;
}

class TopItem {
  const TopItem(this.name, this.qtyMilli, this.totalMinor);
  final String name;
  final int qtyMilli;
  final int totalMinor;
}

/// Everything the dashboard shows, read from the phone's own sales records (nothing is invented or estimated).
class DashboardData {
  const DashboardData({
    required this.date,
    required this.bills,
    required this.grossMinor,
    required this.refundsMinor,
    required this.discountMinor,
    required this.cashMinor,
    required this.otherMinor,
    required this.creditMinor,
    required this.expensesMinor,
    required this.udhaarDueMinor,
    required this.udhaarCustomers,
    required this.openOrders,
    required this.tablesTotal,
    required this.tablesOccupied,
    required this.byType,
    required this.last7,
    required this.top,
    required this.lowStock,
  });
  final String date;
  final int bills;
  final int grossMinor;
  final int refundsMinor;
  final int discountMinor;
  final int cashMinor;
  final int otherMinor;
  final int creditMinor;
  final int expensesMinor;
  final int udhaarDueMinor;
  final int udhaarCustomers;

  /// Held / running orders not paid yet.
  final int openOrders;
  final int tablesTotal;
  final int tablesOccupied;
  final Map<String, int> byType;
  final List<DayPoint> last7;
  final List<TopItem> top;
  final int lowStock;

  int get netMinor => grossMinor - refundsMinor;
  /// Net sales of yesterday (the day before today in [last7]).
  int get yesterdayMinor => last7.length >= 2 ? last7[last7.length - 2].netMinor : 0;

  /// Today against yesterday in percent; null when yesterday had no sales (a percentage would mean nothing).
  int? get vsYesterdayPct => yesterdayMinor <= 0 ? null : ((netMinor - yesterdayMinor) * 100 / yesterdayMinor).round();

  int get avgBillMinor => bills == 0 ? 0 : (grossMinor / bills).round();
}

class DashboardService {
  DashboardService(this.h);
  final DbHelper h;

  static String dateMinus(String date, int days) {
    final p = date.split('-').map(int.parse).toList();
    final d = DateTime(p[0], p[1], p[2]).subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<DashboardData> load() async {
    final today = await h.openBusinessDate(); // after the day is closed, "today" starts again from zero
    final from7 = dateMinus(today, 6);
    final t = (await h.q("SELECT COUNT(*) AS n, COALESCE(SUM(total_minor),0) AS gross, COALESCE(SUM(discount_minor),0) AS disc FROM \"order\" WHERE business_date = ? AND status IN ('paid','void','refunded')", [today])).first;
    final refunds = (await h.q('SELECT COALESCE(SUM(r.amount_minor),0) AS s FROM refund r JOIN "order" o ON o.id = r.order_id WHERE o.business_date = ?', [today])).first['s'] as int;
    final pay = await h.q("SELECT p.method_kind AS k, COALESCE(SUM(p.amount_minor),0) AS s FROM payment p JOIN \"order\" o ON o.id = p.order_id WHERE o.business_date = ? AND o.status IN ('paid') GROUP BY p.method_kind", [today]);
    int kind(Set<String> ks) => pay.where((r) => ks.contains(r['k'])).fold<int>(0, (s, r) => s + (r['s'] as int));
    final expenses = (await h.q('SELECT COALESCE(SUM(amount_minor),0) AS s FROM expense WHERE business_date = ?', [today])).first['s'] as int;
    final udhaar = (await h.q('SELECT COUNT(*) AS n, COALESCE(SUM(b),0) AS s FROM (SELECT SUM(amount_minor) AS b FROM customer_ledger GROUP BY customer_id HAVING SUM(amount_minor) > 0)')).first;
    final open = (await h.q("SELECT COUNT(*) AS n FROM \"order\" WHERE status IN ('draft','held','new','preparing','ready','served') AND EXISTS (SELECT 1 FROM order_item i WHERE i.order_id = \"order\".id)")).first['n'] as int;
    final tables = (await h.q("SELECT COUNT(*) AS n, COALESCE(SUM(status = 'occupied'),0) AS occ FROM dining_table WHERE deleted_at IS NULL")).first;
    final types = await h.q("SELECT order_type AS ty, COALESCE(SUM(total_minor),0) AS s FROM \"order\" WHERE business_date = ? AND status = 'paid' GROUP BY order_type", [today]);
    final days = await h.q("SELECT business_date AS d, COUNT(*) AS n, COALESCE(SUM(total_minor),0) AS s FROM \"order\" WHERE business_date >= ? AND status IN ('paid','void','refunded') GROUP BY business_date", [from7]);
    final refundDays = await h.q('SELECT o.business_date AS d, COALESCE(SUM(r.amount_minor),0) AS s FROM refund r JOIN "order" o ON o.id = r.order_id WHERE o.business_date >= ? GROUP BY o.business_date', [from7]);
    final top = await h.q("SELECT i.name AS n, SUM(i.qty_milli) AS q, SUM(i.line_total_minor) AS s FROM order_item i JOIN \"order\" o ON o.id = i.order_id WHERE o.business_date = ? AND o.status = 'paid' AND i.status = 'active' GROUP BY i.name ORDER BY s DESC LIMIT 5", [today]);
    var low = 0;
    try {
      low = (await h.q('SELECT COUNT(*) AS n FROM stock_item WHERE deleted_at IS NULL AND reorder_level_milli > 0 AND (SELECT COALESCE(SUM(delta_milli),0) FROM stock_movement m WHERE m.stock_item_id = stock_item.id) <= reorder_level_milli')).first['n'] as int;
    } catch (_) {}
    return DashboardData(
      date: today,
      bills: t['n'] as int,
      grossMinor: t['gross'] as int,
      refundsMinor: refunds,
      discountMinor: t['disc'] as int,
      cashMinor: kind({'cash'}),
      creditMinor: kind({'credit'}),
      otherMinor: kind({'card', 'wallet', 'bank', 'other'}),
      expensesMinor: expenses,
      udhaarDueMinor: udhaar['s'] as int,
      udhaarCustomers: udhaar['n'] as int,
      openOrders: open,
      tablesTotal: tables['n'] as int,
      tablesOccupied: (tables['occ'] as num).toInt(),
      byType: {for (final r in types) r['ty'] as String: r['s'] as int},
      last7: [
        for (var i = 6; i >= 0; i--)
          () {
            final d = dateMinus(today, i);
            final row = days.where((r) => r['d'] == d).firstOrNull;
            final ref = refundDays.where((r) => r['d'] == d).firstOrNull;
            return DayPoint(d, ((row?['s'] as int?) ?? 0) - ((ref?['s'] as int?) ?? 0), (row?['n'] as int?) ?? 0);
          }()
      ],
      top: [for (final r in top) TopItem(r['n'] as String, r['q'] as int, r['s'] as int)],
      lowStock: low,
    );
  }
}
