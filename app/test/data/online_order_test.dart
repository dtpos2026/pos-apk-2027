import 'package:drift/native.dart';
import 'package:dt_food_pos/data/customer_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/kitchen_service.dart';
import 'package:dt_food_pos/data/online_order_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late OnlineOrderService svc;
  late PrintService print_;
  late KitchenService kitchen;
  late PosService pos;
  final clock = DateTime(2026, 1, 12, 20);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final h = DbHelper(db, now: () => clock);
    pos = PosService(db, now: () => clock);
    svc = OnlineOrderService(h, pos, CustomerService(h));
    print_ = PrintService(db, now: () => clock);
    kitchen = KitchenService(h);
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await db.customStatement("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await db.customStatement("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
  });
  tearDown(() => db.close());

  final burgers = [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000)];

  test('an online order waits as pending with its channel, customer and address; the customer is saved for next time', () async {
    final id = await svc.create(channel: 'whatsapp', customerName: 'Ahmed', phone: '03001234567', address: 'House 5, Narang', items: burgers, note: 'no onion', staffId: 's1');
    final o = (await svc.orders()).single;
    expect([o.id, o.channel, o.customerName, o.phone, o.address, o.pending, o.totalMinor, o.note], [id, 'whatsapp', 'Ahmed', '03001234567', 'House 5, Narang', true, 90000, 'no onion']);
    expect(o.itemsText, '2 x Zinger Burger');
    expect(await kitchen.tickets(), isEmpty, reason: 'not in the kitchen until accepted');
    // the same phone again re-uses the saved customer
    await svc.create(channel: 'phone', customerName: 'Ahmed', phone: '03001234567', items: burgers, staffId: 's1');
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM customer').getSingle()).data['n'], 1);
  });

  test('accepting sends it to the kitchen board; it is paid like any order; rejecting removes a waiting order', () async {
    final id = await svc.create(channel: 'foodpanda', customerName: 'Sara', items: burgers, staffId: 's1');
    await print_.queueKot(id, onlyNew: true);
    expect((await kitchen.tickets()).single.status, 'new');
    var o = (await svc.orders()).single;
    expect(o.pending, isFalse);
    await kitchen.advance(id);
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');
    expect(await svc.orders(), isEmpty, reason: 'a paid order leaves the inbox');

    final r = await svc.create(channel: 'phone', customerName: 'Bilal', items: burgers, staffId: 's1');
    await svc.reject(r);
    expect(await svc.orders(), isEmpty);
    await expectLater(svc.reject(id), throwsA(isA<PosException>()), reason: 'a paid order cannot be rejected');
    await expectLater(svc.create(channel: 'phone', customerName: '', items: burgers, staffId: 's1'), throwsA(isA<PosException>()));
  });
}
