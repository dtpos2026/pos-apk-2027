import 'dart:typed_data';

import 'package:dt_food_pos/domain/escpos.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/receipt.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/receipt_template.dart';
import 'package:dt_food_pos/domain/token.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rast implements TextRasterizer {
  final seen = <String>[];
  RasterImage _img() => RasterImage(widthPx: 8, heightPx: 1, bits: Uint8List(1));
  @override
  Future<RasterImage> text(String text, {required int widthPx, PrintAlign align = PrintAlign.left, bool bold = false, int scale = 1}) async {
    seen.add(text);
    return _img();
  }

  @override
  Future<RasterImage> row(String left, String right, {required int widthPx, bool bold = false}) async {
    seen.add('$left|$right');
    return _img();
  }
}

/// Printable width of a rendered line: double-width text occupies two columns per character.
void expectFits(ReceiptDoc doc, int paperMm, String why) {
  final cols = columnsFor(paperMm);
  for (final l in doc.lines) {
    switch (l) {
      case RText():
        for (final line in EscPosBuilder.wrap(l.text, (cols / l.width).floor())) {
          expect(line.length * l.width, lessThanOrEqualTo(cols), reason: '$why: "${l.text}" x${l.width}');
        }
      case RCols():
        for (final line in layoutCols(l.cells, l.widths, cols)) {
          expect(line.length, lessThanOrEqualTo(cols), reason: '$why: $line');
        }
      case RRow():
        // the label wraps, the amount never does
        expect(l.right.length, lessThan(cols), reason: why);
      default:
    }
  }
}

void main() {
  const kinds = TokenKind.values;

  group('every ready-made design, every kind of sample, both paper widths', () {
    for (final id in builtInTemplateOrder) {
      for (final paper in [58, 80]) {
        for (final kind in kinds) {
          test('$id on $paper mm with $kind data fits the paper, shows the token and never crashes', () {
            final t = builtInTemplates[id]!;
            final slip = sampleSlip(kind, businessName: 'Burger Point');
            final doc = buildTokenSlipDoc(t, slip, paperMm: paper);
            expectFits(doc, paper, '$id/$paper/$kind');
            final text = docToText(doc, paper);
            expect(text, contains(slip.label), reason: id == 'product' || id == 'tandoor' || id == 'stall' || id == 'premium' || id == 'classic' || id == 'price' || id == 'coupon' ? 'every design prints the number' : '');
            expect(text, contains('Powered by Digital Target'));
            // real ESC/POS bytes
            final bytes = (EscPosRenderer(paperMm: paper).renderSync(doc)..cut()).toBytes();
            expect(bytes.length, greaterThan(40));
          });
        }
      }
    }
  });

  test('all ready-made designs are genuinely different from each other', () {
    final slip = sampleSlip(TokenKind.price, businessName: 'Burger Point');
    final texts = {for (final id in builtInTemplateOrder) id: previewSlip(builtInTemplates[id]!, slip)};
    expect(texts.values.toSet().length, builtInTemplateOrder.length);
    expect(builtInTemplateOrder.length, 12);
    expect(texts['price'], allOf(contains('Rate'), contains('Amount'), contains('TOTAL'), contains('Discount')));
    expect(texts['classic'], isNot(contains('Zinger')));
    expect(texts['product'], contains('2 x Zinger Burger'));
    expect(previewSlip(builtInTemplates['tandoor']!, sampleSlip(TokenKind.tandoor, businessName: 'X')), contains('Collect from'));
    expect(texts['premium'], contains('[QR]'));
    expect(texts['stall'], contains('COLLECT FROM'));
  });

  test('tandoor design prints big quantities: the item lines are triple size', () {
    final doc = buildTokenSlipDoc(builtInTemplates['tandoor']!, sampleSlip(TokenKind.tandoor, businessName: 'X'));
    final roti = doc.lines.whereType<RText>().firstWhere((l) => l.text.contains('Roti'));
    expect(roti.text, startsWith('6'));
    expect(roti.height, 3);
    expect(roti.bold, isTrue);
  });

  test('token number is as large as fits: 5x for short numbers, smaller for long ones', () {
    final t = builtInTemplates['classic']!;
    int sizeOf(String label) {
      final s = sampleSlip(TokenKind.order, businessName: 'X');
      final doc = buildTokenSlipDoc(t, TokenSlip(businessName: 'X', label: label, dateTime: s.dateTime), paperMm: 58);
      return doc.lines.whereType<RText>().firstWhere((l) => l.text == label).width;
    }

    expect(sizeOf('A17'), 5);
    expect(sizeOf('ABC12345'), 4); // 32 / 8
    expect(sizeOf('ABC1234567890'), 2);
  });

  group('editing', () {
    final base = builtInTemplates['classic']!;
    TokenSlip slip() => sampleSlip(TokenKind.order, businessName: 'Burger Point');

    test('hide, show, reorder, align, resize and re-word blocks', () {
      var t = base;
      String text() => previewSlip(t, slip());
      expect(text(), contains('TOKEN'));
      expect(text(), contains('Please wait for your number'));
      // hide
      t = t.copyWith(blocks: [for (final b in t.blocks) b.type == BlockType.text ? b.copyWith(show: false) : b]);
      expect(text(), isNot(contains('Please wait')));
      // re-word the heading
      t = t.copyWith(blocks: [for (final b in t.blocks) b.type == BlockType.title ? b.copyWith(text: 'YOUR NUMBER') : b]);
      expect(text(), contains('YOUR NUMBER'));
      // show items with prices
      t = t.copyWith(blocks: [for (final b in t.blocks) b.type == BlockType.items ? b.copyWith(show: true, align: PrintAlign.left).withFlag('price', true).withFlag('amount', true) : b]);
      expect(text(), allOf(contains('Zinger'), contains('450.00'), contains('900.00')));
      // reorder: items before the token
      final items = t.blocks.firstWhere((b) => b.type == BlockType.items);
      final moved = [items, ...t.blocks.where((b) => b != items)];
      t = t.copyWith(blocks: moved);
      expect(text().indexOf('Zinger'), lessThan(text().indexOf('A17')));
      // align
      t = t.copyWith(blocks: [for (final b in t.blocks) b.type == BlockType.business ? b.copyWith(align: PrintAlign.right) : b]);
      final line = text().split('\n').firstWhere((l) => l.contains('Burger Point'));
      expect(line, startsWith(' '));
      // size
      t = t.copyWith(blocks: [for (final b in t.blocks) b.type == BlockType.token ? b.copyWith(size: 1) : b]);
      final doc = buildTokenSlipDoc(t, slip());
      expect(doc.lines.whereType<RText>().firstWhere((l) => l.text == 'A17').height, 1);
    });

    test('border style changes the rule lines; "none" removes them', () {
      String rules(String border) => previewSlip(base.copyWith(border: border), slip()).split('\n').firstWhere((l) => l.length >= 30 && !l.contains(RegExp(r'[A-Za-z0-9]')), orElse: () => '');
      expect(rules('line'), startsWith('---'));
      expect(rules('double'), startsWith('==='));
      expect(rules('dots'), startsWith('...'));
      expect(rules('stars'), startsWith('***'));
      expect(rules('none'), '');
    });

    test('top and bottom margins feed paper', () {
      final doc = buildTokenSlipDoc(base.copyWith(topFeed: 3, bottomFeed: 5), slip());
      expect((doc.lines.first as RFeed).lines, 3);
      expect((doc.lines.last as RFeed).lines, 5);
      expect(buildTokenSlipDoc(base.copyWith(topFeed: 0, bottomFeed: 0), slip()).lines.first, isNot(isA<RFeed>()));
    });

    test('free text, collect line and show/hide of every data block', () {
      var t = base.copyWith(blocks: [
        const TokenBlock(BlockType.collect, text: 'Collect from window 3'),
        const TokenBlock(BlockType.orderNo, align: PrintAlign.left),
        const TokenBlock(BlockType.cashier, align: PrintAlign.left),
        const TokenBlock(BlockType.orderType),
        const TokenBlock(BlockType.totals, flags: {'discount': true}),
        const TokenBlock(BlockType.space, size: 2),
      ]);
      final s = previewSlip(t, slip());
      expect(s, allOf(contains('Collect from window 3'), contains('INV-20260112-0001'), contains('Ali'), contains('Dine-in Table T4'), contains('TOTAL PKR'), contains('Discount')));
      t = t.copyWith(blocks: [for (final b in t.blocks) b.copyWith(show: false)]);
      expect(previewSlip(t, slip()).trim(), '');
    });

    test('reprint is marked on the slip', () {
      expect(previewSlip(base, slip().reprint()), contains('REPRINT'));
      expect(previewSlip(base, slip()), isNot(contains('REPRINT')));
    });

    test('a design survives JSON, tolerates unknown blocks', () {
      final t = builtInTemplates['premium']!.copyWith(name: 'Mine', lang: 'both', border: 'dots', topFeed: 2, bottomFeed: 4);
      final back = TokenDesign.decode(t.encode(), id: 'x')!;
      expect(back.name, 'Mine');
      expect(back.lang, 'both');
      expect(back.border, 'dots');
      expect(back.topFeed, 2);
      expect(back.bottomFeed, 4);
      expect(back.blocks.map((b) => b.type), t.blocks.map((b) => b.type));
      expect(back.blocks.map((b) => b.flags), t.blocks.map((b) => b.flags));
      final odd = TokenDesign.decode('{"name":"n","border":"zzz","blocks":[{"t":"future"},{"t":"token","z":99}]}', id: 'y')!;
      expect(odd.blocks.single.type, BlockType.token);
      expect(odd.blocks.single.size, 5);
      expect(odd.border, 'line');
    });
  });

  group('Urdu and bilingual', () {
    test('Urdu item names and Urdu words go through the bitmap path; English-only slips never touch it', () async {
      final r = _Rast();
      final t = builtInTemplates['price']!.copyWith(lang: 'ur');
      final slip = sampleSlip(TokenKind.price, businessName: 'Burger Point', lang: 'ur');
      final b = await EscPosRenderer(paperMm: 58, rasterizer: r).render(buildTokenSlipDoc(t, slip));
      expect(b.toBytes(), isNotEmpty);
      expect(r.seen.any((s) => s.contains('چکن کڑاہی')), isTrue, reason: 'item name');
      expect(r.seen.any((s) => s.contains('ٹوکن') || s.contains('کل')), isTrue, reason: 'Urdu standard words');
      final en = _Rast();
      await EscPosRenderer(paperMm: 58, rasterizer: en).render(buildTokenSlipDoc(builtInTemplates['price']!, sampleSlip(TokenKind.price, businessName: 'X')));
      expect(en.seen, isEmpty);
    });

    test('bilingual shows both words on one line; Urdu-only replaces English', () {
      final slip = sampleSlip(TokenKind.price, businessName: 'X');
      final both = previewSlip(builtInTemplates['price']!.copyWith(lang: 'both'), slip);
      expect(both, allOf(contains('Date تاریخ'), contains('TOTAL کل')));
      final ur = previewSlip(builtInTemplates['price']!.copyWith(lang: 'ur'), slip);
      expect(ur, allOf(contains('تاریخ'), isNot(contains('Date'))));
    });

    test('second-language wording is added for bilingual designs only', () {
      final t = TokenDesign(id: 'x', name: 'x', blocks: const [TokenBlock(BlockType.title, text: 'TOKEN', textAlt: 'ٹوکن')]);
      final slip = sampleSlip(TokenKind.order, businessName: 'X');
      expect(previewSlip(t, slip), isNot(contains('ٹوکن')));
      expect(previewSlip(t.copyWith(lang: 'both'), slip), allOf(contains('TOKEN'), contains('ٹوکن')));
    });
  });

  group('coupon', () {
    test('code, value and QR are on the coupon design', () {
      final s = previewSlip(builtInTemplates['coupon']!, sampleSlip(TokenKind.coupon, businessName: 'X'));
      expect(s, allOf(contains('CP-7K4M9-X2QPD'), contains('PKR 500.00'), contains('[QR]'), contains('ONE use')));
    });
    test('formatCouponCode accepts what a cashier types', () {
      expect(formatCouponCode('cp7k4m9x2qpd'), 'CP-7K4M9-X2QPD');
      expect(formatCouponCode(' CP-7K4M9-X2QPD '), 'CP-7K4M9-X2QPD');
      expect(formatCouponCode('7k4m9 x2qpd'), 'CP-7K4M9-X2QPD');
    });
  });

  group('layout helpers', () {
    test('layoutCols: fixed right columns, wrapped names, 80 mm is wider', () {
      final l = layoutCols(['Chicken Karahi Special Plate', '2', '1,200.00', '2,400.00'], [4, 9, 9], 32);
      expect(l.first.length, 32);
      expect(l.first.endsWith('2,400.00'), isTrue);
      expect(l.length, greaterThan(1));
      final wide = layoutCols(['Zinger', '2', '450.00', '900.00'], [4, 8, 9], 48);
      expect(wide.single.length, 48);
    });
    test('amount in words', () {
      expect(amountInWords(457400, Currency.pkr), 'FOUR THOUSAND FIVE HUNDRED SEVENTY-FOUR ONLY');
      expect(amountInWords(612245, Currency.pkr), 'SIX THOUSAND ONE HUNDRED TWENTY-TWO AND 45/100 ONLY');
      expect(amountInWords(100000, Currency.pkr), 'ONE THOUSAND ONLY');
    });
  });

  group('bill styles (58 and 80 mm)', () {
    ReceiptData d() => ReceiptData(
          businessName: 'Burger Point',
          invoiceNo: 'INV-1',
          dateTime: '2026-01-12 19:40',
          orderTypeLabel: 'Dine-in',
          tableLabel: 'T4',
          cashier: 'Ali',
          token: 'A17',
          lines: const [
            ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000),
            ReceiptLine(name: 'Chicken Karahi Special Plate', qtyMilli: 1000, unitPriceMinor: 120000, totalMinor: 120000, modifiers: ['Extra gravy']),
          ],
          subtotalMinor: 210000,
          discountMinor: 10000,
          totalMinor: 200000,
          payments: const [ReceiptPayment('Cash', 200000)],
        );

    for (final style in billStyles) {
      for (final paper in [58, 80]) {
        test('$style on $paper mm fits and carries the essentials', () {
          final design = const BillDesign().withStyle(style);
          final doc = buildBillDoc(d(), template: design);
          expectFits(doc, paper, '$style/$paper');
          final text = docToText(doc, paper);
          expect(text, allOf(contains(style == 'bold' ? 'Burger' : 'Burger Point'), contains('INV-1'), contains('2,000.00'), contains('Zinger')));
          expect(text, contains('A17'), reason: 'order token on the bill');
        });
      }
    }

    test('boxed bill is a table with amount in words; modern numbers items and centres the total; compact is shortest', () {
      String t(String s) => previewBill(d(), template: const BillDesign().withStyle(s));
      expect(t('boxed'), allOf(contains('Item'), contains('Rate'), contains('PRE-PAYMENT BILL'), contains('TWO THOUSAND ONLY'), contains('NET BILL')));
      expect(t('modern'), allOf(contains('1 Zinger Burger x 2'), contains('- Burger Point -'), contains('- - - -')));
      expect(t('compact').split('\n').length, lessThan(t('classic').split('\n').length));
      expect(const BillDesign().withStyle('classic').style, 'classic');
    });

    test('DT Retail look: boxed TYPE/TOKEN cells, black TOTAL bar (reverse print), powered-by line', () {
      final design = const BillDesign().withStyle('dtretail');
      final text = previewBill(d(), template: design);
      expect(text, allOf(contains('TYPE'), contains('TOKEN'), contains('#A17'), contains('TOTAL'), contains('Powered by Digital Target')));
      final bytes = EscPosRenderer(paperMm: 58).renderSync(buildBillDoc(d(), template: design)).toBytes();
      final at = [for (var i = 0; i < bytes.length - 2; i++) if (bytes[i] == 0x1D && bytes[i + 1] == 0x42 && bytes[i + 2] == 1) i];
      expect(at, hasLength(1), reason: 'reverse print is switched on for the total only');
    });

    test('token on the bill can be switched off', () {
      expect(previewBill(d(), template: const BillDesign(showToken: false)), isNot(contains('A17')));
    });
  });

  group('kitchen tickets', () {
    final lines = [const KotLine('Zinger Burger', 2000, modifiers: ['No onion'], note: 'spicy'), const KotLine('Fries', 1000)];
    for (final style in kotStyles) {
      for (final paper in [58, 80]) {
        test('$style KOT on $paper mm', () {
          final doc = buildKotDoc(station: 'Grill', orderLabel: 'INV-1', orderTypeLabel: 'Dine-in', tableLabel: 'T4', dateTime: '19:40', lines: lines, waiter: 'Sara', token: 'A17', design: KotDesign.defaults.copyWith(style: style));
          expectFits(doc, paper, 'kot $style');
          final text = docToText(doc, paper);
          expect(text, allOf(contains(style == 'big' ? 'Zinger' : '2 x Zinger Burger'), contains('No onion'), contains('spicy'), contains('A17'), contains('Items: 3')));
        });
      }
    }
    test('KOT options: hide token/table/waiter/notes, change heading, reprint marker', () {
      final doc = buildKotDoc(
          station: 'Grill', orderLabel: 'INV-1', orderTypeLabel: 'Dine-in', tableLabel: 'T4', dateTime: '19:40', lines: lines, waiter: 'Sara', token: 'A17', isReprint: true,
          design: const KotDesign(showToken: false, showTable: false, showWaiter: false, showNotes: false, title: 'KITCHEN'));
      final text = docToText(doc, 58);
      expect(text, allOf(contains('KITCHEN'), contains('REPRINT'), isNot(contains('A17')), isNot(contains('T4')), isNot(contains('Sara')), isNot(contains('spicy'))));
      expect(KotDesign.decode(const KotDesign(style: 'big', copies: 2).encode()).copies, 2);
    });
  });
}
