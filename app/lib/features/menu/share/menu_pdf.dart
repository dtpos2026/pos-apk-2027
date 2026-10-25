import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import 'menu_doc.dart';
import 'menu_png.dart' show MenuLabels;

/// The QR of the WhatsApp link as picture bytes (PNG), for the PDF.
Future<Uint8List?> qrPngBytes(String? link, {int size = 360}) async {
  if (link == null) return null;
  final d = await QrPainter(data: link, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000))).toImageData(size.toDouble());
  return d?.buffer.asUint8List();
}

/// The menu as an A4 PDF, ready to print: a header with the logo, name and contact, each category with its items (picture, name,
/// description, sizes, price; a deal lists what is inside), page numbers, and the WhatsApp ordering block with a QR at the end.
/// [script] is a font with Urdu/Arabic letters so names in any language print.
Future<Uint8List> buildMenuPdf(MenuDoc d, {MenuLabels labels = const MenuLabels(), pw.Font? script}) async {
  final primary = PdfColor.fromInt(d.primary), accent = PdfColor.fromInt(d.accent);
  final light = (primary.red * 0.299 + primary.green * 0.587 + primary.blue * 0.114) > 0.62;
  final onPrimary = light ? PdfColors.grey900 : PdfColors.white;
  final accentText = (accent.red * 0.299 + accent.green * 0.587 + accent.blue * 0.114) > 0.62 ? PdfColor.fromInt(0xFF8A5A00) : accent;
  // a light tint of a colour as a SOLID colour (many PDF viewers ignore transparency and would paint it as the full colour)
  PdfColor tint(PdfColor c, double a) => PdfColor(1 - (1 - c.red) * a, 1 - (1 - c.green) * a, 1 - (1 - c.blue) * a);
  final doc = pw.Document(title: '${d.name} - ${labels.menu}', author: d.name, creator: 'DT Food POS');
  pw.MemoryImage? img(Uint8List? b) {
    if (b == null || b.isEmpty) return null;
    try {
      return pw.MemoryImage(b);
    } catch (_) {
      return null; // a damaged picture must never stop the menu
    }
  }

  final logo = img(d.logo);
  final qr = img(await qrPngBytes(d.qrLink));
  final mark = img(d.brandMark);

  pw.Widget header(pw.Context c) {
    if (c.pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: pw.BoxDecoration(color: primary, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(children: [pw.Expanded(child: pw.Text(d.name, style: pw.TextStyle(color: onPrimary, fontSize: 15, fontWeight: pw.FontWeight.bold))), pw.Text(labels.menu.toUpperCase(), style: pw.TextStyle(color: onPrimary, fontSize: 11, fontWeight: pw.FontWeight.bold))]),
      );
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(12), color: primary),
      child: pw.Column(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(18), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null) pw.Container(width: 64, height: 64, margin: const pw.EdgeInsets.only(right: 14), decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle), padding: const pw.EdgeInsets.all(4), child: pw.Image(logo, fit: pw.BoxFit.contain)),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(d.name, style: pw.TextStyle(color: onPrimary, fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text([labels.menu.toUpperCase(), if ((d.address ?? '').isNotEmpty) d.address!, if ((d.phone ?? '').isNotEmpty) d.phone!].join('   |   '), style: pw.TextStyle(color: onPrimary, fontSize: 10.5)),
            pw.SizedBox(height: 2),
            pw.Text('${labels.pricesIn} ${d.currencyCode}', style: pw.TextStyle(color: onPrimary, fontSize: 9)),
          ]),
        ),
        ])),
        pw.Container(height: 5, decoration: pw.BoxDecoration(color: accent, borderRadius: const pw.BorderRadius.only(bottomLeft: pw.Radius.circular(12), bottomRight: pw.Radius.circular(12)))),
      ]),
    );
  }

  pw.Widget title(MenuSection s) {
    final col = s.deals ? accentText : primary;
    final si = img(s.image);
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
      decoration: pw.BoxDecoration(color: tint(col, 0.12), borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(children: [
        pw.Container(width: 5, height: 30, decoration: pw.BoxDecoration(color: col, borderRadius: const pw.BorderRadius.only(topLeft: pw.Radius.circular(8), bottomLeft: pw.Radius.circular(8)))),
        pw.SizedBox(width: 9),
        if (si != null) pw.Container(width: 22, height: 22, margin: const pw.EdgeInsets.only(right: 8), child: pw.ClipOval(child: pw.Image(si, fit: pw.BoxFit.cover))),
        pw.Text(s.title, style: pw.TextStyle(color: col, fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  pw.Widget row(MenuSection s, MenuEntry e) {
    final im = img(e.image);
    final col = s.deals ? accentText : primary;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.6))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: 52,
          height: 52,
          margin: const pw.EdgeInsets.only(right: 10),
          child: im != null
              ? pw.ClipRRect(horizontalRadius: 6, verticalRadius: 6, child: pw.Image(im, fit: pw.BoxFit.cover))
              : pw.Container(
                  decoration: pw.BoxDecoration(color: tint(col, 0.14), borderRadius: pw.BorderRadius.circular(6)),
                  alignment: pw.Alignment.center,
                  child: pw.Text(e.name.trim().isEmpty ? '' : e.name.trim().substring(0, 1).toUpperCase(), style: pw.TextStyle(color: col, fontSize: 22, fontWeight: pw.FontWeight.bold))),
        ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(e.name, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
            if ((e.description ?? '').trim().isNotEmpty) pw.Text(e.description!.trim(), style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
            if (e.sizes.isNotEmpty) pw.Text(e.sizes.join('   •   '), style: pw.TextStyle(fontSize: 9.5, color: primary, fontWeight: pw.FontWeight.bold)),
            if (e.inside.isNotEmpty) pw.Text(e.inside.join('   •   '), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ]),
        ),
        pw.SizedBox(width: 8),
        pw.Text(e.price, style: pw.TextStyle(fontSize: 13.5, fontWeight: pw.FontWeight.bold, color: col)),
      ]),
    );
  }

  final body = <pw.Widget>[];
  for (final s in d.sections) {
    // the title travels with its first item, so a category never starts at the bottom of a page alone
    body.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [title(s), if (s.entries.isNotEmpty) row(s, s.entries.first)]));
    for (final e in s.entries.skip(1)) {
      body.add(row(s, e));
    }
  }
  body.add(pw.Container(
    margin: const pw.EdgeInsets.only(top: 18),
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(color: tint(primary, 0.07), border: pw.Border.all(color: primary, width: 0.8), borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(labels.orderOnWhatsApp, style: pw.TextStyle(color: primary, fontSize: 16, fontWeight: pw.FontWeight.bold)),
          if ((d.phone ?? '').isNotEmpty) pw.Text(d.phone!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(labels.orderHow, style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
          if ((d.address ?? '').isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(d.address!, style: const pw.TextStyle(fontSize: 10))),
        ]),
      ),
      if (qr != null) pw.Column(children: [pw.Image(qr, width: 92, height: 92), pw.Text(labels.scanToOrder, style: pw.TextStyle(color: primary, fontSize: 9, fontWeight: pw.FontWeight.bold))]),
    ]),
  ));

  doc.addPage(pw.MultiPage(
    theme: pw.ThemeData.withFont(fontFallback: [?script]),
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(30, 30, 30, 34),
    maxPages: 400,
    header: header,
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Text(d.name, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Row(children: [
        if (mark != null) pw.Padding(padding: const pw.EdgeInsets.only(right: 4), child: pw.Image(mark, width: 11, height: 11)),
        pw.Text(labels.poweredBy, style: pw.TextStyle(fontSize: 8, color: primary, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text('${labels.page} ${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ]),
    build: (c) => body,
  ));
  return doc.save();
}
