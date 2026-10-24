import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/escpos.dart';
import '../../domain/receipt_doc.dart';

/// On-screen thermal paper rendered from the SAME [ReceiptDoc] the printer prints: text columns, logo bitmap
/// (after the printer's black/white conversion), alignment and Urdu/Arabic lines, so the owner sees what will come out.
class ReceiptPaper extends StatelessWidget {
  const ReceiptPaper({super.key, required this.doc, required this.paperMm});
  final ReceiptDoc doc;
  final int paperMm;

  static const double fontSize = 13;
  static const double charWidth = fontSize * 0.6;

  /// Width of the text area for [cols] columns (with a little slack for floating-point glyph advances).
  static double textWidthFor(int cols) => cols * charWidth + 3;

  @override
  Widget build(BuildContext context) {
    final cols = columnsFor(paperMm);
    // a little slack: glyph advances are floating point and a line of exactly `cols` characters must never wrap or clip
    final textWidth = textWidthFor(cols);
    final children = <Widget>[];
    for (final l in doc.lines) {
      children.add(_line(l, cols, textWidth));
    }
    return Container(
      key: const ValueKey('receipt-paper'),
      width: textWidth + 32,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['NotoNaskhArabic'], fontSize: fontSize, height: 1.3, color: Colors.black87),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  TextAlign _ta(PrintAlign a) => switch (a) { PrintAlign.left => TextAlign.left, PrintAlign.center => TextAlign.center, PrintAlign.right => TextAlign.right };

  Widget _line(RLine l, int cols, double textWidth) {
    switch (l) {
      case RText() when l.box && l.width == 1 && l.height == 1 && !needsRaster(l.text):
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in layoutBoxText(l.text, l.align, cols))
            SizedBox(width: textWidth, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(line, softWrap: false, style: TextStyle(fontWeight: l.bold ? FontWeight.w800 : FontWeight.w400)))),
        ]);
      case RText():
        final size = fontSize * (l.height > l.width ? l.height : l.width).clamp(1, 4);
        return SizedBox(
          width: textWidth,
          child: Text(l.text, textAlign: _ta(l.align), style: TextStyle(fontWeight: l.bold ? FontWeight.w800 : FontWeight.w400, fontSize: size, height: 1.25)),
        );
      case RRow():
        final raster = (needsRaster(l.left) || needsRaster(l.right)) && !l.inverse;
        if (raster) {
          return SizedBox(
            width: textWidth,
            child: Row(children: [
              Expanded(child: Text(l.left, textAlign: TextAlign.left, style: TextStyle(fontWeight: l.bold ? FontWeight.w800 : FontWeight.w400))),
              Text(l.right, style: TextStyle(fontWeight: l.bold ? FontWeight.w800 : FontWeight.w400)),
            ]),
          );
        }
        final weight = l.bold ? FontWeight.w800 : FontWeight.w400;
        if (l.inverse) {
          return Container(
            key: const ValueKey('receipt-inverse'),
            width: textWidth,
            color: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: Colors.white, fontWeight: weight, fontSize: fontSize * (l.height > 1 ? 1.5 : 1)),
              child: Row(children: [Expanded(child: Text(l.left)), Text(l.right)]),
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in layoutRow(l.left, l.right, cols, box: l.box))
            // double-height rows keep their width and are stretched vertically, exactly like ESC ! on the printer
            SizedBox(
              width: textWidth,
              height: fontSize * 1.3 * l.height,
              child: Transform(
                transform: Matrix4.diagonal3Values(1, l.height.toDouble(), 1),
                alignment: Alignment.topLeft,
                // Align loosens the tight height from the SizedBox above, so the line keeps ONE line of height and the transform doubles it
                child: Align(alignment: Alignment.topLeft, child: SizedBox(width: textWidth, height: fontSize * 1.3, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(line, softWrap: false, style: TextStyle(fontWeight: weight))))),
              ),
            ),
        ]);
      case RCols():
        final weight = l.bold ? FontWeight.w800 : FontWeight.w400;
        if (l.cells.any(needsRaster)) {
          return SizedBox(
            width: textWidth,
            child: Row(children: [
              Expanded(child: Text(l.cells.first, style: TextStyle(fontWeight: weight))),
              Text(l.cells.skip(1).where((c) => c.isNotEmpty).join('  '), style: TextStyle(fontWeight: weight)),
            ]),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in layoutCols(l.cells, l.widths, cols, box: l.box))
            SizedBox(width: textWidth, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(line, softWrap: false, style: TextStyle(fontWeight: weight)))),
        ]);
      case RRule():
        return SizedBox(width: textWidth, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(ruleText(l.ch, cols), softWrap: false, style: const TextStyle(color: Colors.black45))));
      case RImage():
        return SizedBox(width: textWidth, child: _ImagePreview(image: l.image.padded(dotsFor(paperMm), l.align), width: textWidth));
      case RQr():
        return SizedBox(width: textWidth, child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: QrImageView(data: l.data, size: 110, padding: EdgeInsets.zero, backgroundColor: Colors.white))));
      case RFeed():
        return SizedBox(height: fontSize * 1.3 * l.lines);
    }
  }
}

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.image, required this.width});
  final RasterImage image;
  final double width;
  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _ImagePreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.image, widget.image)) _decode();
  }

  void _decode() {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(widget.image.toRgba(), widget.image.widthPx, widget.image.heightPx, ui.PixelFormat.rgba8888, c.complete);
    c.future.then((i) {
      if (mounted) setState(() => _img = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = _img;
    final h = widget.width * widget.image.heightPx / widget.image.widthPx;
    return SizedBox(height: h, width: widget.width, child: i == null ? null : RawImage(key: const ValueKey('logo-preview'), image: i, fit: BoxFit.fill, filterQuality: FilterQuality.none));
  }
}
