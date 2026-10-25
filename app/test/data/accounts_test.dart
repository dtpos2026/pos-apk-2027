import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/expense_service.dart';
import 'package:dt_food_pos/data/inventory_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/recipe_service.dart';
import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/data/shift_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DbHelper h;
  late InventoryService inv;
  late ExpenseService exp;
  late ReportService rep;
  late String flour, supplier;
  final clock = DateTime(2026, 1, 12, 10);
  Future<int> n(String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    h = DbHelper(db, now: () => clock);
    inv = InventoryService(h);
    exp = ExpenseService(h);
    rep = ReportService(h);
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await db.customStatement("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1), ('bank','Meezan Bank','bank',1), ('cr','Udhaar','credit',1)");
    flour = await inv.saveItem(name: 'Flour', unit: 'kg', staffId: 's1');
    supplier = await inv.saveSupplier(name: 'Ahmed Traders');
    await ShiftService(db, PosService(db, now: () => clock), now: () => clock).openShift('s1', openingCashMinor: 100000);
  });
  tearDown(() => db.close());

  test('purchases and supplier payments record the account they were paid from; cash also leaves the drawer', () async {
    final line = [PurchaseInput(stockItemId: flour, qtyMilli: 10000, unitCostMinor: 20000)]; // 200,000 total
    await inv.purchase(supplierId: supplier, lines: line, paidMinor: 50000, methodId: 'bank', staffId: 's1');
    expect(await n("SELECT COUNT(*) AS n FROM cash_movement"), 0, reason: 'bank money does not touch the drawer');
    await inv.paySupplier(supplierId: supplier, amountMinor: 30000, methodId: 'cash', staffId: 's1');
    expect(await n("SELECT COALESCE(SUM(amount_minor),0) AS n FROM cash_movement WHERE direction = 'out'"), 30000);
    await inv.purchase(lines: line, paidMinor: 200000, staffId: 's1'); // no account named: cash, no supplier
    expect(await n("SELECT COALESCE(SUM(amount_minor),0) AS n FROM cash_movement WHERE direction = 'out'"), 230000);
    await expectLater(inv.paySupplier(supplierId: supplier, amountMinor: 1000, methodId: 'cr', staffId: 's1'), throwsA(isA<PosException>()), reason: 'credit is not money leaving');
    await expectLater(inv.paySupplier(supplierId: supplier, amountMinor: 1000, methodId: 'nope', staffId: 's1'), throwsA(isA<PosException>()));

    final out = await rep.moneyOut('2026-01-01', '2026-12-31');
    expect(out.map((o) => '${o.kind}:${o.method}:${o.amountMinor}').toSet(), {'supplier:Meezan Bank:50000', 'supplier:Cash:30000', 'purchase:Cash:200000'});
  });

  test('an expense can be deleted: it leaves the reports, cash goes back in the drawer, the audit trail keeps it', () async {
    final a = await exp.add(amountMinor: 5000, category: 'Gas', methodId: 'cash', staffId: 's1');
    final b = await exp.add(amountMinor: 7000, category: 'Rent', methodId: 'bank', staffId: 's1');
    expect(await n("SELECT COALESCE(SUM(amount_minor),0) AS n FROM cash_movement WHERE direction = 'out'"), 5000);
    expect(await exp.delete(a, staffId: 's1'), isTrue);
    expect(await exp.delete(a, staffId: 's1'), isFalse, reason: 'already gone');
    expect(await n("SELECT COALESCE(SUM(amount_minor),0) AS n FROM cash_movement WHERE direction = 'in'"), 5000);
    expect(await exp.delete(b, staffId: 's1'), isTrue);
    expect(await n('SELECT COUNT(*) AS n FROM expense'), 0);
    expect(await n("SELECT COUNT(*) AS n FROM audit_log WHERE event = 'expense.delete' AND critical = 1"), 2);
  });

  test('the accounts report shows, per account, what came in, was paid back and was paid out', () async {
    await db.customStatement("INSERT INTO \"order\"(id, order_type, status, business_date, created_at, updated_at, total_minor) VALUES ('o1','counter','paid','2026-01-12',1,1,100000)");
    await db.customStatement("INSERT INTO payment(id, order_id, method_id, method_kind, amount_minor, created_at) VALUES ('p1','o1','cash','cash',60000,1), ('p2','o1','bank','bank',40000,1)");
    await exp.add(amountMinor: 5000, category: 'Gas', methodId: 'cash', staffId: 's1');
    await inv.purchase(supplierId: supplier, lines: [PurchaseInput(stockItemId: flour, qtyMilli: 1000, unitCostMinor: 20000)], paidMinor: 20000, methodId: 'bank', staffId: 's1');
    final acc = {for (final a in await rep.accounts('2026-01-12', '2026-01-12')) a.name: a};
    expect([acc['Cash']!.inMinor, acc['Cash']!.outMinor, acc['Cash']!.netMinor], [60000, 5000, 55000]);
    expect([acc['Meezan Bank']!.inMinor, acc['Meezan Bank']!.outMinor, acc['Meezan Bank']!.netMinor], [40000, 20000, 20000]);
  });

  test('upgrading to schema 8 adds the account columns once', () async {
    await migrateToV8(db);
    await migrateToV8(db);
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM pragma_table_info('purchase') WHERE name = 'method_id'").getSingle()).data['n'], 1);
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM pragma_table_info('supplier_ledger') WHERE name = 'method_id'").getSingle()).data['n'], 1);
  });

  test('recipes: one row per size, the cost follows the ingredients, a size recipe replaces the base one when selling', () async {
    await db.customStatement("INSERT INTO category(id,name,updated_at) VALUES ('c','Pizza',1)");
    await db.customStatement("INSERT INTO product(id,name,category_id,base_price_minor,updated_at) VALUES ('pz','Pizza','c',80000,1), ('dr','Cola',NULL,10000,1)");
    await db.customStatement("INSERT INTO product_variant(id,product_id,name,price_minor,updated_at) VALUES ('sm','pz','Small',60000,1), ('lg','pz','Large',110000,1)");
    final recipes = RecipeService(h);
    var rows = await recipes.rows();
    expect(rows.map((r) => r.label), ['Cola', 'Pizza · Small', 'Pizza · Large']);
    expect(rows.every((r) => !r.hasRecipe), isTrue);

    await inv.purchase(supplierId: supplier, lines: [PurchaseInput(stockItemId: flour, qtyMilli: 10000, unitCostMinor: 20000)], paidMinor: 200000, staffId: 's1'); // flour 200/kg
    await inv.saveRecipe(productId: 'pz', variantId: 'sm', ingredientsMilli: {flour: 200}); // 0.2 kg
    await inv.saveRecipe(productId: 'pz', variantId: 'lg', ingredientsMilli: {flour: 400});
    rows = await recipes.rows(search: 'pizza');
    final small = rows.firstWhere((r) => r.variantName == 'Small'), large = rows.firstWhere((r) => r.variantName == 'Large');
    expect([small.ingredients, small.costMinor, large.costMinor], [1, 4000, 8000]);
    expect(small.marginPct, ((60000 - 4000) * 100 / 60000).round());
    expect((await recipes.ingredients('pz', 'lg')).single.name, 'Flour');

    // selling a large pizza takes the large recipe only (not base + large)
    await inv.saveRecipe(productId: 'pz', ingredientsMilli: {flour: 100});
    final pos = PosService(db, now: () => clock);
    final id = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: 'pz', variantId: 'lg', name: 'Pizza Large', qtyMilli: 2000, unitPriceMinor: 110000)]), staffId: 's1');
    final before = await inv.onHand(flour);
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 220000)], staffId: 's1');
    expect(before - await inv.onHand(flour), 800, reason: '2 large pizzas x 0.4 kg');
    // a size without its own recipe falls back to the base recipe
    final id2 = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: 'pz', name: 'Pizza', qtyMilli: 1000, unitPriceMinor: 80000)]), staffId: 's1');
    final b2 = await inv.onHand(flour);
    await pos.settleOrder(orderId: id2, payments: [const SettlePayment(methodId: 'cash', amountMinor: 80000)], staffId: 's1');
    expect(b2 - await inv.onHand(flour), 100);
    expect(Variable.withString('x').value, 'x');
  });

  test('recipe units: kg can be written in grams, litres in millilitres', () {
    expect(recipeUnits('kg').map((u) => u.unit), ['kg', 'g']);
    expect(recipeUnits('l').last.perStockUnit, 1000);
    expect(recipeUnits('pc').map((u) => u.unit), ['pc']);
  });
}
