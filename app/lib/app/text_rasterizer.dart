import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/escpos.dart';
import '../domain/receipt_doc.dart';

/// Draws Urdu/Arabic text with the Flutter text engine (correct letter shaping and right-to-left order) and turns it
/// into a 1-bit bitmap for the printer. Slower and bigger than ESC/POS text, but the only way thermal printers
/// without Arabic fonts can print these scripts.
class FlutterTextRasterizer implements TextRasterizer, DocumentRasterizer {
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

  // ---- the whole slip as one picture ("original design") ----
  static const _pad = 4.0;

  TextPainter _tp(String text, double size, {bool bold = false, TextAlign align = TextAlign.left, double? width, Color color = const Color(0xFF000000), bool italic = false}) {
    final p = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: 'Inter', fontFamilyFallback: const ['NotoNaskhArabic'], fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: color, height: 1.3)),
      textDirection: _dir(text),
      textAlign: align,
    );
    width == null ? p.layout() : p.layout(minWidth: width, maxWidth: width);
    return p;
  }

  static double _scale(int w, int h) {
    final m = w > h ? w : h;
    return switch (m) { 1 => 1.0, 2 => 1.5, 3 => 2.6, _ => 3.2 };
  }

  @override
  Future<RasterImage> document(ReceiptDoc doc, {required int widthPx}) async {
    final w = widthPx.toDouble(), inner = w - 2 * _pad;
    const base = 21.0;
    final items = <({double h, void Function(Canvas c, double y) draw})>[];
    final images = <RasterImage, ui.Image>{};
    for (final l in doc.lines) {
      if (l is RImage) {
        final im = await _decode(l.image.padded(widthPx, l.align));
        images[l.image] = im;
      }
    }
    final black = Paint()..color = const Color(0xFF000000);
    for (final l in doc.lines) {
      switch (l) {
        case RText():
          final size = base * _scale(l.width, l.height);
          if (l.box) {
            final tp = _tp(l.text, size, bold: l.bold, align: TextAlign.center, width: inner - 20);
            final h = tp.height + 14;
            items.add((h: h + 6, draw: (c, y) {
              c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, h), Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFF000000));
              tp.paint(c, Offset(_pad + 10, y + 10));
            }));
          } else if (l.inverse) {
            final tp = _tp(l.text, size, bold: true, align: _align(l.align), width: inner - 16, color: const Color(0xFFFFFFFF));
            items.add((h: tp.height + 12, draw: (c, y) {
              c.drawRect(Rect.fromLTWH(_pad, y + 2, inner, tp.height + 8), black);
              tp.paint(c, Offset(_pad + 8, y + 6));
            }));
          } else {
            final tp = _tp(l.text, size, bold: l.bold, align: _align(l.align), width: inner);
            items.add((h: tp.height + 2, draw: (c, y) => tp.paint(c, Offset(_pad, y + 1))));
          }
        case RRow():
          final size = base * (l.height > 1 ? 1.25 : 1.0);
          final r = _tp(l.right, size, bold: l.bold || l.inverse);
          final lp = _tp(l.left, size, bold: l.bold || l.inverse, width: null);
          final maxLeft = (inner - r.width - 14).clamp(40.0, inner);
          final left = _tp(l.left, size, bold: l.bold || l.inverse, align: TextAlign.left, width: maxLeft);
          lp.dispose();
          final h = (left.height > r.height ? left.height : r.height);
          if (l.inverse) {
            final lw = _tp(l.left, size, bold: true, width: maxLeft, color: const Color(0xFFFFFFFF));
            final rw = _tp(l.right, size, bold: true, color: const Color(0xFFFFFFFF));
            items.add((h: h + 16, draw: (c, y) {
              c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, h + 10), black);
              lw.paint(c, Offset(_pad + 10, y + 8));
              rw.paint(c, Offset(_pad + inner - rw.width - 10, y + 8));
            }));
          } else {
            items.add((h: h + 2, draw: (c, y) {
              left.paint(c, Offset(_pad, y + 1));
              r.paint(c, Offset(_pad + inner - r.width, y + 1));
            }));
          }
        case RCols():
          final totalW = l.widths.fold<int>(0, (a, b) => a + b);
          final unit = (inner * 0.55) / (totalW == 0 ? 1 : totalW);
          final cols = [for (final x in l.widths) x * unit];
          final tailW = cols.fold<double>(0, (a, b) => a + b);
          final first = _tp(l.cells.first, base, bold: l.bold, width: inner - tailW - 8);
          final tails = [for (var i = 0; i < cols.length; i++) _tp(i + 1 < l.cells.length ? l.cells[i + 1] : '', base, bold: l.bold)];
          items.add((h: first.height + 2, draw: (c, y) {
            first.paint(c, Offset(_pad, y + 1));
            var x = _pad + inner - tailW;
            for (var i = 0; i < cols.length; i++) {
              tails[i].paint(c, Offset(x + cols[i] - tails[i].width, y + 1));
              x += cols[i];
            }
          }));
        case RCells():
          final n = l.heads.length;
          final stacked = n <= 2;
          final cw = stacked ? inner : inner / n;
          final cells = [
            for (var i = 0; i < n; i++) (head: _tp(l.heads[i], base * 0.78, align: TextAlign.center, width: cw - 8), value: _tp(i < l.values.length ? l.values[i] : '', base * (stacked ? 1.2 : 1.05), bold: true, align: TextAlign.center, width: cw - 8)),
          ];
          final ch = cells.fold<double>(0, (m, e) => e.head.height + e.value.height + 12 > m ? e.head.height + e.value.height + 12 : m);
          final total = stacked ? ch * n : ch;
          items.add((h: total + 8, draw: (c, y) {
            final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFF000000);
            c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, total), stroke);
            for (var i = 0; i < n; i++) {
              final x = stacked ? _pad : _pad + cw * i, yy = stacked ? y + 3 + ch * i : y + 3;
              if (i > 0) c.drawLine(stacked ? Offset(_pad, yy) : Offset(x, yy), stacked ? Offset(_pad + inner, yy) : Offset(x, yy + ch), stroke);
              cells[i].head.paint(c, Offset(x + 4, yy + 4));
              cells[i].value.paint(c, Offset(x + 4, yy + 6 + cells[i].head.height));
            }
          }));
        case RRule():
          final solid = l.ch == '=';
          items.add((h: 12, draw: (c, y) {
            final paint = Paint()..color = const Color(0xFF000000)..strokeWidth = solid ? 3 : 1.6;
            if (solid) {
              c.drawLine(Offset(_pad, y + 6), Offset(_pad + inner, y + 6), paint);
            } else {
              for (var x = _pad; x < _pad + inner; x += 10) {
                c.drawLine(Offset(x, y + 6), Offset((x + 6).clamp(0, _pad + inner), y + 6), paint);
              }
            }
          }));
        case RImage():
          final im = images[l.image]!;
          items.add((h: im.height.toDouble() + 4, draw: (c, y) => c.drawImage(im, Offset(0, y + 2), Paint())));
        case RQr():
          const size = 150.0;
          items.add((h: size + 12, draw: (c, y) {
            c.save();
            c.translate((w - size) / 2, y + 6);
            QrPainter(data: l.data, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(color: Color(0xFF000000), eyeShape: QrEyeShape.square), dataModuleStyle: const QrDataModuleStyle(color: Color(0xFF000000), dataModuleShape: QrDataModuleShape.square)).paint(c, const Size(size, size));
            c.restore();
          }));
        case RFeed():
          items.add((h: 18.0 * l.lines, draw: (c, y) {}));
      }
    }
    final height = items.fold<double>(8, (a, e) => a + e.h).ceil();
    final out = await _capture(widthPx, height, (c) {
      var y = 4.0;
      for (final e in items) {
        e.draw(c, y);
        y += e.h;
      }
    });
    for (final im in images.values) {
      im.dispose();
    }
    return out;
  }

  Future<ui.Image> _decode(RasterImage img) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(img.toRgba(), img.widthPx, img.heightPx, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
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
