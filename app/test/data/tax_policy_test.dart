import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:dt_food_pos/domain/bill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no tax on any bill unless the owner switches it on; then one rate for every item; a manual service charge adds to the bill', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // an item that still has an old 16% tax rate attached (as older setups did)
    await db.customStatement("INSERT INTO tax_rate(id,name,rate_bp,inclusive,updated_at) VALUES ('t16','GST',1600,0,1)");
    await db.customStatement("INSERT INTO product(id,name,base_price_minor,tax_rate_id,updated_at) VALUES ('p','Burger',100000,'t16',1)");

    expect((await loadProducts(db)).single.taxBp, 0, reason: 'off by default: the old rate is ignored');
    BillResult bill(List<MenuProduct> ps, [BillConfig c = const BillConfig()]) => calculateBill([for (final p in ps) BillLineInput(id: p.id, unitPriceMinor: p.priceMinor, qtyMilli: 1000, taxRateBp: p.taxBp, taxInclusive: p.taxInclusive)], c);
    expect(bill(await loadProducts(db)).totalMinor, 100000, reason: 'the bill is just the price');
    expect(bill(await loadProducts(db)).taxMinor, 0);

    await setSetting(db, TaxPolicy.keyOn, '1', 1);
    await setSetting(db, TaxPolicy.keyRate, '500', 1); // 5 %
    var p = (await loadProducts(db)).single;
    expect([p.taxBp, p.taxInclusive], [500, false]);
    expect(bill([p]).totalMinor, 105000, reason: '5 % added on top');
    await setSetting(db, TaxPolicy.keyInclusive, '1', 1);
    p = (await loadProducts(db)).single;
    expect(bill([p]).totalMinor, 100000, reason: 'prices already include it: the total does not change');
    expect(bill([p]).taxMinor, greaterThan(0), reason: 'but the tax inside is shown');

    // a service charge by hand: a percentage, or money
    expect(bill(await loadProducts(db), const BillConfig(serviceChargeBp: 1000)).serviceChargeMinor, 10000);
    expect(bill(await loadProducts(db), const BillConfig(serviceChargeFixedMinor: 15000)).totalMinor, 115000);
  });
}
