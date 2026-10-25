import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Who a PDF belongs to: the restaurant's logo, name and contact on the left, the DT Food POS mark on the right.
class PdfBrand {
  const PdfBrand({required this.name, this.address, this.phone, this.logo, this.dtMark});
  final String name;
  final String? address;
  final String? phone;

  /// The restaurant's own logo (PNG/JPEG bytes), if one is set in Settings > Business.
  final Uint8List? logo;

  /// The Digital Target mark in red (PNG bytes).
  final Uint8List? dtMark;
}

const pdfBrandRed = PdfColor.fromInt(0xFFC92A2A);

/// The top of every PDF: restaurant logo + name + contact, the report title under it, and the company mark at the right.
pw.Widget pdfBrandHeader(PdfBrand b, {required String title, String? subtitle}) {
  pw.ImageProvider? img(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null; // a damaged picture must never stop the report
    }
  }

  final logo = img(b.logo), mark = img(b.dtMark);
  final contact = [if ((b.address ?? '').trim().isNotEmpty) b.address!.trim(), if ((b.phone ?? '').trim().isNotEmpty) b.phone!.trim()].join('  ·  ');
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      if (logo != null) pw.Container(width: 46, height: 46, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo, fit: pw.BoxFit.contain)),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(b.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (contact.isNotEmpty) pw.Text(contact, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
      ),
      if (mark != null)
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.SizedBox(width: 30, height: 30, child: pw.Image(mark, fit: pw.BoxFit.contain)),
          pw.SizedBox(height: 2),
          pw.Text('DT Food POS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: pdfBrandRed)),
        ]),
    ]),
    pw.SizedBox(height: 6),
    pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: pdfBrandRed)),
    if (subtitle != null) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
    pw.Divider(color: pdfBrandRed),
  ]);
}
