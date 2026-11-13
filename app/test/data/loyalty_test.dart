import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/loyalty_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/domain/loyalty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PosService pos;
  late LoyaltyService loyalty;
  final clock = DateTime(2026, 1, 12, 12);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
    await sql("INSERT INTO customer(id,name,phone,updated_at) VALUES ('c1','Sara','03001234567',1)");
    pos = PosService(db, now: () => clock);
    loyalty = LoyaltyService(db, now: () => clock);
  });
  tearDown(() => db.close());

  Future<String> order(int burgers, {String? customer = 'c1'}) => pos.saveDraft(
      DraftOrder(orderType: 'counter', customerId: customer, items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: burgers * 1000, unitPriceMinor: 45000)]),
      staffId: 's1');

  test('off by default: no points are earned', () async {
    await pos.settleOrder(orderId: await order(2), payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');
    expect(await loyalty.balance('c1'), 0);
  });

  test('earn on money paid, spend as a payment, and a void gives spent points back and takes earned ones away', () async {
    await loyalty.save(const LoyaltyConfig(enabled: true)); // 1 point per 100, 1 point = 1
    await pos.settleOrder(orderId: await order(2), payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');
    expect(await loyalty.balance('c1'), 9, reason: '900 paid -> 9 points');

    // 450 bill: 5 paid with points, 445 cash -> earns 4 more on the 445
    final id = await order(1);
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: loyaltyMethodId, amountMinor: 500), const SettlePayment(methodId: 'cash', amountMinor: 44500)], staffId: 's1');
    expect(await loyalty.balance('c1'), 9 - 5 + 4);

    await pos.refundOrder(orderId: id, staffId: 's1', reason: 'mistake');
    expect(await loyalty.balance('c1'), 9, reason: 'back to before that bill');
  });

  test('cannot pay with more points than the customer has, or without a customer', () async {
    await loyalty.save(const LoyaltyConfig(enabled: true));
    await expectLater(
        pos.settleOrder(orderId: await order(1), payments: [const SettlePayment(methodId: loyaltyMethodId, amountMinor: 45000)], staffId: 's1'),
        throwsA(isA<PosException>().having((e) => e.code, 'code', 'points_short')));
    await expectLater(
        pos.settleOrder(orderId: await order(1, customer: null), payments: [const SettlePayment(methodId: loyaltyMethodId, amountMinor: 100), const SettlePayment(methodId: 'cash', amountMinor: 44900)], staffId: 's1'),
        throwsA(isA<PosException>().having((e) => e.code, 'code', 'points_need_customer')));
  });

  test('settings survive save and load; damaged settings mean off', () async {
    await loyalty.save(const LoyaltyConfig(enabled: true, spendStepMinor: 50000, pointsPerStep: 2, pointValueMinor: 50, minRedeem: 10));
    final c = await loyalty.config();
    expect((c.enabled, c.spendStepMinor, c.pointsPerStep, c.pointValueMinor, c.minRedeem), (true, 50000, 2, 50, 10));
    expect(LoyaltyConfig.decode('junk').enabled, isFalse);
    expect(c.pointsFor(120), 3, reason: 'a part of a point counts as a whole point');
  });
}
