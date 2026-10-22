import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/menu_import.dart';
import 'package:dt_food_pos/domain/csv.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late MenuImporter imp;
Future<int> count(String t) async => (await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle()).data['n'] as int;

void main() {
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    var n = 0;
    imp = MenuImporter(db, newId: () => 'id-${++n}', now: () => DateTime(2026, 1, 12));
  });
  tearDown(() => db.close());

  group('parseCsv', () {
    test('quotes, commas, escaped quotes, newlines in fields, CRLF, BOM, blank lines', () {
      final rows = parseCsv('﻿a,b\r\n"x, y","say ""hi"""\n\n"multi\nline",z\n');
      expect(rows, [
        ['a', 'b'],
        ['x, y', 'say "hi"'],
        ['multi\nline', 'z'],
      ]);
    });
    test('empty fields are kept', () {
      expect(parseCsv('a,,c\n,,\n'), [
        ['a', '', 'c'],
        ['', '', ''],
      ]);
    });
    test('unterminated quote is an error', () {
      expect(() => parseCsv('a,"b'), throwsFormatException);
    });
    test('urdu text survives', () {
      expect(parseCsv('چکن برگر,450')[0][0], 'چکن برگر');
    });
  });

  test('the downloadable template imports cleanly', () async {
    final r = await imp.import(menuCsvTemplate(), dryRun: false);
    expect(r.ok, isTrue);
    expect(r.committed, isTrue);
    expect(r.creates, 2);
    expect(await count('product'), 2);
    expect(await count('category'), 2);
    expect(await count('tax_rate'), 1); // both rows use 16%
    final p = (await db.customSelect("SELECT * FROM product WHERE sku='BRG-001'").getSingle()).data;
    expect(p['base_price_minor'], 45000);
    expect(p['track_stock'], 0);
  });

  test('dry run reports but writes nothing', () async {
    final r = await imp.import(menuCsvTemplate());
    expect(r.committed, isFalse);
    expect(r.creates, 2);
    expect(await count('product'), 0);
  });

  test('row-level errors with line numbers; nothing is written (no partial import)', () async {
    const csv = 'category,name,price,sku,unit,tax_percent,available\n'
        'A,Good,100,S1,pc,16,yes\n'
        'A,,100,S2,pc,16,yes\n'
        'A,BadPrice,12x,S3,pc,16,yes\n'
        'A,BadUnit,100,S4,box,16,yes\n'
        'A,BadTax,100,S5,pc,150,yes\n'
        'A,BadFlag,100,S6,pc,16,maybe\n'
        'A,Dup,100,S1,pc,16,yes\n';
    final r = await imp.import(csv, dryRun: false);
    expect(r.committed, isFalse);
    expect(r.issues.map((i) => '${i.row}:${i.field}'), ['3:name', '4:price', '5:unit', '6:tax_percent', '7:available', '8:sku']);
    expect(await count('product'), 0);
    expect(await count('category'), 0);
  });

  test('existing SKU updates the product; new SKU creates; outbox gets one row per product', () async {
    await imp.import('name,price,sku\nTea,100,T1\n', dryRun: false);
    final r = await imp.import('name,price,sku\nTea Deluxe,150,T1\nCoffee,200,C1\n', dryRun: false);
    expect(r.updates, 1);
    expect(r.creates, 1);
    expect(await count('product'), 2);
    expect((await db.customSelect("SELECT name, base_price_minor, version FROM product WHERE sku='T1'").getSingle()).data, {'name': 'Tea Deluxe', 'base_price_minor': 15000, 'version': 2});
    expect(await count('outbox'), 3);
  });

  test('missing required columns and empty files are reported', () async {
    expect((await imp.import('foo,bar\n1,2\n')).issues.map((i) => i.field), ['name', 'price']);
    expect((await imp.import('')).ok, isFalse);
    expect((await imp.import('name,price\n"broken')).ok, isFalse);
  });

  test('weight items and urdu names import', () async {
    final r = await imp.import('name,price,unit\nچکن (کلو),1800,kg\n', dryRun: false);
    expect(r.ok, isTrue);
    expect((await db.customSelect('SELECT name, unit FROM product').getSingle()).data, {'name': 'چکن (کلو)', 'unit': 'kg'});
  });
}
