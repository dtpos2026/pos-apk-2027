import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/report_pdf.dart';
import 'package:dt_food_pos/domain/report_slip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report slip: every report in short sections, fits 58 mm, long lists are cut', () {
    final d = ReportPdfData(
      businessName: 'Takeaway Pizza',
      from: '2026-11-12',
      to: '2026-11-12',
      currency: Currency.pkr,
      salesMinor: 1250000,
      refundsMinor: 50000,
      taxMinor: 0,
      expensesMinor: 200000,
      bills: 42,
      byMethod: const {'Cash': 900000, 'JazzCash': 350000},
      items: [for (var i = 0; i < 20; i++) ReportLine(label: 'Item $i', qtyMilli: 2000, amountMinor: 10000)],
      categories: const [ReportLine(label: 'Pizza', qtyMilli: 30000, amountMinor: 900000)],
      cashiers: const [ReportLine(label: 'Ali', qtyMilli: 0, amountMinor: 1250000, bills: 42)],
      generatedAt: DateTime(2026, 11, 13, 1, 5),
    );
    final doc = buildReportSlip(d,
        profit: const [ProfitLine(label: 'Pizza', qtyMilli: 10000, revenueMinor: 500000, costMinor: 300000)],
        accounts: const [AccountLine(name: 'Cash', inMinor: 900000)],
        moneyOut: const [MoneyOut(date: '2026-11-12', kind: 'expense', title: 'Gas', method: 'Cash', amountMinor: 200000)]);
    expect(doc.graphic, isFalse, reason: 'printer font: fast and sharp');
    final text = EscPosRenderer(paperMm: 58).renderSync(doc).previewText;
    for (final s in ['SALES REPORT', 'Takeaway Pizza', 'PAYMENTS', 'ITEMS', 'CATEGORIES', 'CASHIERS', 'PROFIT', 'MONEY OUT', 'ACCOUNTS', '+ 5 more', 'Gross profit']) {
      expect(text, contains(s));
    }
    expect(text, contains('10,000.00'), reason: 'net = sales - refunds - expenses');
    for (final line in text.split('\n')) {
      expect(line.length, lessThanOrEqualTo(32), reason: 'fits the 58 mm paper: "$line"');
    }
  });
}
