import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/inventory_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final clock = DateTime(2026, 1, 12, 12);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('t','Chai',15000,1)");
  });
  tearDown(() => db.close());

  test('profit per item = revenue - recipe cost at average stock cost; items without a recipe show no cost', () async {
    final h = DbHelper(db, now: () => clock);
    final inv = InventoryService(h);
    // 1 kg chicken at 400 per kg; a burger uses 200 g
    final chicken = await inv.saveItem(name: 'Chicken', unit: 'kg', openingMilli: 10000, openingCostMinor: 40000, staffId: 's1');
    await inv.saveRecipe(productId: 'b', ingredientsMilli: {chicken: 200});
    final pos = PosService(db, now: () => clock);
    final id = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [
      CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 3000, unitPriceMinor: 45000),
      CartItem(productId: 't', name: 'Chai', qtyMilli: 1000, unitPriceMinor: 15000),
    ]), staffId: 's1');
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 150000)], staffId: 's1');

    final lines = await ReportService(h).profitWise('2026-01-12', '2026-01-12');
    final burger = lines.firstWhere((l) => l.label == 'Zinger Burger');
    expect(burger.revenueMinor, 135000);
    expect(burger.costMinor, 24000, reason: '3 burgers x 200 g x 400/kg');
    expect(burger.profitMinor, 111000);
    expect(burger.marginPct, 82);
    final chai = lines.firstWhere((l) => l.label == 'Chai');
    expect(chai.costMinor, isNull);
    expect(chai.profitMinor, isNull);
  });
}
