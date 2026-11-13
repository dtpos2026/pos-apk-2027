import '../data/report_service.dart';
import 'escpos.dart' show PrintAlign;
import 'money.dart';
import 'receipt_doc.dart';
import 'report_pdf.dart';

/// The sales report as a short 58/80 mm slip: every report on one compact ticket, in the printer's own font (fast and sharp).
/// Same figures as the Reports screen and the PDF. Lists are cut to [maxLines] rows each so the slip never runs metres long.
ReceiptDoc buildReportSlip(
  ReportPdfData d, {
  List<ProfitLine> profit = const [],
  List<AccountLine> accounts = const [],
  List<MoneyOut> moneyOut = const [],
  List<HourLine> hours = const [],
  int maxLines = 15,
}) {
  String m(int v) => formatMinor(v, currency: d.currency, symbol: false);
  String two(int n) => n.toString().padLeft(2, '0');
  final at = d.generatedAt;
  final lines = <RLine>[
    if (d.businessName.isNotEmpty) RText(d.businessName, align: PrintAlign.center, bold: true),
    const RText('SALES REPORT', align: PrintAlign.center, bold: true),
    RText(d.from == d.to ? d.from : '${d.from} to ${d.to}', align: PrintAlign.center),
    const RRule('='),
    RRow('Sales', m(d.salesMinor)),
    if (d.refundsMinor != 0) RRow('Refunds', '-${m(d.refundsMinor)}'),
    if (d.expensesMinor != 0) RRow('Expenses', '-${m(d.expensesMinor)}'),
    if (d.taxMinor != 0) RRow('Tax (in sales)', m(d.taxMinor)),
    RRow('NET (${d.currency.code})', m(d.salesMinor - d.refundsMinor - d.expensesMinor), bold: true),
    if (d.bills != null) RRow('Bills', '${d.bills}'),
  ];

  void section(String title, List<(String, String)> rows) {
    if (rows.isEmpty) return;
    lines
      ..add(const RRule())
      ..add(RText(title, bold: true));
    for (final r in rows.take(maxLines)) {
      lines.add(RRow(r.$1, r.$2));
    }
    if (rows.length > maxLines) lines.add(RText('+ ${rows.length - maxLines} more'));
  }

  section('PAYMENTS', [for (final e in d.byMethod.entries) if (e.value != 0) (e.key, m(e.value))]);
  section('ITEMS (qty)', [for (final l in d.items) ('${formatQty(l.qtyMilli)} ${l.label}', m(l.amountMinor))]);
  section('CATEGORIES', [for (final l in d.categories) (l.label, m(l.amountMinor))]);
  section('CASHIERS', [for (final l in d.cashiers) ('${l.label}${l.bills > 0 ? ' (${l.bills})' : ''}', m(l.amountMinor))]);
  final costed = profit.where((p) => p.costMinor != null).toList();
  if (costed.isNotEmpty) {
    final rev = costed.fold<int>(0, (a, p) => a + p.revenueMinor), cost = costed.fold<int>(0, (a, p) => a + p.costMinor!);
    section('PROFIT (items with recipe)', [('Revenue', m(rev)), ('Cost', m(cost)), ('Gross profit', m(rev - cost))]);
  }
  String h12(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}';
  final busy = [...hours]..sort((a, b) => b.bills.compareTo(a.bills));
  section('PEAK HOURS (bills)', [for (final l in busy.take(5)) ('${h12(l.hour)}-${h12((l.hour + 1) % 24)} (${l.bills})', m(l.amountMinor))]);
  final outByKind = <String, int>{};
  for (final o in moneyOut) {
    outByKind[o.kind] = (outByKind[o.kind] ?? 0) + o.amountMinor;
  }
  section('MONEY OUT', [for (final e in outByKind.entries) ('${e.key[0].toUpperCase()}${e.key.substring(1)}', m(e.value))]);
  section('ACCOUNTS (net)', [for (final a in accounts) if (a.netMinor != 0 || a.inMinor != 0) (a.name, m(a.netMinor))]);
  lines
    ..add(const RRule('='))
    ..add(RText('Printed ${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}', align: PrintAlign.center));
  return ReceiptDoc(lines);
}
