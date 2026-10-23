import 'dart:typed_data';

import 'bill_labels.dart';
import 'escpos.dart';
import 'money.dart';
import 'receipt_doc.dart';
import 'receipt_template.dart';

class ReceiptLine {
  const ReceiptLine({required this.name, required this.qtyMilli, required this.unitPriceMinor, required this.totalMinor, this.modifiers = const [], this.note});
  final String name;
  final int qtyMilli;
  final int unitPriceMinor;
  final int totalMinor;
  final List<String> modifiers;
  final String? note;
}

class ReceiptPayment {
  const ReceiptPayment(this.label, this.amountMinor);
  final String label;
  final int amountMinor;
}

class ReceiptData {
  const ReceiptData({
    required this.businessName,
    required this.invoiceNo,
    required this.dateTime,
    required this.orderTypeLabel,
    required this.lines,
    required this.subtotalMinor,
    required this.totalMinor,
    this.address,
    this.phone,
    this.taxLabel,
    this.taxNumber,
    this.tableLabel,
    this.cashier,
    this.discountMinor = 0,
    this.serviceChargeMinor = 0,
    this.deliveryChargeMinor = 0,
    this.taxMinor = 0,
    this.tipMinor = 0,
    this.roundingMinor = 0,
    this.payments = const [],
    this.changeMinor = 0,
    this.footer,
    this.qrData,
    this.isDuplicate = false,
    this.currency = Currency.pkr,
    this.logo,
  });
  final String businessName;
  final String? address;
  final String? phone;
  final String? taxLabel;
  final String? taxNumber;
  final String invoiceNo;
  final String dateTime;
  final String orderTypeLabel;
  final String? tableLabel;
  final String? cashier;
  final List<ReceiptLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int serviceChargeMinor;
  final int deliveryChargeMinor;
  final int taxMinor;
  final int tipMinor;
  final int roundingMinor;
  final int totalMinor;
  final List<ReceiptPayment> payments;
  final int changeMinor;
  final String? footer;
  final String? qrData;
  final bool isDuplicate;
  final Currency currency;

  /// Logo already converted to a 1-bit bitmap for this paper width (see logo.dart). null = no logo.
  final RasterImage? logo;
}

String _m(int minor, Currency c) => formatMinor(minor, currency: c, symbol: false);

/// Builds the customer bill as a [ReceiptDoc]: logo, name, address, phone and tax number centred by default,
/// then the invoice details, items, totals, payments and footer. Which blocks appear is up to the [template].
ReceiptDoc buildBillDoc(ReceiptData d, {BillDesign template = BillDesign.defaults}) {
  final t = template;
  final L = BillLabels.of(t.language);
  final h = t.headerAlign;
  final body = L.rtl ? PrintAlign.right : PrintAlign.left;
  final lines = <RLine>[];
  // label on the reading-start side, value on the other: flipped for right-to-left bills
  RLine row(String label, String value, {bool bold = false, int height = 1}) => L.rtl ? RRow(value, label, bold: bold, height: height) : RRow(label, value, bold: bold, height: height);
  String typeLabel(String code) => switch (code) { 'Dine-in' => L['dine_in'], 'Takeaway' => L['takeaway'], 'Delivery' => L['delivery_type'], 'Counter' => L['counter'], _ => code };

  if (d.isDuplicate) lines.add(RText(L['duplicate'], align: PrintAlign.center, bold: true));
  if (t.showLogo && d.logo != null) lines.add(RImage(d.logo!, align: h));
  lines.add(RText(d.businessName, align: h, bold: true, width: t.nameSize, height: t.nameSize));
  for (final l in t.headerLines.where((l) => l.trim().isNotEmpty)) {
    lines.add(RText(l, align: h));
  }
  if (t.showAddress && (d.address?.trim().isNotEmpty ?? false)) lines.add(RText(d.address!, align: h));
  // numbers inside a right-to-left line are wrapped in a left-to-right isolate so 0300-1234567 never comes out reversed
  String ltr(String s) => L.rtl ? '\u2066$s\u2069' : s;
  if (t.showPhone && (d.phone?.trim().isNotEmpty ?? false)) lines.add(RText('${L['tel']}: ${ltr(d.phone!)}', align: h));
  if (t.showTaxNumber && (d.taxNumber?.trim().isNotEmpty ?? false)) lines.add(RText('${d.taxLabel ?? 'Tax no'}: ${ltr(d.taxNumber!)}', align: h));
  lines.add(const RRule());
  lines.add(row(L['invoice'], d.invoiceNo));
  lines.add(row(L['date'], d.dateTime));
  if (t.showOrderType) {
    final type = typeLabel(d.orderTypeLabel);
    lines.add(row(L['type'], t.showTable && d.tableLabel != null ? '$type ${d.tableLabel}' : type));
  }
  if (t.showCashier && d.cashier != null) lines.add(row(L['cashier'], d.cashier!));
  lines.add(const RRule());
  for (final l in d.lines) {
    // reading order: left-to-right bills say "2 x Burger", right-to-left bills say "Burger x 2" (name first, from the right)
    lines.add(row(L.rtl ? '${l.name} x ${formatQty(l.qtyMilli)}' : '${formatQty(l.qtyMilli)} x ${l.name}', _m(l.totalMinor, d.currency)));
    for (final m in l.modifiers) {
      lines.add(RText('   + $m', align: body));
    }
    if (l.note != null) lines.add(RText('   * ${l.note}', align: body));
  }
  lines.add(const RRule());
  lines.add(row(L['subtotal'], _m(d.subtotalMinor, d.currency)));
  if (d.discountMinor > 0) lines.add(row(L['discount'], '-${_m(d.discountMinor, d.currency)}'));
  if (d.serviceChargeMinor > 0) lines.add(row(L['service'], _m(d.serviceChargeMinor, d.currency)));
  if (d.deliveryChargeMinor > 0) lines.add(row(L['delivery'], _m(d.deliveryChargeMinor, d.currency)));
  if (d.taxMinor > 0) lines.add(row(L['tax'], _m(d.taxMinor, d.currency)));
  if (d.tipMinor > 0) lines.add(row(L['tip'], _m(d.tipMinor, d.currency)));
  if (d.roundingMinor != 0) lines.add(row(L['rounding'], _m(d.roundingMinor, d.currency)));
  lines.add(row('${L['total']} ${d.currency.code}', _m(d.totalMinor, d.currency), bold: true, height: 2));
  for (final p in d.payments) {
    final label = switch (p.label) { 'Cash' => L['cash'], 'Card' => L['card'], _ => p.label };
    lines.add(row(label, _m(p.amountMinor, d.currency)));
  }
  if (d.changeMinor > 0) lines.add(row(L['change'], _m(d.changeMinor, d.currency)));
  lines.add(const RRule());
  final footers = t.footerLines.map((l) => l == BillDesign.defaultFooter ? L['thanks'] : l).where((l) => l.trim().isNotEmpty);
  for (final l in footers) {
    lines.add(RText(l, align: PrintAlign.center));
  }
  final qr = t.qrText ?? d.qrData;
  if (qr != null && qr.isNotEmpty) {
    lines.add(const RFeed());
    lines.add(RQr(qr));
  }
  if (t.showPoweredBy) lines.add(const RText('Powered by Digital Target', align: PrintAlign.center));
  return ReceiptDoc(lines, copies: t.copies);
}

/// Customer bill as ESC/POS bytes (synchronous: Arabic-script text prints as '?'; use [buildBillBytes] for that).
Uint8List buildBill(ReceiptData d, {int paperMm = 58, int? copies, BillDesign template = BillDesign.defaults}) {
  final t = copies == null ? template : template.copyWith(copies: copies);
  final b = EscPosRenderer(paperMm: paperMm).renderSync(buildBillDoc(d, template: t));
  return (b..cut()).toBytes();
}

/// Full render: Urdu/Arabic lines are printed as bitmaps when a [rasterizer] is given.
Future<Uint8List> buildBillBytes(ReceiptData d, {int paperMm = 58, BillDesign template = BillDesign.defaults, TextRasterizer? rasterizer}) async {
  final b = await EscPosRenderer(paperMm: paperMm, rasterizer: rasterizer).render(buildBillDoc(d, template: template));
  return (b..cut()).toBytes();
}

/// The text the printer prints (alignment applied, without control codes): fallback preview and tests.
String previewBill(ReceiptData d, {int paperMm = 58, BillDesign template = BillDesign.defaults}) =>
    docToText(buildBillDoc(d, template: template), paperMm);

/// Names of fields in [d] that contain Arabic-script text and therefore need bitmap rendering.
List<String> rasterFields(ReceiptData d) {
  final out = <String>[];
  void chk(String field, String? v) {
    if (v != null && needsRaster(v)) out.add(field);
  }

  chk('businessName', d.businessName);
  chk('address', d.address);
  chk('footer', d.footer);
  chk('cashier', d.cashier);
  for (var i = 0; i < d.lines.length; i++) {
    chk('lines[$i].name', d.lines[i].name);
    chk('lines[$i].note', d.lines[i].note);
    for (final m in d.lines[i].modifiers) {
      chk('lines[$i].modifier', m);
    }
  }
  return out;
}

class KotLine {
  const KotLine(this.name, this.qtyMilli, {this.modifiers = const [], this.note});
  final String name;
  final int qtyMilli;
  final List<String> modifiers;
  final String? note;
}

/// Kitchen order ticket for one station: big, no prices.
Uint8List buildKot({
  required String station,
  required String orderLabel,
  required String orderTypeLabel,
  required String dateTime,
  required List<KotLine> lines,
  String? tableLabel,
  String? waiter,
  int paperMm = 58,
  bool isReprint = false,
}) {
  final b = EscPosBuilder(paperMm: paperMm).init().codePage(0);
  b.align(PrintAlign.center).bold(true).size(width: 2, height: 2).line('KOT');
  b.size().line(station.toUpperCase()).bold(false);
  if (isReprint) b.bold(true).line('*** REPRINT ***').bold(false);
  b.align(PrintAlign.left).divider();
  b.row('Order', orderLabel);
  b.row('Type', tableLabel == null ? orderTypeLabel : '$orderTypeLabel $tableLabel');
  b.row('Time', dateTime);
  if (waiter != null) b.row('Waiter', waiter);
  b.divider();
  for (final l in lines) {
    b.bold(true).size(height: 2).wrapped('${formatQty(l.qtyMilli)} x ${l.name}').size().bold(false);
    for (final m in l.modifiers) {
      b.line('   + $m');
    }
    if (l.note != null) b.line('   * ${l.note}');
  }
  b.divider().cut();
  return b.toBytes();
}
