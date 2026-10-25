import 'package:drift/native.dart';
import 'package:dt_food_pos/data/customer_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/online_order_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late OnlineOrderService svc;
  late PosService pos;
  final clock = DateTime(2026, 1, 12, 20);
  final burgers = [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000)];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final h = DbHelper(db, now: () => clock);
    pos = PosService(db, now: () => clock);
    svc = OnlineOrderService(h, pos, CustomerService(h));
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await db.customStatement("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await db.customStatement("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
    await db.customStatement("INSERT INTO team_member(id,kind,name,updated_at) VALUES ('rd','rider','Kamran',1)");
  });
  tearDown(() => db.close());

  Future<String> sourceId(String name) async => (await svc.sources()).firstWhere((s) => s.name == name).id;

  test('order sources start with the usual list, can be added, renamed, switched off; used ones are hidden not erased', () async {
    final list = await svc.sources();
    expect(list.map((s) => s.name), ['Direct WhatsApp Order', 'Phone Order', 'Walk-in / Manual Entry', 'Foodpanda', 'Grab & Go', 'Other / Custom Source']);
    expect(list.where((s) => s.platform).map((s) => s.name), ['Foodpanda', 'Grab & Go']);
    final id = await svc.saveSource(name: 'Cheetay', platform: true);
    expect((await svc.sources()).last.name, 'Cheetay');
    await expectLater(svc.saveSource(name: 'cheetay', platform: true), throwsA(isA<PosException>()), reason: 'no two sources with one name');
    await expectLater(svc.saveSource(name: ' ', platform: false), throwsA(isA<PosException>()));
    await svc.saveSource(id: id, name: 'Cheetay Food', platform: true);
    final order = await svc.create(sourceId: id, customerName: 'A', phone: '0300', address: 'x', city: 'Lahore', items: burgers, platformRef: 'C-1', staffId: 's1');
    await svc.deleteSource(id);
    expect((await svc.sources(activeOnly: true)).any((s) => s.id == id), isFalse);
    expect((await svc.byId(order))!.sourceName, 'Cheetay Food', reason: 'old orders keep the name');
    final unused = await svc.saveSource(name: 'Temp', platform: false);
    await svc.deleteSource(unused);
    expect((await svc.sources()).any((s) => s.name == 'Temp'), isFalse);
  });

  test('a new delivery order saves the customer with city, links it, keeps charge and discount, and defaults the source', () async {
    final id = await svc.create(customerName: 'Ahmed', phone: '03001234567', address: 'House 5, Narang', city: 'Burewala', items: burgers, deliveryChargeMinor: 15000, discountMinor: 10000, note: 'no onion', staffId: 's1');
    final o = (await svc.byId(id))!;
    expect([o.customerName, o.phone, o.address, o.city, o.sourceName, o.platform, o.deliveryStatus, o.pending], ['Ahmed', '03001234567', 'House 5, Narang', 'Burewala', 'Walk-in / Manual Entry', false, 'pending', true]);
    expect([o.subtotalMinor, o.discountMinor, o.deliveryChargeMinor, o.totalMinor], [90000, 10000, 15000, 95000]);
    expect(o.paymentStatus, 'unpaid');
    expect((await db.customSelect("SELECT city, address FROM customer WHERE phone = '03001234567'").getSingle()).data, {'city': 'Burewala', 'address': 'House 5, Narang'});
    expect(o.customerId, isNotNull);

    // the same phone again re-uses the customer and learns nothing it already knows; an existing customer can be picked by id
    final again = await svc.create(customerName: 'Ahmed', phone: '03001234567', address: 'elsewhere', items: burgers, staffId: 's1');
    expect((await db.customSelect('SELECT COUNT(*) n FROM customer').getSingle()).data['n'], 1);
    expect((await svc.byId(again))!.customerId, o.customerId);
    final picked = await svc.create(customerId: o.customerId, items: burgers, staffId: 's1');
    final p = (await svc.byId(picked))!;
    expect([p.customerName, p.address, p.city], ['Ahmed', 'House 5, Narang', 'Burewala'], reason: 'filled from the saved customer');
  });

  test('validation: items, name, address for a delivery, valid source, amounts, and the same platform order twice', () async {
    await expectLater(svc.create(customerName: 'A', address: 'x', items: const [], staffId: 's1'), throwsA(isA<PosException>()));
    await expectLater(svc.create(customerName: '', address: 'x', items: burgers, staffId: 's1'), throwsA(isA<PosException>()));
    await expectLater(svc.create(customerName: 'A', items: burgers, staffId: 's1'), throwsA(isA<PosException>()), reason: 'a delivery needs an address');
    await svc.create(customerName: 'A', items: burgers, fulfilment: 'pickup', staffId: 's1'); // pickup: no address needed
    final fp = await sourceId('Foodpanda');
    await svc.create(sourceId: fp, customerName: 'FP customer', items: burgers, platformRef: 'FP-1001', staffId: 's1'); // a platform has the address
    await expectLater(svc.create(sourceId: fp, customerName: 'FP customer', items: burgers, platformRef: 'fp-1001', staffId: 's1'), throwsA(isA<PosException>()), reason: 'duplicate platform order');
    await svc.create(sourceId: await sourceId('Grab & Go'), customerName: 'G', items: burgers, platformRef: 'FP-1001', staffId: 's1'); // another platform may reuse a number
    await expectLater(svc.create(sourceId: 'nope', customerName: 'A', address: 'x', items: burgers, staffId: 's1'), throwsA(isA<PosException>()));
    await expectLater(svc.create(customerName: 'A', address: 'x', items: burgers, deliveryChargeMinor: -1, staffId: 's1'), throwsA(isA<PosException>()));
  });

  test('forward steps, rider, history, kitchen link and cancel rules', () async {
    final id = await svc.create(customerName: 'Sara', address: 'x', items: burgers, staffId: 's1');
    await PrintService(db, now: () => clock).queueKot(id, onlyNew: true); // confirming sends it to the kitchen
    expect((await svc.byId(id))!.deliveryStatus, 'confirmed');
    await svc.setStatus(id, 'confirmed', staffId: 's1');
    await svc.setStatus(id, 'preparing', staffId: 's1');
    await svc.setStatus(id, 'ready', staffId: 's1');
    await expectLater(svc.setStatus(id, 'dispatched', staffId: 's1'), throwsA(isA<PosException>()), reason: 'needs a rider');
    await svc.setStatus(id, 'dispatched', riderId: 'rd', staffId: 's1');
    expect((await svc.byId(id))!.riderName, 'Kamran');
    await expectLater(svc.setStatus(id, 'preparing', staffId: 's1'), throwsA(isA<PosException>()), reason: 'no going back');
    await svc.setStatus(id, 'delivered', staffId: 's1');
    expect((await svc.history(id)).map((s) => s.status), ['pending', 'confirmed', 'preparing', 'ready', 'dispatched', 'delivered']);
    expect((await svc.history(id)).first.staff, 'Ali');
    await expectLater(svc.setStatus(id, 'cancelled', staffId: 's1'), throwsA(isA<PosException>()), reason: 'delivered is final');

    // a pickup never goes out with a rider
    final pk = await svc.create(customerName: 'Pick', fulfilment: 'pickup', items: burgers, staffId: 's1');
    expect(OnlineOrderService.nextSteps('ready', fulfilment: 'pickup'), ['delivered', 'cancelled']);
    expect(OnlineOrderService.nextSteps('ready'), ['dispatched', 'delivered', 'cancelled']);
    await svc.setStatus(pk, 'cancelled', staffId: 's1');
    expect((await svc.byId(pk))!.deliveryStatus, 'cancelled');

    // paid orders cannot be cancelled here
    final paid = await svc.create(customerName: 'Paid', address: 'x', items: burgers, staffId: 's1');
    await PrintService(db, now: () => clock).queueKot(paid, onlyNew: true);
    await pos.settleOrder(orderId: paid, payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');
    expect((await svc.byId(paid))!.paymentStatus, 'paid');
    await expectLater(svc.setStatus(paid, 'cancelled', staffId: 's1'), throwsA(isA<PosException>()));
  });

  test('reports: direct and platform sales apart, per source, filters by source, payment and status; POS delivery orders are included', () async {
    final fp = await sourceId('Foodpanda');
    final a = await svc.create(customerName: 'A', address: 'x', items: burgers, staffId: 's1'); // direct, 900
    final b = await svc.create(sourceId: fp, customerName: 'B', items: burgers, platformRef: 'F1', staffId: 's1'); // platform, 900
    final c = await svc.create(sourceId: fp, customerName: 'C', items: burgers, platformRef: 'F2', staffId: 's1');
    await svc.setStatus(c, 'cancelled', staffId: 's1');
    final print_ = PrintService(db, now: () => clock);
    await print_.queueKot(b, onlyNew: true);
    await pos.settleOrder(orderId: b, payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');
    // an order taken in the POS with the Delivery type
    final posOrder = await pos.saveDraft(DraftOrder(orderType: 'delivery', items: burgers, deliveryAddress: 'Main road'), staffId: 's1');
    await pos.settleOrder(orderId: posOrder, payments: [const SettlePayment(methodId: 'cash', amountMinor: 90000)], staffId: 's1');

    final t = await svc.totals('2026-01-01', '2026-12-31');
    expect([t.direct.orders, t.direct.salesMinor], [2, 180000], reason: 'the typed-in direct order and the POS one');
    expect([t.platforms.orders, t.platforms.salesMinor, t.platforms.paidMinor, t.platforms.cancelled], [2, 90000, 90000, 1]);
    expect(t.bySource.firstWhere((s) => s.name == 'Foodpanda').salesMinor, 90000);
    expect((await svc.list(platform: true)).length, 2);
    expect((await svc.list(platform: false)).length, 2);
    expect((await svc.list(payment: 'paid')).map((o) => o.id).toSet(), {b, posOrder});
    expect((await svc.list(status: 'cancelled')).single.id, c);
    expect((await svc.list(openOnly: true)).map((o) => o.id).toSet(), {a, b}, reason: 'delivered/cancelled are closed; a paid platform order is still to be handed over');
    expect((await svc.byId(posOrder))!.deliveryStatus, 'delivered');
    expect((await svc.list(from: '2030-01-01', to: '2030-12-31')), isEmpty);
  });

  test('upgrading to schema 9 is harmless twice and keeps old orders', () async {
    await migrateToV9(db);
    await migrateToV9(db);
    expect((await db.customSelect("SELECT COUNT(*) n FROM pragma_table_info('customer') WHERE name = 'city'").getSingle()).data['n'], 1);
    expect((await db.customSelect("SELECT COUNT(*) n FROM pragma_table_info('product') WHERE name = 'description'").getSingle()).data['n'], 1);
  });
}
