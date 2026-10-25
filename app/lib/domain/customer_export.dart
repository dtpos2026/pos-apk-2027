import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/customer_service.dart';
import 'csv.dart';
import 'money.dart';
import 'pdf_brand.dart';

/// The customer list as a spreadsheet: Name, Phone, Address, Owes (udhaar), Credit limit.
String customersCsv(List<CustomerRow> customers, {required Currency currency}) {
  String n(int v) => (v / currency.factor).toStringAsFixed(currency.minorDigits);
  final b = StringBuffer('Name,Phone,Address,Owes,Credit limit\n');
  for (final c in customers) {
    b.writeln([c.name, c.phone ?? '', c.address ?? '', n(c.balanceMinor), n(c.creditLimitMinor)].map(csvEscape).join(','));
  }
  return b.toString();
}

/// The customer list as an A4 PDF in the brand red. [script] is a font with Urdu/Arabic letters so any name prints.
Future<Uint8List> buildCustomersPdf({required String businessName, required List<CustomerRow> customers, required Currency currency, required DateTime generatedAt, pw.Font? script, PdfBrand? identity}) async {
  String money(int m) => formatMinor(m, currency: currency);
  const brand = PdfColor.fromInt(0xFFC92A2A);
  final owing = customers.where((c) => c.balanceMinor > 0).fold<int>(0, (s, c) => s + c.balanceMinor);
  final doc = pw.Document(title: 'Customers', author: businessName, creator: 'DT Food POS');
  doc.addPage(pw.MultiPage(
    theme: pw.ThemeData.withFont(fontFallback: [?script]),
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    maxPages: 500,
    header: (c) => pdfBrandHeader(identity ?? PdfBrand(name: businessName), title: 'Customers', subtitle: '${customers.length} customers  ·  Udhaar due ${money(owing)}'),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Generated ${generatedAt.toString().substring(0, 16)} · DT Food POS · Powered by Digital Target', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (c) => [
      pw.TableHelper.fromTextArray(
        headers: ['Name', 'Phone', 'Address', 'Owes'],
        data: [for (final x in customers) [x.name, x.phone ?? '', x.address ?? '', x.balanceMinor > 0 ? money(x.balanceMinor) : '']],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: brand),
        cellStyle: const pw.TextStyle(fontSize: 10),
        columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2.2), 2: const pw.FlexColumnWidth(4), 3: const pw.FlexColumnWidth(2)},
        cellAlignments: {3: pw.Alignment.centerRight},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
    ],
  ));
  return doc.save();
}
