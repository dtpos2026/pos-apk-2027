import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kitchen ticket of a delivery order shows who and where; other orders show nothing extra', () {
    ReceiptDoc doc(List<String> to) => buildKotDoc(station: 'Kitchen', orderLabel: 'A1', orderTypeLabel: 'Delivery', dateTime: '2026-10-25 12:00', lines: [KotLine('Zinger', 1000)], deliveryTo: to);
    final text = docToText(doc(['Bilal', 'Tel: 0311-2222222', 'Street 9']), 58);
    expect(text, contains('Bilal'));
    expect(text, contains('0311-2222222'));
    expect(text, contains('Street 9'));
    expect(docToText(doc(const []), 58), isNot(contains('Tel:')));
  });
}
