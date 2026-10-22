import 'dart:typed_data';

import 'escpos.dart';
import 'money.dart';

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
}

String _m(int minor, Currency c) => formatMinor(minor, currency: c, symbol: false);

/// Customer bill. Text is ASCII-only; if [ReceiptData] contains Arabic-script text, the caller must render those
/// lines to bitmaps (see [needsRaster]) instead; this builder reports which fields need it via [rasterFields].
Uint8List buildBill(ReceiptData d, {int paperMm = 58, int copies = 1}) => _bill(d, paperMm, copies).toBytes();

/// The exact text that [buildBill] prints (without control codes): used for the on-screen print preview.
String previewBill(ReceiptData d, {int paperMm = 58}) => _bill(d, paperMm, 1).previewText;

EscPosBuilder _bill(ReceiptData d, int paperMm, int copies) {
  final b = EscPosBuilder(paperMm: paperMm);
  for (var copy = 0; copy < copies; copy++) {
    b.init().codePage(0);
    if (d.isDuplicate) {
      b.align(PrintAlign.center).bold(true).line('*** DUPLICATE ***').bold(false);
    }
    b.align(PrintAlign.center).bold(true).size(width: 2, height: 2).wrapped(d.businessName).size().bold(false);
    if (d.address != null) b.wrapped(d.address!);
    if (d.phone != null) b.line('Tel: ${d.phone}');
    if (d.taxNumber != null) b.line('${d.taxLabel ?? 'Tax no'}: ${d.taxNumber}');
    b.align(PrintAlign.left).divider();
    b.row('Invoice', d.invoiceNo);
    b.row('Date', d.dateTime);
    b.row('Type', d.tableLabel == null ? d.orderTypeLabel : '${d.orderTypeLabel} ${d.tableLabel}');
    if (d.cashier != null) b.row('Cashier', d.cashier!);
    b.divider();
    for (final l in d.lines) {
      b.row('${formatQty(l.qtyMilli)} x ${l.name}', _m(l.totalMinor, d.currency));
      for (final m in l.modifiers) {
        b.line('   + $m');
      }
      if (l.note != null) b.line('   * ${l.note}');
    }
    b.divider();
    b.row('Subtotal', _m(d.subtotalMinor, d.currency));
    if (d.discountMinor > 0) b.row('Discount', '-${_m(d.discountMinor, d.currency)}');
    if (d.serviceChargeMinor > 0) b.row('Service charge', _m(d.serviceChargeMinor, d.currency));
    if (d.deliveryChargeMinor > 0) b.row('Delivery', _m(d.deliveryChargeMinor, d.currency));
    if (d.taxMinor > 0) b.row('Tax', _m(d.taxMinor, d.currency));
    if (d.tipMinor > 0) b.row('Tip', _m(d.tipMinor, d.currency));
    if (d.roundingMinor != 0) b.row('Rounding', _m(d.roundingMinor, d.currency));
    b.bold(true).size(height: 2).row('TOTAL ${d.currency.code}', _m(d.totalMinor, d.currency)).size().bold(false);
    for (final p in d.payments) {
      b.row(p.label, _m(p.amountMinor, d.currency));
    }
    if (d.changeMinor > 0) b.row('Change', _m(d.changeMinor, d.currency));
    b.divider();
    b.align(PrintAlign.center);
    if (d.footer != null) b.wrapped(d.footer!);
    if (d.qrData != null) b.feed(1).qr(d.qrData!);
    b.line('Powered by Digital Target');
    b.cut();
  }
  return b;
}

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
