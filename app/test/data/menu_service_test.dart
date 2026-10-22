import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/menu_service.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late MenuService svc;
Future<int> count(String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;

void main() {
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    var n = 0;
    svc = MenuService(db, newId: () => 'id-${++n}', now: () => DateTime(2026, 1, 12));
  });
  tearDown(() => db.close());

  test('create, edit and price-change audit, with versioned outbox rows', () async {
    final id = await svc.saveProduct(name: 'Zinger', priceMinor: 45000, categoryName: 'Burgers', sku: 'Z1', staffId: 's');
    await svc.saveProduct(id: id, name: 'Zinger', priceMinor: 49000, categoryName: 'Burgers', sku: 'Z1', staffId: 's');
    final p = (await loadProducts(db)).single;
    expect(p.priceMinor, 49000);
    expect(p.categoryName, 'Burgers');
    expect(await count("SELECT COUNT(*) AS n FROM audit_log WHERE event = 'product.price_change'"), 1);
    expect(await count('SELECT COUNT(*) AS n FROM outbox'), 2);
    expect(await count('SELECT COUNT(*) AS n FROM category'), 1); // reused, not duplicated
  });

  test('validation: name, price and duplicate SKU', () async {
    await svc.saveProduct(name: 'A', priceMinor: 1, sku: 'S1', staffId: 's');
    await expectLater(svc.saveProduct(name: ' ', priceMinor: 1, staffId: 's'), throwsA(isA<MenuException>()));
    await expectLater(svc.saveProduct(name: 'B', priceMinor: -1, staffId: 's'), throwsA(isA<MenuException>()));
    await expectLater(svc.saveProduct(name: 'B', priceMinor: 1, sku: 'S1', staffId: 's'), throwsA(isA<MenuException>()));
    expect(await count('SELECT COUNT(*) AS n FROM product'), 1);
  });

  test('availability toggle and soft delete (tombstone) sync', () async {
    final id = await svc.saveProduct(name: 'A', priceMinor: 100, staffId: 's');
    await svc.setAvailable(id, false, staffId: 's');
    expect((await loadProducts(db)).single.available, isFalse);
    await svc.deleteProduct(id, staffId: 's');
    expect(await loadProducts(db), isEmpty);
    expect(await count("SELECT COUNT(*) AS n FROM outbox WHERE op = 'delete'"), 1);
    expect(await count("SELECT COUNT(*) AS n FROM audit_log WHERE event = 'product.delete' AND critical = 1"), 1);
  });

  test('search by name, SKU and barcode', () async {
    await svc.saveProduct(name: 'Chicken Karahi', priceMinor: 100, sku: 'KRH', staffId: 's');
    await db.customStatement("INSERT INTO product(id,name,base_price_minor,barcode,updated_at) VALUES ('b','Cola',100,'6281000',1)");
    expect((await loadProducts(db, search: 'kara')).map((p) => p.name), ['Chicken Karahi']);
    expect((await loadProducts(db, search: 'krh')).length, 1);
    expect((await loadProducts(db, search: '6281000')).map((p) => p.name), ['Cola']);
  });
}
