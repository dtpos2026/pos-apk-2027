import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/bill_ops.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PosService pos;
  late PrintService printSvc;
  late BillOps ops;
  final clock = DateTime(2026, 1, 12, 19, 40);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
  Future<int> n(String q, [List<Object?> a = const []]) async => (await db.customSelect(q, variables: [for (final x in a) Variable(x)]).getSingle()).data['n'] as int;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pos = PosService(db, now: () => clock);
    printSvc = PrintService(db, now: () => clock);
    ops = BillOps(DbHelper(db, now: () => clock), pos);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1), ('f','Fries',15000,1)");
    await sql("INSERT INTO area(id,name,updated_at) VALUES ('a','Hall',1)");
    await sql("INSERT INTO dining_table(id,area_id,label,seats,status,updated_at) VALUES ('t1','a','T1',4,'free',1), ('t2','a','T2',4,'free',1), ('t3','a','T3',4,'free',1)");
  });
  tearDown(() => db.close());

  CartItem burger(int qty, {int kot = 0, int disc = 0}) => CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: qty, unitPriceMinor: 45000, kotSentMilli: kot, lineDiscountMinor: disc);
  CartItem fries(int qty) => CartItem(productId: 'f', name: 'Fries', qtyMilli: qty, unitPriceMinor: 15000);
  Future<String> bill(String table, List<CartItem> items) => pos.saveDraft(DraftOrder(orderType: 'dine_in', tableId: table, items: items), staffId: 's1');
  Future<int> total(String id) => n('SELECT total_minor AS n FROM "order" WHERE id = ?', [id]);

  test('merge: both bills become one, equal lines are added, totals are right, the table of the old bill is freed', () async {
    final a = await bill('t1', [burger(1000), fries(1000)]);
    final b = await bill('t2', [burger(2000)]);
    await ops.merge(fromOrderId: b, intoOrderId: a, staffId: 's1');
    final d = (await pos.loadDraft(a))!;
    expect(d.items.map((i) => '${i.name}:${i.qtyMilli}').toList(), ['Zinger Burger:3000', 'Fries:1000']);
    expect(await total(a), 3 * 45000 + 15000);
    expect(await n('SELECT COUNT(*) AS n FROM "order" WHERE id = ?', [b]), 0, reason: 'the kitchen never saw it: nothing is kept');
    expect((await db.customSelect("SELECT status FROM dining_table WHERE id = 't2'").getSingle()).data['status'], 'free');
    expect((await db.customSelect("SELECT status FROM dining_table WHERE id = 't1'").getSingle()).data['status'], 'occupied');
  });

  test('merge keeps the kitchen history: a bill the kitchen saw is kept as cancelled (never a sale) and its items are not re-sent', () async {
    final a = await bill('t1', [fries(1000)]);
    final b = await bill('t2', [burger(1000)]);
    await printSvc.sendToKitchen(b);
    await ops.merge(fromOrderId: b, intoOrderId: a, staffId: 's1');
    expect((await db.customSelect('SELECT status, total_minor FROM "order" WHERE id = ?', variables: [Variable.withString(b)]).getSingle()).data, {'status': 'cancelled', 'total_minor': 0});
    final d = (await pos.loadDraft(a))!;
    expect(d.items.firstWhere((i) => i.name == 'Zinger Burger').kotSentMilli, 1000, reason: 'already with the kitchen: the next KOT prints only what is new');
    expect(await n("SELECT COUNT(*) AS n FROM kitchen_event WHERE order_id = ?", [b]), greaterThan(0));
    // the merged bill can be paid; the cancelled one is never counted
    await pos.settleOrder(orderId: a, payments: [const SettlePayment(methodId: 'cash', amountMinor: 60000)], staffId: 's1');
    expect(await n("SELECT COALESCE(SUM(total_minor),0) AS n FROM \"order\" WHERE status = 'paid'"), 60000);
  });

  test('split: part of a line goes to a new bill on another table; both bills add up to the original', () async {
    final a = await bill('t1', [burger(3000, disc: 3000), fries(1000)]);
    final before = await total(a);
    final c = await ops.move(fromOrderId: a, picks: const [MovePick(0, 1000)], toTableId: 't3', staffId: 's1');
    final left = (await pos.loadDraft(a))!;
    final moved = (await pos.loadDraft(c))!;
    expect(left.items.first.qtyMilli, 2000);
    expect(moved.items.single.qtyMilli, 1000);
    expect(left.items.first.lineDiscountMinor + moved.items.single.lineDiscountMinor, 3000, reason: 'the discount follows the quantity and nothing is lost');
    expect(await total(a) + await total(c), before);
    expect((await db.customSelect("SELECT status FROM dining_table WHERE id = 't3'").getSingle()).data['status'], 'occupied');
  });

  test('split keeps the kitchen count: 3 burgers, 2 already sent, move 1 -> the moved one is the unsent one', () async {
    final a = await bill('t1', [burger(3000, kot: 2000)]);
    final c = await ops.move(fromOrderId: a, picks: const [MovePick(0, 1000)], toTableId: 't2', staffId: 's1');
    expect((await pos.loadDraft(a))!.items.single.kotSentMilli, 2000);
    expect((await pos.loadDraft(c))!.items.single.kotSentMilli, 0);
  });

  test('moving everything to another existing bill retires the first one; moving into a paid or missing bill is refused', () async {
    final a = await bill('t1', [fries(2000)]);
    final b = await bill('t2', [fries(1000), burger(1000)]);
    await ops.move(fromOrderId: a, picks: const [MovePick(0, 2000)], toOrderId: b, staffId: 's1');
    expect((await pos.loadDraft(b))!.items.firstWhere((i) => i.name == 'Fries').qtyMilli, 3000);
    expect(await n('SELECT COUNT(*) AS n FROM "order" WHERE id = ?', [a]), 0);
    final c = await bill('t3', [fries(1000)]);
    await pos.settleOrder(orderId: c, payments: [const SettlePayment(methodId: 'cash', amountMinor: 15000)], staffId: 's1');
    await expectLater(ops.merge(fromOrderId: b, intoOrderId: c, staffId: 's1'), throwsA(isA<PosException>()));
    await expectLater(ops.move(fromOrderId: b, picks: const [MovePick(0, 99000)], toTableId: 't1', staffId: 's1'), throwsA(isA<PosException>()), reason: 'cannot move more than the bill has');
    await expectLater(ops.move(fromOrderId: b, picks: const [], toTableId: 't1', staffId: 's1'), throwsA(isA<PosException>()));
  });

  test('a busy table cannot receive a split', () async {
    final a = await bill('t1', [fries(2000)]);
    await bill('t2', [burger(1000)]);
    await expectLater(ops.move(fromOrderId: a, picks: const [MovePick(0, 1000)], toTableId: 't2', staffId: 's1'), throwsA(isA<PosException>()));
    expect((await pos.loadDraft(a))!.items.single.qtyMilli, 2000, reason: 'nothing changed');
  });
}
