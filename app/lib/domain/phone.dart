/// Converts a local number to the international digits WhatsApp needs: "0300-1234567" -> "923001234567" (PK),
/// "050 123 4567" -> "971501234567" (UAE). Returns null when it does not look like a phone number.
String? internationalPhone(String raw, {required String countryCode}) {
  var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.startsWith('+')) {
    d = d.substring(1);
  } else if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.startsWith('0')) {
    d = countryCode + d.substring(1);
  } else if (!d.startsWith(countryCode)) {
    d = countryCode + d;
  }
  d = d.replaceAll('+', '');
  return d.length >= 10 && d.length <= 15 ? d : null;
}

/// Country calling code from the business currency (PKR -> 92, AED -> 971).
String callingCodeFor(String currencyCode) => currencyCode == 'AED' ? '971' : '92';
