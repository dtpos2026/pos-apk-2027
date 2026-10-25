import 'dart:io';

import 'package:dt_food_pos/app/text_rasterizer.dart';
import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/receipt_template.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

ReceiptData _data({String? table, String? token = '004'}) => ReceiptData(
      businessName: 'Takeaway Pizza',
      address: 'Sadar Bazar oppsit Abu Bakar Bakers Narang',
      phone: '03054967080',
      invoiceNo: 'ORD-000005',
      dateTime: '24/10/2026 01:35 AM',
      orderTypeLabel: table == null ? 'Takeaway' : 'Dine-in',
      tableLabel: table,
      token: token,
      cashier: 'Administrator',
      lines: const [ReceiptLine(name: 'Platter Shawarma', qtyMilli: 1000, unitPriceMinor: 50000, totalMinor: 50000), ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000, modifiers: ['Extra mayo'])],
      subtotalMinor: 140000,
      totalMinor: 140000,
      payments: const [ReceiptPayment('Cash', 150000)],
      changeMinor: 10000,
    );

void main() {
  testWidgets('original design: the whole bill is ONE picture (boxed type/token, black TOTAL bar) sent to the printer in bands', (t) async {
    await t.runAsync(() async {
      await loadAppFonts();
      final design = BillDesign.defaults.withStyle('original');
      final doc = buildBillDoc(_data(), template: design);
      expect(doc.graphic, isTrue);
      expect(doc.lines.whereType<RCells>().single.values, ['TAKEAWAY', '#004']);
      expect(doc.lines.whereType<RRow>().any((r) => r.inverse && r.left == 'TOTAL'), isTrue);

      final img = await const FlutterTextRasterizer().document(doc, widthPx: 384);
      expect(img.widthPx, 384);
      expect(img.heightPx, greaterThan(400));
      expect(img.bits.any((b) => b != 0), isTrue);

      final bytes = (await EscPosRenderer(paperMm: 58, rasterizer: const FlutterTextRasterizer()).render(doc)).toBytes();
      expect(bytes.length, greaterThan(img.bits.length ~/ 2));

      final dine = buildBillDoc(_data(table: 'Table 4'), template: design);
      expect(dine.lines.whereType<RCells>().single.heads, ['TYPE', 'TABLE', 'TOKEN']);

      final dir = Platform.environment['SCREENSHOT_DIR'];
      if (dir != null) {
        Directory(dir).createSync(recursive: true);
        for (final e in {'takeaway': doc, 'dinein': dine}.entries) {
          final im = await const FlutterTextRasterizer().document(e.value, widthPx: 384);
          // PBM -> PNG-less: write as PGM text-free binary (viewable after conversion)
          final out = BytesBuilderPgm(im).bytes();
          File('$dir/original_${e.key}.pgm').writeAsBytesSync(out);
        }
      }
    });
  });
}

class BytesBuilderPgm {
  BytesBuilderPgm(this.im);
  final RasterImage im;
  List<int> bytes() {
    final b = <int>[...'P5\n${im.widthPx} ${im.heightPx}\n255\n'.codeUnits];
    for (var y = 0; y < im.heightPx; y++) {
      for (var x = 0; x < im.widthPx; x++) {
        b.add(im.pixel(x, y) ? 0 : 255);
      }
    }
    return b;
  }
}
