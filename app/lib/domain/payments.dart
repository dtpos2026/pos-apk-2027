enum PaymentKind { cash, card, bank, wallet, credit, other }

class PaymentInput {
  const PaymentInput(this.kind, this.amountMinor);
  final PaymentKind kind;

  /// For cash this is the amount handed over (may exceed what is due); for everything else it is the amount charged.
  final int amountMinor;
}

class SettlementResult {
  const SettlementResult({required this.paidMinor, required this.changeMinor, required this.dueMinor, required this.appliedMinor});

  /// Amount each input payment actually contributed, in input order (cash minus its change).
  final List<int> appliedMinor;

  /// Amount that actually settles the bill (cash change is excluded).
  final int paidMinor;
  final int changeMinor;
  final int dueMinor;
  bool get isSettled => dueMinor == 0;
}

/// Evaluates a (possibly split) payment against [totalMinor].
/// Only cash may exceed the amount due (it produces change). Any other method that would overpay is an error,
/// because there is nothing to hand back. Non-cash payments are applied before cash so change is only ever cash.
SettlementResult settle(int totalMinor, List<PaymentInput> payments) {
  if (totalMinor < 0) throw ArgumentError('total must not be negative');
  var remaining = totalMinor;
  var paid = 0;
  final applied = List<int>.filled(payments.length, 0);
  for (var i = 0; i < payments.length; i++) {
    final p = payments[i];
    if (p.kind == PaymentKind.cash) continue;
    if (p.amountMinor <= 0) throw ArgumentError('payment must be positive');
    if (p.amountMinor > remaining) throw ArgumentError('${p.kind.name} payment exceeds the amount due');
    remaining -= p.amountMinor;
    paid += p.amountMinor;
    applied[i] = p.amountMinor;
  }
  var change = 0;
  for (var i = 0; i < payments.length; i++) {
    final p = payments[i];
    if (p.kind != PaymentKind.cash) continue;
    if (p.amountMinor <= 0) throw ArgumentError('payment must be positive');
    final a = p.amountMinor > remaining ? remaining : p.amountMinor;
    change += p.amountMinor - a;
    remaining -= a;
    paid += a;
    applied[i] = a;
  }
  return SettlementResult(paidMinor: paid, changeMinor: change, dueMinor: remaining, appliedMinor: applied);
}
