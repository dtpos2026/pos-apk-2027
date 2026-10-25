import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/receipt_template.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptData _d({bool dineIn = true}) => ReceiptData(
      businessName: 'Burger Point',
      invoiceNo: 'INV-1',
      dateTime: '2026-01-12 19:40',
      orderTypeLabel: dineIn ? 'Dine-in' : 'Takeaway',
      tableLabel: dineIn ? 'T4' : null,
      area: dineIn ? 'Outdoor' : null,
      waiter: dineIn ? 'Sara' : null,
      lines: const [ReceiptLine(name: 'Zinger', qtyMilli: 1000, unitPriceMinor: 45000, totalMinor: 45000)],
      subtotalMinor: 45000,
      totalMinor: 45000,
      footer: 'Thanks',
    );

void main() {
  test('a dine-in bill ends with the table (and its area) and the waiter, in every design; other orders show neither', () {
    for (final style in billStyles) {
      final design = BillDesign.defaults.withStyle(style);
      final lines = buildBillDoc(_d(), template: design).lines.whereType<RText>().map((l) => l.text).toList();
      expect(lines.any((l) => l == 'Table: T4  (Outdoor)'), isTrue, reason: '$style shows table and area');
      expect(lines.any((l) => l == 'Waiter: Sara'), isTrue, reason: '$style shows the waiter');
      final all = buildBillDoc(_d(), template: design).lines;
      final tableAt = all.indexWhere((l) => l is RText && l.text == 'Table: T4  (Outdoor)');
      expect(tableAt, greaterThanOrEqualTo(all.length * 2 ~/ 3), reason: '$style: at the end of the bill, not the top');
      final plain = buildBillDoc(_d(dineIn: false), template: design).lines.whereType<RText>().map((l) => l.text).toList();
      expect(plain.any((l) => l.startsWith('Waiter')), isFalse);
    }
  });
}
