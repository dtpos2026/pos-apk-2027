import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/customer_export.dart';
import 'package:dt_food_pos/domain/pdf_brand.dart';
import 'package:dt_food_pos/domain/report_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('report PDF builds with Urdu item names and many rows (multi-page)', () async {
    final font = pw.Font.ttf(File('assets/fonts/NotoNaskhArabic.ttf').readAsBytesSync().buffer.asByteData());
    final bytes = await buildReportPdf(
      ReportPdfData(
        businessName: 'Burger Point',
        from: '2026-01-01',
        to: '2026-01-31',
        currency: Currency.pkr,
        salesMinor: 1234500,
        refundsMinor: 4500,
        taxMinor: 100000,
        expensesMinor: 200000,
        byMethod: const {'Cash': 1000000, 'Card': 234500},
        items: [for (var i = 0; i < 120; i++) ReportLine(label: i.isEven ? 'چکن کڑاہی $i' : 'Zinger $i', qtyMilli: 1500, amountMinor: 45000, bills: 3)],
        generatedAt: DateTime(2026, 2, 1, 9),
      ),
      script: font,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length, greaterThan(1));
  });

  ReportPdfData data({PdfBrand? brand}) => ReportPdfData(
        businessName: 'Burger Point', from: '2026-01-01', to: '2026-01-01', currency: Currency.pkr, salesMinor: 1000, refundsMinor: 0, taxMinor: 0, expensesMinor: 0, generatedAt: DateTime(2026, 2, 1, 9), brand: brand);
  int images(List<int> b) => RegExp(r'/Subtype\s*/Image').allMatches(String.fromCharCodes(b)).length;

  test('PDF header carries the restaurant logo and the DT mark, and a damaged logo never stops the report', () async {
    final plain = await buildReportPdf(data());
    expect(images(plain), 0);
    final logo = File('assets/brand/app_icon_512.png').readAsBytesSync();
    final mark = File('assets/brand/dt_mark_red.png').readAsBytesSync();
    final branded = await buildReportPdf(data(brand: PdfBrand(name: 'Burger Point', address: 'Main Bazaar', phone: '0300', logo: logo, dtMark: mark)));
    expect(images(branded), greaterThanOrEqualTo(2));
    final broken = await buildReportPdf(data(brand: PdfBrand(name: 'Burger Point', logo: Uint8List.fromList([1, 2, 3]), dtMark: mark)));
    expect(String.fromCharCodes(broken.take(5)), '%PDF-');
    expect(images(broken), greaterThanOrEqualTo(1));
    final customers = await buildCustomersPdf(businessName: 'Burger Point', customers: const [], currency: Currency.pkr, generatedAt: DateTime(2026, 2, 1), identity: PdfBrand(name: 'Burger Point', logo: logo, dtMark: mark));
    expect(images(customers), greaterThanOrEqualTo(2));
  });
}
