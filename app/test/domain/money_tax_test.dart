import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/tax.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('roundDiv', () {
    test('rounds half away from zero', () {
      expect(roundDiv(5, 2), 3);
      expect(roundDiv(-5, 2), -3);
      expect(roundDiv(4, 3), 1);
      expect(roundDiv(0, 7), 0);
    });
  });

  group('formatMinor / parseMinor', () {
    test('formats with grouping and currency', () {
      expect(formatMinor(123450), 'PKR 1,234.50');
      expect(formatMinor(5, currency: Currency.aed), 'AED 0.05');
      expect(formatMinor(-100000, symbol: false), '-1,000.00');
      expect(formatMinor(1234567, currency: const Currency('JPY', minorDigits: 0)), 'JPY 1,234,567');
    });
    test('parses user input', () {
      expect(parseMinor('1,250.5'), 125050);
      expect(parseMinor('10'), 1000);
      expect(parseMinor('0.05'), 5);
      expect(parseMinor('1.234'), isNull);
      expect(parseMinor('abc'), isNull);
      expect(parseMinor('-5'), isNull);
    });
    test('quantity', () {
      expect(formatQty(1000), '1');
      expect(formatQty(1500), '1.5');
      expect(formatQty(250), '0.25');
      expect(formatQty(2005), '2.005');
    });
  });

  group('splitTax', () {
    test('exclusive adds tax on top', () {
      final s = splitTax(10000, 500, inclusive: false); // 100.00 at 5%
      expect(s.netMinor, 10000);
      expect(s.taxMinor, 500);
      expect(s.grossMinor, 10500);
    });
    test('inclusive extracts tax and sums exactly', () {
      final s = splitTax(10500, 500, inclusive: true);
      expect(s.netMinor, 10000);
      expect(s.taxMinor, 500);
      for (final amount in [1, 99, 12345, 99999]) {
        final x = splitTax(amount, 1600, inclusive: true);
        expect(x.netMinor + x.taxMinor, amount);
      }
    });
    test('zero rate', () {
      expect(splitTax(1234, 0, inclusive: false).taxMinor, 0);
      expect(splitTax(1234, 0, inclusive: true).netMinor, 1234);
    });
  });
}
