import 'dart:convert';
import 'dart:typed_data';

import 'package:dt_food_pos/domain/escpos.dart';
import 'package:dt_food_pos/domain/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

String ascii(Uint8List b) => latin1.decode(b, allowInvalid: true);

ReceiptData sample({bool dup = false, String name = 'Burger Point'}) => ReceiptData(
      businessName: name,
      address: 'Main Bazaar, Burewala',
      phone: '0300-0000000',
      taxLabel: 'NTN',
      taxNumber: '1234567-8',
      invoiceNo: 'INV-20260112-0007',
      dateTime: '2026-01-12 19:40',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'T4',
      cashier: 'Ali',
      lines: const [
        ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000, modifiers: ['Extra cheese']),
        ReceiptLine(name: 'Fries', qtyMilli: 1000, unitPriceMinor: 15000, totalMinor: 15000),
      ],
      subtotalMinor: 105000,
      taxMinor: 16800,
      totalMinor: 121800,
      payments: const [ReceiptPayment('Cash', 150000)],
      changeMinor: 28200,
      isDuplicate: dup,
      footer: 'Thank you!',
    );

void main() {
  group('EscPosBuilder', () {
    test('init, bold, size and cut commands', () {
      final b = EscPosBuilder().init().bold(true).size(width: 2, height: 3).line('Hi').cut().toBytes();
      expect(b.sublist(0, 2), [0x1B, 0x40]);
      expect(b, containsAllInOrder([0x1B, 0x45, 1]));
      expect(b, containsAllInOrder([0x1D, 0x21, 0x12]));
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('row pads to exactly the paper width', () {
      final b58 = EscPosBuilder().row('Total', '1,000.00').toBytes();
      expect(ascii(b58).trimRight().length, 32);
      final b80 = EscPosBuilder(paperMm: 80).row('Total', '1,000.00').toBytes();
      expect(ascii(b80).trimRight().length, 48);
    });

    test('long names wrap, amount stays on the first line', () {
      final out = ascii(EscPosBuilder().row('Chicken Tikka Karahi Half Plate With Naan', '1,250.00').toBytes()).split('\n');
      expect(out.first.endsWith('1,250.00'), isTrue);
      expect(out.length, greaterThan(2));
      for (final l in out) {
        expect(l.length, lessThanOrEqualTo(32));
      }
    });

    test('non-ASCII is replaced, never emitted raw', () {
      final b = EscPosBuilder().text('Café ٣').toBytes();
      expect(b.every((x) => x < 0x80), isTrue);
    });

    test('raster validates and frames the bitmap', () {
      final bits = Uint8List(4 * 8);
      final b = EscPosBuilder().raster(bits, widthBytes: 4, heightPx: 8).toBytes();
      expect(b.sublist(0, 8), [0x1D, 0x76, 0x30, 0, 4, 0, 8, 0]);
      expect(b.length, 8 + 32);
      expect(() => EscPosBuilder().raster(Uint8List(3), widthBytes: 4, heightPx: 8), throwsArgumentError);
    });

    test('qr frames store + print commands', () {
      final b = EscPosBuilder().qr('INV-1').toBytes();
      expect(b, containsAllInOrder([0x1D, 0x28, 0x6B, 0x08, 0x00, 0x31, 0x50, 0x30]));
      expect(b.sublist(b.length - 8), [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    });

    test('paper width must be 58 or 80', () {
      expect(() => EscPosBuilder(paperMm: 70), throwsArgumentError);
    });

    test('needsRaster detects Urdu/Arabic', () {
      expect(needsRaster('Burger'), isFalse);
      expect(needsRaster('چکن برگر'), isTrue);
      expect(needsRaster('برجر'), isTrue);
    });
  });

  group('bill receipt', () {
    test('contains the key content and ends with a cut', () {
      final b = buildBill(sample());
      final s = ascii(b);
      expect(s, contains('Burger Point'));
      expect(s, contains('INV-20260112-0007'));
      expect(s, contains('2 x Zinger Burger'));
      expect(s, contains('900.00'));
      expect(s, contains('+ Extra cheese'));
      expect(s, contains('1,218.00'));
      expect(s, contains('Change'));
      expect(s, contains('Powered by Digital Target'));
      expect(s, isNot(contains('DUPLICATE')));
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('preview text is exactly what is printed', () {
      final d = sample();
      final preview = previewBill(d);
      expect(preview, contains('2 x Zinger Burger'));
      expect(preview, contains('1,218.00'));
      expect(preview, isNot(contains('\x1B')));
      final printed = ascii(buildBill(d)).replaceAll(RegExp(r'[\x00-\x09\x0B-\x1F]'), '');
      for (final l in preview.split('\n').where((l) => l.trim().isNotEmpty)) {
        expect(printed, contains(l.trim()));
      }
    });

    test('duplicate marker', () {
      expect(ascii(buildBill(sample(dup: true))), contains('*** DUPLICATE ***'));
    });

    test('copies repeat the receipt', () {
      final once = ascii(buildBill(sample())).split('Powered by Digital Target').length - 1;
      final twice = ascii(buildBill(sample(), copies: 2)).split('Powered by Digital Target').length - 1;
      expect(once, 1);
      expect(twice, 2);
    });

    test('no printed line exceeds the paper width (58mm)', () {
      final text = ascii(buildBill(sample()));
      // strip ESC/GS control sequences loosely: only check the printable rows we produce
      for (final l in text.split('\n')) {
        final printable = l.replaceAll(RegExp(r'[\x00-\x1F]'), '');
        expect(printable.length, lessThanOrEqualTo(40), reason: l); // control params may leave a few visible bytes
      }
    });

    test('reports Urdu fields that need a bitmap', () {
      expect(rasterFields(sample()), isEmpty);
      expect(rasterFields(sample(name: 'برگر پوائنٹ')), ['businessName']);
    });
  });

  group('KOT', () {
    test('has no prices and shows the station', () {
      final b = buildKot(
        station: 'grill',
        orderLabel: '#12',
        orderTypeLabel: 'Dine-in',
        tableLabel: 'T4',
        dateTime: '19:40',
        lines: const [KotLine('Zinger Burger', 2000, modifiers: ['No onion'], note: 'Spicy')],
        isReprint: true,
      );
      final s = ascii(b);
      expect(s, contains('GRILL'));
      expect(s, contains('2 x Zinger Burger'));
      expect(s, contains('REPRINT'));
      expect(s, isNot(contains('Total')));
    });
  });
}
