import '../data/shift_service.dart';
import 'escpos.dart';
import 'money.dart';
import 'receipt_doc.dart';

String _time(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The day-close (Z) slip, for the printer and for sharing as text. Same figures as the Day close screen.
ReceiptDoc buildZReportDoc(ZReport z, {required String businessName, required Currency currency, required String printedAt}) {
  String m(int v) => formatMinor(v, currency: currency, symbol: false);
  return ReceiptDoc([
    RText(businessName, align: PrintAlign.center, bold: true),
    const RText('DAY CLOSE (Z REPORT)', align: PrintAlign.center, bold: true),
    RText(z.date, align: PrintAlign.center),
    if (z.closedAt == null) const RText('NOT CLOSED YET (preview)', align: PrintAlign.center),
    const RRule(),
    RRow('Bills', '${z.bills}'),
    RRow('Gross sales', m(z.grossMinor)),
    RRow('Discounts given', m(z.discountMinor)),
    RRow('Refunds', m(z.refundsMinor)),
    RRow('NET SALES', m(z.netMinor), bold: true),
    RRow('Tax included', m(z.taxMinor)),
    const RRule(),
    const RText('Received by method', bold: true),
    for (final e in z.byMethod.entries) RRow(e.key, m(e.value)),
    if (z.byMethod.isEmpty) const RText('-'),
    const RRule(),
    RRow('Udhaar given', m(z.creditGivenMinor)),
    RRow('Udhaar recovered', m(z.creditRecoveredMinor)),
    RRow('Expenses', m(z.expensesMinor)),
    const RRule(),
    const RText('Cash drawer', bold: true),
    for (final s in z.shifts) ...[
      RText('${s.staff}  ${_time(s.openedAt)}-${s.closedAt == null ? 'open' : _time(s.closedAt!)}'),
      RRow('  Opening', m(s.openingMinor)),
      if (s.expectedMinor != null) RRow('  Expected', m(s.expectedMinor!)),
      if (s.countedMinor != null) RRow('  Counted', m(s.countedMinor!)),
      if (s.varianceMinor != null) RRow('  Short/over', m(s.varianceMinor!), bold: true),
    ],
    if (z.shifts.isEmpty) const RText('No shift'),
    const RRule(),
    RText('Printed $printedAt', align: PrintAlign.center),
    const RText('DT Food POS - Powered by Digital Target', align: PrintAlign.center),
    const RFeed(3),
  ]);
}
