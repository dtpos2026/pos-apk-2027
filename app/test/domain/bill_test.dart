import 'package:dt_food_pos/domain/bill.dart';
import 'package:dt_food_pos/domain/payments.dart';
import 'package:flutter_test/flutter_test.dart';

BillLineInput line(String id, int price, int qtyMilli,
        {int mods = 0, int disc = 0, int taxBp = 0, bool inclusive = false}) =>
    BillLineInput(
        id: id, unitPriceMinor: price, qtyMilli: qtyMilli, modifiersMinor: mods, lineDiscountMinor: disc, taxRateBp: taxBp, taxInclusive: inclusive);

void main() {
  group('calculateBill', () {
    test('simple untaxed bill', () {
      final r = calculateBill([line('a', 25000, 2000), line('b', 5000, 1000)]);
      expect(r.subtotalMinor, 55000);
      expect(r.totalMinor, 55000);
      expect(r.taxMinor, 0);
    });

    test('weight item and modifiers', () {
      final r = calculateBill([line('kg', 80000, 1500, mods: 2000)]); // (800+20) x 1.5kg
      expect(r.subtotalMinor, 123000);
    });

    test('exclusive tax is added to the total', () {
      final r = calculateBill([line('a', 10000, 1000, taxBp: 1600)]);
      expect(r.taxMinor, 1600);
      expect(r.totalMinor, 11600);
    });

    test('inclusive tax is contained in the total (UAE 5% VAT)', () {
      final r = calculateBill([line('a', 10500, 1000, taxBp: 500, inclusive: true)]);
      expect(r.taxMinor, 500);
      expect(r.totalMinor, 10500);
    });

    test('percentage bill discount reduces tax too', () {
      final r = calculateBill(
        [line('a', 10000, 1000, taxBp: 1000)],
        const BillConfig(billDiscount: Discount.percent(1000)), // 10% off
      );
      expect(r.discountMinor, 1000);
      expect(r.taxMinor, 900); // tax on 90.00
      expect(r.totalMinor, 9900);
    });

    test('bill discount allocation sums exactly across awkward lines', () {
      final lines = [line('a', 3333, 1000), line('b', 3333, 1000), line('c', 3334, 1000)];
      final r = calculateBill(lines, const BillConfig(billDiscount: Discount.fixed(1000)));
      expect(r.lines.fold<int>(0, (s, l) => s + l.discountMinor), 1000);
      expect(r.totalMinor, 10000 - 1000);
    });

    test('service charge, delivery, tip and rounding', () {
      final r = calculateBill(
        [line('a', 100000, 1000)],
        const BillConfig(serviceChargeBp: 1000, deliveryChargeMinor: 15000, tipMinor: 3333, rounding: RoundingMode.nearest10),
      );
      // 1000 + 100 service + 150 delivery + 33.33 tip = 1283.33 -> 1280 (nearest 10)
      expect(r.serviceChargeMinor, 10000);
      expect(r.roundingMinor, -333);
      expect(r.totalMinor, 128000);
    });

    test('taxable service charge', () {
      final r = calculateBill(
        [line('a', 10000, 1000)],
        const BillConfig(serviceChargeBp: 1000, serviceChargeTaxBp: 1600),
      );
      expect(r.serviceChargeMinor, 1000);
      expect(r.taxMinor, 160);
      expect(r.totalMinor, 11160);
    });

    test('line discount cannot exceed the line', () {
      expect(() => calculateBill([line('a', 1000, 1000, disc: 1001)]), throwsArgumentError);
    });
    test('rejects bad input', () {
      expect(() => calculateBill([line('a', 1000, 0)]), throwsArgumentError);
      expect(() => calculateBill([line('a', 1000, 1000)], const BillConfig(billDiscount: Discount.percent(10001))), throwsArgumentError);
      expect(() => calculateBill([line('a', 1000, 1000)], const BillConfig(billDiscount: Discount.fixed(1001))), throwsArgumentError);
    });

    test('empty bill is zero', () {
      expect(calculateBill([]).totalMinor, 0);
    });
  });

  group('allocate', () {
    test('parts always sum to the amount', () {
      for (final amount in [0, 1, 7, 100, 999]) {
        final parts = allocate(amount, [1, 1, 1]);
        expect(parts.fold<int>(0, (a, b) => a + b), amount);
      }
      expect(allocate(5, [0, 0]), [0, 0]);
    });
  });

  group('settle', () {
    test('cash change', () {
      final r = settle(8750, [const PaymentInput(PaymentKind.cash, 10000)]);
      expect(r.changeMinor, 1250);
      expect(r.paidMinor, 8750);
      expect(r.appliedMinor, [8750]);
      expect(r.isSettled, isTrue);
    });
    test('split card + cash', () {
      final r = settle(10000, [const PaymentInput(PaymentKind.cash, 5000), const PaymentInput(PaymentKind.card, 4000)]);
      expect(r.dueMinor, 1000);
      expect(r.isSettled, isFalse);
    });
    test('card applied first so change is only cash', () {
      final r = settle(10000, [const PaymentInput(PaymentKind.cash, 7000), const PaymentInput(PaymentKind.wallet, 6000)]);
      expect(r.paidMinor, 10000);
      expect(r.changeMinor, 3000);
      expect(r.appliedMinor, [4000, 6000]);
    });
    test('non-cash overpay is rejected', () {
      expect(() => settle(1000, [const PaymentInput(PaymentKind.card, 1500)]), throwsArgumentError);
    });
    test('zero or negative payment is rejected', () {
      expect(() => settle(1000, [const PaymentInput(PaymentKind.cash, 0)]), throwsArgumentError);
    });
  });
}
