import 'dart:typed_data';

import 'package:dt_food_pos/domain/escpos.dart';
import 'package:dt_food_pos/domain/logo.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png(img.Image i) => Uint8List.fromList(img.encodePng(i));

/// Black filled circle on white.
img.Image blackCircle(int size) {
  final i = img.Image(width: size, height: size, numChannels: 4)..clear(img.ColorRgba8(255, 255, 255, 255));
  img.fillCircle(i, x: size ~/ 2, y: size ~/ 2, radius: size ~/ 2 - 2, color: img.ColorRgba8(0, 0, 0, 255));
  return i;
}

int blackPixels(RasterImage r) {
  var n = 0;
  for (var y = 0; y < r.heightPx; y++) {
    for (var x = 0; x < r.widthPx; x++) {
      if (r.pixel(x, y)) n++;
    }
  }
  return n;
}

void main() {
  test('a big logo is scaled to at most 60% of the paper width and the height limit', () {
    final r = prepareLogo(png(blackCircle(800)), paperMm: 58);
    expect(r.widthPx, lessThanOrEqualTo((384 * 0.6).floor()));
    expect(r.heightPx, lessThanOrEqualTo(170));
    expect(blackPixels(r), greaterThan(500));
    expect(r.pixel(r.widthPx ~/ 2, r.heightPx ~/ 2), isTrue); // centre of the circle is ink
    expect(r.pixel(0, 0), isFalse); // corner is paper
  });

  test('80 mm paper allows a wider logo than 58 mm', () {
    final wide = img.Image(width: 900, height: 100, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 255));
    expect(prepareLogo(png(wide), paperMm: 80, maxHeightDots: 400).widthPx, greaterThan(prepareLogo(png(wide), paperMm: 58, maxHeightDots: 400).widthPx));
  });

  test('a white logo on a transparent background is printed as ink, not lost', () {
    final i = img.Image(width: 100, height: 100, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(i, x1: 20, y1: 20, x2: 80, y2: 80, color: img.ColorRgba8(255, 255, 255, 255));
    final r = prepareLogo(png(i), paperMm: 58);
    expect(blackPixels(r), greaterThan(r.widthPx * r.heightPx ~/ 4));
    expect(r.pixel(r.widthPx ~/ 2, r.heightPx ~/ 2), isTrue);
    expect(r.pixel(0, 0), isFalse);
  });

  test('a gradient is dithered (has both black and white pixels in the same area)', () {
    final g = img.Image(width: 120, height: 60, numChannels: 4);
    for (var y = 0; y < 60; y++) {
      for (var x = 0; x < 120; x++) {
        final v = (x * 255 / 119).round();
        g.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    final r = prepareLogo(png(g), paperMm: 58);
    var leftBlack = 0, midBlack = 0;
    for (var y = 0; y < r.heightPx; y++) {
      for (var x = 0; x < r.widthPx; x++) {
        if (!r.pixel(x, y)) continue;
        if (x < r.widthPx ~/ 4) leftBlack++;
        if (x >= r.widthPx * 3 ~/ 8 && x < r.widthPx * 5 ~/ 8) midBlack++;
      }
    }
    expect(leftBlack, greaterThan(midBlack)); // darker on the left
    expect(midBlack, greaterThan(0)); // the middle is a mix, not all or nothing
  });

  test('not a picture is a clear error', () {
    expect(() => prepareLogo(Uint8List.fromList([1, 2, 3, 4]), paperMm: 58), throwsA(isA<LogoException>()));
    expect(() => normalizeLogoFile(Uint8List.fromList([1, 2, 3])), throwsA(isA<LogoException>()));
  });

  test('normalizeLogoFile shrinks big pictures to a PNG', () {
    final out = normalizeLogoFile(png(blackCircle(2000)), maxSide: 600);
    final d = img.decodePng(out)!;
    expect(d.width, 600);
    expect(d.height, 600);
  });

  test('padded() centres the picture on a full-width canvas', () {
    final small = RasterImage(widthPx: 16, heightPx: 1, bits: Uint8List.fromList([0xFF, 0xFF]));
    final p = small.padded(64, PrintAlign.center);
    expect(p.widthPx, 64);
    expect([for (var x = 0; x < 64; x++) p.pixel(x, 0)].indexOf(true), 24); // (64 - 16) / 2
    expect(small.padded(64, PrintAlign.left).pixel(0, 0), isTrue);
    expect(small.padded(64, PrintAlign.right).pixel(63, 0), isTrue);
    expect(small.padded(64, PrintAlign.right).pixel(47, 0), isFalse);
  });
}
