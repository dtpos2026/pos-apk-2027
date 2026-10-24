import '../domain/csv.dart';
import 'db_helper.dart';

class ReportLine {
  const ReportLine({required this.label, required this.qtyMilli, required this.amountMinor, this.bills = 0});
  final String label;
  final int qtyMilli;
  final int amountMinor;
  final int bills;
}

/// One menu item's sales against what its recipe costs. [costMinor] is null when the item has no recipe (cost unknown, never guessed).
class ProfitLine {
  const ProfitLine({required this.label, required this.qtyMilli, required this.revenueMinor, required this.costMinor});
  final String label;
  final int qtyMilli;
  final int revenueMinor;
  final int? costMinor;
  int? get profitMinor => costMinor == null ? null : revenueMinor - costMinor!;

  /// Margin in percent of the revenue; null when there is no cost or no revenue.
  int? get marginPct => costMinor == null || revenueMinor <= 0 ? null : ((revenueMinor - costMinor!) * 100 / revenueMinor).round();
}

/// Sales breakdowns for a date range (inclusive, business dates 'YYYY-MM-DD'). Only paid bills count here;
/// voided bills are excluded, and refunds are reported separately in the daily summary.
class ReportService {
  ReportService(this.h);
  final DbHelper h;

  Future<List<ReportLine>> itemWise(String from, String to) async => [
        for (final r in await h.q(
            "SELECT i.name AS label, SUM(i.qty_milli) AS qty, SUM(i.line_total_minor) AS amount, COUNT(DISTINCT o.id) AS bills FROM order_item i JOIN \"order\" o ON o.id = i.order_id WHERE o.status IN ('paid','refunded') AND i.status = 'active' AND o.business_date BETWEEN ? AND ? GROUP BY i.name ORDER BY amount DESC, label",
            [from, to]))
          ReportLine(label: r['label'] as String, qtyMilli: r['qty'] as int, amountMinor: r['amount'] as int, bills: r['bills'] as int)
      ];

  /// Per item: revenue, the cost of the stock its recipe uses (at the average cost of that stock) and the profit.
  /// Items without a recipe show revenue only.
  Future<List<ProfitLine>> profitWise(String from, String to) async {
    final sold = await h.q(
        "SELECT i.name AS label, i.product_id AS pid, i.variant_id AS vid, SUM(i.qty_milli) AS qty, SUM(i.line_total_minor) AS amount FROM order_item i JOIN \"order\" o ON o.id = i.order_id WHERE o.status IN ('paid','refunded') AND i.status = 'active' AND o.business_date BETWEEN ? AND ? GROUP BY i.product_id, i.variant_id, i.name",
        [from, to]);
    // cost of ONE portion = sum(recipe qty x average cost per unit of that stock item)
    final recipe = await h.q('SELECT rl.product_id AS pid, rl.variant_id AS vid, SUM(rl.qty_milli * s.avg_cost_minor_per_unit / 1000.0) AS cost FROM recipe_line rl JOIN stock_item s ON s.id = rl.stock_item_id GROUP BY rl.product_id, rl.variant_id');
    double? portion(String pid, String? vid) {
      final exact = recipe.where((r) => r['pid'] == pid && r['vid'] == vid).firstOrNull;
      final base = recipe.where((r) => r['pid'] == pid && r['vid'] == null).firstOrNull;
      final r = exact ?? base;
      return r == null ? null : (r['cost'] as num).toDouble();
    }

    final byName = <String, (int, int, double?)>{};
    for (final r in sold) {
      final unit = portion(r['pid'] as String, r['vid'] as String?);
      final qty = r['qty'] as int;
      final cost = unit == null ? null : unit * qty / 1000;
      final prev = byName[r['label'] as String];
      byName[r['label'] as String] = (
        (prev?.$1 ?? 0) + qty,
        (prev?.$2 ?? 0) + (r['amount'] as int),
        cost == null && prev?.$3 == null ? null : (prev?.$3 ?? 0) + (cost ?? 0),
      );
    }
    final out = [for (final e in byName.entries) ProfitLine(label: e.key, qtyMilli: e.value.$1, revenueMinor: e.value.$2, costMinor: e.value.$3?.round())];
    out.sort((a, b) => (b.profitMinor ?? b.revenueMinor).compareTo(a.profitMinor ?? a.revenueMinor));
    return out;
  }

  Future<List<ReportLine>> categoryWise(String from, String to) async => [
        for (final r in await h.q(
            "SELECT COALESCE(c.name, '-') AS label, SUM(i.qty_milli) AS qty, SUM(i.line_total_minor) AS amount, COUNT(DISTINCT o.id) AS bills FROM order_item i JOIN \"order\" o ON o.id = i.order_id LEFT JOIN product p ON p.id = i.product_id LEFT JOIN category c ON c.id = p.category_id WHERE o.status IN ('paid','refunded') AND i.status = 'active' AND o.business_date BETWEEN ? AND ? GROUP BY label ORDER BY amount DESC, label",
            [from, to]))
          ReportLine(label: r['label'] as String, qtyMilli: r['qty'] as int, amountMinor: r['amount'] as int, bills: r['bills'] as int)
      ];

  Future<List<ReportLine>> cashierWise(String from, String to) async => [
        for (final r in await h.q(
            "SELECT COALESCE(s.name, '-') AS label, COUNT(*) AS bills, SUM(o.total_minor) AS amount FROM \"order\" o LEFT JOIN staff s ON s.id = o.cashier_id WHERE o.status IN ('paid','refunded') AND o.business_date BETWEEN ? AND ? GROUP BY label ORDER BY amount DESC, label",
            [from, to]))
          ReportLine(label: r['label'] as String, qtyMilli: 0, amountMinor: r['amount'] as int, bills: r['bills'] as int)
      ];

  /// Expenses and profit for the range: sales minus refunds minus expenses (cost of stock sold is not deducted).
  Future<({int sales, int refunds, int expenses, int tax})> totals(String from, String to) async {
    final sales = await h.intValue("SELECT COALESCE(SUM(total_minor),0) FROM \"order\" WHERE status IN ('paid','void','refunded') AND business_date BETWEEN ? AND ?", [from, to]);
    final refunds = await h.intValue('SELECT COALESCE(SUM(r.amount_minor),0) FROM refund r JOIN "order" o ON o.id = r.order_id WHERE o.business_date BETWEEN ? AND ?', [from, to]);
    final expenses = await h.intValue('SELECT COALESCE(SUM(amount_minor),0) FROM expense WHERE business_date BETWEEN ? AND ?', [from, to]);
    final tax = await h.intValue("SELECT COALESCE(SUM(tax_minor),0) FROM \"order\" WHERE status IN ('paid','void','refunded') AND business_date BETWEEN ? AND ?", [from, to]);
    return (sales: sales, refunds: refunds, expenses: expenses, tax: tax);
  }
}

String _money(int minor) => '${minor ~/ 100}.${(minor % 100).abs().toString().padLeft(2, '0')}';
String _qty(int milli) => milli % 1000 == 0 ? '${milli ~/ 1000}' : (milli / 1000).toStringAsFixed(3);

/// CSV (opens in Excel) for any of the breakdowns. Quantities and money are plain numbers, not formatted text.
String reportCsv(List<ReportLine> lines, {required String labelHeader, bool withQty = true}) {
  final head = [labelHeader, if (withQty) 'Quantity', 'Bills', 'Amount'].map(csvEscape).join(',');
  final rows = [for (final l in lines) [csvEscape(l.label), if (withQty) _qty(l.qtyMilli), '${l.bills}', _money(l.amountMinor)].join(',')];
  return '$head\n${rows.join('\n')}\n';
}
