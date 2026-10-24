import 'dart:typed_data';

import 'escpos.dart';

/// A 1-bit-per-pixel picture (rows padded to whole bytes, most significant bit first, 1 = black).
class RasterImage {
  RasterImage({required this.widthPx, required this.heightPx, required this.bits}) {
    if (bits.length != widthBytes * heightPx) throw ArgumentError('bitmap data length mismatch');
  }
  final int widthPx;
  final int heightPx;
  final Uint8List bits;
  int get widthBytes => (widthPx + 7) ~/ 8;

  /// A copy on a white canvas [totalWidthPx] wide with this picture placed left, centre or right. Printers do not
  /// reliably honour ESC a for bitmaps, so alignment is baked into the bitmap itself.
  RasterImage padded(int totalWidthPx, PrintAlign align) {
    if (widthPx >= totalWidthPx) return this;
    final total = (totalWidthPx + 7) ~/ 8 * 8;
    final shift = switch (align) { PrintAlign.left => 0, PrintAlign.center => (total - widthPx) ~/ 2, PrintAlign.right => total - widthPx };
    final out = Uint8List((total ~/ 8) * heightPx);
    for (var y = 0; y < heightPx; y++) {
      for (var x = 0; x < widthPx; x++) {
        if (pixel(x, y)) {
          final nx = x + shift;
          out[y * (total ~/ 8) + (nx >> 3)] |= 0x80 >> (nx & 7);
        }
      }
    }
    return RasterImage(widthPx: total, heightPx: heightPx, bits: out);
  }

  bool pixel(int x, int y) => (bits[y * widthBytes + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// RGBA pixels (black on white) for on-screen preview.
  Uint8List toRgba() {
    final out = Uint8List(widthPx * heightPx * 4);
    for (var y = 0; y < heightPx; y++) {
      for (var x = 0; x < widthPx; x++) {
        final v = pixel(x, y) ? 0 : 255;
        final o = (y * widthPx + x) * 4;
        out[o] = v;
        out[o + 1] = v;
        out[o + 2] = v;
        out[o + 3] = 255;
      }
    }
    return out;
  }
}

sealed class RLine {
  const RLine();
}

class RText extends RLine {
  const RText(this.text, {this.align = PrintAlign.left, this.bold = false, this.width = 1, this.height = 1, this.box = false, this.inverse = false});
  final String text;
  final PrintAlign align;
  final bool bold;
  final int width;
  final int height;

  /// Drawn inside a text box: "| text |" (normal size only).
  final bool box;

  /// White text on a black bar (ESC/POS reverse print).
  final bool inverse;
}

/// "left ......... right" on one line.
class RRow extends RLine {
  const RRow(this.left, this.right, {this.bold = false, this.height = 1, this.box = false, this.inverse = false});
  final String left;
  final String right;
  final bool bold;
  final int height;
  final bool box;
  final bool inverse;
}

/// A table row: the first cell takes what the others leave and wraps; the others are right-aligned and never wrap.
/// [widths] are the fixed columns of every cell after the first, for 58 mm paper; 80 mm paper widens them by half.
class RCols extends RLine {
  const RCols(this.cells, this.widths, {this.bold = false, this.box = false});
  final List<String> cells;
  final List<int> widths;
  final bool bold;
  final bool box;
}

class RRule extends RLine {
  const RRule([this.ch = '-']);
  final String ch;
}

class RImage extends RLine {
  const RImage(this.image, {this.align = PrintAlign.center});
  final RasterImage image;
  final PrintAlign align;
}

class RQr extends RLine {
  const RQr(this.data, {this.moduleSize = 5});
  final String data;
  final int moduleSize;
}

class RFeed extends RLine {
  const RFeed([this.lines = 1]);
  final int lines;
}

/// What to print, independent of how: the printer (ESC/POS) and the on-screen preview are both rendered from this,
/// so what the owner sees while designing the receipt is what comes out of the printer.
class ReceiptDoc {
  const ReceiptDoc(this.lines, {this.copies = 1});
  final List<RLine> lines;
  final int copies;
}

/// Columns of text on the paper (font A): 32 for 58 mm, 48 for 80 mm.
int columnsFor(int paperMm) => paperMm == 80 ? 48 : 32;

/// Dots across the paper: 384 for 58 mm, 576 for 80 mm.
int dotsFor(int paperMm) => paperMm == 80 ? 576 : 384;

/// "| text      |" with the text padded to [inner] characters.
String boxed(String text, int inner) => '| ${text.padRight(inner)} |';

/// Text lines inside a box, wrapped and aligned inside [columns].
List<String> layoutBoxText(String text, PrintAlign align, int columns) {
  final inner = columns - 4;
  return [
    for (final line in EscPosBuilder.wrap(text, inner))
      boxed(switch (align) { PrintAlign.center => line.padLeft((inner + line.length) ~/ 2).padRight(inner), PrintAlign.right => line.padLeft(inner), PrintAlign.left => line }, inner)
  ];
}

/// Lays out a two-column row. If the left text does not fit it wraps and the right text stays on the first line.
List<String> layoutRow(String left, String right, int columns, {bool box = false}) {
  if (box && columns > 8) return [for (final l in layoutRow(left, right, columns - 4)) boxed(l, columns - 4)];
  final avail = columns - right.length - 1;
  final parts = avail > 0 ? EscPosBuilder.wrap(left, avail) : [left];
  final first = parts.isEmpty ? '' : parts.first;
  return [first.padRight(columns - right.length) + right, ...parts.skip(1)];
}

/// Lays out a table row ([RCols]) as text lines of exactly [columns] characters (the first line; wrapped name lines follow).
List<String> layoutCols(List<String> cells, List<int> widths, int columns, {bool box = false}) {
  if (box && columns > 8) return [for (final l in layoutCols(cells, widths, columns - 4)) boxed(l, columns - 4)];
  final scale = columns >= 48 ? 1.5 : 1.0;
  final w = [for (final x in widths) (x * scale).round()];
  final tail = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    final c = i + 1 < cells.length ? cells[i + 1] : '';
    final v = c.length > w[i] - 1 ? c.substring(0, w[i] - 1) : c;
    tail.write(v.padLeft(w[i]));
  }
  final avail = columns - tail.length;
  final parts = avail > 0 ? EscPosBuilder.wrap(cells.isEmpty ? '' : cells.first, avail) : [cells.first];
  final first = parts.isEmpty ? '' : parts.first;
  return [first.padRight(avail) + tail.toString(), ...parts.skip(1)];
}

/// Turns Arabic-script text into bitmaps for printers that have no fonts for it. Implemented in the app layer
/// (it needs the Flutter text engine for correct shaping and right-to-left order).
abstract class TextRasterizer {
  Future<RasterImage> text(String text, {required int widthPx, PrintAlign align = PrintAlign.left, bool bold = false, int scale = 1});
  Future<RasterImage> row(String left, String right, {required int widthPx, bool bold = false});
}

/// Renders a [ReceiptDoc] to ESC/POS bytes.
class EscPosRenderer {
  EscPosRenderer({required this.paperMm, this.rasterizer});
  final int paperMm;
  final TextRasterizer? rasterizer;

  EscPosBuilder _start() => EscPosBuilder(paperMm: paperMm).init().codePage(0);

  /// Synchronous render. Arabic-script lines cannot be printed without a rasterizer and come out as '?'.
  EscPosBuilder renderSync(ReceiptDoc doc) {
    final b = _start();
    for (var c = 0; c < doc.copies; c++) {
      for (final l in doc.lines) {
        _simple(b, l);
      }
    }
    return b;
  }

  /// Full render: Arabic-script text is rasterized when a [rasterizer] is available.
  Future<EscPosBuilder> render(ReceiptDoc doc) async {
    final b = _start();
    final dots = dotsFor(paperMm);
    for (var c = 0; c < doc.copies; c++) {
      for (final l in doc.lines) {
        final r = rasterizer;
        if (r != null && l is RText && needsRaster(l.text)) {
          final img = await r.text(l.text, widthPx: dots, align: l.align, bold: l.bold, scale: l.height);
          b.align(PrintAlign.left).raster(img.bits, widthBytes: img.widthBytes, heightPx: img.heightPx);
        } else if (r != null && l is RRow && (needsRaster(l.left) || needsRaster(l.right))) {
          final img = await r.row(l.left, l.right, widthPx: dots, bold: l.bold);
          b.align(PrintAlign.left).raster(img.bits, widthBytes: img.widthBytes, heightPx: img.heightPx);
        } else if (r != null && l is RCols && l.cells.any(needsRaster)) {
          final img = await r.row(l.cells.first, l.cells.skip(1).where((c) => c.isNotEmpty).join('  '), widthPx: dots, bold: l.bold);
          b.align(PrintAlign.left).raster(img.bits, widthBytes: img.widthBytes, heightPx: img.heightPx);
        } else {
          _simple(b, l);
        }
      }
    }
    return b;
  }

  void _simple(EscPosBuilder b, RLine l) {
    switch (l) {
      case RText() when l.box && l.width == 1 && l.height == 1:
        b.align(PrintAlign.left).bold(l.bold);
        for (final line in layoutBoxText(l.text, l.align, b.columns)) {
          b.line(line);
        }
        b.bold(false);
      case RText():
        b.align(l.align).bold(l.bold).size(width: l.width, height: l.height).inverse(l.inverse);
        // double-width text has half the columns: wrap to what fits
        final cols = (b.columns / l.width).floor();
        for (final line in EscPosBuilder.wrap(l.text, cols)) {
          b.line(line);
        }
        b.inverse(false).size().bold(false).align(PrintAlign.left);
      case RRow():
        b.align(PrintAlign.left).bold(l.bold).size(height: l.height).inverse(l.inverse);
        for (final line in layoutRow(l.left, l.right, b.columns, box: l.box)) {
          b.line(line);
        }
        b.inverse(false).size().bold(false);
      case RCols():
        b.align(PrintAlign.left).bold(l.bold);
        for (final line in layoutCols(l.cells, l.widths, b.columns, box: l.box)) {
          b.line(line);
        }
        b.bold(false);
      case RRule():
        b.align(PrintAlign.left).line(_rule(l.ch, b.columns));
      case RImage():
        final img = l.image.padded(dotsFor(paperMm), l.align);
        b.align(PrintAlign.left).raster(img.bits, widthBytes: img.widthBytes, heightPx: img.heightPx);
      case RQr():
        b.align(PrintAlign.center).qr(l.data, moduleSize: l.moduleSize).align(PrintAlign.left);
      case RFeed():
        b.feed(l.lines);
    }
    if (l is RFeed) return;
  }

  /// Cut after the last copy of each ticket (appended by callers that want a cut).
  static void cut(EscPosBuilder b) => b.cut();
}

/// Plain-text rendering with alignment applied, used by tests and as a text fallback.
String docToText(ReceiptDoc doc, int paperMm) {
  final cols = columnsFor(paperMm);
  final out = StringBuffer();
  // [w] is the character width multiplier: a double-width character occupies two paper columns.
  String align(String s, PrintAlign a, int cols, [int w = 1]) {
    final phys = s.length * w;
    return switch (a) {
      PrintAlign.center => phys >= cols * w ? s : '${' ' * ((cols * w - phys) ~/ 2)}$s',
      PrintAlign.right => phys >= cols * w ? s : '${' ' * (cols * w - phys)}$s',
      PrintAlign.left => s,
    };
  }
  for (final l in doc.lines) {
    switch (l) {
      case RText() when l.box && l.width == 1 && l.height == 1:
        for (final line in layoutBoxText(l.text, l.align, cols)) {
          out.writeln(line);
        }
      case RText():
        for (final line in EscPosBuilder.wrap(l.text, (cols / l.width).floor())) {
          out.writeln(align(line, l.align, (cols / l.width).floor(), l.width));
        }
      case RRow():
        for (final line in layoutRow(l.left, l.right, cols, box: l.box)) {
          out.writeln(line);
        }
      case RCols():
        for (final line in layoutCols(l.cells, l.widths, cols, box: l.box)) {
          out.writeln(line);
        }
      case RRule():
        out.writeln(_rule(l.ch, cols));
      case RImage():
        out.writeln(align('[logo]', l.align, cols));
      case RQr():
        out.writeln(align('[QR]', PrintAlign.center, cols));
      case RFeed():
        for (var i = 0; i < l.lines; i++) {
          out.writeln();
        }
    }
  }
  return out.toString();
}

/// A full-width rule; a multi-character pattern such as '- ' repeats and is cut to the paper width.
String _rule(String ch, int cols) => ruleText(ch, cols);
String ruleText(String ch, int cols) => ch == '+' ? '+${'-' * (cols - 2)}+' : (ch * (cols ~/ ch.length + 1)).substring(0, cols);
