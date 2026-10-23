import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../domain/escpos.dart';
import '../domain/receipt_doc.dart';

/// Draws Urdu/Arabic text with the Flutter text engine (correct letter shaping and right-to-left order) and turns it
/// into a 1-bit bitmap for the printer. Slower and bigger than ESC/POS text, but the only way thermal printers
/// without Arabic fonts can print these scripts.
class FlutterTextRasterizer implements TextRasterizer {
  const FlutterTextRasterizer({this.baseSize = 24});
  final double baseSize;

  TextStyle _style(bool bold, int scale) => TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoNaskhArabic'],
        fontSize: baseSize * scale,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: const Color(0xFF000000),
        height: 1.35,
      );

  TextDirection _dir(String s) => RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]').hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

  TextAlign _align(PrintAlign a) => switch (a) { PrintAlign.left => TextAlign.left, PrintAlign.center => TextAlign.center, PrintAlign.right => TextAlign.right };

  @override
  Future<RasterImage> text(String text, {required int widthPx, PrintAlign align = PrintAlign.left, bool bold = false, int scale = 1}) async {
    final tp = TextPainter(text: TextSpan(text: text, style: _style(bold, scale.clamp(1, 3))), textDirection: _dir(text), textAlign: _align(align))
      ..layout(minWidth: widthPx.toDouble(), maxWidth: widthPx.toDouble());
    return _capture(widthPx, tp.height.ceil() + 6, (c) => tp.paint(c, const Offset(0, 3)));
  }

  @override
  Future<RasterImage> row(String left, String right, {required int widthPx, bool bold = false}) async {
    final r = TextPainter(text: TextSpan(text: right, style: _style(bold, 1)), textDirection: _dir(right))..layout();
    final l = TextPainter(text: TextSpan(text: left, style: _style(bold, 1)), textDirection: _dir(left), textAlign: TextAlign.left)
      ..layout(minWidth: 0, maxWidth: (widthPx - r.width - 10).clamp(40, widthPx).toDouble());
    final h = (l.height > r.height ? l.height : r.height).ceil() + 6;
    return _capture(widthPx, h, (c) {
      l.paint(c, const Offset(0, 3));
      r.paint(c, Offset(widthPx - r.width, 3));
    });
  }

  Future<RasterImage> _capture(int w, int h, void Function(Canvas) draw) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    draw(canvas);
    final image = await rec.endRecording().toImage(w, h);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    final rowBytes = (w + 7) ~/ 8;
    final bits = Uint8List(rowBytes * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        final lum = 0.299 * data.getUint8(o) + 0.587 * data.getUint8(o + 1) + 0.114 * data.getUint8(o + 2);
        if (lum < 150) bits[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return RasterImage(widthPx: w, heightPx: h, bits: bits);
  }
}
