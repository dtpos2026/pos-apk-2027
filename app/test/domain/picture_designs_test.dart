import 'dart:io';
import 'dart:ui' as ui;

import 'package:dt_food_pos/app/text_rasterizer.dart';
import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/receipt_template.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

ReceiptData _data() => ReceiptData(
      businessName: 'Digital Target',
      address: 'Main Boulevard, Gulberg III, Lahore',
      phone: '0300-1234567',
      invoiceNo: 'ORD-000123',
      dateTime: '13/11/2026 06:18 PM',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'Table 4',
      token: '027',
      cashier: 'Cashier',
      lines: const [
        ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000, modifiers: ['Extra mayo']),
        ReceiptLine(name: 'French Fries', qtyMilli: 1000, unitPriceMinor: 25000, totalMinor: 25000),
        ReceiptLine(name: 'Cold Drink 500ml', qtyMilli: 3000, unitPriceMinor: 12000, totalMinor: 36000),
      ],
      subtotalMinor: 151000,
      discountMinor: 6000,
      totalMinor: 145000,
      payments: const [ReceiptPayment('Cash', 150000)],
      changeMinor: 5000,
    );

void main() {
  for (final style in ['stamp', 'elegant', 'sheet', 'framed', 'mini']) {
    testWidgets('picture design "$style": one picture, the full 58 mm width, every amount on it', (t) async {
      await t.runAsync(() async {
        await loadAppFonts();
        final doc = buildBillDoc(_data(), template: BillDesign.defaults.withStyle(style));
        expect(doc.graphic, isTrue);
        final text = docToText(doc, 58);
        for (final s in ['Zinger Burger', '900.00', '1,450.00', 'Cold Drink 500ml']) {
          expect(text, contains(s), reason: style);
        }
        final img = await const FlutterTextRasterizer().document(doc, widthPx: 384);
        expect(img.widthPx, 384);
        final out = Platform.environment['DESIGN_DIR'];
        if (out != null) {
          final pic = await const FlutterTextRasterizer().documentImage(doc, widthPx: 384);
          final png = await pic.toByteData(format: ui.ImageByteFormat.png);
          File('$out/$style.png').writeAsBytesSync(png!.buffer.asUint8List());
        }
      });
    });
  }
}
