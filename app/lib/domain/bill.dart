import 'money.dart';
import 'tax.dart';

enum DiscountKind { fixed, percent }

/// [value] is minor units for [DiscountKind.fixed], basis points for [DiscountKind.percent] (1000 = 10%).
class Discount {
  const Discount.fixed(int minor)
      : kind = DiscountKind.fixed,
        value = minor;
  const Discount.percent(int bp)
      : kind = DiscountKind.percent,
        value = bp;
  final DiscountKind kind;
  final int value;
}

enum RoundingMode {
  none(1),
  nearest1(100),
  nearest5(500),
  nearest10(1000);

  const RoundingMode(this.stepMinor);

  /// Step in minor units for a 2-digit currency.
  final int stepMinor;
}

class BillLineInput {
  const BillLineInput({
    required this.id,
    required this.unitPriceMinor,
    required this.qtyMilli,
    this.modifiersMinor = 0,
    this.lineDiscountMinor = 0,
    this.taxRateBp = 0,
    this.taxInclusive = false,
  });
  final String id;
  final int unitPriceMinor;
  final int qtyMilli;

  /// Sum of selected modifier prices for ONE unit.
  final int modifiersMinor;
  final int lineDiscountMinor;
  final int taxRateBp;
  final bool taxInclusive;
}

class BillConfig {
  const BillConfig({
    this.billDiscount,
    this.serviceChargeBp = 0,
    this.serviceChargeFixedMinor = 0,
    this.serviceChargeTaxBp = 0,
    this.deliveryChargeMinor = 0,
    this.tipMinor = 0,
    this.rounding = RoundingMode.none,
  });
  final Discount? billDiscount;
  final int serviceChargeBp;

  /// A service charge in money (added to the percentage one): set by hand on a bill.
  final int serviceChargeFixedMinor;

  /// Tax added on top of the service charge (0 = service charge is not taxed).
  final int serviceChargeTaxBp;
  final int deliveryChargeMinor;
  final int tipMinor;
  final RoundingMode rounding;

  /// A copy with some fields changed; [clearDiscount] removes the bill discount.
  BillConfig copyWith({Discount? billDiscount, bool clearDiscount = false, int? serviceChargeBp, int? serviceChargeFixedMinor, int? serviceChargeTaxBp, int? deliveryChargeMinor, int? tipMinor, RoundingMode? rounding}) => BillConfig(
        billDiscount: clearDiscount ? null : (billDiscount ?? this.billDiscount),
        serviceChargeBp: serviceChargeBp ?? this.serviceChargeBp,
        serviceChargeFixedMinor: serviceChargeFixedMinor ?? this.serviceChargeFixedMinor,
        serviceChargeTaxBp: serviceChargeTaxBp ?? this.serviceChargeTaxBp,
        deliveryChargeMinor: deliveryChargeMinor ?? this.deliveryChargeMinor,
        tipMinor: tipMinor ?? this.tipMinor,
        rounding: rounding ?? this.rounding,
      );
}

class BillLineResult {
  const BillLineResult({
    required this.id,
    required this.grossMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
  });
  final String id;

  /// unit price (+ modifiers) x qty, before any discount.
  final int grossMinor;

  /// line discount + this line's share of the bill discount.
  final int discountMinor;
  final int taxMinor;

  /// What the customer pays for this line: gross - discount (+ tax when tax is exclusive).
  final int totalMinor;
}

class BillResult {
  const BillResult({
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.serviceChargeMinor,
    required this.deliveryChargeMinor,
    required this.taxMinor,
    required this.tipMinor,
    required this.roundingMinor,
    required this.totalMinor,
  });
  final List<BillLineResult> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int serviceChargeMinor;
  final int deliveryChargeMinor;

  /// All tax contained in the total (exclusive tax added + inclusive tax extracted + tax on service charge).
  final int taxMinor;
  final int tipMinor;
  final int roundingMinor;
  final int totalMinor;
}

/// Splits [amount] across [weights] proportionally; the parts always sum to exactly [amount]
/// (largest remainder method, ties go to the earlier index).
List<int> allocate(int amount, List<int> weights) {
  final total = weights.fold<int>(0, (a, b) => a + b);
  if (amount == 0 || total == 0) return List.filled(weights.length, 0);
  final parts = <int>[];
  final remainders = <int>[];
  var given = 0;
  for (final w in weights) {
    final p = amount * w ~/ total;
    parts.add(p);
    remainders.add(amount * w % total);
    given += p;
  }
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final c = remainders[b].compareTo(remainders[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var i = 0; i < amount - given; i++) {
    parts[order[i]]++;
  }
  return parts;
}

BillResult calculateBill(List<BillLineInput> inputs, [BillConfig config = const BillConfig()]) {
  final gross = <int>[];
  final afterLine = <int>[];
  for (final l in inputs) {
    if (l.qtyMilli <= 0) throw ArgumentError('quantity must be positive (${l.id})');
    if (l.unitPriceMinor < 0 || l.modifiersMinor < 0) throw ArgumentError('price must not be negative (${l.id})');
    final g = roundDiv((l.unitPriceMinor + l.modifiersMinor) * l.qtyMilli, 1000);
    if (l.lineDiscountMinor < 0 || l.lineDiscountMinor > g) {
      throw ArgumentError('line discount out of range (${l.id})');
    }
    gross.add(g);
    afterLine.add(g - l.lineDiscountMinor);
  }
  final base = afterLine.fold<int>(0, (a, b) => a + b);

  var billDiscount = 0;
  final d = config.billDiscount;
  if (d != null) {
    if (d.value < 0) throw ArgumentError('discount must not be negative');
    billDiscount = d.kind == DiscountKind.percent ? roundDiv(base * d.value, 10000) : d.value;
    if (d.kind == DiscountKind.percent && d.value > 10000) throw ArgumentError('discount above 100%');
    if (billDiscount > base) throw ArgumentError('discount larger than the bill');
  }
  final shares = allocate(billDiscount, afterLine);

  final lines = <BillLineResult>[];
  var taxTotal = 0;
  var exclusiveTax = 0;
  var afterDiscountSum = 0;
  for (var i = 0; i < inputs.length; i++) {
    final l = inputs[i];
    final amount = afterLine[i] - shares[i];
    final split = splitTax(amount, l.taxRateBp, inclusive: l.taxInclusive);
    taxTotal += split.taxMinor;
    if (!l.taxInclusive) exclusiveTax += split.taxMinor;
    afterDiscountSum += amount;
    lines.add(BillLineResult(
      id: l.id,
      grossMinor: gross[i],
      discountMinor: l.lineDiscountMinor + shares[i],
      taxMinor: split.taxMinor,
      totalMinor: amount + (l.taxInclusive ? 0 : split.taxMinor),
    ));
  }

  final service = roundDiv(afterDiscountSum * config.serviceChargeBp, 10000) + config.serviceChargeFixedMinor;
  final serviceTax = roundDiv(service * config.serviceChargeTaxBp, 10000);
  taxTotal += serviceTax;

  final beforeRounding =
      afterDiscountSum + exclusiveTax + service + serviceTax + config.deliveryChargeMinor + config.tipMinor;
  final step = config.rounding.stepMinor;
  final rounded = step == 1 ? beforeRounding : roundDiv(beforeRounding, step) * step;

  return BillResult(
    lines: lines,
    subtotalMinor: gross.fold<int>(0, (a, b) => a + b),
    discountMinor: lines.fold<int>(0, (a, b) => a + b.discountMinor),
    serviceChargeMinor: service,
    deliveryChargeMinor: config.deliveryChargeMinor,
    taxMinor: taxTotal,
    tipMinor: config.tipMinor,
    roundingMinor: rounded - beforeRounding,
    totalMinor: rounded,
  );
}
