import 'package:drift/native.dart';
import 'package:dt_food_pos/data/auth_service.dart';
import 'package:dt_food_pos/data/bill_history.dart';
import 'package:dt_food_pos/data/customer_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/expense_service.dart';
import 'package:dt_food_pos/data/inventory_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/data/setup_service.dart';
import 'package:dt_food_pos/data/shift_service.dart';
import 'package:dt_food_pos/data/staff_service.dart';
import 'package:dt_food_pos/data/table_service.dart';
import 'package:dt_food_pos/domain/day_close_doc.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late DbHelper h;
late PosService pos;
late ShiftService shifts;
late AuthService auth;
late String owner;
late String cashId, cardId, creditId;
var clock = DateTime(2026, 1, 12, 10);

Future<int> count(String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;
Future<String> methodId(String kind) async => (await db.customSelect("SELECT id FROM payment_method WHERE kind = '$kind'").getSingle()).data['id'] as String;

Future<String> product(String id, String name, int price, {String? sku}) async {
  await db.customStatement('INSERT INTO product(id,name,base_price_minor,sku,updated_at) VALUES (?,?,?,?,1)', [id, name, price, sku]);
  return id;
}

Future<String> sell(String productId, int price, List<SettlePayment> pays, {String? customer, String? table, String? shift}) async {
  final o = await pos.saveDraft(DraftOrder(orderType: table == null ? 'counter' : 'dine_in', tableId: table, customerId: customer, items: [CartItem(productId: productId, name: productId, qtyMilli: 1000, unitPriceMinor: price)]), staffId: owner);
  await pos.settleOrder(orderId: o, payments: pays, staffId: owner, shiftId: shift);
  return o;
}

void main() {
  reportTests();
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime(2026, 1, 12, 10);
    var n = 0;
    String nid() => 'id-${++n}';
    h = DbHelper(db, now: () => clock, newId: nid);
    pos = PosService(db, now: () => clock, newId: nid);
    shifts = ShiftService(db, pos, now: () => clock, newId: nid);
    auth = AuthService(db, now: () => clock, iterations: 1000);
    owner = await SetupService(db, auth, now: () => clock, newId: nid).completeSetup(businessName: 'T', ownerName: 'Owner', pin: '1234');
    cashId = await methodId('cash');
    cardId = await methodId('card');
    creditId = await methodId('credit');
  });
  tearDown(() => db.close());

  group('day close (Z report)', () {
    test('Z report adds up sales, discounts, refunds, methods, udhaar, expenses and the cash drawer', () async {
      final cust = await CustomerService(h).save(name: 'Ahmed', creditLimitMinor: 500000, staffId: owner);
      await product('p', 'Karahi', 100000);
      final shift = await shifts.openShift(owner, openingCashMinor: 5000);
      await sell('p', 100000, [SettlePayment(methodId: cashId, amountMinor: 100000)], shift: shift);
      await sell('p', 100000, [SettlePayment(methodId: cardId, amountMinor: 100000)], shift: shift);
      await sell('p', 100000, [SettlePayment(methodId: creditId, amountMinor: 100000)], customer: cust, shift: shift);
      await CustomerService(h).receivePayment(customerId: cust, amountMinor: 40000, methodId: cashId, staffId: owner);
      await ExpenseService(h).add(amountMinor: 3000, category: 'Gas', methodId: cashId, staffId: owner);
      final before = await shifts.zReport('2026-01-12');
      expect(before.bills, 3);
      expect(before.netMinor, 300000);
      expect(before.creditGivenMinor, 100000);
      expect(before.creditRecoveredMinor, 40000);
      expect(before.expensesMinor, 3000);
      expect(before.anyShiftOpen, isTrue);
      expect(before.closedAt, isNull);
      // an open shift no longer blocks the day: it is counted here and closed together with the day
      final exp = (await shifts.summary(shift)).expectedMinor;
      await shifts.closeShift(shift, countedMinor: exp - 500);
      await shifts.closeDay('2026-01-12', staffId: owner);
      final z = await shifts.zReport('2026-01-12');
      expect(z.closedAt, isNotNull);
      expect(z.cashVarianceMinor, -500);
      final text = docToText(buildZReportDoc(z, businessName: 'T', currency: Currency.pkr, printedAt: '2026-01-12 23:00'), 58);
      expect(text, contains('DAY CLOSE (Z REPORT)'));
      expect(text, contains('NET SALES'));
      expect(text, contains('3,000.00'));
      expect(text, contains('Udhaar given'));
      expect(text, contains('-5.00'));
      expect(text, isNot(contains('NOT CLOSED YET')));
    });
  });

  group('customers and udhaar', () {
    late CustomerService svc;
    setUp(() => svc = CustomerService(h));

    test('create, validate, no duplicate phone', () async {
      final id = await svc.save(name: 'Ahmed', phone: '0300-1', creditLimitMinor: 100000, staffId: owner);
      expect((await svc.list()).single.name, 'Ahmed');
      await expectLater(svc.save(name: ' ', staffId: owner), throwsA(isA<PosException>()));
      await expectLater(svc.save(name: 'B', phone: '0300-1', staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'duplicate_phone')));
      await svc.save(id: id, name: 'Ahmed Khan', phone: '0300-1', creditLimitMinor: 200000, staffId: owner);
      expect((await svc.list(search: 'khan')).single.creditLimitMinor, 200000);
    });

    test('credit sale raises the balance, recovery lowers it, overpaying is refused', () async {
      final c = await svc.save(name: 'Ahmed', creditLimitMinor: 100000, staffId: owner);
      await product('p', 'Tea', 50000);
      await sell('p', 50000, [SettlePayment(methodId: creditId, amountMinor: 50000)], customer: c);
      expect(await svc.balance(c), 50000);
      await svc.receivePayment(customerId: c, amountMinor: 20000, methodId: cardId, staffId: owner);
      expect(await svc.balance(c), 30000);
      await expectLater(svc.receivePayment(customerId: c, amountMinor: 30001, methodId: cardId, staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'overpay')));
      await expectLater(svc.receivePayment(customerId: c, amountMinor: 100, methodId: creditId, staffId: owner), throwsA(isA<PosException>()));
      expect((await svc.ledger(c)).map((e) => e.kind), ['recovery', 'sale_credit']);
      expect((await svc.list()).single.balanceMinor, 30000);
    });

    test('cash recovery goes into the open shift drawer', () async {
      final c = await svc.save(name: 'Ahmed', creditLimitMinor: 100000, staffId: owner);
      await product('p', 'Tea', 50000);
      await sell('p', 50000, [SettlePayment(methodId: creditId, amountMinor: 50000)], customer: c);
      final s = await shifts.openShift(owner, openingCashMinor: 10000);
      await svc.receivePayment(customerId: c, amountMinor: 20000, methodId: cashId, staffId: owner);
      expect((await shifts.summary(s)).expectedMinor, 30000);
    });
  });

  group('expenses', () {
    late ExpenseService svc;
    setUp(() => svc = ExpenseService(h));

    test('cash expense leaves the drawer, card expense does not; categories are reused', () async {
      final s = await shifts.openShift(owner, openingCashMinor: 100000);
      await svc.add(amountMinor: 30000, category: 'Gas', methodId: cashId, staffId: owner);
      await svc.add(amountMinor: 50000, category: 'gas', methodId: cardId, staffId: owner, note: 'cylinder');
      expect((await shifts.summary(s)).expectedMinor, 70000);
      expect(await count('SELECT COUNT(*) AS n FROM expense_category'), 1);
      expect(await svc.totalFor('2026-01-12'), 80000);
      expect((await svc.forDate('2026-01-12')).map((e) => e.amountMinor), [50000, 30000]);
    });

    test('validation', () async {
      await expectLater(svc.add(amountMinor: 0, category: 'Gas', methodId: cashId, staffId: owner), throwsA(isA<PosException>()));
      await expectLater(svc.add(amountMinor: 1, category: ' ', methodId: cashId, staffId: owner), throwsA(isA<PosException>()));
      await expectLater(svc.add(amountMinor: 1, category: 'Gas', methodId: 'nope', staffId: owner), throwsA(isA<PosException>()));
      expect(await count('SELECT COUNT(*) AS n FROM expense'), 0);
    });
  });

  group('staff management', () {
    late StaffService svc;
    late String cashierRole, managerRole, ownerRole;
    setUp(() async {
      svc = StaffService(h, auth);
      cashierRole = (await db.customSelect("SELECT id FROM role WHERE name = 'Cashier'").getSingle()).data['id'] as String;
      managerRole = (await db.customSelect("SELECT id FROM role WHERE name = 'Manager'").getSingle()).data['id'] as String;
      ownerRole = (await db.customSelect("SELECT id FROM role WHERE name = 'Owner'").getSingle()).data['id'] as String;
    });

    test('owner adds staff; cashiers and managers cannot manage staff', () async {
      final c = await svc.add(actor: owner, name: 'Sara', roleId: cashierRole, pin: '5555');
      expect(await auth.verifyPin(c, '5555'), PinResult.ok);
      await expectLater(svc.add(actor: c, name: 'X', roleId: cashierRole, pin: '1111'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'permission_denied')));
      final m = await svc.add(actor: owner, name: 'Mgr', roleId: managerRole, pin: '2222');
      await expectLater(svc.setActive(actor: m, staffId: c, active: false), throwsA(isA<PosException>()));
      expect(await count("SELECT COUNT(*) AS n FROM audit_log WHERE event = 'staff.add' AND critical = 1"), 2);
    });

    test('the last owner can never be removed or demoted; nobody can deactivate themselves', () async {
      await expectLater(svc.setActive(actor: owner, staffId: owner, active: false), throwsA(isA<PosException>().having((e) => e.code, 'code', 'self')));
      final owner2 = await svc.add(actor: owner, name: 'Owner2', roleId: ownerRole, pin: '3333');
      await svc.setActive(actor: owner2, staffId: owner, active: false); // fine: owner2 remains
      await expectLater(svc.setActive(actor: owner2, staffId: owner2, active: false), throwsA(isA<PosException>()));
      await expectLater(svc.changeRole(actor: owner2, staffId: owner2, roleId: cashierRole), throwsA(isA<PosException>().having((e) => e.code, 'code', 'last_owner')));
    });

    test('deactivated staff cannot sign in; reactivating restores access; reset PIN works', () async {
      final c = await svc.add(actor: owner, name: 'Sara', roleId: cashierRole, pin: '5555');
      await svc.setActive(actor: owner, staffId: c, active: false);
      expect(await auth.verifyPin(c, '5555'), PinResult.unknown);
      await svc.setActive(actor: owner, staffId: c, active: true);
      await svc.resetPin(actor: owner, staffId: c, newPin: '7777');
      expect(await auth.verifyPin(c, '5555'), PinResult.wrong);
      expect(await auth.verifyPin(c, '7777'), PinResult.ok);
      await svc.changeRole(actor: owner, staffId: c, roleId: managerRole);
      expect((await svc.list()).firstWhere((s) => s.id == c).roleName, 'Manager');
    });
  });

  group('inventory', () {
    late InventoryService svc;
    setUp(() => svc = InventoryService(h));

    test('opening stock, purchase with weighted average cost, valuation', () async {
      final flour = await svc.saveItem(name: 'Flour', unit: 'kg', reorderLevelMilli: 5000, openingMilli: 10000, openingCostMinor: 10000, staffId: owner); // 10 kg @ 100
      await svc.purchase(lines: [PurchaseInput(stockItemId: flour, qtyMilli: 10000, unitCostMinor: 14000)], paidMinor: 140000, staffId: owner); // +10 kg @ 140
      final r = (await svc.list()).single;
      expect(r.onHandMilli, 20000);
      expect(r.avgCostMinor, 12000); // (10x100 + 10x140) / 20
      expect(await svc.valuation(), 240000);
    });

    test('credit purchase becomes payable, can be paid, never overpaid', () async {
      final item = await svc.saveItem(name: 'Oil', unit: 'l', staffId: owner);
      final sup = await svc.saveSupplier(name: 'Metro');
      await svc.purchase(supplierId: sup, lines: [PurchaseInput(stockItemId: item, qtyMilli: 5000, unitCostMinor: 40000)], paidMinor: 50000, staffId: owner); // total 2000.00, paid 500
      expect(await svc.supplierBalance(sup), 150000);
      await svc.paySupplier(supplierId: sup, amountMinor: 100000, staffId: owner);
      expect(await svc.supplierBalance(sup), 50000);
      await expectLater(svc.paySupplier(supplierId: sup, amountMinor: 60000, staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'overpay')));
      await expectLater(svc.purchase(lines: [PurchaseInput(stockItemId: item, qtyMilli: 1000, unitCostMinor: 100)], paidMinor: 0, staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'supplier_required')));
    });

    test('wastage needs a reason; a stock count books the difference; low stock is reported', () async {
      final item = await svc.saveItem(name: 'Chicken', unit: 'kg', reorderLevelMilli: 3000, openingMilli: 10000, staffId: owner);
      await expectLater(svc.wastage(stockItemId: item, qtyMilli: 1000, reason: ' ', staffId: owner), throwsA(isA<PosException>()));
      await svc.wastage(stockItemId: item, qtyMilli: 2000, reason: 'Spoiled', staffId: owner);
      expect(await svc.onHand(item), 8000);
      expect(await svc.stockCount(stockItemId: item, countedMilli: 2500, staffId: owner), -5500);
      expect(await svc.onHand(item), 2500);
      expect((await svc.list(lowOnly: true)).single.name, 'Chicken');
      expect(await svc.stockCount(stockItemId: item, countedMilli: 2500, staffId: owner), 0);
    });

    test('a recipe makes a sale deduct the ingredients', () async {
      final bun = await svc.saveItem(name: 'Bun', unit: 'pc', openingMilli: 10000, staffId: owner);
      final patty = await svc.saveItem(name: 'Patty', unit: 'pc', openingMilli: 10000, staffId: owner);
      await product('burger', 'Burger', 45000);
      await svc.saveRecipe(productId: 'burger', ingredientsMilli: {bun: 1000, patty: 1000});
      expect((await svc.recipe('burger')).length, 2);
      await sell('burger', 45000, [SettlePayment(methodId: cashId, amountMinor: 45000)]);
      expect(await svc.onHand(bun), 9000);
      await svc.saveRecipe(productId: 'burger', ingredientsMilli: {bun: 2000}); // replaced, not appended
      expect((await svc.recipe('burger')).keys, [bun]);
    });

    test('validation', () async {
      await expectLater(svc.saveItem(name: '', unit: 'kg', staffId: owner), throwsA(isA<PosException>()));
      await expectLater(svc.saveItem(name: 'X', unit: 'box', staffId: owner), throwsA(isA<PosException>()));
      await expectLater(svc.purchase(lines: [], staffId: owner), throwsA(isA<PosException>()));
    });
  });

  group('tables', () {
    late TableService svc;
    setUp(() => svc = TableService(h));

    test('areas and tables, duplicate labels refused, status reflects open orders', () async {
      final a = await svc.saveArea(name: 'Hall');
      final t1 = await svc.saveTable(areaId: a, label: 'T1', seats: 4);
      await expectLater(svc.saveTable(areaId: a, label: 't1'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'duplicate')));
      await product('p', 'Tea', 10000);
      final order = await pos.saveDraft(DraftOrder(orderType: 'dine_in', tableId: t1, items: [const CartItem(productId: 'p', name: 'Tea', qtyMilli: 2000, unitPriceMinor: 10000)]), staffId: owner);
      final row = (await svc.tables()).single;
      expect([row.status, row.orderId, row.orderTotalMinor], ['occupied', order, 20000]);
      await expectLater(svc.setStatus(t1, 'cleaning'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'in_use')));
      await expectLater(svc.deleteTable(t1), throwsA(isA<PosException>()));
      await pos.settleOrder(orderId: order, payments: [SettlePayment(methodId: cashId, amountMinor: 20000)], staffId: owner);
      expect((await svc.tables()).single.status, 'free');
      await svc.setStatus(t1, 'reserved');
      expect((await svc.tables()).single.status, 'reserved');
      await svc.deleteTable(t1);
      expect(await svc.tables(), isEmpty);
    });

    test('transfer moves an open order to a free table and rejects busy or settled cases', () async {
      final a = await svc.saveArea(name: 'Hall');
      final t1 = await svc.saveTable(areaId: a, label: 'T1');
      final t2 = await svc.saveTable(areaId: a, label: 'T2');
      final t3 = await svc.saveTable(areaId: a, label: 'T3');
      await product('p', 'Tea', 10000);
      const item = CartItem(productId: 'p', name: 'Tea', qtyMilli: 1000, unitPriceMinor: 10000);
      final o1 = await pos.saveDraft(DraftOrder(orderType: 'dine_in', tableId: t1, items: const [item]), staffId: owner);
      await pos.saveDraft(DraftOrder(orderType: 'dine_in', tableId: t2, items: const [item]), staffId: owner);
      await expectLater(svc.transfer(orderId: o1, toTableId: t2, staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'table_busy')));
      await svc.transfer(orderId: o1, toTableId: t3, staffId: owner);
      final byLabel = {for (final t in await svc.tables()) t.label: t.status};
      expect(byLabel, {'T1': 'free', 'T2': 'occupied', 'T3': 'occupied'});
      await pos.settleOrder(orderId: o1, payments: [SettlePayment(methodId: cashId, amountMinor: 10000)], staffId: owner);
      await expectLater(svc.transfer(orderId: o1, toTableId: t1, staffId: owner), throwsA(isA<PosException>().having((e) => e.code, 'code', 'not_editable')));
    });

    test('waiter assignment shows on the table', () async {
      final a = await svc.saveArea(name: 'Hall');
      final t = await svc.saveTable(areaId: a, label: 'T1');
      await svc.assignWaiter(t, owner);
      expect((await svc.tables()).single.waiterName, 'Owner');
      await svc.assignWaiter(t, null);
      expect((await svc.tables()).single.waiterName, isNull);
    });
  });

  group('bill history', () {
    test('lists settled bills with refund state and filters by search', () async {
      await product('p', 'Tea', 10000);
      final a = await sell('p', 10000, [SettlePayment(methodId: cashId, amountMinor: 10000)]);
      await sell('p', 10000, [SettlePayment(methodId: cardId, amountMinor: 10000)]);
      await pos.refundOrder(orderId: a, staffId: owner, reason: 'Wrong', amountMinor: 4000);
      final rows = await BillHistory(h).forDate('2026-01-12');
      expect(rows.length, 2);
      final refunded = rows.firstWhere((r) => r.id == a);
      expect([refunded.refundedMinor, refunded.netMinor, refunded.canRefund], [4000, 6000, true]);
      expect((await BillHistory(h).forDate('2026-01-12', search: '0002')).single.invoiceNo, 'INV-20260112-0002');
      expect(await BillHistory(h).forDate('2026-01-13'), isEmpty);
      await pos.refundOrder(orderId: a, staffId: owner, reason: 'Rest');
      expect((await BillHistory(h).forDate('2026-01-12')).firstWhere((r) => r.id == a).canRefund, isFalse);
    });
  });
}

void reportTests() {
  group('reports', () {
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      clock = DateTime(2026, 1, 12, 10);
      var n = 0;
      String nid() => 'id-${++n}';
      h = DbHelper(db, now: () => clock, newId: nid);
      pos = PosService(db, now: () => clock, newId: nid);
      auth = AuthService(db, now: () => clock, iterations: 1000);
      owner = await SetupService(db, auth, now: () => clock, newId: nid).completeSetup(businessName: 'T', ownerName: 'Owner', pin: '1234');
      cashId = await methodId('cash');
      await db.customStatement("INSERT INTO category(id,name,updated_at) VALUES ('c1','Burgers',1), ('c2','Drinks',1)");
      await db.customStatement("INSERT INTO product(id,name,base_price_minor,category_id,updated_at) VALUES ('b','Burger',45000,'c1',1), ('d','Cola',10000,'c2',1)");
    });
    tearDown(() => db.close());

    Future<void> saleOf(Map<String, int> qty) async {
      final items = [for (final e in qty.entries) CartItem(productId: e.key, name: e.key == 'b' ? 'Burger' : 'Cola', qtyMilli: e.value * 1000, unitPriceMinor: e.key == 'b' ? 45000 : 10000)];
      final o = await pos.saveDraft(DraftOrder(orderType: 'counter', items: items), staffId: owner);
      final total = qty.entries.fold<int>(0, (s, e) => s + e.value * (e.key == 'b' ? 45000 : 10000));
      await pos.settleOrder(orderId: o, payments: [SettlePayment(methodId: cashId, amountMinor: total)], staffId: owner);
    }

    test('item, category and cashier breakdowns; voided bills are excluded; CSV is plain numbers', () async {
      await saleOf({'b': 2, 'd': 1});
      await saleOf({'b': 1});
      clock = DateTime(2026, 1, 13, 10);
      await saleOf({'d': 3});
      final voided = await pos.saveDraft(DraftOrder(orderType: 'counter', items: const [CartItem(productId: 'b', name: 'Burger', qtyMilli: 1000, unitPriceMinor: 45000)]), staffId: owner);
      await pos.settleOrder(orderId: voided, payments: [SettlePayment(methodId: cashId, amountMinor: 45000)], staffId: owner);
      await pos.refundOrder(orderId: voided, staffId: owner, reason: 'Wrong');

      final svc = ReportService(h);
      final items = await svc.itemWise('2026-01-12', '2026-01-13');
      expect({for (final i in items) i.label: [i.qtyMilli ~/ 1000, i.amountMinor]}, {'Burger': [3, 135000], 'Cola': [4, 40000]});
      expect((await svc.itemWise('2026-01-12', '2026-01-12')).map((i) => i.label), ['Burger', 'Cola']);
      expect({for (final c in await svc.categoryWise('2026-01-12', '2026-01-13')) c.label: c.amountMinor}, {'Burgers': 135000, 'Drinks': 40000});
      final who = (await svc.cashierWise('2026-01-12', '2026-01-13')).single;
      expect([who.label, who.bills, who.amountMinor], ['Owner', 3, 175000]);

      final t = await svc.totals('2026-01-12', '2026-01-13');
      expect([t.sales, t.refunds], [220000, 45000]);

      final csv = reportCsv(items, labelHeader: 'Item');
      expect(csv.split('\n').first, 'Item,Quantity,Bills,Amount');
      expect(csv, contains('Burger,3,2,1350.00'));
      expect(reportCsv([const ReportLine(label: 'Chicken, boneless "special"', qtyMilli: 1500, amountMinor: 123456, bills: 1)], labelHeader: 'Item'), contains('"Chicken, boneless ""special""",1.500,1,1234.56'));
    });
  });
}
