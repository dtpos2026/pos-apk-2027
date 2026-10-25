import 'package:dt_food_pos/data/customer_service.dart';
import 'package:dt_food_pos/domain/customer_export.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/promo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the message is personal: name and restaurant are filled in, an empty name leaves no gap', () {
    expect(promoMessage('Hello {name}, welcome to {shop}!', name: ' Ahmed ', shop: 'Burger Point'), 'Hello Ahmed, welcome to Burger Point!');
    expect(promoMessage('Hi {name}! {shop} sale', name: '', shop: 'Burger Point'), 'Hi! Burger Point sale');
    for (final t in promoTemplates.values) {
      expect(promoMessage(t, name: 'Ali', shop: 'X'), isNot(contains('{')));
    }
  });

  test('the queue goes one customer at a time, skips numbers that are empty and never messages the same number twice', () {
    final q = PromoQueue(const [
      PromoTarget(name: 'A', phone: '0300-1111111'),
      PromoTarget(name: 'B', phone: ''),
      PromoTarget(name: 'A again', phone: '0300 1111111'),
      PromoTarget(name: 'C', phone: '0311-2222222'),
    ], template: 'Hi {name}', shop: 'S');
    expect(q.total, 2);
    expect(q.current!.name, 'A');
    expect(q.currentText, 'Hi A');
    q.advance();
    expect(q.currentText, 'Hi C');
    expect(q.finished, isFalse);
    q.advance();
    expect(q.finished, isTrue);
    expect(q.currentText, isNull);
    q.advance();
    expect(q.done, 2, reason: 'cannot go past the end');
  });

  test('the customer list exports to CSV with Urdu names, commas and udhaar, and to a PDF', () async {
    const list = [
      CustomerRow(id: '1', name: 'Ahmed, Raza', phone: '0300-1111111', address: 'House 5, Model Town', creditLimitMinor: 500000, balanceMinor: 125050),
      CustomerRow(id: '2', name: 'احمد علی', creditLimitMinor: 0, balanceMinor: 0),
    ];
    final csv = customersCsv(list, currency: Currency.pkr);
    expect(csv.split('\n').first, 'Name,Phone,Address,Owes,Credit limit');
    expect(csv, contains('"Ahmed, Raza",0300-1111111,"House 5, Model Town",1250.50,5000.00'));
    expect(csv, contains('احمد علی,,,0.00,0.00'));
    final pdf = await buildCustomersPdf(businessName: 'Burger Point', customers: list, currency: Currency.pkr, generatedAt: DateTime(2026, 1, 12, 19, 40));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(1000));
  });
}
