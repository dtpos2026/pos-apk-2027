import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/deal_service.dart';
import 'package:dt_food_pos/data/menu_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/data/receipt_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DealService deals;
  late PosService pos;
  final clock = DateTime(2026, 1, 12, 19, 40);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
  Future<int> n(String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deals = DealService(db, MenuService(db, now: () => clock));
    pos = PosService(db, now: () => clock);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1), ('p','Chicken Pizza',90000,1), ('c','Cola',10000,1)");
    await sql("INSERT INTO product_variant(id,product_id,name,price_minor,updated_at) VALUES ('pl','p','Large',120000,1), ('pm','p','Medium',90000,1)");
    await sql("INSERT INTO stock_item(id,name,unit,updated_at) VALUES ('bun','Bun','pc',1), ('dough','Dough','pc',1)");
    await sql("INSERT INTO recipe_line(product_id,variant_id,stock_item_id,qty_milli) VALUES ('b',NULL,'bun',1000), ('p','pl','dough',2000)");
  });
  tearDown(() => db.close());

  const family = [DealPick(productId: 'b', qtyMilli: 2000), DealPick(productId: 'p', variantId: 'pl'), DealPick(productId: 'c')];

  test('a deal is saved as a menu item in the Deals category with its contents and the saving', () async {
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    final d = (await deals.get(id))!;
    expect(d.name, 'Family Deal');
    expect(d.items.map((i) => i.label), ['Zinger Burger', 'Chicken Pizza (Large)', 'Cola']);
    expect(d.regularMinor, 2 * 45000 + 120000 + 10000);
    expect(d.savingMinor, 220000 - 200000);
    final row = (await db.customSelect("SELECT p.kind AS k, c.name AS cat FROM product p JOIN category c ON c.id = p.category_id WHERE p.id = ?", variables: [Variable.withString(id)]).getSingle()).data;
    expect(row, {'k': 'combo', 'cat': 'Deals'});
  });

  test('editing replaces the contents; hiding a deal hides it from the menu list of active deals; deleting removes it', () async {
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    await deals.save(id: id, name: 'Family Deal', priceMinor: 180000, active: false, items: const [DealPick(productId: 'b')], staffId: 's1');
    expect((await deals.get(id))!.items, hasLength(1));
    expect((await deals.get(id))!.priceMinor, 180000);
    expect(await deals.deals(activeOnly: true), isEmpty);
    await deals.delete(id, staffId: 's1');
    expect(await deals.deals(), isEmpty);
  });

  test('bad deals are refused in plain words: no items, no price, a sized item without its size, a deal inside a deal, a duplicate name', () async {
    Future<String?> why(List<DealPick> items, {int price = 1000, String name = 'X'}) async {
      try {
        await deals.save(name: name, priceMinor: price, items: items, staffId: 's1');
        return null;
      } on MenuException catch (e) {
        return e.message;
      }
    }

    expect(await why(const []), contains('at least one item'));
    expect(await why(family, price: 0), contains('more than zero'));
    expect(await why(const [DealPick(productId: 'p')]), contains('has sizes'));
    expect(await why(const [DealPick(productId: 'b', variantId: 'pl')]), contains('does not belong'));
    expect(await why(const [DealPick(productId: 'nope')]), contains('no longer on the menu'));
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    expect(await why([DealPick(productId: id)]), contains('deal itself'));
    expect(await why(family, name: 'family deal'), contains('already exists'));
    expect(await n("SELECT COUNT(*) AS n FROM product WHERE kind = 'combo'"), 1, reason: 'nothing half-saved');
  });

  test('selling a deal bills the deal price and takes stock from the items inside it', () async {
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    final order = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: id, name: 'Family Deal', qtyMilli: 2000, unitPriceMinor: 200000)]), staffId: 's1');
    final done = await pos.settleOrder(orderId: order, payments: [const SettlePayment(methodId: 'cash', amountMinor: 400000)], staffId: 's1');
    expect(done.totalMinor, 400000);
    // 2 deals x 2 burgers = 4 buns; 2 deals x 1 large pizza x 2 dough = 4 dough
    expect(await n("SELECT -COALESCE(SUM(delta_milli),0) AS n FROM stock_movement WHERE stock_item_id = 'bun'"), 4000);
    expect(await n("SELECT -COALESCE(SUM(delta_milli),0) AS n FROM stock_movement WHERE stock_item_id = 'dough'"), 4000);
  });

  test('the customer bill of a deal lists what is inside it under the deal name', () async {
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    final order = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: id, name: 'Family Deal', qtyMilli: 2000, unitPriceMinor: 200000)]), staffId: 's1');
    await pos.settleOrder(orderId: order, payments: [const SettlePayment(methodId: 'cash', amountMinor: 400000)], staffId: 's1');
    final r = await loadReceipt(db, order);
    expect(r.lines.single.name, 'Family Deal');
    expect(r.lines.single.modifiers, ['4 x Zinger Burger', '2 x Chicken Pizza (Large)', '2 x Cola']);
  });

  test('the kitchen ticket of a deal lists what is inside it (totals for the quantity sold)', () async {
    await sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('k','K','lan','x',58,'kot',1)");
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    final order = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: id, name: 'Family Deal', qtyMilli: 2000, unitPriceMinor: 200000)]), staffId: 's1');
    final ids = await PrintService(db, now: () => clock).queueKot(order);
    expect(ids, hasLength(1));
    final bytes = (await db.customSelect('SELECT payload FROM print_job').get()).first.data['payload'];
    final text = String.fromCharCodes((bytes as List<int>).where((b) => b >= 32 && b < 127));
    expect(text, contains('4 x Zinger Burger'));
    expect(text, contains('2 x Chicken Pizza (Large)'));
    expect(text, contains('2 x Cola'));
  });

  test('an older database (no deal table) is upgraded safely, twice is harmless, and existing menu data is kept', () async {
    await sql('DROP TABLE deal_item');
    await migrateToV4(db);
    await migrateToV4(db);
    final id = await deals.save(name: 'Family Deal', priceMinor: 200000, items: family, staffId: 's1');
    expect((await deals.get(id))!.items, hasLength(3));
    expect(await n("SELECT COUNT(*) AS n FROM product WHERE kind = 'item'"), 3);
  });
}
