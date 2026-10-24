import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/kitchen_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PosService pos;
  late PrintService printSvc;
  late KitchenService kitchen;
  final clock = DateTime(2026, 1, 12, 19, 40);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pos = PosService(db, now: () => clock);
    printSvc = PrintService(db, now: () => clock);
    kitchen = KitchenService(DbHelper(db, now: () => clock));
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
  });
  tearDown(() => db.close());

  Future<String> draft(int qty) => pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: qty, unitPriceMinor: 45000)]), staffId: 's1');

  test('sending to the kitchen (even with no kitchen printer) puts the order on the board; one tap moves it along', () async {
    expect(await kitchen.tickets(), isEmpty);
    final id = await draft(2000);
    await printSvc.queueKot(id, onlyNew: true);
    var t = (await kitchen.tickets()).single;
    expect(t.status, 'new');
    expect(t.lines.single.name, 'Zinger Burger');
    await kitchen.advance(id);
    expect((await kitchen.tickets()).single.status, 'preparing');
    await kitchen.advance(id);
    expect((await kitchen.tickets()).single.status, 'ready');
    await kitchen.advance(id);
    expect(await kitchen.tickets(), isEmpty, reason: 'served leaves the board');
  });

  test('an order that was never sent is not on the board; paid orders leave it', () async {
    final id = await draft(1000);
    expect(await kitchen.tickets(), isEmpty);
    await printSvc.queueKot(id, onlyNew: true);
    expect(await kitchen.tickets(), hasLength(1));
    await pos.settleOrder(orderId: id, payments: [SettlePayment(methodId: 'cash', amountMinor: 45000)], staffId: 's1');
    expect(await kitchen.tickets(), isEmpty);
  });
}
