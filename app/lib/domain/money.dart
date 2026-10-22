/// Money is always an integer count of minor units (paisa / fils). Never a double.
class Currency {
  const Currency(this.code, {this.minorDigits = 2});
  final String code;
  final int minorDigits;

  static const pkr = Currency('PKR');
  static const aed = Currency('AED');

  int get factor {
    var f = 1;
    for (var i = 0; i < minorDigits; i++) {
      f *= 10;
    }
    return f;
  }
}

/// Integer division rounding half away from zero (so a refund mirrors the sale it reverses).
int roundDiv(int numerator, int denominator) {
  if (denominator <= 0) throw ArgumentError('denominator must be positive');
  final n = numerator.abs();
  final q = (2 * n + denominator) ~/ (2 * denominator);
  return numerator < 0 ? -q : q;
}

/// "PKR 1,234.50". [symbol] false returns just "1,234.50".
String formatMinor(int minor, {Currency currency = Currency.pkr, bool symbol = true}) {
  final neg = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ currency.factor;
  final frac = abs % currency.factor;
  final wholeStr = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final fracStr = currency.minorDigits == 0 ? '' : '.${frac.toString().padLeft(currency.minorDigits, '0')}';
  final body = '${neg ? '-' : ''}$wholeStr$fracStr';
  return symbol ? '${currency.code} $body' : body;
}

/// Parses user input such as "1,250.5" into minor units. Returns null if invalid.
int? parseMinor(String input, {Currency currency = Currency.pkr}) {
  final s = input.trim().replaceAll(',', '');
  final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  var frac = m.group(2) ?? '';
  if (frac.length > currency.minorDigits) return null;
  frac = frac.padRight(currency.minorDigits, '0');
  return whole * currency.factor + (frac.isEmpty ? 0 : int.parse(frac));
}

/// Quantity in thousandths: 1500 -> "1.5", 2000 -> "2".
String formatQty(int qtyMilli) {
  final whole = qtyMilli ~/ 1000;
  final frac = qtyMilli % 1000;
  if (frac == 0) return '$whole';
  return '$whole.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}
