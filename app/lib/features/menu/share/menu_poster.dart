import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import 'menu_doc.dart';
import 'menu_png.dart' show MenuLabels, pngPageHeight, pngPageWidth;

/// A ready-made look for the shared menu. The restaurant picks one in "Share menu"; every look makes the same pages for the picture
/// (PNG) and the PDF: an optional cover, then the dishes in cards, then the ordering card.
class MenuTemplate {
  const MenuTemplate({
    required this.id,
    required this.nameKey,
    required this.bgTop,
    required this.bgBottom,
    required this.text,
    required this.muted,
    required this.accent,
    required this.card,
    required this.priceFill,
    required this.priceText,
    required this.title,
    required this.cards3,
    this.ribbon = const Color(0xFFFFFFFF),
    this.ribbonText = const Color(0xFF3A0B0B),
  });
  final String id, nameKey;
  final Color bgTop, bgBottom, text, muted, accent, card, priceFill, priceText;

  /// Section titles: 'ribbon' (white ribbon), 'bar' (slanted colour bar) or 'gold' (gold words with a line).
  final String title;

  /// Dishes as 3 photo cards across (true) or 2 across with a small picture beside the words (false).
  final bool cards3;
  final Color ribbon, ribbonText;
}

/// 'classic' is the white/red look made by the older renderers (picture + vector PDF); the others are made by [renderPosterPages].
const menuTemplateIds = ['classic', 'royal', 'blackred', 'spice'];

const menuTemplates = <MenuTemplate>[
  // Deep maroon with gold, white ribbons and photo cards (like a printed restaurant brochure).
  MenuTemplate(id: 'royal', nameKey: 'mt_royal', bgTop: Color(0xFF5A1214), bgBottom: Color(0xFF2B0708), text: Color(0xFFFFF4E0), muted: Color(0xFFE3C9B0), accent: Color(0xFFF5B301), card: Color(0x22FFFFFF), priceFill: Color(0x00000000), priceText: Color(0xFFF5B301), title: 'ribbon', cards3: true),
  // Black with red bars and red price tags.
  MenuTemplate(id: 'blackred', nameKey: 'mt_blackred', bgTop: Color(0xFF1B1B1B), bgBottom: Color(0xFF090909), text: Color(0xFFFFFFFF), muted: Color(0xFFBDBDBD), accent: Color(0xFFE11D1D), card: Color(0x1FFFFFFF), priceFill: Color(0xFFE11D1D), priceText: Color(0xFFFFFFFF), title: 'bar', cards3: false),
  // Charcoal with golden headings and round pictures.
  MenuTemplate(id: 'spice', nameKey: 'mt_spice', bgTop: Color(0xFF2A2623), bgBottom: Color(0xFF121110), text: Color(0xFFF7F1E6), muted: Color(0xFFC8BFAF), accent: Color(0xFFF2C230), card: Color(0x1AFFFFFF), priceFill: Color(0x00000000), priceText: Color(0xFFF2C230), title: 'gold', cards3: false),
];

MenuTemplate? menuTemplateById(String id) => menuTemplates.where((t) => t.id == id).firstOrNull;

const _fonts = ['NotoNaskhArabic', 'NotoNastaliqUrdu'];
const _m = 48.0;
const _footer = 84.0;

TextStyle _st(double size, Color c, {FontWeight w = FontWeight.w500}) => TextStyle(fontFamily: 'Inter', fontFamilyFallback: _fonts, fontSize: size, color: c, fontWeight: w, height: 1.22);

TextPainter _tp(String s, TextStyle st, double width, {int maxLines = 1, TextAlign align = TextAlign.left}) {
  final p = TextPainter(text: TextSpan(text: s, style: st), textDirection: RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]').hasMatch(s) ? TextDirection.rtl : TextDirection.ltr, textAlign: align, maxLines: maxLines, ellipsis: '…');
  p.layout(minWidth: align == TextAlign.left ? 0 : width, maxWidth: width);
  return p;
}

Future<ui.Image?> _decode(Uint8List? b, int w) async {
  if (b == null || b.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(b, targetWidth: w);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

void _img(Canvas c, ui.Image im, Rect to, {double radius = 0, bool circle = false}) {
  final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
  final s = math.max(to.width / src.width, to.height / src.height);
  final dst = Rect.fromCenter(center: to.center, width: src.width * s, height: src.height * s);
  c.save();
  c.clipRRect(RRect.fromRectAndRadius(to, Radius.circular(circle ? to.shortestSide / 2 : radius)));
  c.drawImageRect(im, src, dst, Paint()..filterQuality = FilterQuality.high);
  c.restore();
}

class _Block {
  _Block(this.h, this.paint, {this.keep = false});
  final double h;
  final void Function(Canvas c, double y) paint;
  final bool keep;
}

/// Makes the menu as page pictures in the chosen [t] look: a cover (if [cover]), the dishes, and the ordering card. [scale] 1 = 1080 x 1528;
/// the PDF uses 2 for a sharper print. Returns PNG bytes, one per page.
Future<List<Uint8List>> renderPosterPages(MenuDoc d, MenuTemplate t, {MenuLabels labels = const MenuLabels(), bool cover = true, double scale = 1}) async {
  const w = 1080.0, h = 1528.0;
  final logo = await _decode(d.logo, 300);
  final brand = await _decode(d.brandMark, 64);
  final cache = <Uint8List, ui.Image?>{};
  Future<ui.Image?> imageOf(Uint8List? b, int px) async => b == null ? null : (cache[b] ??= await _decode(b, px));

  Paint fill(Color c) => Paint()..color = c;
  void ribbon(Canvas c, Rect r, Color col) {
    final n = r.height * 0.32;
    final p = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right - n, r.center.dy)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left + n, r.center.dy)
      ..close();
    c.drawShadow(p, const Color(0xFF000000), 4, false);
    c.drawPath(p, fill(col));
  }

  // ---- background and frame of a page ----
  void background(Canvas c, {required bool isCover}) {
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), [t.bgTop, t.bgBottom]));
    switch (t.id) {
      case 'blackred':
        final a = Path()..moveTo(0, 0)..lineTo(w * 0.55, 0)..lineTo(w * 0.3, 70)..lineTo(0, 70)..close();
        c.drawPath(a, fill(t.accent));
        final b = Path()..moveTo(0, h)..lineTo(w, h)..lineTo(w, h - 120)..lineTo(w * 0.42, h - 92)..lineTo(0, h - 120)..close();
        c.drawPath(b, fill(t.accent));
        c.drawPath(Path()..moveTo(w * 0.55, 0)..lineTo(w * 0.75, 0)..lineTo(w * 0.5, 70)..lineTo(w * 0.3, 70)..close(), fill(const Color(0xFFFFC107)));
      case 'spice':
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(22, 22, w - 44, h - 44), const Radius.circular(18)), Paint()..color = t.accent.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 3);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 34, w - 68, h - 68), const Radius.circular(12)), Paint()..color = t.accent.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      default:
        c.drawRect(const Rect.fromLTWH(0, 0, w, 10), fill(t.accent));
        c.drawRect(const Rect.fromLTWH(0, h - 10, w, 10), fill(t.accent));
    }
  }

  // ---- page footer: name, brand, page number ----
  void footer(Canvas c, int index, int total) {
    final y = h - (t.id == 'blackred' ? 126 : 74);
    c.drawLine(Offset(_m, y), Offset(w - _m, y), Paint()..color = (t.id == 'blackred' ? const Color(0xFFFFFFFF) : t.muted).withValues(alpha: 0.35)..strokeWidth = 1.5);
    // the black & red look has a red band at the bottom: its footer words are white
    final onBand = t.id == 'blackred';
    final fc = onBand ? const Color(0xFFFFFFFF) : t.muted;
    _tp(d.name, _st(22, fc), 340).paint(c, Offset(_m, y + 14));
    final pb = _tp(labels.poweredBy, _st(22, onBand ? const Color(0xFFFFFFFF) : t.accent, w: FontWeight.w700), 420, align: TextAlign.center);
    final bx = (w - pb.width) / 2 + (brand == null ? 0 : 16);
    pb.paint(c, Offset(bx, y + 14));
    if (brand != null) {
      c.saveLayer(Rect.fromLTWH(bx - 36, y + 12, 28, 28), Paint());
      _img(c, brand, Rect.fromLTWH(bx - 36, y + 12, 28, 28));
      c.restore();
    }
    _tp('${labels.page} ${index + 1} / $total', _st(22, fc), 240, align: TextAlign.right).paint(c, Offset(w - _m - 240, y + 14));
  }

  // ---- blocks of the content pages ----
  final gap = 22.0;
  final inner = w - 2 * _m;
  final blocks = <_Block>[];

  Future<void> addSection(MenuSection s) async {
    final col = s.deals ? const Color(0xFFFFC107) : t.accent;
    blocks.add(_Block(112, (c, y) {
      final r = Rect.fromLTWH(_m, y + 18, inner, 66);
      switch (t.title) {
        case 'ribbon':
          ribbon(c, Rect.fromLTWH(_m + 70, y + 18, inner - 140, 66), t.ribbon);
          final tp = _tp(s.title.toUpperCase(), _st(34, t.ribbonText, w: FontWeight.w800), inner - 260, align: TextAlign.center);
          tp.paint(c, Offset(_m + 130, y + 18 + (66 - tp.height) / 2));
        case 'bar':
          final p = Path()..moveTo(_m, r.top)..lineTo(_m + inner * 0.62, r.top)..lineTo(_m + inner * 0.62 - 26, r.bottom)..lineTo(_m, r.bottom)..close();
          c.drawPath(p, fill(t.accent));
          final tp = _tp(s.title.toUpperCase(), _st(34, const Color(0xFFFFFFFF), w: FontWeight.w800), inner * 0.55);
          tp.paint(c, Offset(_m + 24, r.top + (66 - tp.height) / 2));
          c.drawRect(Rect.fromLTWH(_m, r.bottom + 6, inner, 3), fill(const Color(0xFFFFC107)));
        default:
          final tp = _tp(s.title.toUpperCase(), _st(38, col, w: FontWeight.w800), inner * 0.6);
          tp.paint(c, Offset(_m + 6, r.top + (66 - tp.height) / 2));
          final lx = _m + 6 + tp.width + 18;
          c.drawLine(Offset(lx, r.center.dy), Offset(w - _m, r.center.dy), Paint()..color = col.withValues(alpha: 0.6)..strokeWidth = 2);
      }
    }, keep: true));
  }

  Future<void> addEntries(MenuSection s) async {
    final per = t.cards3 ? 3 : 2;
    final cw = (inner - gap * (per - 1)) / per;
    for (var i = 0; i < s.entries.length; i += per) {
      final row = s.entries.sublist(i, math.min(i + per, s.entries.length));
      final cells = <({double h, void Function(Canvas c, double x, double y) paint})>[];
      for (final e in row) {
        final photo = await imageOf(e.image, t.cards3 ? 420 : 240);
        final priceCol = s.deals ? const Color(0xFFFFC107) : t.priceText;
        if (t.cards3) {
          const ph = 196.0, pad = 14.0;
          final tw = cw - 2 * pad;
          final name = _tp(e.name, _st(27, t.text, w: FontWeight.w800), tw, maxLines: 2);
          final desc = (e.description ?? '').trim().isEmpty ? null : _tp(e.description!.trim(), _st(19, t.muted), tw, maxLines: 2);
          final extra = e.sizes.isNotEmpty ? e.sizes.join('  •  ') : (e.inside.isNotEmpty ? e.inside.join('  •  ') : '');
          final ex = extra.isEmpty ? null : _tp(extra, _st(19, t.accent, w: FontWeight.w700), tw, maxLines: 2);
          final price = _tp(e.price, _st(30, priceCol, w: FontWeight.w800), tw);
          final ch = pad + ph + 10 + name.height + (desc == null ? 0 : 4 + desc.height) + (ex == null ? 0 : 4 + ex.height) + 8 + price.height + pad;
          cells.add((h: ch, paint: (c, x, y) {
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cw, ch), const Radius.circular(20)), fill(t.card));
            final r = Rect.fromLTWH(x + pad, y + pad, tw, ph);
            if (photo != null) {
              _img(c, photo, r, radius: 14);
            } else {
              c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)), fill(t.accent.withValues(alpha: 0.18)));
              final ch1 = _tp(e.name.trim().isEmpty ? '' : e.name.trim()[0].toUpperCase(), _st(80, t.accent, w: FontWeight.w800), tw, align: TextAlign.center);
              ch1.paint(c, Offset(r.left, r.top + (ph - ch1.height) / 2));
            }
            var ty = y + pad + ph + 10;
            name.paint(c, Offset(x + pad, ty));
            ty += name.height;
            if (desc != null) {
              ty += 4;
              desc.paint(c, Offset(x + pad, ty));
              ty += desc.height;
            }
            if (ex != null) {
              ty += 4;
              ex.paint(c, Offset(x + pad, ty));
              ty += ex.height;
            }
            price.paint(c, Offset(x + pad, ty + 8));
          }));
        } else {
          const ps = 138.0, pad = 14.0;
          final tx = pad + ps + 16;
          final tw = cw - tx - pad;
          final name = _tp(e.name, _st(27, t.text, w: FontWeight.w800), tw, maxLines: 2);
          final desc = (e.description ?? '').trim().isEmpty ? null : _tp(e.description!.trim(), _st(19, t.muted), tw, maxLines: 2);
          final extra = e.sizes.isNotEmpty ? e.sizes.join('  •  ') : (e.inside.isNotEmpty ? e.inside.join('  •  ') : '');
          final ex = extra.isEmpty ? null : _tp(extra, _st(19, t.accent, w: FontWeight.w700), tw, maxLines: 2);
          final price = _tp(e.price, _st(30, t.priceFill.a > 0 ? t.priceText : priceCol, w: FontWeight.w800), tw);
          final textH = name.height + (desc == null ? 0 : 4 + desc.height) + (ex == null ? 0 : 4 + ex.height) + 10 + price.height + (t.priceFill.a > 0 ? 12 : 0);
          final ch = math.max(ps, textH) + 2 * pad;
          cells.add((h: ch, paint: (c, x, y) {
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, cw, ch), const Radius.circular(20)), fill(t.card));
            final r = Rect.fromLTWH(x + pad, y + pad, ps, ps);
            final round = t.id == 'spice';
            if (photo != null) {
              _img(c, photo, r, radius: 16, circle: round);
            } else {
              if (round) {
                c.drawCircle(r.center, ps / 2, fill(t.accent.withValues(alpha: 0.18)));
              } else {
                c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)), fill(t.accent.withValues(alpha: 0.18)));
              }
              final ch1 = _tp(e.name.trim().isEmpty ? '' : e.name.trim()[0].toUpperCase(), _st(58, t.accent, w: FontWeight.w800), ps, align: TextAlign.center);
              ch1.paint(c, Offset(r.left, r.top + (ps - ch1.height) / 2));
            }
            var ty = y + pad;
            name.paint(c, Offset(x + tx, ty));
            ty += name.height;
            if (desc != null) {
              ty += 4;
              desc.paint(c, Offset(x + tx, ty));
              ty += desc.height;
            }
            if (ex != null) {
              ty += 4;
              ex.paint(c, Offset(x + tx, ty));
              ty += ex.height;
            }
            ty += 10;
            if (t.priceFill.a > 0) {
              // a price tag
              c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + tx, ty, price.width + 28, price.height + 10), const Radius.circular(8)), fill(s.deals ? const Color(0xFFFFC107) : t.priceFill));
              price.paint(c, Offset(x + tx + 14, ty + 5));
            } else {
              price.paint(c, Offset(x + tx, ty));
            }
          }));
        }
      }
      final rowH = cells.fold<double>(0, (m, e) => math.max(m, e.h));
      blocks.add(_Block(rowH + gap, (c, y) {
        for (var k = 0; k < cells.length; k++) {
          cells[k].paint(c, _m + k * (cw + gap), y);
        }
      }));
    }
  }

  for (final s in d.sections) {
    await addSection(s);
    await addEntries(s);
  }

  // ---- the ordering card ----
  const cardH = 330.0;
  void closing(Canvas c, double y) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(_m, y, inner, cardH - 20), const Radius.circular(26));
    c.drawRRect(r, fill(t.card));
    c.drawRRect(r, Paint()..color = t.accent.withValues(alpha: 0.7)..style = PaintingStyle.stroke..strokeWidth = 3);
    final hasQr = d.qrLink != null;
    final tw = inner - 70 - (hasQr ? 270 : 0);
    var ty = y + 34.0;
    void line(String s, double size, Color col, {FontWeight wt = FontWeight.w500, int lines = 2}) {
      if (s.trim().isEmpty) return;
      final p = _tp(s, _st(size, col, w: wt), tw, maxLines: lines);
      p.paint(c, Offset(_m + 36, ty));
      ty += p.height + 8;
    }

    line(labels.orderOnWhatsApp, 38, t.accent, wt: FontWeight.w800);
    if ((d.phone ?? '').isNotEmpty) line(d.phone!, 36, t.text, wt: FontWeight.w700);
    line(labels.orderHow, 22, t.muted, lines: 3);
    line(d.address ?? '', 22, t.text);
    if (hasQr) {
      final qs = 210.0, qx = w - _m - 36 - qs, qy = y + 34;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qx - 12, qy - 12, qs + 24, qs + 24), const Radius.circular(16)), fill(const Color(0xFFFFFFFF)));
      c.save();
      c.translate(qx, qy);
      QrPainter(data: d.qrLink!, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111111))).paint(c, Size(qs, qs));
      c.restore();
      _tp(labels.scanToOrder, _st(21, t.accent, w: FontWeight.w700), qs + 24, align: TextAlign.center).paint(c, Offset(qx - 12, qy + qs + 18));
    }
  }

  // ---- pagination ----
  final firstTop = cover ? 150.0 : 330.0, nextTop = 150.0;
  final pages = <List<(_Block, double)>>[[]];
  var y = firstTop;
  final limit = h - _footer - (t.id == 'blackred' ? 50 : 0);
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    var need = b.h;
    if (b.keep && i + 1 < blocks.length) need += blocks[i + 1].h;
    if (y + need > limit && pages.last.isNotEmpty) {
      pages.add([]);
      y = nextTop;
    }
    pages.last.add((b, y));
    y += b.h;
  }
  var closingY = y + 10;
  if (closingY + cardH > limit) {
    pages.add([]);
    closingY = nextTop + 10;
  }
  final total = pages.length + (cover ? 1 : 0);

  // ---- header of a content page ----
  void header(Canvas c, bool big) {
    if (!big) {
      final tp = _tp(d.name.toUpperCase(), _st(40, t.text, w: FontWeight.w800), w - 2 * _m - 220);
      tp.paint(c, Offset(_m + (t.id == 'blackred' ? 0 : 0), t.id == 'blackred' ? 86 : 52));
      final m = _tp(labels.menu.toUpperCase(), _st(30, t.accent, w: FontWeight.w800), 200, align: TextAlign.right);
      m.paint(c, Offset(w - _m - 200, t.id == 'blackred' ? 92 : 58));
      return;
    }
    var lx = _m;
    if (logo != null) {
      c.drawCircle(const Offset(_m + 70, 130), 72, fill(const Color(0xFFFFFFFF)));
      _img(c, logo, const Rect.fromLTWH(_m + 8, 68, 124, 124), circle: true);
      lx = _m + 164;
    }
    final name = _tp(d.name.toUpperCase(), _st(58, t.text, w: FontWeight.w800), w - lx - _m, maxLines: 2);
    name.paint(c, Offset(lx, 70));
    final sub = [labels.menu.toUpperCase(), if ((d.phone ?? '').isNotEmpty) d.phone!].join('   |   ');
    _tp(sub, _st(26, t.accent, w: FontWeight.w700), w - lx - _m, maxLines: 2).paint(c, Offset(lx, 74 + name.height + 6));
  }

  Future<Uint8List> toPng(void Function(Canvas c) draw) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w * scale, h * scale));
    c.scale(scale);
    draw(c);
    final image = await rec.endRecording().toImage((w * scale).round(), (h * scale).round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  // ---- the cover ----
  Future<Uint8List> paintCover() async {
    ui.Image? hero;
    for (final s in d.sections) {
      for (final e in s.entries) {
        if (e.image != null && !identical(e.image, d.logo) && !identical(e.image, s.image)) {
          hero = await imageOf(e.image, 760);
          break;
        }
      }
      if (hero != null) break;
    }
    hero ??= await imageOf(d.sections.expand((s) => s.entries).map((e) => e.image).whereType<Uint8List>().firstOrNull, 760) ?? logo;
    return toPng((c) {
      background(c, isCover: true);
      // the restaurant name on a ribbon
      final rw = math.min(w - 2 * _m, 700.0);
      ribbon(c, Rect.fromLTWH((w - rw) / 2, 120, rw, 76), t.id == 'blackred' ? t.accent : t.ribbon);
      final nm = _tp(d.name.toUpperCase(), _st(34, t.id == 'blackred' ? const Color(0xFFFFFFFF) : t.ribbonText, w: FontWeight.w800), rw - 150, align: TextAlign.center);
      nm.paint(c, Offset((w - nm.width) / 2, 120 + (76 - nm.height) / 2));
      // the big word
      final big = _tp(labels.menu.toUpperCase(), _st(190, t.accent, w: FontWeight.w900), w - 2 * _m, align: TextAlign.center);
      big.paint(c, Offset(_m, 220));
      final tag = _tp(labels.tagline.toUpperCase(), _st(40, t.text, w: FontWeight.w700), w - 2 * _m, align: TextAlign.center);
      tag.paint(c, Offset(_m, 220 + big.height + 4));
      // the picture
      final cy = 835.0, cr = 300.0;
      if (t.id == 'royal') {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.5, cy - 250, w * 0.5 - _m, 560), const Radius.circular(30)), fill(t.accent));
      } else {
        c.drawCircle(Offset(w / 2 + 26, cy + 20), cr + 26, fill(t.accent.withValues(alpha: 0.9)));
      }
      c.drawCircle(Offset(w / 2, cy), cr + 14, fill(const Color(0xFFFFFFFF)));
      if (hero != null) {
        _img(c, hero, Rect.fromCircle(center: Offset(w / 2, cy), radius: cr), circle: true);
      } else {
        c.drawCircle(Offset(w / 2, cy), cr, fill(t.accent.withValues(alpha: 0.25)));
      }
      // contact + QR
      var ty = 1190.0;
      final hasQr = d.qrLink != null;
      final tw = w - 2 * _m - (hasQr ? 250 : 0);
      void line(String s, double size, Color col, {FontWeight wt = FontWeight.w600, int lines = 2}) {
        if (s.trim().isEmpty) return;
        final p = _tp(s, _st(size, col, w: wt), tw, maxLines: lines);
        p.paint(c, Offset(_m + 10, ty));
        ty += p.height + 6;
      }

      line(labels.orderOnWhatsApp.toUpperCase(), 28, t.accent, wt: FontWeight.w800);
      line(d.phone ?? '', 46, t.text, wt: FontWeight.w800);
      line(d.address ?? '', 24, t.muted);
      if (hasQr) {
        const qs = 170.0;
        final qx = w - _m - qs - 10, qy = 1180.0;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(qx - 10, qy - 10, qs + 20, qs + 20), const Radius.circular(14)), fill(const Color(0xFFFFFFFF)));
        c.save();
        c.translate(qx, qy);
        QrPainter(data: d.qrLink!, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111111))).paint(c, const Size(qs, qs));
        c.restore();
      }
      footer(c, 0, total);
    });
  }

  final out = <Uint8List>[];
  if (cover) out.add(await paintCover());
  for (var i = 0; i < pages.length; i++) {
    final index = i + (cover ? 1 : 0);
    out.add(await toPng((c) {
      background(c, isCover: false);
      header(c, i == 0 && !cover);
      for (final (b, by) in pages[i]) {
        b.paint(c, by);
      }
      if (i == pages.length - 1) closing(c, closingY);
      footer(c, index, total);
    }));
  }
  return out;
}

/// The poster pages as an A4 PDF (each page is the picture, so the PDF looks exactly like the PNG).
Future<Uint8List> posterPdf(List<Uint8List> pngPages, String title) async {
  final doc = pw.Document(title: title, creator: 'DT Food POS');
  for (final p in pngPages) {
    final image = pw.MemoryImage(p);
    doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero, build: (_) => pw.Image(image, fit: pw.BoxFit.fill)));
  }
  return doc.save();
}

/// The page picture size used by every look.
const posterAspect = pngPageWidth / pngPageHeight;
