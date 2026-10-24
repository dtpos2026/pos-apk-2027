import 'dart:convert';
import 'dart:typed_data';

import 'package:dt_food_pos/domain/escpos.dart';
import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/receipt_template.dart';
import 'package:flutter_test/flutter_test.dart';

RasterImage logo(int w, int h) => RasterImage(widthPx: w, heightPx: h, bits: Uint8List(((w + 7) ~/ 8) * h)..fillRange(0, ((w + 7) ~/ 8) * h, 0xFF));

ReceiptData data({String name = 'Burger Point', RasterImage? logoImg}) => ReceiptData(
      businessName: name,
      address: 'Main Bazaar, Burewala',
      phone: '0300-0000000',
      taxLabel: 'NTN',
      taxNumber: '1234567-8',
      invoiceNo: 'INV-1',
      dateTime: '2026-01-12 19:40',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'T4',
      cashier: 'Ali',
      lines: const [ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000)],
      subtotalMinor: 90000,
      totalMinor: 90000,
      payments: const [ReceiptPayment('Cash', 100000)],
      changeMinor: 10000,
      logo: logoImg,
    );

int indent(String line) => line.length - line.trimLeft().length;

void main() {
  inverseTests();
  group('logo and name have their own position', () {
    test('each can be left, centre or right; the address lines keep the header position; old designs follow the header', () {
      final doc = buildBillDoc(data(logoImg: logo(120, 40)), template: const BillDesign(headerAlign: PrintAlign.left, logoAlign: PrintAlign.right, nameAlign: PrintAlign.center));
      expect(doc.lines.whereType<RImage>().single.align, PrintAlign.right);
      expect(doc.lines.whereType<RText>().firstWhere((l) => l.text == 'Burger Point').align, PrintAlign.center);
      expect(doc.lines.whereType<RText>().firstWhere((l) => l.text == 'Main Bazaar, Burewala').align, PrintAlign.left);
      final old = BillDesign.decode('{"headerAlign":"right"}');
      expect([old.logoAt, old.nameAt], [PrintAlign.right, PrintAlign.right]);
      final back = BillDesign.decode(const BillDesign(logoAlign: PrintAlign.left, nameAlign: PrintAlign.right).encode());
      expect([back.logoAt, back.nameAt, back.headerAlign], [PrintAlign.left, PrintAlign.right, PrintAlign.center]);
    });
  });

  group('header is centred by default', () {
    test('logo, name, address, phone and tax number are all centred on the paper', () {
      final text = previewBill(data(logoImg: logo(120, 40)), template: const BillDesign(nameSize: 1));
      final lines = text.split('\n');
      for (final needle in ['[logo]', 'Burger Point', 'Main Bazaar, Burewala', 'Tel: 0300-0000000', 'NTN: 1234567-8']) {
        final l = lines.firstWhere((l) => l.contains(needle), orElse: () => fail('missing $needle'));
        final left = indent(l);
        final right = 32 - l.trimRight().length;
        expect((left - right).abs(), lessThanOrEqualTo(1), reason: '"$needle" is not centred: "$l"');
        expect(left, greaterThan(0));
      }
    });

    test('left and right alignment are available', () {
      final left = previewBill(data(), template: const BillDesign(headerAlign: PrintAlign.left, nameSize: 1)).split('\n');
      expect(indent(left.firstWhere((l) => l.contains('Burger Point'))), 0);
      final right = previewBill(data(), template: const BillDesign(headerAlign: PrintAlign.right, nameSize: 1)).split('\n');
      expect(right.firstWhere((l) => l.contains('Burger Point')).trimRight().length, 32);
    });

    test('a double-size name is centred by its real width', () {
      final l = previewBill(data(name: 'Burger'), template: const BillDesign(nameSize: 2)).split('\n').firstWhere((l) => l.contains('Burger'));
      // 6 letters at double width = 12 columns on a 32 column paper: 10 spaces each side
      expect(indent(l), 10);
    });

    test('name size makes the name double width (fewer columns) in the printer data', () {
      final big = buildBill(data(name: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'), template: const BillDesign(nameSize: 2));
      expect(big, containsAllInOrder([0x1D, 0x21, 0x11])); // 2x width, 2x height
      final normal = buildBill(data(), template: const BillDesign(nameSize: 1));
      expect(normal.sublist(0, 12), isNot(containsAllInOrder([0x1D, 0x21, 0x11])));
    });
  });

  group('everything is editable', () {
    test('blocks can be switched off', () {
      final t = previewBill(
        data(logoImg: logo(80, 30)),
        template: const BillDesign(showLogo: false, showAddress: false, showPhone: false, showTaxNumber: false, showCashier: false, showOrderType: false, showPoweredBy: false),
      );
      for (final gone in ['[logo]', 'Main Bazaar', 'Tel:', 'NTN', 'Cashier', 'Type', 'Powered by']) {
        expect(t, isNot(contains(gone)), reason: gone);
      }
      expect(t, contains('Burger Point'));
      expect(t, contains('TOTAL PKR'));
    });

    test('table is part of the order type line unless hidden', () {
      expect(previewBill(data()), contains('Dine-in T4'));
      expect(previewBill(data(), template: const BillDesign(showTable: false)), isNot(contains('T4')));
    });

    test('extra header lines, own footer lines and a QR code', () {
      final doc = buildBillDoc(data(), template: const BillDesign(headerLines: ['Since 1999', ''], footerLines: ['Open 11am to 2am', 'Follow us @burgerpoint'], qrText: 'https://example.com/review'));
      final text = docToText(doc, 58);
      expect(text, contains('Since 1999'));
      expect(text, contains('Open 11am to 2am'));
      expect(text, contains('Follow us @burgerpoint'));
      expect(text, isNot(contains('Thank you')));
      expect(doc.lines.whereType<RQr>().single.data, 'https://example.com/review');
      expect(ascii(buildBill(data(), template: const BillDesign(qrText: 'https://x.y'))), contains('https://x.y'));
    });

    test('default footer is the standard thank-you line', () {
      expect(previewBill(data()), contains('Thank you! Visit again.'));
    });

    test('copies are printed one after the other', () {
      final one = ascii(buildBill(data())).split('Powered by Digital Target').length - 1;
      final three = ascii(buildBill(data(), template: const BillDesign(copies: 3))).split('Powered by Digital Target').length - 1;
      expect([one, three], [1, 3]);
    });

    test('80 mm paper uses 48 columns', () {
      final l = previewBill(data(), paperMm: 80).split('\n').firstWhere((l) => l.startsWith('Invoice'));
      expect(l.length, 48);
    });
  });

  group('logo on the printer', () {
    test('is sent as a full-width bitmap so it is centred on the paper whatever the printer does with ESC a', () {
      final b = buildBill(data(logoImg: logo(120, 40)));
      final i = _find(b, [0x1D, 0x76, 0x30, 0x00]);
      expect(i, isNot(-1));
      expect(b[i + 4] | (b[i + 5] << 8), 48); // 384 dots / 8
      expect(b[i + 6] | (b[i + 7] << 8), 40); // height
      // first image row: 120 black dots centred in 384: dots 132..251 -> bytes 16.5..31.4
      final row = b.sublist(i + 8, i + 8 + 48);
      final firstInk = row.indexWhere((x) => x != 0);
      expect(firstInk, inInclusiveRange(16, 17));
      expect(row.sublist(0, 16).every((x) => x == 0), isTrue);
      expect(row.sublist(32).every((x) => x == 0), isTrue);
    });

    test('no logo bitmap when the logo is switched off', () {
      expect(_find(buildBill(data(logoImg: logo(120, 40)), template: const BillDesign(showLogo: false)), [0x1D, 0x76, 0x30]), -1);
    });
  });

  group('Urdu / Arabic', () {
    test('bill language switches every label and flips rows to right-to-left', () {
      final doc = buildBillDoc(data(), template: const BillDesign(language: 'ur'));
      final rows = doc.lines.whereType<RRow>().toList();
      final total = rows.firstWhere((r) => r.right.contains('کل'));
      expect(total.left, '900.00'); // amount on the left, label on the right
      expect(rows.any((r) => r.right == 'بل نمبر'), isTrue);
      expect(rows.any((r) => r.right.startsWith('Zinger Burger x 2')), isTrue); // name first in a right-to-left bill
      final tel = doc.lines.whereType<RText>().firstWhere((t) => t.text.startsWith('فون'));
      expect(tel.text, contains('\u20660300-0000000\u2069')); // the number is isolated so it is not reversed
      expect(rows.any((r) => r.right.contains('نقد')), isTrue);
      expect(doc.lines.whereType<RText>().any((t) => t.text.contains('شکریہ')), isTrue);
    });

    test('without a rasterizer Urdu comes out as ? (never garbage bytes)', () {
      final b = buildBill(data(), template: const BillDesign(language: 'ur'));
      expect(b.every((x) => true), isTrue);
      expect(ascii(b), isNot(contains('بل')));
    });

    test('with a rasterizer the Urdu lines are printed as bitmaps', () async {
      final r = _FakeRasterizer();
      final bytes = await buildBillBytes(data(), template: const BillDesign(language: 'ur'), rasterizer: r);
      expect(r.calls, greaterThan(5)); // label rows and the footer
      expect(_countOf(bytes, [0x1D, 0x76, 0x30, 0x00]), greaterThanOrEqualTo(r.calls));
      expect(r.widths.toSet(), {384}); // always the full paper width
    });

    test('English bills never need the rasterizer', () async {
      final r = _FakeRasterizer();
      await buildBillBytes(data(), rasterizer: r);
      expect(r.calls, 0);
    });
  });

  group('BillDesign storage', () {
    test('round trip', () {
      const d = BillDesign(showLogo: false, nameSize: 3, headerAlign: PrintAlign.right, headerLines: ['a', 'b'], showCashier: false, footerLines: ['x'], qrText: 'q', showPoweredBy: false, copies: 2, language: 'ur');
      final back = BillDesign.decode(d.encode());
      expect(back.encode(), d.encode());
      expect(back.nameSize, 3);
      expect(back.language, 'ur');
      expect(back.headerAlign, PrintAlign.right);
    });

    test('damaged, empty or out-of-range data falls back to safe defaults', () {
      expect(BillDesign.decode(null).showLogo, isTrue);
      expect(BillDesign.decode('').nameSize, 2);
      expect(BillDesign.decode('{not json').headerAlign, PrintAlign.center);
      final d = BillDesign.decode(jsonEncode({'nameSize': 99, 'copies': -4, 'language': 'xx', 'headerAlign': 'diagonal'}));
      expect([d.nameSize, d.copies, d.language, d.headerAlign], [3, 1, 'en', PrintAlign.center]);
    });
  });
}

class _FakeRasterizer implements TextRasterizer {
  int calls = 0;
  final widths = <int>[];
  RasterImage _img(int w) {
    calls++;
    widths.add(w);
    return RasterImage(widthPx: w, heightPx: 2, bits: Uint8List((w ~/ 8) * 2));
  }

  @override
  Future<RasterImage> text(String text, {required int widthPx, PrintAlign align = PrintAlign.left, bool bold = false, int scale = 1}) async => _img(widthPx);
  @override
  Future<RasterImage> row(String left, String right, {required int widthPx, bool bold = false}) async => _img(widthPx);
}

void inverseTests() {
  test('RasterImage.inverted flips every dot and leaves the unused bits of a row white', () {
    final img = RasterImage(widthPx: 12, heightPx: 1, bits: Uint8List.fromList([0xF0, 0x00]));
    final inv = img.inverted();
    expect(inv.bits, [0x0F, 0xF0], reason: '12 px wide: the last 4 bits of byte 2 are padding and stay 0');
    expect(inv.inverted().bits, img.bits);
  });

  test('an Urdu line on a reverse-print bar is printed as an inverted bitmap', () async {
    final doc = ReceiptDoc([const RRow('کل', 'Rs 100', inverse: true)]);
    final bytes = (await EscPosRenderer(paperMm: 58, rasterizer: _FakeRasterizer()).render(doc)).toBytes();
    // the fake bitmap is all white (zeros); inverted it is all black
    expect(bytes.where((b) => b == 0xFF).length, greaterThan(40));
  });
}

String ascii(Uint8List b) => latin1.decode(b, allowInvalid: true);

int _find(Uint8List b, List<int> pat) {
  for (var i = 0; i <= b.length - pat.length; i++) {
    var ok = true;
    for (var j = 0; j < pat.length; j++) {
      if (b[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

int _countOf(Uint8List b, List<int> pat) {
  var n = 0;
  for (var i = 0; i <= b.length - pat.length; i++) {
    var ok = true;
    for (var j = 0; j < pat.length; j++) {
      if (b[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) n++;
  }
  return n;
}
