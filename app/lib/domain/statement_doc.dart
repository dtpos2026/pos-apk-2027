import 'escpos.dart';
import 'money.dart';
import 'receipt_doc.dart';

/// One line of a customer's credit statement. [amountMinor] is positive when the customer took credit and negative when they paid.
class StatementLine {
  const StatementLine({required this.at, required this.description, required this.amountMinor, required this.balanceMinor});
  final DateTime at;
  final String description;
  final int amountMinor;

  /// What the customer owed after this line.
  final int balanceMinor;
}

String _d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// The credit (udhaar) statement of one customer: every credit sale and repayment with the running balance. For printing,
/// previewing, sharing as a picture or as text.
ReceiptDoc buildStatementDoc({required String businessName, required String customerName, String? phone, required List<StatementLine> lines, required int balanceMinor, required Currency currency, required String printedAt}) {
  String m(int v) => formatMinor(v, currency: currency, symbol: false);
  final taken = lines.where((l) => l.amountMinor > 0).fold<int>(0, (s, l) => s + l.amountMinor);
  final paid = -lines.where((l) => l.amountMinor < 0).fold<int>(0, (s, l) => s + l.amountMinor);
  return ReceiptDoc([
    RText(businessName, align: PrintAlign.center, bold: true),
    const RText('CREDIT STATEMENT', align: PrintAlign.center, bold: true),
    const RRule(),
    RText(customerName, bold: true),
    if (phone != null && phone.isNotEmpty) RText(phone),
    const RRule(),
    for (final l in lines) ...[
      RRow('${_d(l.at)}  ${l.description}', l.amountMinor < 0 ? '-${m(-l.amountMinor)}' : m(l.amountMinor)),
      RRow('   balance', m(l.balanceMinor)),
    ],
    if (lines.isEmpty) const RText('No entries'),
    const RRule(),
    RRow('Credit taken', m(taken)),
    RRow('Paid back', m(paid)),
    RRow('BALANCE DUE', m(balanceMinor), bold: true, height: 2),
    const RRule(),
    RText('Printed $printedAt', align: PrintAlign.center),
    const RText('DT Food POS - Powered by Digital Target', align: PrintAlign.center),
    const RFeed(3),
  ]);
}

/// The same statement as a CSV (opens in Excel): date, description, credit, payment, balance.
String statementCsv(List<StatementLine> lines, {required Currency currency}) {
  String n(int v) => (v / currency.factor).toStringAsFixed(currency.minorDigits);
  String esc(String s) => s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('Date,Description,Credit,Payment,Balance\n');
  for (final l in lines) {
    b.writeln('${_d(l.at)},${esc(l.description)},${l.amountMinor > 0 ? n(l.amountMinor) : ''},${l.amountMinor < 0 ? n(-l.amountMinor) : ''},${n(l.balanceMinor)}');
  }
  return b.toString();
}
