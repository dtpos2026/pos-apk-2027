import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/domain/bill.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late PosService svc;
var clock = DateTime(2026, 1, 12, 19, 40);
var idCounter = 0;

Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
Future<int> count(String table, [String where = '1=1']) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table WHERE $where').getSingle()).data['n'] as int;
Future<int> sum(String q) async => (await db.customSelect(q).getSingle()).data['s'] as int;

Future<void> seed() async {
  await sql("INSERT INTO role(id,name,permissions,is_system,updated_at) VALUES ('r-owner','Owner','[\"*\"]',1,1)");
  await sql("INSERT INTO role(id,name,permissions,is_system,updated_at) VALUES ('r-cash','Cashier','[]',1,1)");
  await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('owner','Owner','r-owner','h','s',1)");
  await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('cashier','Cashier','r-cash','h','s',1)");
  await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
  await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('card','Card','card',1)");
  await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('udhaar','Udhaar','credit',1)");
  await sql("INSERT INTO product(id,name,base_price_minor,track_stock,updated_at) VALUES ('burger','Burger',50000,0,1)");
  await sql("INSERT INTO product(id,name,base_price_minor,track_stock,updated_at) VALUES ('cola','Cola',10000,1,1)");
  await sql("INSERT INTO stock_item(id,name,unit,product_id,updated_at) VALUES ('st-cola','Cola can','pc','cola',1)");
  await sql("INSERT INTO stock_item(id,name,unit,updated_at) VALUES ('st-bun','Bun','pc',1)");
  await sql("INSERT INTO stock_movement(id,stock_item_id,delta_milli,reason,created_at) VALUES ('open1','st-cola',10000,'opening',1)");
  await sql("INSERT INTO stock_movement(id,stock_item_id,delta_milli,reason,created_at) VALUES ('open2','st-bun',10000,'opening',1)");
  await sql("INSERT INTO recipe_line(product_id,variant_id,stock_item_id,qty_milli) VALUES ('burger',NULL,'st-bun',1000)");
  await sql("INSERT INTO customer(id,name,credit_limit_minor,updated_at) VALUES ('c1','Ahmed',100000,1)");
  await sql("INSERT INTO area(id,name,updated_at) VALUES ('a1','Hall',1)");
  await sql("INSERT INTO dining_table(id,area_id,label,updated_at) VALUES ('t1','a1','T1',1)");
}

CartItem burger({int qty = 1000, int disc = 0}) => CartItem(productId: 'burger', name: 'Burger', qtyMilli: qty, unitPriceMinor: 50000, lineDiscountMinor: disc, taxRateBp: 1600);
CartItem cola() => const CartItem(productId: 'cola', name: 'Cola', qtyMilli: 1000, unitPriceMinor: 10000);

Future<String> draft([List<CartItem>? items, String? customer, String? table, BillConfig? cfg]) => svc.saveDraft(
      DraftOrder(orderType: table == null ? 'counter' : 'dine_in', items: items ?? [burger()], customerId: customer, tableId: table, config: cfg ?? const BillConfig()),
      staffId: 'owner',
    );

void main() {
  draftTests();
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    idCounter = 0;
    clock = DateTime(2026, 1, 12, 19, 40);
    svc = PosService(db, now: () => clock, newId: () => 'id-${++idCounter}');
    await seed();
  });
  tearDown(() => db.close());

  test('draft is persisted and re-saving replaces its items', () async {
    final id = await draft([burger(), cola()]);
    expect(await count('order_item', "order_id='$id'"), 2);
    await svc.saveDraft(DraftOrder(id: id, orderType: 'counter', items: [burger(qty: 2000)]), staffId: 'owner');
    expect(await count('order_item', "order_id='$id'"), 1);
    expect(await sum("SELECT total_minor AS s FROM \"order\" WHERE id='$id'"), 116000); // 2 x 500 + 16% tax
  });

  test('settle cash: invoice number, payment row with tender and change, audit and outbox', () async {
    final id = await draft();
    final r = await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 100000)], staffId: 'cashier');
    expect(r.invoiceNo, 'INV-20260112-0001');
    expect(r.totalMinor, 58000);
    expect(r.changeMinor, 42000);
    final p = await db.customSelect('SELECT * FROM payment').getSingle();
    expect(p.data['amount_minor'], 58000);
    expect(p.data['tendered_minor'], 100000);
    expect(p.data['change_minor'], 42000);
    expect(await count('audit_log', "event='bill.settle'"), 1);
    expect(await count('outbox', "idempotency_key='order:$id:settle'"), 1);
  });

  test('invoice numbers are gap-free and sequential, and restart each day', () async {
    final a = await svc.settleOrder(orderId: await draft(), payments: [const SettlePayment(methodId: 'card', amountMinor: 58000)], staffId: 'cashier');
    final b = await svc.settleOrder(orderId: await draft(), payments: [const SettlePayment(methodId: 'card', amountMinor: 58000)], staffId: 'cashier');
    expect([a.invoiceNo, b.invoiceNo], ['INV-20260112-0001', 'INV-20260112-0002']);
    clock = DateTime(2026, 1, 13, 10);
    final c = await svc.settleOrder(orderId: await draft(), payments: [const SettlePayment(methodId: 'card', amountMinor: 58000)], staffId: 'cashier');
    expect(c.invoiceNo, 'INV-20260113-0001');
  });

  test('retrying settle after a crash does not duplicate anything', () async {
    final id = await draft();
    final pay = [const SettlePayment(methodId: 'cash', amountMinor: 58000)];
    final first = await svc.settleOrder(orderId: id, payments: pay, staffId: 'cashier');
    final again = await svc.settleOrder(orderId: id, payments: pay, staffId: 'cashier');
    expect(again.alreadySettled, isTrue);
    expect(again.invoiceNo, first.invoiceNo);
    expect(await count('payment'), 1);
    expect(await count('outbox'), 1);
    expect(await count('stock_movement', "reason='recipe'"), 1);
  });

  test('underpayment is rejected and leaves no trace (invoice number not consumed)', () async {
    final id = await draft();
    await expectLater(svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 1000)], staffId: 'cashier'), throwsA(isA<PosException>()));
    expect(await count('payment'), 0);
    expect(await count('invoice_sequence'), 0);
    expect((await db.customSelect("SELECT status FROM \"order\" WHERE id='$id'").getSingle()).data['status'], 'draft');
  });

  test('a failure midway rolls back the WHOLE settlement (crash safety)', () async {
    final id = await draft([burger(), cola()]);
    await sql("CREATE TRIGGER boom BEFORE INSERT ON audit_log WHEN NEW.event = 'bill.settle' BEGIN SELECT RAISE(ABORT, 'simulated crash'); END");
    await expectLater(svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 80000)], staffId: 'cashier'), throwsA(anything));
    expect(await count('payment'), 0);
    expect(await count('outbox'), 0);
    expect(await count('invoice_sequence', 'last_no > 0'), 0);
    expect(await count('stock_movement', "reason IN ('sale','recipe')"), 0);
    expect((await db.customSelect("SELECT status FROM \"order\" WHERE id='$id'").getSingle()).data['status'], 'draft');
    // and it succeeds once the fault is gone
    await sql('DROP TRIGGER boom');
    final r = await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 80000)], staffId: 'cashier');
    expect(r.invoiceNo, 'INV-20260112-0001');
  });

  test('stock: recipe and direct stock deduct on sale, come back on void', () async {
    final id = await draft([burger(qty: 2000), cola()]);
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'card', amountMinor: 126000)], staffId: 'cashier');
    expect(await sum("SELECT SUM(delta_milli) AS s FROM stock_movement WHERE stock_item_id='st-bun'"), 10000 - 2000);
    expect(await sum("SELECT SUM(delta_milli) AS s FROM stock_movement WHERE stock_item_id='st-cola'"), 10000 - 1000);
    await svc.refundOrder(orderId: id, staffId: 'owner', reason: 'Customer left');
    expect(await sum("SELECT SUM(delta_milli) AS s FROM stock_movement WHERE stock_item_id='st-bun'"), 10000);
    expect(await sum("SELECT SUM(delta_milli) AS s FROM stock_movement WHERE stock_item_id='st-cola'"), 10000);
  });

  test('udhaar: posts to the customer ledger, enforces the limit, void reverses it', () async {
    final id = await draft([burger()], 'c1');
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'udhaar', amountMinor: 58000)], staffId: 'cashier');
    expect(await sum("SELECT SUM(amount_minor) AS s FROM customer_ledger WHERE customer_id='c1'"), 58000);
    final id2 = await draft([burger(qty: 2000)], 'c1'); // 1160.00 would push balance past the 1000.00 limit
    await expectLater(svc.settleOrder(orderId: id2, payments: [const SettlePayment(methodId: 'udhaar', amountMinor: 116000)], staffId: 'cashier'),
        throwsA(isA<PosException>().having((e) => e.code, 'code', 'credit_limit')));
    await svc.refundOrder(orderId: id, staffId: 'owner', reason: 'Wrong order');
    expect(await sum("SELECT SUM(amount_minor) AS s FROM customer_ledger WHERE customer_id='c1'"), 0);
  });

  test('credit sale without a customer is rejected', () async {
    final id = await draft();
    await expectLater(svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'udhaar', amountMinor: 58000)], staffId: 'cashier'),
        throwsA(isA<PosException>().having((e) => e.code, 'code', 'credit_needs_customer')));
  });

  test('permissions: cashier cannot discount, void or refund; reason is mandatory', () async {
    await expectLater(
        svc.saveDraft(DraftOrder(orderType: 'counter', items: [burger()], config: const BillConfig(billDiscount: Discount.percent(1000))), staffId: 'cashier'),
        throwsA(isA<PosException>().having((e) => e.code, 'code', 'permission_denied')));
    final id = await draft();
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    await expectLater(svc.refundOrder(orderId: id, staffId: 'cashier', reason: 'x'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'permission_denied')));
    await expectLater(svc.refundOrder(orderId: id, staffId: 'owner', reason: '  '), throwsA(isA<PosException>().having((e) => e.code, 'code', 'reason_required')));
    expect(await count('refund'), 0);
  });

  test('discount by an authorised user changes the total and the tax', () async {
    final id = await draft([burger()], null, null, const BillConfig(billDiscount: Discount.percent(1000)));
    final r = await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 52200)], staffId: 'owner');
    expect(r.totalMinor, 52200); // 450.00 + 16% = 522.00
  });

  test('partial refund then the rest; over-refund rejected; critical audit row written', () async {
    final id = await draft();
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    await svc.refundOrder(orderId: id, staffId: 'owner', reason: 'Cold food', amountMinor: 20000);
    expect((await db.customSelect("SELECT status FROM \"order\" WHERE id='$id'").getSingle()).data['status'], 'paid');
    await expectLater(svc.refundOrder(orderId: id, staffId: 'owner', reason: 'again', amountMinor: 40000), throwsA(isA<PosException>().having((e) => e.code, 'code', 'bad_amount')));
    await svc.refundOrder(orderId: id, staffId: 'owner', reason: 'Rest', amountMinor: 38000);
    expect((await db.customSelect("SELECT status FROM \"order\" WHERE id='$id'").getSingle()).data['status'], 'refunded');
    expect(await count('audit_log', "event='bill.refund' AND critical=1"), 2);
  });

  test('a settled order cannot be edited', () async {
    final id = await draft();
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    await expectLater(svc.saveDraft(DraftOrder(id: id, orderType: 'counter', items: [cola()]), staffId: 'owner'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'not_editable')));
  });

  test('dine-in: table becomes occupied, then free on settlement', () async {
    final id = await draft([burger()], null, 't1');
    Future<String> st() async => (await db.customSelect("SELECT status FROM dining_table WHERE id='t1'").getSingle()).data['status'] as String;
    expect(await st(), 'occupied');
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    expect(await st(), 'free');
  });

  test('payment rows cannot be altered afterwards (append-only guard)', () async {
    final id = await draft();
    await svc.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    await expectLater(sql('UPDATE payment SET amount_minor = 1'), throwsA(anything));
    await expectLater(sql('DELETE FROM payment'), throwsA(anything));
  });

  test('daily report separates gross, refunds and net', () async {
    final a = await draft();
    await svc.settleOrder(orderId: a, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'cashier');
    final b = await draft([burger(qty: 2000)]);
    await svc.settleOrder(orderId: b, payments: [const SettlePayment(methodId: 'card', amountMinor: 116000)], staffId: 'cashier');
    await svc.refundOrder(orderId: a, staffId: 'owner', reason: 'Void', methodId: 'cash');
    final rep = await svc.salesReport('2026-01-12');
    expect(rep.bills, 2);
    expect(rep.grossMinor, 174000);
    expect(rep.refundsMinor, 58000);
    expect(rep.netMinor, 116000);
    expect(rep.byMethod, {'Cash': 58000, 'Card': 116000});
  });
}

void draftTests() {
  group('draft recovery', () {
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      idCounter = 0;
      clock = DateTime(2026, 1, 12, 19, 40);
      svc = PosService(db, now: () => clock, newId: () => 'id-${++idCounter}');
      await seed();
    });
    tearDown(() => db.close());

    test('a draft survives an app restart and reloads exactly', () async {
      final id = await svc.saveDraft(
        DraftOrder(orderType: 'dine_in', tableId: 't1', items: [
          CartItem(productId: 'burger', name: 'Burger', qtyMilli: 2000, unitPriceMinor: 50000, taxRateBp: 1600, modifiers: const [CartModifier(name: 'Extra cheese', priceMinor: 5000)], note: 'No onion'),
        ]),
        staffId: 'owner',
      );
      final fresh = PosService(db, now: () => clock); // "app restarted"
      expect(await fresh.latestDraftId(), id);
      final d = (await fresh.loadDraft(id))!;
      expect(d.orderType, 'dine_in');
      expect(d.tableId, 't1');
      expect(d.items.single.qtyMilli, 2000);
      expect(d.items.single.modifiers.single.name, 'Extra cheese');
      expect(d.items.single.note, 'No onion');
    });

    test('discarding frees the table and removes everything; settled orders cannot be discarded', () async {
      final id = await svc.saveDraft(DraftOrder(orderType: 'dine_in', tableId: 't1', items: [burger()]), staffId: 'owner');
      await svc.discardDraft(id);
      expect(await count('"order"'), 0);
      expect(await count('order_item'), 0);
      expect((await db.customSelect("SELECT status FROM dining_table WHERE id='t1'").getSingle()).data['status'], 'free');
      final id2 = await svc.saveDraft(DraftOrder(orderType: 'counter', items: [burger()]), staffId: 'owner');
      await svc.settleOrder(orderId: id2, payments: [const SettlePayment(methodId: 'cash', amountMinor: 58000)], staffId: 'owner');
      await expectLater(svc.discardDraft(id2), throwsA(isA<PosException>()));
      expect(await svc.latestDraftId(), isNull);
    });
  });
}
