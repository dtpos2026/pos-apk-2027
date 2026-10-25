import 'package:drift/drift.dart' show Variable;
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

  test('sending to the kitchen (even with no kitchen printer) puts the order on the board; one tap moves it along to Completed', () async {
    expect(await kitchen.tickets(), isEmpty);
    final id = await draft(2000);
    await printSvc.queueKot(id, onlyNew: true);
    var t = (await kitchen.tickets()).single;
    expect(t.status, 'new');
    expect(t.lines.single.name, 'Zinger Burger');
    await kitchen.advance(id);
    expect((await kitchen.tickets(status: 'preparing')).single.orderId, id);
    await kitchen.advance(id);
    expect((await kitchen.tickets(status: 'ready')).single.orderId, id);
    await kitchen.advance(id);
    expect(await kitchen.tickets(status: 'ready'), isEmpty);
    expect((await kitchen.tickets(status: 'served')).single.orderId, id, reason: 'completed orders stay on the Completed list');
    await expectLater(kitchen.advance(id), throwsA(isA<PosException>()), reason: 'nothing after completed');
    expect(await kitchen.counts(), {'new': 0, 'preparing': 0, 'ready': 0, 'served': 1});
  });

  test('paying the bill finishes its kitchen ticket by itself (Completed); the history stays and the bill stays paid', () async {
    final id = await draft(1000);
    await printSvc.sendToKitchen(id);
    expect(await kitchen.tickets(), hasLength(1));
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 45000)], staffId: 's1');
    expect(await kitchen.tickets(), isEmpty, reason: 'no longer waiting in the kitchen');
    final done = (await kitchen.tickets(status: 'served')).single;
    expect(done.paid, isTrue);
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM kitchen_event WHERE order_id = ?", variables: [Variable.withString(id)]).getSingle()).data['n'], 2, reason: 'new, then completed');
    expect((await db.customSelect('SELECT status FROM "order" WHERE id = ?', variables: [Variable.withString(id)]).getSingle()).data['status'], 'paid', reason: 'the bill stays paid');
    await expectLater(kitchen.advance(id), throwsA(isA<PosException>()), reason: 'already completed');
  });

  test('an order that was never sent is not on the board; sending twice makes one ticket', () async {
    final id = await draft(1000);
    expect(await kitchen.tickets(), isEmpty);
    expect((await printSvc.sendToKitchen(id)).sent, isTrue);
    expect((await printSvc.sendToKitchen(id)).sent, isFalse, reason: 'a double tap or a retry sends nothing new');
    expect(await kitchen.tickets(), hasLength(1));
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM kitchen_event').getSingle()).data['n'], 1);
  });

  test('cancelling: an order never sent is removed; one sent to the kitchen is kept as cancelled and never counts as a sale', () async {
    final unsent = await draft(1000);
    await pos.cancelOrder(unsent, staffId: 's1');
    expect(await db.customSelect('SELECT COUNT(*) AS n FROM "order"').getSingle().then((r) => r.data['n']), 0);

    final sent = await draft(2000);
    await printSvc.sendToKitchen(sent);
    await expectLater(pos.discardDraft(sent), throwsA(isA<PosException>()), reason: 'the kitchen has it: it can only be cancelled, never deleted');
    await pos.cancelOrder(sent, staffId: 's1', reason: 'customer left');
    final row = (await db.customSelect('SELECT status FROM "order" WHERE id = ?', variables: [Variable.withString(sent)]).getSingle()).data;
    expect(row['status'], 'cancelled');
    expect(await kitchen.tickets(), isEmpty, reason: 'off the kitchen board');
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM order_item WHERE order_id = ? AND kot_sent_at IS NOT NULL", variables: [Variable.withString(sent)]).getSingle()).data['n'], 1, reason: 'kitchen history is kept');
    final report = await pos.salesReport('2026-01-12');
    expect(report.bills, 0, reason: 'a cancelled order is not a sale');
    await expectLater(pos.cancelOrder(sent, staffId: 's1'), throwsA(isA<PosException>()), reason: 'already cancelled');
  });

  test('the upgrade rebuilds the order table so older databases accept the cancelled status without losing orders', () async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    final id = await draft(1000);
    final ddl = (await db.customSelect("SELECT sql FROM sqlite_master WHERE name = 'order'").getSingle()).data['sql'] as String;
    // pretend this is a database from before: the old CHECK has no 'cancelled'
    await db.customStatement('ALTER TABLE "order" RENAME TO order_keep');
    await db.customStatement(ddl.replaceFirst(RegExp(r",\s*'cancelled'"), ''));
    await db.customStatement('INSERT INTO "order" SELECT * FROM order_keep');
    await db.customStatement('DROP TABLE order_keep');
    await expectLater(db.customStatement("UPDATE \"order\" SET status = 'cancelled'"), throwsA(anything));

    await migrateToV3(db);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM "order" WHERE id = ?', variables: [Variable.withString(id)]).getSingle()).data['n'], 1, reason: 'the order survived the rebuild');
    await db.customStatement("UPDATE \"order\" SET status = 'cancelled'");
    expect((await db.customSelect("SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'cancelled'").getSingle()).data['n'], 1);
  });
}
