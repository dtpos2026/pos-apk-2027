import 'dart:convert';

/// The payment method row that stands for "paid with points" (kind other, hidden from the normal payment lists).
const loyaltyMethodId = 'loyalty';
const loyaltySettingKey = 'loyalty.config';

/// Loyalty points, fully offline: a customer on a paid bill earns points for what was paid in money, and can later spend
/// them as part of a payment. Off until the owner switches it on.
class LoyaltyConfig {
  const LoyaltyConfig({this.enabled = false, this.spendStepMinor = 10000, this.pointsPerStep = 1, this.pointValueMinor = 100, this.minRedeem = 0});
  final bool enabled;

  /// Every full [spendStepMinor] paid earns [pointsPerStep] points (default: 1 point per 100).
  final int spendStepMinor;
  final int pointsPerStep;

  /// What one point is worth when spent (default: 1 point = 1).
  final int pointValueMinor;

  /// Points a customer needs before they can spend any.
  final int minRedeem;

  int earnFor(int paidMinor) => !enabled || spendStepMinor <= 0 || paidMinor <= 0 ? 0 : (paidMinor ~/ spendStepMinor) * pointsPerStep;
  int valueOf(int points) => points * pointValueMinor;

  /// Points needed to pay [amountMinor] (rounded up: a part of a point is a whole point).
  int pointsFor(int amountMinor) => pointValueMinor <= 0 ? 0 : (amountMinor + pointValueMinor - 1) ~/ pointValueMinor;

  String encode() => jsonEncode({'on': enabled, 'step': spendStepMinor, 'per': pointsPerStep, 'value': pointValueMinor, 'min': minRedeem});
  static LoyaltyConfig decode(String? raw) {
    try {
      final j = jsonDecode(raw ?? '') as Map<String, dynamic>;
      int n(String k, int d) => j[k] is int && (j[k] as int) >= 0 ? j[k] as int : d;
      return LoyaltyConfig(enabled: j['on'] == true, spendStepMinor: n('step', 10000), pointsPerStep: n('per', 1), pointValueMinor: n('value', 100), minRedeem: n('min', 0));
    } catch (_) {
      return const LoyaltyConfig();
    }
  }
}
