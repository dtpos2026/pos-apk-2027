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
    this.token,
    this.deliveryTo = const [],
  });

  /// Who the delivery is for (name, phone, address); empty for other order types.
  final List<String> deliveryTo;

  /// Token label ("17", "A17") when the order has one, printed big on the bill.
  final String? token;
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
/// then the invoice details, items, totals, payments and footer. Which blocks appear, and the look ([BillDesign.style]),
/// is up to the [template].
ReceiptDoc buildBillDoc(ReceiptData d, {BillDesign template = BillDesign.defaults}) {
  final t = template;
  final L = BillLabels.of(t.language);
  final h = t.headerAlign;
  final body = L.rtl ? PrintAlign.right : PrintAlign.left;
  final style = t.style;
  final grid = style == 'grid';
  final RLine rule = switch (style) {
    'modern' => const RRule('- '),
    'boxed' || 'restaurant' || 'bold' => const RRule('='),
    'grid' => const RRule('+'),
    'luxury' => const RRule('*'),
    'ticket' => const RRule('. '),
    'minimal' => const RFeed(),
    _ => const RRule(),
  };
  final lines = <RLine>[];
  // label on the reading-start side, value on the other: flipped for right-to-left bills
  RLine row(String label, String value, {bool bold = false, int height = 1}) => L.rtl ? RRow(value, label, bold: bold, height: height, box: grid) : RRow(label, value, bold: bold, height: height, box: grid);
  String typeLabel(String code) => switch (code) { 'Dine-in' => L['dine_in'], 'Takeaway' => L['takeaway'], 'Delivery' => L['delivery_type'], 'Counter' => L['counter'], _ => code };
  String money(int v) => _m(v, d.currency);

  if (d.isDuplicate) lines.add(RText(L['duplicate'], align: PrintAlign.center, bold: true));
  if (t.showLogo && d.logo != null) lines.add(RImage(d.logo!, align: t.logoAt));
  final name = style == 'modern' ? '- ${d.businessName} -' : d.businessName.toUpperCase() == d.businessName && style == 'luxury' ? d.businessName : d.businessName;
  lines.add(RText(name, align: t.nameAt, bold: true, width: t.nameSize, height: t.nameSize));
  for (final l in t.headerLines.where((l) => l.trim().isNotEmpty)) {
    lines.add(RText(l, align: h));
  }
  if (t.showAddress && (d.address?.trim().isNotEmpty ?? false)) lines.add(RText(d.address!, align: h));
  // numbers inside a right-to-left line are wrapped in a left-to-right isolate so 0300-1234567 never comes out reversed
  String ltr(String s) => L.rtl ? '\u2066$s\u2069' : s;
  if (t.showPhone && (d.phone?.trim().isNotEmpty ?? false)) lines.add(RText('${L['tel']}: ${ltr(d.phone!)}', align: h));
  if (t.showTaxNumber && (d.taxNumber?.trim().isNotEmpty ?? false)) lines.add(RText('${d.taxLabel ?? 'Tax no'}: ${ltr(d.taxNumber!)}', align: h));
  if (t.title.trim().isNotEmpty) {
    lines
      ..add(rule)
      ..add(RText(t.title.trim(), align: PrintAlign.center, bold: true, box: grid))
      ..add(rule);
  } else {
    lines.add(rule);
  }
  final dtr = style == 'dtretail';
  if (dtr) {
    // boxed TYPE / TABLE / TOKEN cells, as on the DT Retail POS slips
    final type = typeLabel(d.orderTypeLabel).toUpperCase();
    final hasTable = t.showTable && d.tableLabel != null;
    if (hasTable || d.token != null) {
      final head = [L['type'].toUpperCase(), if (hasTable) L['table'].toUpperCase(), if (d.token != null) L['token'].toUpperCase()];
      final vals = [type, if (hasTable) d.tableLabel!, if (d.token != null) '#${d.token}'];
      final w = [for (var i = 1; i < head.length; i++) 9];
      lines
        ..add(const RRule('+'))
        ..add(RCols(head, w, box: true))
        ..add(RCols(vals, w, bold: true, box: true))
        ..add(const RRule('+'));
    } else {
      lines.add(RText(type, align: PrintAlign.center, bold: true, box: true));
    }
  } else if (t.showToken && d.token != null) {
    lines
      ..add(RText('${L['token']} #', align: PrintAlign.center))
      ..add(RText(d.token!, align: PrintAlign.center, bold: true, width: 3, height: 3))
      ..add(rule);
  }
  lines.add(row(L['invoice'], d.invoiceNo));
  lines.add(row(L['date'], d.dateTime));
  if (t.showOrderType && !dtr) {
    final type = typeLabel(d.orderTypeLabel);
    lines.add(row(L['type'], t.showTable && d.tableLabel != null ? '$type ${d.tableLabel}' : type));
  }
  if (t.showCashier && d.cashier != null) lines.add(row(L['cashier'], d.cashier!));
  for (final x in d.deliveryTo) {
    lines.add(RText(x, align: body));
  }
  lines.add(rule);

  // items
  final numbered = style == 'retail' || style == 'tax' || grid;
  final table = (style == 'boxed' || numbered) && !L.rtl;
  if (table) {
    lines.add(RCols([numbered ? 'Sr  ${L['item']}' : L['item'], L['qty'], L['rate'], L['amount']], const [5, 7, 9], bold: true, box: grid));
    lines.add(grid ? const RRule('+') : const RRule());
  }
  var n = 0;
  for (final l in d.lines) {
    n++;
    final qty = formatQty(l.qtyMilli);
    if (table) {
      lines.add(RCols([numbered ? '$n  ${l.name}' : l.name, qty, money(l.unitPriceMinor), money(l.totalMinor)], const [5, 7, 9], box: grid));
    } else if (style == 'ticket') {
      lines.add(RText(L.rtl ? '${l.name} x $qty' : '$qty x ${l.name}', align: body, bold: true));
    } else if (style == 'minimal') {
      lines.add(row(L.rtl ? '${l.name} $qty' : '$qty ${l.name}', money(l.totalMinor)));
    } else if (style == 'bold') {
      lines.add(row(L.rtl ? '${l.name} x $qty' : '$qty x ${l.name}', money(l.totalMinor), bold: true));
    } else if (style == 'modern') {
      lines.add(row(L.rtl ? '${l.name} x $qty  .$n' : '$n  ${l.name} x $qty', money(l.totalMinor)));
    } else {
      // reading order: left-to-right bills say "2 x Burger", right-to-left bills say "Burger x 2" (name first, from the right)
      lines.add(row(L.rtl ? '${l.name} x $qty' : '$qty x ${l.name}', money(l.totalMinor)));
    }
    for (final m in l.modifiers) {
      lines.add(RText('   + $m', align: body));
    }
    if (l.note != null && style != 'compact') lines.add(RText('   * ${l.note}', align: body));
  }
  lines.add(rule);
  if (t.showItemCount) {
    final count = d.lines.fold<int>(0, (s, l) => s + l.qtyMilli) / 1000;
    lines.add(row('${L['items']}: ${formatQty((count * 1000).round())}', ''));
  }
  final onlySubtotal = d.discountMinor == 0 && d.serviceChargeMinor == 0 && d.deliveryChargeMinor == 0 && d.taxMinor == 0 && d.tipMinor == 0 && d.roundingMinor == 0;
  if (style != 'ticket' && !(style == 'compact' && onlySubtotal)) lines.add(row(style == 'tax' ? 'Gross Amount' : L['subtotal'], money(d.subtotalMinor)));
  if (d.discountMinor > 0) lines.add(row(L['discount'], '-${money(d.discountMinor)}'));
  if (d.serviceChargeMinor > 0) lines.add(row(L['service'], money(d.serviceChargeMinor)));
  if (d.deliveryChargeMinor > 0) lines.add(row(L['delivery'], money(d.deliveryChargeMinor)));
  if (style == 'tax' && d.taxMinor > 0) lines.add(row('Value excl. tax', money(d.totalMinor - d.taxMinor)));
  if (d.taxMinor > 0) lines.add(row(L['tax'], money(d.taxMinor)));
  if (d.tipMinor > 0) lines.add(row(L['tip'], money(d.tipMinor)));
  if (d.roundingMinor != 0) lines.add(row(L['rounding'], money(d.roundingMinor)));
  switch (style) {
    case 'dtretail':
      final totalWord = L['total'].toUpperCase(), totalValue = '${d.currency.code} ${money(d.totalMinor)}';
      lines.add(L.rtl ? RRow(totalValue, totalWord, bold: true, height: 2, inverse: true) : RRow(totalWord, totalValue, bold: true, height: 2, inverse: true));
    case 'boxed':
      lines.add(rule);
      lines.add(row('${L['net_bill']} ${d.currency.code}', money(d.totalMinor), bold: true, height: 2));
    case 'modern' || 'bold' || 'luxury':
      lines.add(rule);
      lines.add(RText('${L['total']} ${d.currency.code}', align: PrintAlign.center, bold: true));
      lines.add(RText(money(d.totalMinor), align: PrintAlign.center, bold: true, width: 2, height: 2));
    case 'grid':
      lines.add(row('GRAND TOTAL', money(d.totalMinor), bold: true, height: 2));
    case 'tax':
      lines.add(rule);
      lines.add(row('NET PAYABLE', '${d.currency.code} ${money(d.totalMinor)}', bold: true, height: 2));
    case 'minimal':
      lines.add(row('${L['total']} ${d.currency.code}', money(d.totalMinor), bold: true));
    default:
      lines.add(row('${L['total']} ${d.currency.code}', money(d.totalMinor), bold: true, height: 2));
  }
  if (t.amountInWords && t.language == 'en') lines.add(RText(amountInWords(d.totalMinor, d.currency), align: PrintAlign.center));
  if (style == 'modern' && d.payments.isNotEmpty) lines.add(rule);
  for (final p in d.payments) {
    final label = switch (p.label) { 'Cash' => L['cash'], 'Card' => L['card'], _ => p.label };
    lines.add(row(label, money(p.amountMinor)));
  }
  if (d.changeMinor > 0) lines.add(row(L['change'], money(d.changeMinor)));
  lines.add(rule);
  final footers = t.footerLines.map((l) => l == BillDesign.defaultFooter ? L['thanks'] : l).where((l) => l.trim().isNotEmpty);
  for (final l in footers) {
    lines.add(RText(l, align: PrintAlign.center));
  }
  if (style == 'modern') lines.add(rule);
  final qr = t.qrText ?? d.qrData ?? (style == 'tax' ? d.invoiceNo : null);
  if (qr != null && qr.isNotEmpty) {
    lines.add(const RFeed());
    lines.add(RQr(qr));
  }
  if (t.showPoweredBy) lines.add(RText(dtr ? 'Powered by Digital Target · DT Food POS' : 'Powered by Digital Target', align: PrintAlign.center));
  return ReceiptDoc(lines, copies: t.copies);
}

const _ones = ['ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN', 'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN'];
const _tens = ['', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY', 'EIGHTY', 'NINETY'];

String _words(int n) {
  if (n < 20) return _ones[n];
  if (n < 100) return _tens[n ~/ 10] + (n % 10 == 0 ? '' : '-${_ones[n % 10]}');
  if (n < 1000) return '${_ones[n ~/ 100]} HUNDRED${n % 100 == 0 ? '' : ' ${_words(n % 100)}'}';
  for (final (size, word) in const [(1000000000, 'BILLION'), (1000000, 'MILLION'), (1000, 'THOUSAND')]) {
    if (n >= size) return '${_words(n ~/ size)} $word${n % size == 0 ? '' : ' ${_words(n % size)}'}';
  }
  return '$n';
}

/// "FOUR THOUSAND FIVE HUNDRED SEVENTY-FOUR ONLY" (international system, as printed on Pakistani bills).
/// A fractional part is written as "AND 45/100".
String amountInWords(int minor, Currency c) {
  final div = c.minorDigits == 0 ? 1 : [1, 10, 100, 1000][c.minorDigits];
  final major = minor.abs() ~/ div, frac = minor.abs() % div;
  final f = frac == 0 ? '' : ' AND $frac/$div';
  return '${minor < 0 ? 'MINUS ' : ''}${_words(major)}$f ONLY';
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

/// Kitchen order ticket for one station: big, no prices. The look comes from [design].
ReceiptDoc buildKotDoc({
  required String station,
  required String orderLabel,
  required String orderTypeLabel,
  required String dateTime,
  required List<KotLine> lines,
  String? tableLabel,
  String? waiter,
  String? token,
  List<String> deliveryTo = const [],
  bool isReprint = false,
  KotDesign design = KotDesign.defaults,
}) {
  final style = design.style;
  final out = <RLine>[];
  final big = style == 'big';
  if (style == 'compact') {
    out.add(RRow('${design.title} ${station.toUpperCase()}', dateTime, bold: true));
    if (isReprint) out.add(const RText('*** REPRINT ***', align: PrintAlign.center, bold: true));
    final where = [if (design.showToken && token != null) 'Token $token', if (design.showTable && tableLabel != null) '$orderTypeLabel $tableLabel' else orderTypeLabel].join('  ');
    out.add(RRow(where, orderLabel));
  } else {
    out.add(RText(design.title, align: PrintAlign.center, bold: true, width: 2, height: 2));
    out.add(RText(station.toUpperCase(), align: PrintAlign.center, bold: true));
    if (isReprint) out.add(const RText('*** REPRINT ***', align: PrintAlign.center, bold: true));
    if (design.showToken && token != null) {
      out
        ..add(const RRule('='))
        ..add(RText('TOKEN $token', align: PrintAlign.center, bold: true, width: big ? 3 : 2, height: big ? 3 : 2));
    }
    if (big && design.showTable && tableLabel != null) out.add(RText('TABLE $tableLabel', align: PrintAlign.center, bold: true, width: 2, height: 2));
    out.add(const RRule());
    out.add(RRow('Order', orderLabel));
    out.add(RRow('Type', design.showTable && tableLabel != null ? '$orderTypeLabel $tableLabel' : orderTypeLabel));
    out.add(RRow('Time', dateTime));
  }
  if (design.showWaiter && waiter != null) out.add(RRow('Waiter', waiter));
  for (final x in deliveryTo) {
    out.add(RText(x, bold: true));
  }
  out.add(const RRule());
  for (final l in lines) {
    out.add(RText('${formatQty(l.qtyMilli)} x ${l.name}', bold: true, width: big ? 2 : 1, height: style == 'compact' ? 1 : 2));
    for (final m in l.modifiers) {
      out.add(RText('   + $m'));
    }
    if (design.showNotes && l.note != null) out.add(RText('   * ${l.note}', bold: big));
  }
  out.add(const RRule());
  final items = lines.fold<int>(0, (s, l) => s + l.qtyMilli);
  out.add(RText('Items: ${formatQty(items)}', align: PrintAlign.right));
  return ReceiptDoc(out, copies: design.copies);
}

/// Kitchen ticket as ESC/POS bytes (synchronous; Urdu item names need [buildKotDoc] + a rasterizer).
Uint8List buildKot({
  required String station,
  required String orderLabel,
  required String orderTypeLabel,
  required String dateTime,
  required List<KotLine> lines,
  String? tableLabel,
  String? waiter,
  String? token,
  int paperMm = 58,
  bool isReprint = false,
  KotDesign design = KotDesign.defaults,
}) {
  final doc = buildKotDoc(station: station, orderLabel: orderLabel, orderTypeLabel: orderTypeLabel, dateTime: dateTime, lines: lines, tableLabel: tableLabel, waiter: waiter, token: token, isReprint: isReprint, design: design);
  final b = EscPosRenderer(paperMm: paperMm).renderSync(doc);
  return (b..cut()).toBytes();
}
