import 'dart:convert';
import 'dart:typed_data';

enum PrintAlign { left, center, right }

/// True if [s] contains Arabic-script characters (Urdu, Arabic, Persian). Thermal printers have no fonts for them,
/// so such lines must be rendered to a bitmap and sent with [EscPosBuilder.raster].
bool needsRaster(String s) => RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]').hasMatch(s);

/// Minimal ESC/POS command builder (58 mm = 32 columns, 80 mm = 48 columns, font A).
class EscPosBuilder {
  EscPosBuilder({this.paperMm = 58}) {
    if (paperMm != 58 && paperMm != 80) throw ArgumentError('paper must be 58 or 80 mm');
  }
  final int paperMm;
  final _bytes = BytesBuilder();

  int get columns => paperMm == 80 ? 48 : 32;
  Uint8List toBytes() => _bytes.toBytes();

  void _raw(List<int> b) => _bytes.add(b);

  EscPosBuilder init() {
    _raw([0x1B, 0x40]);
    return this;
  }

  /// ESC t n, selects the printer's code page (0 = CP437).
  EscPosBuilder codePage(int n) {
    _raw([0x1B, 0x74, n]);
    return this;
  }

  EscPosBuilder align(PrintAlign a) {
    _raw([0x1B, 0x61, a.index]);
    return this;
  }

  EscPosBuilder bold(bool on) {
    _raw([0x1B, 0x45, on ? 1 : 0]);
    return this;
  }

  /// Character size multiplier 1..8 for width and height.
  EscPosBuilder size({int width = 1, int height = 1}) {
    if (width < 1 || width > 8 || height < 1 || height > 8) throw ArgumentError('size must be 1..8');
    _raw([0x1D, 0x21, ((width - 1) << 4) | (height - 1)]);
    return this;
  }

  /// Printable ASCII only; anything else becomes '?' (use [raster] for non-Latin scripts).
  List<int> _ascii(String s) => s.runes.map((r) => (r >= 0x20 && r < 0x7F) ? r : 0x3F).toList();

  EscPosBuilder text(String s) {
    _raw(_ascii(s));
    return this;
  }

  EscPosBuilder line([String s = '']) {
    _raw(_ascii(s));
    _raw([0x0A]);
    return this;
  }

  /// Wraps [s] to the paper width on word boundaries.
  EscPosBuilder wrapped(String s) {
    for (final l in wrap(s, columns)) {
      line(l);
    }
    return this;
  }

  /// "left ........ right" on one line. If it does not fit, left is wrapped and right stays on the first line.
  EscPosBuilder row(String left, String right) {
    final avail = columns - right.length - 1;
    final parts = avail > 0 ? wrap(left, avail) : [left];
    final first = parts.isEmpty ? '' : parts.first;
    line(first.padRight(columns - right.length) + right);
    for (final p in parts.skip(1)) {
      line(p);
    }
    return this;
  }

  EscPosBuilder divider([String ch = '-']) {
    line(ch * columns);
    return this;
  }

  EscPosBuilder feed([int lines = 1]) {
    _raw([0x1B, 0x64, lines]);
    return this;
  }

  /// Partial cut after feeding a few lines.
  EscPosBuilder cut() {
    feed(3);
    _raw([0x1D, 0x56, 0x42, 0x00]);
    return this;
  }

  /// Opens the cash drawer on pin 2.
  EscPosBuilder openDrawer() {
    _raw([0x1B, 0x70, 0x00, 0x19, 0xFA]);
    return this;
  }

  /// QR code (model 2). [data] is ASCII/UTF-8.
  EscPosBuilder qr(String data, {int moduleSize = 5}) {
    final d = utf8.encode(data);
    if (d.isEmpty || d.length > 7000) throw ArgumentError('QR data length out of range');
    _raw([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]); // model 2
    _raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize.clamp(1, 16)]);
    _raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]); // error correction L
    final n = d.length + 3;
    _raw([0x1D, 0x28, 0x6B, n & 0xFF, n >> 8, 0x31, 0x50, 0x30, ...d]);
    _raw([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]); // print
    return this;
  }

  /// Prints a 1-bit-per-pixel bitmap (GS v 0). [bits] is row-major, MSB first, [widthBytes] bytes per row.
  /// Used for logos and for Urdu/Arabic text rendered to a bitmap.
  EscPosBuilder raster(Uint8List bits, {required int widthBytes, required int heightPx}) {
    if (widthBytes <= 0 || widthBytes > 0xFFFF || heightPx <= 0 || heightPx > 0xFFFF) throw ArgumentError('bad bitmap size');
    if (bits.length != widthBytes * heightPx) throw ArgumentError('bitmap data length mismatch');
    _raw([0x1D, 0x76, 0x30, 0x00, widthBytes & 0xFF, widthBytes >> 8, heightPx & 0xFF, heightPx >> 8]);
    _raw(bits);
    return this;
  }

  static List<String> wrap(String s, int width) {
    final out = <String>[];
    for (final para in s.split('\n')) {
      var cur = '';
      for (final word in para.split(' ')) {
        if (word.isEmpty) continue;
        var w = word;
        while (w.length > width) {
          if (cur.isNotEmpty) {
            out.add(cur);
            cur = '';
          }
          out.add(w.substring(0, width));
          w = w.substring(width);
        }
        if (cur.isEmpty) {
          cur = w;
        } else if (cur.length + 1 + w.length <= width) {
          cur = '$cur $w';
        } else {
          out.add(cur);
          cur = w;
        }
      }
      out.add(cur);
    }
    return out;
  }
}
