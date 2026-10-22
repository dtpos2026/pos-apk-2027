import 'package:drift/native.dart';
import 'package:dt_food_pos/data/auth_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:dt_food_pos/data/setup_service.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late SetupService setup;
Future<int> count(String q) async => (await db.customSelect(q).getSingle()).data['n'] as int;

void main() {
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    setup = SetupService(db, AuthService(db, iterations: 1000));
  });
  tearDown(() => db.close());

  test('first-run setup creates roles, owner, payment methods and the business', () async {
    expect(await setup.isConfigured(), isFalse);
    final id = await setup.completeSetup(businessName: 'Burger Point', ownerName: 'Ali', pin: '1234', phone: '0300-0000000');
    expect(await setup.isConfigured(), isTrue);
    expect(await count('SELECT COUNT(*) AS n FROM role'), 5);
    expect(await count("SELECT COUNT(*) AS n FROM payment_method WHERE kind = 'cash'"), 1);
    expect(await count("SELECT COUNT(*) AS n FROM payment_method WHERE kind = 'credit'"), 1);
    expect(await count('SELECT COUNT(*) AS n FROM tax_rate'), 0); // Pakistan: owner enters their own rate
    final b = (await loadBusiness(db))!;
    expect(b.name, 'Burger Point');
    expect(b.currency.code, 'PKR');
    final s = (await loadSession(db, id))!;
    expect(s.roleName, 'Owner');
    expect(s.can('anything'), isTrue);
  });

  test('UAE setup uses AED and a 5% inclusive VAT rate', () async {
    await setup.completeSetup(businessName: 'Shawarma House', ownerName: 'Omar', pin: '4321', country: 'AE');
    expect((await loadBusiness(db))!.currency.code, 'AED');
    final t = (await db.customSelect('SELECT rate_bp, inclusive FROM tax_rate').getSingle()).data;
    expect(t, {'rate_bp': 500, 'inclusive': 1});
  });

  test('cashier role cannot discount, void or manage the menu', () async {
    final id = await setup.completeSetup(businessName: 'X', ownerName: 'Y', pin: '1234');
    final cashierRole = (await db.customSelect("SELECT id FROM role WHERE name = 'Cashier'").getSingle()).data['id'] as String;
    final cid = await AuthService(db, iterations: 1000).createStaff(name: 'Sara', roleId: cashierRole, pin: '5555');
    final s = (await loadSession(db, cid))!;
    expect(s.can('pos.sell'), isTrue);
    expect(s.can('discount.apply'), isFalse);
    expect(s.can('bill.void'), isFalse);
    expect(s.can('menu.manage'), isFalse);
    expect(id, isNot(cid));
  });

  test('setup cannot run twice and validates input', () async {
    await setup.completeSetup(businessName: 'X', ownerName: 'Y', pin: '1234');
    await expectLater(setup.completeSetup(businessName: 'Z', ownerName: 'Y', pin: '1234'), throwsStateError);
    final db2 = AppDatabase(NativeDatabase.memory());
    final s2 = SetupService(db2, AuthService(db2, iterations: 1000));
    await expectLater(s2.completeSetup(businessName: ' ', ownerName: 'Y', pin: '1234'), throwsArgumentError);
    await expectLater(s2.completeSetup(businessName: 'X', ownerName: 'Y', pin: '12'), throwsArgumentError);
    expect(await s2.isConfigured(), isFalse); // failed setup leaves nothing half-created
    await db2.close();
  });
}
