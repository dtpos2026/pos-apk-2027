import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/deal_import.dart';
import 'package:dt_food_pos/data/deal_service.dart';
import 'package:dt_food_pos/data/menu_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DealService deals;
  late DealImporter imp;
  Future<void> sql(String s) => db.customStatement(s);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deals = DealService(db, MenuService(db));
    imp = DealImporter(db, deals);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO category(id,name,updated_at) VALUES ('c1','Burgers',1), ('c2','Pizza',1), ('c3','Drinks',1)");
    await sql("INSERT INTO product(id,category_id,name,sku,base_price_minor,updated_at) VALUES ('b','c1','Zinger Burger','BRG-1',45000,1), ('p','c2','Chicken Pizza','PZ-1',90000,1), ('d','c3','Cola 500ml','DRK-1',10000,1)");
    await sql("INSERT INTO product_variant(id,product_id,name,price_minor,updated_at) VALUES ('pl','p','Large',120000,1), ('pm','p','Medium',90000,1)");
  });
  tearDown(() => db.close());

  test('the template imports as two deals', () async {
    // the template's last drink is not on this menu: that deal is refused, the other still imports
    final r = await imp.import(dealCsvTemplate(), staffId: 's1');
    expect(r.committed, isTrue);
    expect(r.created, 1, reason: 'Student Deal');
    expect(r.invalid, 1, reason: 'Family Deal has "1.5 Liter Drink" which is not on the menu');
    expect(r.allIssues.map((i) => i.toString()).join('\n'), contains('1.5 Liter Drink'));
    final all = await deals.deals();
    expect(all.map((d) => d.name), ['Student Deal']);
    expect(all.single.priceMinor, 79900);
  });

  test('rows group by deal name, blank name continues the deal, sizes and codes work, quantities of the same item add up', () async {
    const csv = 'Deal Name,Deal Price,Item Name,Quantity,Variant,Category,Item Code,Active\n'
        'Family,"Rs 2,499",Zinger Burger,2,,,,Yes\n'
        ',,,1,Large,,PZ-1,\n'
        ',,Cola 500ml,1,,Drinks,,\n'
        ',,Zinger Burger,1,,,,\n';
    final r = await imp.import(csv, staffId: 's1');
    expect(r.created, 1, reason: r.allIssues.join('; '));
    final d = (await deals.deals()).single;
    expect(d.priceMinor, 249900);
    expect(d.items.map((i) => '${i.label}:${i.qtyMilli}'), ['Zinger Burger:3000', 'Chicken Pizza (Large):1000', 'Cola 500ml:1000']);
  });

  test('every mistake is explained and a deal with a mistake is not imported at all', () async {
    const csv = 'Deal Name,Deal Price,Item Name,Quantity,Variant\n'
        'A,100,Chicken Pizza,1,\n' // size missing
        'B,100,Zinger Burger,1,Large\n' // size on an item without sizes
        'C,100,Chicken Pizza,1,Giant\n' // unknown size
        'D,100,Zinger Burger,0,\n' // bad qty
        'E,100,Zinger Burger,1,\n' // fine
        'F,100,Zinger Burger,1,\n'
        'F,200,Cola 500ml,1,\n' // price differs
        'G,abc,Zinger Burger,1,\n'; // bad price
    final r = await imp.import(csv, dryRun: true, staffId: 's1');
    expect(r.committed, isFalse);
    expect({for (final d in r.deals) d.name: d.status}, {
      'A': DealStatus.invalid, 'B': DealStatus.invalid, 'C': DealStatus.invalid, 'D': DealStatus.invalid,
      'E': DealStatus.create, 'F': DealStatus.invalid, 'G': DealStatus.invalid,
    });
    final text = r.allIssues.join('\n');
    expect(text, contains('has sizes (Large, Medium)'));
    expect(text, contains('has no sizes'));
    expect(text, contains('has no size "Giant"'));
    expect(text, contains('quantity'));
    expect(text, contains('differs between rows'));
    expect(text, contains('not a valid price'));
    expect(await deals.deals(), isEmpty, reason: 'a dry run writes nothing');
    final real = await imp.import(csv, staffId: 's1');
    expect((await deals.deals()).map((d) => d.name), ['E']);
    expect(real.created, 1);
  });

  test('an existing deal is skipped unless Update is chosen', () async {
    const csv = 'Deal Name,Deal Price,Item Name,Quantity\nStudent,500,Zinger Burger,1\n';
    await imp.import(csv, staffId: 's1');
    const changed = 'Deal Name,Deal Price,Item Name,Quantity\nstudent,400,Cola 500ml,2\n';
    var r = await imp.import(changed, staffId: 's1');
    expect(r.skipped, 1);
    expect((await deals.deals()).single.priceMinor, 50000);
    r = await imp.import(changed, update: true, staffId: 's1');
    expect(r.updated, 1);
    final d = (await deals.deals()).single;
    expect(d.priceMinor, 40000);
    expect(d.items.single.label, 'Cola 500ml');
  });

  test('a file without the needed columns is explained', () async {
    final r = await imp.import('Name,Cost\nA,1\n', staffId: 's1');
    expect(r.fileIssues.single.message, contains('Missing column'));
    expect((await imp.import('', staffId: 's1')).fileIssues.single.message, contains('empty'));
  });
}
