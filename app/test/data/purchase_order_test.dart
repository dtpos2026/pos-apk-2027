import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/inventory_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late InventoryService inv;
  late String chicken, oil, supplier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final h = DbHelper(db, now: () => DateTime(2026, 1, 12, 10));
    inv = InventoryService(h);
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await db.customStatement("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    chicken = await inv.saveItem(name: 'Chicken', unit: 'kg', staffId: 's1');
    oil = await inv.saveItem(name: 'Oil', unit: 'l', staffId: 's1');
    supplier = await inv.saveSupplier(name: 'Ahmed Traders', phone: '03001234567');
  });
  tearDown(() => db.close());

  test('a purchase order is numbered, listed, sent, then received: stock goes up and the supplier is owed', () async {
    final id = await inv.createPurchaseOrder(supplierId: supplier, lines: [PurchaseInput(stockItemId: chicken, qtyMilli: 10000, unitCostMinor: 40000), PurchaseInput(stockItemId: oil, qtyMilli: 5000, unitCostMinor: 50000)], note: 'Morning delivery', staffId: 's1');
    var po = (await inv.purchaseOrders()).single;
    expect([po.poNo, po.status, po.lines, po.totalMinor, po.supplierName], ['PO-0001', 'draft', 2, 650000, 'Ahmed Traders']);
    expect(await inv.onHand(chicken), 0, reason: 'ordering books nothing into stock');

    final text = await inv.purchaseOrderText(id, businessName: 'Burger Point');
    expect(text, allOf(contains('PO-0001'), contains('10 kg Chicken'), contains('5 l Oil'), contains('Ahmed Traders'), contains('Morning delivery')));

    await inv.markPurchaseOrderSent(id);
    expect((await inv.purchaseOrders()).single.status, 'sent');

    await inv.receivePurchaseOrder(id, paidMinor: 100000, actualCostMinor: {chicken: 42000}, staffId: 's1');
    po = (await inv.purchaseOrders()).single;
    expect(po.status, 'received');
    expect(await inv.onHand(chicken), 10000);
    expect(await inv.onHand(oil), 5000);
    expect(await inv.supplierBalance(supplier), 420000 + 250000 - 100000, reason: 'the invoice at the real price, less what was paid now');

    await expectLater(inv.receivePurchaseOrder(id, staffId: 's1'), throwsA(isA<PosException>()), reason: 'receiving twice would double the stock');
    await expectLater(inv.cancelPurchaseOrder(id, staffId: 's1'), throwsA(isA<PosException>()));
  });

  test('a cancelled order cannot be received; a second order gets the next number; empty orders are refused', () async {
    final a = await inv.createPurchaseOrder(lines: [PurchaseInput(stockItemId: chicken, qtyMilli: 1000, unitCostMinor: 100)], staffId: 's1');
    await inv.cancelPurchaseOrder(a, staffId: 's1');
    await expectLater(inv.receivePurchaseOrder(a, staffId: 's1'), throwsA(isA<PosException>()));
    await inv.createPurchaseOrder(lines: [PurchaseInput(stockItemId: oil, qtyMilli: 1000, unitCostMinor: 100)], staffId: 's1');
    expect((await inv.purchaseOrders()).map((o) => o.poNo).toSet(), {'PO-0001', 'PO-0002'});
    await expectLater(inv.createPurchaseOrder(lines: const [], staffId: 's1'), throwsA(isA<PosException>()));
  });
}
