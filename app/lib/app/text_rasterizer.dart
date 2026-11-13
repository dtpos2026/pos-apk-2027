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
        height: 1.2,
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
      text: TextSpan(text: text, style: TextStyle(fontFamily: 'Inter', fontFamilyFallback: const ['NotoNaskhArabic'], fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: color, height: 1.15)),
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
    final c = await _compose(doc, widthPx);
    return _capture(widthPx, c.height, c.paint);
  }

  /// The same slip as a smooth picture at [scale]x, for the on-screen preview (the printer gets the 1-bit [document]).
  Future<ui.Image> documentImage(ReceiptDoc doc, {required int widthPx, double scale = 2}) async {
    final c = await _compose(doc, widthPx);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, widthPx.toDouble(), c.height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    c.paint(canvas);
    return rec.endRecording().toImage((widthPx * scale).ceil(), (c.height * scale).ceil());
  }

  Future<({int height, void Function(Canvas) paint})> _compose(ReceiptDoc doc, int widthPx) async {
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
          final lw0 = lp.width;
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
            final leftEnd = (lw0 < maxLeft ? lw0 : maxLeft);
            items.add((h: h + 2, draw: (c, y) {
              left.paint(c, Offset(_pad, y + 1));
              r.paint(c, Offset(_pad + inner - r.width, y + 1));
              if (l.leader) {
                // dots from the label to the value, on the text's last line
                final dot = Paint()..color = const Color(0xFF000000);
                final yy = y + h - 7;
                for (var x = _pad + leftEnd + 6; x < _pad + inner - r.width - 6; x += 6) {
                  c.drawRect(Rect.fromLTWH(x, yy, 2, 2), dot);
                }
              }
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
          final stacked = n <= 2 && !l.across;
          final cw = stacked ? inner : inner / n;
          final cells = [
            for (var i = 0; i < n; i++) (head: _tp(l.heads[i], base * 0.78, align: TextAlign.center, width: cw - 8), value: _tp(i < l.values.length ? l.values[i] : '', base * (stacked ? 1.2 : 1.05), bold: true, align: TextAlign.center, width: cw - 8)),
          ];
          final ch = cells.fold<double>(0, (m, e) => e.head.height + e.value.height + 12 > m ? e.head.height + e.value.height + 12 : m);
          final total = stacked ? ch * n : ch;
          items.add((h: total + 8, draw: (c, y) {
            final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFF000000);
            void line(Offset a, Offset b) => l.dashed ? _dash(c, a, b, stroke) : c.drawLine(a, b, stroke);
            final box = Rect.fromLTWH(_pad, y + 3, inner, total);
            line(box.topLeft, box.topRight);
            line(box.bottomLeft, box.bottomRight);
            line(box.topLeft, box.bottomLeft);
            line(box.topRight, box.bottomRight);
            for (var i = 0; i < n; i++) {
              final x = stacked ? _pad : _pad + cw * i, yy = stacked ? y + 3 + ch * i : y + 3;
              if (i > 0) line(stacked ? Offset(_pad, yy) : Offset(x, yy), stacked ? Offset(_pad + inner, yy) : Offset(x, yy + ch));
              cells[i].head.paint(c, Offset(x + 4, yy + 4));
              cells[i].value.paint(c, Offset(x + 4, yy + 6 + cells[i].head.height));
            }
          }));
        case RDivider():
          final ink = Paint()..color = const Color(0xFF000000)..strokeWidth = 2;
          switch (l.kind) {
            case 'diamond':
              items.add((h: 22, draw: (c, y) {
                final mid = y + 11, cx = _pad + inner / 2;
                c.drawLine(Offset(_pad, mid), Offset(cx - 16, mid), ink);
                c.drawLine(Offset(cx + 16, mid), Offset(_pad + inner, mid), ink);
                c.drawPath(Path()..moveTo(cx, mid - 8)..lineTo(cx + 8, mid)..lineTo(cx, mid + 8)..lineTo(cx - 8, mid)..close(), Paint()..color = const Color(0xFF000000));
              }));
            case 'zigzag':
              items.add((h: 16, draw: (c, y) {
                final path = Path()..moveTo(_pad, y + 14);
                for (var x = _pad; x < _pad + inner; x += 16) {
                  path
                    ..lineTo(x + 8, y + 2)
                    ..lineTo((x + 16).clamp(0, _pad + inner).toDouble(), y + 14);
                }
                path.close();
                c.drawPath(path, Paint()..color = const Color(0xFF000000));
              }));
            default: // double
              items.add((h: 14, draw: (c, y) {
                c.drawLine(Offset(_pad, y + 5), Offset(_pad + inner, y + 5), ink);
                c.drawLine(Offset(_pad, y + 10), Offset(_pad + inner, y + 10), ink);
              }));
          }
        case RKeyGrid():
          final colW = inner * 0.38;
          final rows = [for (final r in l.rows) (k: _tp(r.$1, base * 0.95, bold: true, width: colW - 12), v: _tp(r.$2, base * 0.95, width: inner - colW - 12))];
          final heights = [for (final r in rows) (r.k.height > r.v.height ? r.k.height : r.v.height) + 12];
          final total = heights.fold<double>(0, (a, b) => a + b);
          items.add((h: total + 6, draw: (c, y) {
            final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF000000);
            c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, total), stroke);
            c.drawLine(Offset(_pad + colW, y + 3), Offset(_pad + colW, y + 3 + total), stroke);
            var yy = y + 3;
            for (var i = 0; i < rows.length; i++) {
              if (i > 0) c.drawLine(Offset(_pad, yy), Offset(_pad + inner, yy), stroke);
              rows[i].k.paint(c, Offset(_pad + 6, yy + 6));
              rows[i].v.paint(c, Offset(_pad + colW + 6, yy + 6));
              yy += heights[i];
            }
          }));
        case RItemGrid():
          final amtW = inner * 0.26;
          final hl = _tp(l.head.$1, base, bold: true, width: inner - amtW - 12, color: const Color(0xFFFFFFFF));
          final hr = _tp(l.head.$2, base, bold: true, color: const Color(0xFFFFFFFF));
          final headH = (hl.height > hr.height ? hl.height : hr.height) + 10;
          final rows = [for (final r in l.rows) (t: _tp(r.$1.join('\n'), base, width: inner - amtW - 12), a: _tp(r.$2, base, bold: true))];
          final heights = [for (final r in rows) (r.t.height > r.a.height ? r.t.height : r.a.height) + 12];
          final total = headH + heights.fold<double>(0, (a, b) => a + b);
          items.add((h: total + 6, draw: (c, y) {
            final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF000000);
            c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, headH), black);
            hl.paint(c, Offset(_pad + 6, y + 8));
            hr.paint(c, Offset(_pad + inner - hr.width - 6, y + 8));
            c.drawRect(Rect.fromLTWH(_pad, y + 3, inner, total), stroke);
            c.drawLine(Offset(_pad + inner - amtW, y + 3 + headH), Offset(_pad + inner - amtW, y + 3 + total), stroke);
            var yy = y + 3 + headH;
            for (var i = 0; i < rows.length; i++) {
              if (i > 0) c.drawLine(Offset(_pad, yy), Offset(_pad + inner, yy), stroke);
              rows[i].t.paint(c, Offset(_pad + 6, yy + 6));
              rows[i].a.paint(c, Offset(_pad + inner - rows[i].a.width - 6, yy + 6));
              yy += heights[i];
            }
          }));
        case RStamp():
          final tp = _tp(l.text.split('').join(' '), base * 1.6, bold: true);
          final bw = tp.width + 40, bh = tp.height + 18;
          items.add((h: bh + 22, draw: (c, y) {
            c.save();
            c.translate(_pad + inner / 2, y + 11 + bh / 2);
            c.rotate(-0.06);
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: bw, height: bh), const Radius.circular(14)), Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = const Color(0xFF000000));
            tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
            c.restore();
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
    return (height: height, paint: (Canvas c) {
      var y = 4.0;
      for (final e in items) {
        e.draw(c, y);
        y += e.h;
      }
    });
  }

  static void _dash(Canvas c, Offset a, Offset b, Paint p) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += 12) {
      c.drawLine(a + u * t, a + u * (t + 7 > len ? len : t + 7), p);
    }
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
