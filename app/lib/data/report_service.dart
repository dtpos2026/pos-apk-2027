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

/// One payment that left the business: an expense, a cash purchase, or a payment to a supplier, with the account it came from.
class MoneyOut {
  const MoneyOut({required this.date, required this.kind, required this.title, this.detail, required this.method, required this.amountMinor});
  final String date;

  /// expense | purchase | supplier
  final String kind;
  final String title;
  final String? detail;
  final String method;
  final int amountMinor;
}

/// What came into and went out of one account (cash, a bank, a wallet) in a date range.
class AccountLine {
  const AccountLine({required this.name, this.inMinor = 0, this.refundsMinor = 0, this.outMinor = 0});
  final String name;
  final int inMinor;
  final int refundsMinor;
  final int outMinor;
  int get netMinor => inMinor - refundsMinor - outMinor;
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

  /// Every payment made out of the business in the range, newest first: expenses, purchases bought without a supplier account, and payments to suppliers
  /// (including the part paid when the goods were bought). Each names the account it was paid from.
  Future<List<MoneyOut>> moneyOut(String from, String to) async {
    final out = <MoneyOut>[];
    for (final r in await h.q(
        "SELECT e.business_date AS d, e.amount_minor AS amt, e.note AS note, COALESCE(c.name, '') AS cat, COALESCE(m.name, 'Not recorded') AS method FROM expense e LEFT JOIN expense_category c ON c.id = e.category_id LEFT JOIN payment_method m ON m.id = e.method_id WHERE e.business_date BETWEEN ? AND ? ORDER BY e.created_at",
        [from, to])) {
      out.add(MoneyOut(date: r['d'] as String, kind: 'expense', title: (r['cat'] as String).isEmpty ? 'Expense' : r['cat'] as String, detail: r['note'] as String?, method: r['method'] as String, amountMinor: r['amt'] as int));
    }
    for (final r in await h.q(
        "SELECT p.business_date AS d, p.paid_minor AS amt, p.invoice_ref AS ref, COALESCE(m.name, 'Not recorded') AS method FROM purchase p LEFT JOIN payment_method m ON m.id = p.method_id WHERE p.supplier_id IS NULL AND p.paid_minor > 0 AND p.business_date BETWEEN ? AND ? ORDER BY p.created_at",
        [from, to])) {
      out.add(MoneyOut(date: r['d'] as String, kind: 'purchase', title: 'Purchase', detail: r['ref'] as String?, method: r['method'] as String, amountMinor: r['amt'] as int));
    }
    for (final r in await h.q(
        "SELECT strftime('%Y-%m-%d', l.created_at / 1000, 'unixepoch', 'localtime') AS d, -l.amount_minor AS amt, l.note AS note, s.name AS sup, COALESCE(m.name, 'Not recorded') AS method FROM supplier_ledger l JOIN supplier s ON s.id = l.supplier_id LEFT JOIN payment_method m ON m.id = l.method_id WHERE l.kind = 'payment' AND strftime('%Y-%m-%d', l.created_at / 1000, 'unixepoch', 'localtime') BETWEEN ? AND ? ORDER BY l.created_at",
        [from, to])) {
      out.add(MoneyOut(date: r['d'] as String, kind: 'supplier', title: r['sup'] as String, detail: r['note'] as String?, method: r['method'] as String, amountMinor: r['amt'] as int));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Per account: money received from sales (credit/udhaar is not money), refunds paid back, and everything paid out (see [moneyOut]).
  Future<List<AccountLine>> accounts(String from, String to) async {
    final inn = <String, int>{}, ref = <String, int>{}, outm = <String, int>{};
    for (final r in await h.q(
        "SELECT m.name AS n, SUM(p.amount_minor) AS a FROM payment p JOIN payment_method m ON m.id = p.method_id JOIN \"order\" o ON o.id = p.order_id WHERE p.method_kind <> 'credit' AND o.business_date BETWEEN ? AND ? GROUP BY m.name",
        [from, to])) {
      inn[r['n'] as String] = r['a'] as int;
    }
    for (final r in await h.q(
        "SELECT COALESCE(m.name, 'Not recorded') AS n, SUM(r.amount_minor) AS a FROM refund r JOIN \"order\" o ON o.id = r.order_id LEFT JOIN payment_method m ON m.id = r.method_id WHERE o.business_date BETWEEN ? AND ? GROUP BY 1",
        [from, to])) {
      ref[r['n'] as String] = r['a'] as int;
    }
    for (final o in await moneyOut(from, to)) {
      outm[o.method] = (outm[o.method] ?? 0) + o.amountMinor;
    }
    final names = {...inn.keys, ...ref.keys, ...outm.keys}.toList()..sort();
    return [for (final n in names) AccountLine(name: n, inMinor: inn[n] ?? 0, refundsMinor: ref[n] ?? 0, outMinor: outm[n] ?? 0)];
  }

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
