import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/team_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late TeamService team;
  late PosService pos;
  final clock = DateTime(2026, 1, 12, 19, 40);
  Future<void> sql(String s) => db.customStatement(s);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    team = TeamService(DbHelper(db, now: () => clock));
    pos = PosService(db, now: () => clock);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
  });
  tearDown(() => db.close());

  test('riders: add, edit, hide, delete; no duplicate names; a name is required', () async {
    final id = await team.saveRider(name: 'Kamran', phone: '0301', bikeNo: 'LEA-1', staffId: 's1');
    expect((await team.riders()).single.bikeNo, 'LEA-1');
    await team.saveRider(id: id, name: 'Kamran Ali', staffId: 's1');
    expect((await team.riders()).single.name, 'Kamran Ali');
    await expectLater(team.saveRider(name: 'kamran ali', staffId: 's1'), throwsA(isA<PosException>()));
    await expectLater(team.saveRider(name: '  ', staffId: 's1'), throwsA(isA<PosException>()));
    await team.setActive(id, false, staffId: 's1');
    expect(await team.riders(activeOnly: true), isEmpty);
    expect((await team.riders()).single.active, isFalse);
    await team.delete(id, staffId: 's1');
    expect(await team.riders(), isEmpty);
  });

  test('a delivery order remembers its rider (saved, reloaded, kept when edited) and the rider\'s daily count leaves out cancelled bills', () async {
    final rid = await team.saveRider(name: 'Kamran', staffId: 's1');
    final item = CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 1000, unitPriceMinor: 45000);
    final a = await pos.saveDraft(DraftOrder(orderType: 'delivery', items: [item], riderId: rid), staffId: 's1');
    final b = await pos.saveDraft(DraftOrder(orderType: 'delivery', items: [item, item], riderId: rid), staffId: 's1');
    expect((await pos.loadDraft(a))!.riderId, rid);
    // editing the draft without mentioning the rider keeps it
    await pos.saveDraft(DraftOrder(id: a, orderType: 'delivery', items: [item]), staffId: 's1');
    expect((await pos.loadDraft(a))!.riderId, rid);
    final day = (await db.customSelect('SELECT business_date AS d FROM "order" LIMIT 1').getSingle()).data['d'] as String;
    var r = (await team.riders(day: day)).single;
    expect(r.deliveries, 2);
    expect(r.totalMinor, 3 * 45000);
    await db.customStatement("UPDATE \"order\" SET status = 'cancelled' WHERE id = '$b'");
    r = (await team.riders(day: day)).single;
    expect(r.deliveries, 1);
  });

  test('upgrading an older database twice is harmless and keeps its orders', () async {
    await pos.saveDraft(DraftOrder(orderType: 'counter', items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 1000, unitPriceMinor: 45000)]), staffId: 's1');
    await migrateToV6(db);
    await migrateToV6(db);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM "order"').getSingle()).data['n'], 1);
  });

  test('waiters are a simple list like riders: kept apart, counted by their bills, shown on the table and the printed order', () async {
    final w = await team.saveWaiter(name: 'Sara', staffId: 's1');
    await team.saveRider(name: 'Sara', staffId: 's1'); // the same name as a rider is allowed
    expect((await team.waiters()).map((x) => x.name), ['Sara']);
    expect((await team.riders()).map((x) => x.name), ['Sara']);
    await expectLater(team.saveWaiter(name: 'sara', staffId: 's1'), throwsA(isA<PosException>()));
    final id = await pos.saveDraft(DraftOrder(orderType: 'dine_in', waiterId: w, items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000)]), staffId: 's1');
    final back = await pos.loadDraft(id);
    expect(back!.waiterId, w);
    final today = (await db.customSelect('SELECT business_date d FROM "order" WHERE id = ?', variables: [Variable.withString(id)]).getSingle()).data['d'] as String;
    expect((await team.waiters(day: today)).single.deliveries, 1);
  });

  test('upgrading from schema 6 keeps riders and their orders and lets waiters in', () async {
    await db.customStatement("INSERT INTO team_member(id, kind, name, updated_at) VALUES ('r1','rider','Ali Bike',1)");
    // go back to the version 6 shape: the CHECK only allows riders, no waiter columns
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('ALTER TABLE team_member RENAME TO tm_new');
    await db.customStatement("CREATE TABLE team_member (id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'rider' CHECK (kind IN ('rider')), name TEXT NOT NULL, phone TEXT, bike_no TEXT, active INTEGER NOT NULL DEFAULT 1, version INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL, deleted_at INTEGER)");
    await db.customStatement('INSERT INTO team_member(id, kind, name, phone, bike_no, active, version, updated_at, deleted_at) SELECT id, kind, name, phone, bike_no, active, version, updated_at, deleted_at FROM tm_new');
    await db.customStatement('DROP TABLE tm_new');
    await db.customStatement('PRAGMA foreign_keys = ON');
    await migrateToV7(db);
    await migrateToV7(db);
    await migrateToV10(db); // the picture column, as the real upgrade adds it after version 7
    await migrateToV10(db);
    expect((await team.riders()).map((x) => x.name), contains('Ali Bike'));
    await team.saveWaiter(name: 'Bilal', staffId: 's1');
    expect((await team.waiters()).single.name, 'Bilal');
  });
}
