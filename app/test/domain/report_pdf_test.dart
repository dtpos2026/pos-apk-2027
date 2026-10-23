import 'dart:io';

import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/domain/money.dart';
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
}
