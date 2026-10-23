import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'receipt_doc.dart';

class LogoException implements Exception {
  LogoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Converts a logo file (PNG/JPG/WebP...) into a 1-bit bitmap for a thermal printer.
///
/// * Transparent areas become white. A mostly-white logo on a transparent background (like the Digital Target
///   mark) is printed as black ink instead of vanishing.
/// * Flat logos are thresholded for crisp edges; photographic ones are dithered (Floyd-Steinberg).
/// * The result is at most [maxWidthFraction] of the paper width and [maxHeightDots] tall.
RasterImage prepareLogo(Uint8List fileBytes, {required int paperMm, int maxHeightDots = 170, double maxWidthFraction = 0.6}) {
  final decoded = img.decodeImage(fileBytes);
  if (decoded == null) throw LogoException('This file is not a picture the app can read');
  final paperDots = dotsFor(paperMm);
  final maxW = (paperDots * maxWidthFraction).floor();
  final scale = min(maxW / decoded.width, maxHeightDots / decoded.height);
  final w = max(1, (decoded.width * min(scale, 1.0)).round());
  final h = max(1, (decoded.height * min(scale, 1.0)).round());
  final small = (w == decoded.width && h == decoded.height) ? decoded : img.copyResize(decoded, width: w, height: h, interpolation: img.Interpolation.average);

  // luminance (0 black .. 255 white) over white, plus alpha
  final lum = List<double>.filled(w * h, 255);
  final alpha = List<double>.filled(w * h, 1);
  var opaqueSum = 0.0, opaqueN = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      final a = p.a / p.maxChannelValue;
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / p.maxChannelValue * 255;
      alpha[y * w + x] = a;
      lum[y * w + x] = l * a + 255 * (1 - a);
      if (a > 0.5) {
        opaqueSum += l;
        opaqueN++;
      }
    }
  }
  final lightLogo = opaqueN > 0 && opaqueSum / opaqueN > 200 && alpha.any((a) => a < 0.5);
  if (lightLogo) {
    for (var i = 0; i < lum.length; i++) {
      lum[i] = 255 - alpha[i] * 255; // ink where the logo is opaque
    }
  }

  final levels = <int>{for (final v in lum) (v / 32).round()};
  final dither = levels.length > 6;
  final out = Uint8List((w + 7) ~/ 8 * h);
  final rowBytes = (w + 7) ~/ 8;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final old = lum[y * w + x];
      final black = old < 128;
      if (black) out[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
      if (dither) {
        final err = old - (black ? 0 : 255);
        void spread(int dx, int dy, double f) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < w && ny < h) lum[ny * w + nx] += err * f;
        }

        spread(1, 0, 7 / 16);
        spread(-1, 1, 3 / 16);
        spread(0, 1, 5 / 16);
        spread(1, 1, 1 / 16);
      }
    }
  }
  return RasterImage(widthPx: w, heightPx: h, bits: out);
}

/// Re-encodes any picture as a PNG no larger than [maxSide] pixels: what gets stored as the business logo.
Uint8List normalizeLogoFile(Uint8List fileBytes, {int maxSide = 600}) {
  final d = img.decodeImage(fileBytes);
  if (d == null) throw LogoException('This file is not a picture the app can read');
  final big = max(d.width, d.height);
  final r = big > maxSide ? img.copyResize(d, width: d.width >= d.height ? maxSide : null, height: d.height > d.width ? maxSide : null, interpolation: img.Interpolation.average) : d;
  return Uint8List.fromList(img.encodePng(r));
}
