import 'money.dart';

class TaxSplit {
  const TaxSplit({required this.netMinor, required this.taxMinor});
  final int netMinor;
  final int taxMinor;
  int get grossMinor => netMinor + taxMinor;
}

/// Tax on [amountMinor] at [rateBp] basis points (500 = 5%).
/// Exclusive: amount is the net price and tax is added on top.
/// Inclusive: amount already contains tax; it is extracted so that net + tax == amount exactly.
TaxSplit splitTax(int amountMinor, int rateBp, {required bool inclusive}) {
  if (rateBp < 0) throw ArgumentError('rate must not be negative');
  if (inclusive) {
    final net = roundDiv(amountMinor * 10000, 10000 + rateBp);
    return TaxSplit(netMinor: net, taxMinor: amountMinor - net);
  }
  return TaxSplit(netMinor: amountMinor, taxMinor: roundDiv(amountMinor * rateBp, 10000));
}
