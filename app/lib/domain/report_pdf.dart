import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/report_service.dart';
import 'money.dart';

/// Everything a report PDF shows. Figures come straight from the same queries as the Reports screen.
class ReportPdfData {
  const ReportPdfData({
    required this.businessName,
    required this.from,
    required this.to,
    required this.currency,
    required this.salesMinor,
    required this.refundsMinor,
    required this.taxMinor,
    required this.expensesMinor,
    this.bills,
    this.byMethod = const {},
    this.items = const [],
    this.categories = const [],
    this.cashiers = const [],
    required this.generatedAt,
  });
  final String businessName;
  final String from;
  final String to;
  final Currency currency;
  final int salesMinor;
  final int refundsMinor;
  final int taxMinor;
  final int expensesMinor;
  final int? bills;
  final Map<String, int> byMethod;
  final List<ReportLine> items;
  final List<ReportLine> categories;
  final List<ReportLine> cashiers;
  final DateTime generatedAt;
}

String _qty(int milli) => milli % 1000 == 0 ? '${milli ~/ 1000}' : (milli / 1000).toStringAsFixed(3);

/// A4 sales report. [script] is a TTF with Urdu/Arabic glyphs, used as a fallback so names in any language print.
Future<Uint8List> buildReportPdf(ReportPdfData d, {pw.Font? script}) async {
  String money(int m) => formatMinor(m, currency: d.currency);
  final theme = pw.ThemeData.withFont(fontFallback: [?script]);
  const brand = PdfColor.fromInt(0xFF3C096C);
  final net = d.salesMinor - d.refundsMinor;
  final doc = pw.Document(title: 'Sales report ${d.from} – ${d.to}', author: d.businessName, creator: 'DT Food POS');

  // Returned as separate widgets (not one Column) so a long table can continue on the next page.
  List<pw.Widget> table(String title, List<ReportLine> lines, {bool qty = true}) {
    if (lines.isEmpty) return const [];
    return [
      pw.SizedBox(height: 14),
      pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: brand)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: ['Name', if (qty) 'Qty', 'Bills', 'Amount'],
        data: [for (final l in lines) [l.label, if (qty) _qty(l.qtyMilli), '${l.bills}', money(l.amountMinor)]],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: brand),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {0: pw.Alignment.centerLeft, for (var i = 1; i <= (qty ? 3 : 2); i++) i: pw.Alignment.centerRight},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
    ];
  }

  pw.Widget kv(String k, String v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [pw.Expanded(child: pw.Text(k)), pw.Text(v, style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null)]),
      );

  doc.addPage(pw.MultiPage(
    theme: theme,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    maxPages: 500,
    header: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(d.businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('Sales report  ${d.from == d.to ? d.from : '${d.from} to ${d.to}'}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      pw.Divider(color: brand),
    ]),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Generated ${d.generatedAt.toString().substring(0, 16)} · DT Food POS · Powered by Digital Target', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (c) => [
      pw.Container(
        width: 260,
        child: pw.Column(children: [
          if (d.bills != null) kv('Bills', '${d.bills}'),
          kv('Gross sales', money(d.salesMinor)),
          kv('Refunds', money(d.refundsMinor)),
          kv('Net sales', money(net), strong: true),
          kv('Tax included', money(d.taxMinor)),
          kv('Expenses', money(d.expensesMinor)),
          kv('Net sales minus expenses', money(net - d.expensesMinor), strong: true),
        ]),
      ),
      pw.SizedBox(height: 4),
      pw.Text('Gross = all settled bills incl. tax. Net = gross minus refunds. Cost of stock sold is not deducted.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      if (d.byMethod.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Text('Payments by method', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: brand)),
        pw.Container(width: 260, child: pw.Column(children: [for (final e in d.byMethod.entries) kv(e.key, money(e.value))])),
      ],
      ...table('Items', d.items),
      ...table('Categories', d.categories),
      ...table('Cashiers', d.cashiers, qty: false),
    ],
  ));
  return doc.save();
}
