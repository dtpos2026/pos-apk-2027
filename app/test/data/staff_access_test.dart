import 'package:drift/native.dart';
import 'package:dt_food_pos/data/auth_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:dt_food_pos/data/setup_service.dart';
import 'package:dt_food_pos/data/staff_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StaffService staff;
  late String owner;
  late String cashierRole;
  final clock = DateTime(2026, 1, 12, 19, 40);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final auth = AuthService(db, now: () => clock, iterations: 1000);
    owner = await SetupService(db, auth, now: () => clock).completeSetup(businessName: 'B', ownerName: 'Ali', pin: '1234');
    staff = StaffService(DbHelper(db, now: () => clock), auth);
    cashierRole = (await staff.roles()).firstWhere((r) => r.name == 'Cashier').id;
  });
  tearDown(() => db.close());

  Future<Session> session(String id) async => (await loadSession(db, id))!;

  test('a normal role opens exactly what it always opened (nothing changes for existing staff)', () async {
    final id = await staff.add(actor: owner, name: 'Sara', roleId: cashierRole, pin: '5555');
    final s = await session(id);
    for (final k in ['pos', 'tables', 'kitchen', 'bills', 'customers', 'expenses']) {
      expect(s.canOpen(k, 'pos.sell'), isTrue, reason: k);
    }
    expect(s.canOpen('reports', 'reports.view'), isFalse);
    expect(s.canOpen('menu', 'menu.manage'), isFalse);
    final a = await staff.accessOf(id);
    expect(a.custom, isFalse);
    expect(a.screens, containsAll(['pos', 'tables', 'bills']));
  });

  test('own access: only the ticked screens and actions, the rest closed; the role list does not fill up with private roles', () async {
    final id = await staff.add(actor: owner, name: 'Sara', roleId: cashierRole, pin: '5555');
    final rolesBefore = (await staff.roles()).length;
    await staff.setAccess(actor: owner, staffId: id, screens: {'pos', 'bills', 'reports'}, actions: {'discount.apply'});
    final s = await session(id);
    expect(s.canOpen('pos', 'pos.sell'), isTrue);
    expect(s.canOpen('bills', 'pos.sell'), isTrue);
    expect(s.canOpen('reports', 'reports.view'), isTrue);
    expect(s.canOpen('tables', 'pos.sell'), isFalse, reason: 'not ticked, even though the old Cashier role had it');
    expect(s.canOpen('customers', 'pos.sell'), isFalse);
    expect(s.can('discount.apply'), isTrue);
    expect(s.can('bill.void'), isFalse);
    expect(s.can('reports.view'), isTrue, reason: 'Reports opens, so the report permission comes with it');
    expect((await staff.roles()).length, rolesBefore, reason: 'private roles are not offered when adding staff');
    final a = await staff.accessOf(id);
    expect(a.custom, isTrue);
    expect(a.screens, {'pos', 'bills', 'reports'});
    // changing it again changes the same private role
    await staff.setAccess(actor: owner, staffId: id, screens: {'pos'}, actions: {});
    expect((await session(id)).canOpen('bills', 'pos.sell'), isFalse);
    expect(await db.customSelect('SELECT COUNT(*) AS n FROM role WHERE is_system = 0').getSingle().then((r) => r.data['n']), 1);
  });

  test('nobody can give themselves more power: Staff and Settings cannot be ticked, an owner keeps full access, a cashier cannot edit access', () async {
    final id = await staff.add(actor: owner, name: 'Sara', roleId: cashierRole, pin: '5555');
    await staff.setAccess(actor: owner, staffId: id, screens: {'pos', 'staff', 'settings'}, actions: {'staff.manage', 'bill.void'});
    final s = await session(id);
    expect(s.canOpen('staff', 'staff.manage'), isFalse);
    expect(s.canOpen('settings', 'settings.manage'), isFalse);
    expect(s.can('staff.manage'), isFalse);
    expect(s.can('bill.void'), isTrue);
    await expectLater(staff.setAccess(actor: owner, staffId: owner, screens: {'pos'}, actions: {}), throwsA(isA<PosException>()), reason: 'an owner always has full access');
    await expectLater(staff.setAccess(actor: id, staffId: id, screens: {'pos', 'menu'}, actions: {}), throwsA(isA<PosException>()), reason: 'staff.manage is needed');
    await expectLater(staff.setAccess(actor: owner, staffId: id, screens: {}, actions: {}), throwsA(isA<PosException>()), reason: 'at least one screen');
  });
}
