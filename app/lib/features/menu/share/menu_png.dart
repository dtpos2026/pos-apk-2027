import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'menu_doc.dart';

/// The words on the menu picture / PDF that are not the restaurant's own (so they follow the app language).
class MenuLabels {
  const MenuLabels({
    this.menu = 'Menu',
    this.pricesIn = 'Prices in',
    this.orderOnWhatsApp = 'Order on WhatsApp',
    this.orderHow = 'Send the item names and quantities, your name, full address and city.',
    this.scanToOrder = 'Scan to order',
    this.poweredBy = 'Powered by DT Food POS',
    this.page = 'Page',
  });
  final String menu, pricesIn, orderOnWhatsApp, orderHow, scanToOrder, poweredBy, page;
}

const pngPageWidth = 1080.0;
const pngPageHeight = 1528.0;
const _margin = 36.0;
const _fonts = ['NotoNaskhArabic', 'NotoNastaliqUrdu'];

TextStyle _style(double size, Color color, {FontWeight w = FontWeight.w500}) => TextStyle(fontFamily: 'Inter', fontFamilyFallback: _fonts, fontSize: size, color: color, fontWeight: w, height: 1.25);

TextPainter _tp(String text, TextStyle style, double width, {int maxLines = 1, TextAlign align = TextAlign.left}) =>
    TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textAlign: align, maxLines: maxLines, ellipsis: '…')..layout(minWidth: align == TextAlign.left ? 0 : width, maxWidth: width);

bool _isLight(Color c) => c.computeLuminance() > 0.55;

class _Block {
  _Block(this.height, this.paint, {this.keepWithNext = false});
  final double height;
  final void Function(Canvas c, double y) paint;
  final bool keepWithNext;
}

Future<ui.Image?> _decode(Uint8List? bytes, int width) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

void _drawImage(Canvas c, ui.Image im, Rect to, {double radius = 0, bool cover = true}) {
  final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
  final scale = cover ? math.max(to.width / src.width, to.height / src.height) : math.min(to.width / src.width, to.height / src.height);
  final w = src.width * scale, h = src.height * scale;
  final dst = Rect.fromCenter(center: to.center, width: w, height: h);
  c.save();
  c.clipRRect(RRect.fromRectAndRadius(to, Radius.circular(radius)));
  c.drawImageRect(im, src, dst, Paint()..filterQuality = FilterQuality.high);
  c.restore();
}

/// Draws the menu as 1080-wide pictures (as many pages as the menu needs) and returns them as PNG bytes.
/// Layout: a coloured header with the logo and name, then each category (with its picture) and its items (picture, name, description,
/// sizes, price; a deal lists what is inside it). The last page ends with the WhatsApp ordering card and a QR.
Future<List<Uint8List>> renderMenuPng(MenuDoc d, {MenuLabels labels = const MenuLabels()}) async {
  final primary = Color(d.primary);
  final accent = Color(d.accent);
  final onPrimary = _isLight(primary) ? const Color(0xFF1B1B1B) : const Color(0xFFFFFFFF);
  const ink = Color(0xFF1F1A1A), muted = Color(0xFF6B6262), line = Color(0xFFE9E1E1);
  final accentText = _isLight(accent) ? const Color(0xFF8A5A00) : accent;

  final logo = await _decode(d.logo, 280);
  final images = <Uint8List, ui.Image?>{};
  Future<ui.Image?> imageOf(Uint8List? b, int w) async {
    if (b == null) return null;
    return images[b] ??= await _decode(b, w);
  }

  // ---- blocks ----
  final blocks = <_Block>[];
  for (final s in d.sections) {
    final sImg = await imageOf(s.image, 120);
    blocks.add(_Block(96, (c, y) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(_margin, y + 14, pngPageWidth - 2 * _margin, 70), const Radius.circular(18));
      c.drawRRect(r, Paint()..color = (s.deals ? accent : primary).withValues(alpha: 0.12));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(_margin, y + 14, 12, 70), const Radius.circular(6)), Paint()..color = s.deals ? accent : primary);
      var x = _margin + 34;
      if (sImg != null) {
        _drawImage(c, sImg, Rect.fromLTWH(x, y + 21, 56, 56), radius: 28);
        x += 74;
      }
      final t = _tp(s.title, _style(40, s.deals ? accentText : primary, w: FontWeight.w800), pngPageWidth - x - _margin - 20);
      t.paint(c, Offset(x, y + 14 + (70 - t.height) / 2));
    }, keepWithNext: true));
    for (final e in s.entries) {
      final img = await imageOf(e.image, 260);
      const priceW = 230.0;
      final imgSize = img == null ? 0.0 : 132.0;
      final textX = _margin + 20 + (img == null ? 0 : imgSize + 22);
      final textW = pngPageWidth - _margin - 20 - priceW - 20 - textX;
      final name = _tp(e.name, _style(34, ink, w: FontWeight.w700), textW, maxLines: 2);
      final desc = (e.description ?? '').trim().isEmpty ? null : _tp(e.description!.trim(), _style(26, muted), textW, maxLines: 2);
      final sizes = e.sizes.isEmpty ? null : _tp(e.sizes.join('   •   '), _style(26, primary, w: FontWeight.w700), textW, maxLines: 3);
      final inside = e.inside.isEmpty ? null : _tp(e.inside.join('   •   '), _style(25, muted), textW, maxLines: 4);
      final price = _tp(e.price, _style(38, s.deals ? accentText : primary, w: FontWeight.w800), priceW, align: TextAlign.right);
      var th = name.height;
      for (final p in [desc, sizes, inside]) {
        if (p != null) th += 6 + p.height;
      }
      final h = math.max(imgSize, th) + 40;
      blocks.add(_Block(h, (c, y) {
        if (img != null) _drawImage(c, img, Rect.fromLTWH(_margin + 20, y + 20, imgSize, imgSize), radius: 18);
        var ty = y + 20.0;
        name.paint(c, Offset(textX, ty));
        ty += name.height;
        for (final p in [desc, sizes, inside]) {
          if (p == null) continue;
          ty += 6;
          p.paint(c, Offset(textX, ty));
          ty += p.height;
        }
        price.paint(c, Offset(pngPageWidth - _margin - 20 - priceW, y + 20));
        c.drawLine(Offset(_margin + 20, y + h - 1), Offset(pngPageWidth - _margin - 20, y + h - 1), Paint()..color = line..strokeWidth = 2);
      }));
    }
  }

  // ---- closing card ----
  const cardH = 430.0;
  void closing(Canvas c, double y) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(_margin, y, pngPageWidth - 2 * _margin, cardH - 30), const Radius.circular(28));
    c.drawRRect(r, Paint()..color = primary.withValues(alpha: 0.08));
    c.drawRRect(r, Paint()..color = primary.withValues(alpha: 0.35)..style = PaintingStyle.stroke..strokeWidth = 3);
    final hasQr = d.qrLink != null;
    final tw = pngPageWidth - 2 * _margin - 80 - (hasQr ? 320 : 0);
    var ty = y + 36.0;
    void line_(String text, double size, Color color, {FontWeight w = FontWeight.w500, int lines = 2}) {
      if (text.trim().isEmpty) return;
      final t = _tp(text, _style(size, color, w: w), tw, maxLines: lines);
      t.paint(c, Offset(_margin + 40, ty));
      ty += t.height + 10;
    }

    line_(labels.orderOnWhatsApp, 42, primary, w: FontWeight.w800);
    if ((d.phone ?? '').isNotEmpty) line_(d.phone!, 38, ink, w: FontWeight.w700);
    line_(labels.orderHow, 26, muted, lines: 3);
    line_(d.address ?? '', 26, ink, lines: 2);
    if (hasQr) {
      final qr = QrPainter(data: d.qrLink!, version: QrVersions.auto, gapless: true, eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: primary), dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: ink));
      final qx = pngPageWidth - _margin - 40 - 250.0, qy = y + 28.0;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qx - 14, qy - 14, 278, 278), const Radius.circular(20)), Paint()..color = const Color(0xFFFFFFFF));
      c.save();
      c.translate(qx, qy);
      qr.paint(c, const Size(250, 250));
      c.restore();
      final t = _tp(labels.scanToOrder, _style(26, primary, w: FontWeight.w700), 278, align: TextAlign.center);
      t.paint(c, Offset(qx - 14, qy + 276));
    }
    final p = _tp(labels.poweredBy, _style(24, muted), pngPageWidth - 2 * _margin, align: TextAlign.center);
    p.paint(c, Offset(_margin, y + cardH - 30 - 52));
  }

  // ---- paginate ----
  const firstHeader = 290.0, nextHeader = 130.0, footer = 80.0;
  final pages = <List<(_Block, double)>>[[]];
  var y = firstHeader;
  final limit = pngPageHeight - footer;
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    var need = b.height;
    if (b.keepWithNext && i + 1 < blocks.length) need += blocks[i + 1].height; // a category title never ends a page alone
    if (y + need > limit && pages.last.isNotEmpty) {
      pages.add([]);
      y = nextHeader;
    }
    pages.last.add((b, y));
    y += b.height;
  }
  var closingY = y + 20;
  if (closingY + cardH > limit) {
    pages.add([]);
    closingY = nextHeader + 10;
  }

  // ---- paint every page ----
  Future<Uint8List> paintPage(int index) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, pngPageWidth, pngPageHeight));
    c.drawRect(Rect.fromLTWH(0, 0, pngPageWidth, pngPageHeight), Paint()..color = const Color(0xFFFFFFFF));
    final first = index == 0;
    final hh = first ? firstHeader - 30 : nextHeader - 30;
    final dark = Color.lerp(primary, const Color(0xFF000000), 0.28)!;
    c.drawRect(Rect.fromLTWH(0, 0, pngPageWidth, hh), Paint()..shader = ui.Gradient.linear(const Offset(0, 0), Offset(pngPageWidth, hh), [primary, dark]));
    if (first) {
      var tx = 64.0;
      if (logo != null) {
        c.drawCircle(const Offset(64 + 80, 130), 84, Paint()..color = const Color(0xFFFFFFFF));
        _drawImage(c, logo, const Rect.fromLTWH(64 + 80 - 70, 130 - 70, 140, 140), radius: 70, cover: false);
        tx = 64 + 190;
      }
      final nameT = _tp(d.name, _style(64, onPrimary, w: FontWeight.w800), pngPageWidth - tx - 60, maxLines: 2);
      nameT.paint(c, Offset(tx, 78));
      var ly = 78 + nameT.height + 8;
      final sub = [labels.menu.toUpperCase(), if ((d.address ?? '').isNotEmpty) d.address!, if ((d.phone ?? '').isNotEmpty) d.phone!].join('   |   ');
      final subT = _tp(sub, _style(26, onPrimary.withValues(alpha: 0.92), w: FontWeight.w600), pngPageWidth - tx - 60, maxLines: 2);
      subT.paint(c, Offset(tx, ly));
      final pr = _tp('${labels.pricesIn} ${d.currencyCode}', _style(24, onPrimary.withValues(alpha: 0.85)), pngPageWidth - 2 * 64, align: TextAlign.right);
      pr.paint(c, Offset(64, hh - 44));
    } else {
      final t = _tp(d.name, _style(44, onPrimary, w: FontWeight.w800), pngPageWidth - 280);
      t.paint(c, Offset(64, (hh - t.height) / 2));
      final m = _tp(labels.menu.toUpperCase(), _style(30, onPrimary.withValues(alpha: 0.9), w: FontWeight.w700), 200, align: TextAlign.right);
      m.paint(c, Offset(pngPageWidth - 64 - 200, (hh - m.height) / 2));
    }
    c.drawRect(Rect.fromLTWH(0, hh, pngPageWidth, 8), Paint()..color = accent);
    if (index < pages.length) {
      for (final (b, by) in pages[index]) {
        b.paint(c, by);
      }
    }
    if (index == pages.length - 1) closing(c, closingY);
    // footer
    c.drawLine(const Offset(_margin, pngPageHeight - 64), const Offset(pngPageWidth - _margin, pngPageHeight - 64), Paint()..color = line..strokeWidth = 2);
    final fn = _tp(d.name, _style(24, muted), 700);
    fn.paint(c, Offset(_margin + 8, pngPageHeight - 50));
    final fp = _tp('${labels.page} ${index + 1} / ${pages.length}', _style(24, muted), 300, align: TextAlign.right);
    fp.paint(c, Offset(pngPageWidth - _margin - 8 - 300, pngPageHeight - 50));
    final image = await rec.endRecording().toImage(pngPageWidth.toInt(), pngPageHeight.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  final out = <Uint8List>[];
  for (var i = 0; i < pages.length; i++) {
    out.add(await paintPage(i));
  }
  return out;
}

/// A poster for the counter or a flyer: the restaurant's name and logo, "Order on WhatsApp", the QR and the number. null when the
/// restaurant has no WhatsApp number to link to.
Future<Uint8List?> renderQrCard(MenuDoc d, {MenuLabels labels = const MenuLabels()}) async {
  if (d.qrLink == null) return null;
  const w = 1080.0, h = 1350.0;
  final primary = Color(d.primary);
  final onPrimary = _isLight(primary) ? const Color(0xFF1B1B1B) : const Color(0xFFFFFFFF);
  final dark = Color.lerp(primary, const Color(0xFF000000), 0.28)!;
  final logo = await _decode(d.logo, 280);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFFFFF));
  c.drawRect(const Rect.fromLTWH(0, 0, w, 330), Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(w, 330), [primary, dark]));
  c.drawRect(const Rect.fromLTWH(0, 330, w, 10), Paint()..color = Color(d.accent));
  var ty = 84.0;
  if (logo != null) {
    c.drawCircle(const Offset(w / 2, 120), 78, Paint()..color = const Color(0xFFFFFFFF));
    _drawImage(c, logo, const Rect.fromLTWH(w / 2 - 64, 120 - 64, 128, 128), radius: 64, cover: false);
    ty = 214;
  }
  final name = _tp(d.name, _style(logo == null ? 70 : 58, onPrimary, w: FontWeight.w800), w - 120, maxLines: 2, align: TextAlign.center);
  name.paint(c, Offset(60, ty));
  final title = _tp(labels.orderOnWhatsApp, _style(54, primary, w: FontWeight.w800), w - 120, align: TextAlign.center);
  title.paint(c, const Offset(60, 400));
  final qr = QrPainter(data: d.qrLink!, version: QrVersions.auto, gapless: true, eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: primary), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1F1A1A)));
  const qs = 560.0;
  final qx = (w - qs) / 2, qy = 500.0;
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qx - 28, qy - 28, qs + 56, qs + 56), const Radius.circular(32)), Paint()..color = const Color(0xFFFFFFFF));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qx - 28, qy - 28, qs + 56, qs + 56), const Radius.circular(32)), Paint()..color = primary.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 4);
  c.save();
  c.translate(qx, qy);
  qr.paint(c, const Size(qs, qs));
  c.restore();
  final scan = _tp(labels.scanToOrder, _style(36, primary, w: FontWeight.w700), w - 120, align: TextAlign.center);
  scan.paint(c, Offset(60, qy + qs + 56));
  var by = qy + qs + 56 + scan.height + 22;
  for (final line in [d.phone ?? '', d.address ?? '']) {
    if (line.isEmpty) continue;
    final t = _tp(line, _style(line == d.phone ? 40 : 28, line == d.phone ? const Color(0xFF1F1A1A) : const Color(0xFF6B6262), w: line == d.phone ? FontWeight.w700 : FontWeight.w500), w - 120, maxLines: 2, align: TextAlign.center);
    t.paint(c, Offset(60, by));
    by += t.height + 8;
  }
  final p = _tp(labels.poweredBy, _style(24, const Color(0xFF6B6262)), w - 120, align: TextAlign.center);
  p.paint(c, Offset(60, h - 56));
  final image = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
