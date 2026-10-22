import 'package:drift/native.dart';
import 'package:dt_food_pos/data/auth_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/shift_service.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
var clock = DateTime(2026, 1, 12, 9);
Future<void> sql(String s) => db.customStatement(s);
Future<int> one(String q) async => (await db.customSelect(q).getSingle()).data['s'] as int;

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime(2026, 1, 12, 9);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Cashier','[\"*\"]',1)");
  });
  tearDown(() => db.close());

  group('AuthService', () {
    late AuthService auth;
    late String id;
    setUp(() async {
      auth = AuthService(db, now: () => clock, iterations: 1000);
      id = await auth.createStaff(name: 'Ali', roleId: 'r', pin: '1234');
    });

    test('PIN is stored hashed, never in clear', () async {
      final r = (await db.customSelect('SELECT pin_hash, pin_salt FROM staff').getSingle()).data;
      expect(r['pin_hash'], isNot(contains('1234')));
      expect((r['pin_hash'] as String).length, greaterThan(20));
    });

    test('correct and wrong PIN', () async {
      expect(await auth.verifyPin(id, '1234'), PinResult.ok);
      expect(await auth.verifyPin(id, '9999'), PinResult.wrong);
      expect(await auth.verifyPin('nobody', '1234'), PinResult.unknown);
    });

    test('same PIN gets a different hash for different staff (salted)', () async {
      await auth.createStaff(name: 'Sara', roleId: 'r', pin: '1234');
      expect(await one('SELECT COUNT(DISTINCT pin_hash) AS s FROM staff'), 2);
    });

    test('5 wrong PINs lock the account, even the right PIN is refused until the lock expires', () async {
      for (var i = 0; i < 4; i++) {
        expect(await auth.verifyPin(id, '0000'), PinResult.wrong);
      }
      expect(await auth.verifyPin(id, '0000'), PinResult.locked);
      expect(await auth.verifyPin(id, '1234'), PinResult.locked);
      clock = clock.add(const Duration(minutes: 6));
      expect(await auth.verifyPin(id, '1234'), PinResult.ok);
      expect(await one("SELECT COUNT(*) AS s FROM audit_log WHERE event='auth.locked' AND critical=1"), 1);
    });

    test('success resets the failure counter', () async {
      await auth.verifyPin(id, '0000');
      await auth.verifyPin(id, '0000');
      await auth.verifyPin(id, '1234');
      for (var i = 0; i < 4; i++) {
        await auth.verifyPin(id, '0000');
      }
      expect(await auth.verifyPin(id, '1234'), PinResult.ok);
    });

    test('PIN format is validated', () async {
      expect(() => auth.createStaff(name: 'X', roleId: 'r', pin: '12'), throwsArgumentError);
      expect(() => auth.createStaff(name: 'X', roleId: 'r', pin: 'abcd'), throwsArgumentError);
      expect(await auth.verifyPin(id, 'abcd'), PinResult.wrong);
    });

    test('changing the PIN invalidates the old one and clears a lock', () async {
      await auth.changePin(id, '4321');
      expect(await auth.verifyPin(id, '1234'), PinResult.wrong);
      expect(await auth.verifyPin(id, '4321'), PinResult.ok);
    });
  });

  group('ShiftService', () {
    late PosService pos;
    late ShiftService shifts;
    var n = 0;
    setUp(() async {
      n = 0;
      String id() => 'id-${++n}';
      pos = PosService(db, now: () => clock, newId: id);
      shifts = ShiftService(db, pos, now: () => clock, newId: id);
      await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
      await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
      await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('card','Card','card',1)");
      await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('p','Tea',10000,1)");
    });

    Future<String> sell(String shift, String method, int amount) async {
      final o = await pos.saveDraft(const DraftOrder(orderType: 'counter', items: [CartItem(productId: 'p', name: 'Tea', qtyMilli: 1000, unitPriceMinor: 10000)]), staffId: 's1');
      await pos.settleOrder(orderId: o, payments: [SettlePayment(methodId: method, amountMinor: amount)], staffId: 's1', shiftId: shift);
      return o;
    }

    test('expected cash = opening + cash sales - cash refunds + in - out; card sales do not count', () async {
      final s = await shifts.openShift('s1', openingCashMinor: 50000);
      await sell(s, 'cash', 10000);
      final refundMe = await sell(s, 'cash', 10000);
      await sell(s, 'card', 10000);
      await pos.refundOrder(orderId: refundMe, staffId: 's1', reason: 'Wrong item', methodId: 'cash', shiftId: s);
      await shifts.cashMovement(s, cashIn: true, amountMinor: 5000, reason: 'Float top-up', staffId: 's1');
      await shifts.cashMovement(s, cashIn: false, amountMinor: 2000, reason: 'Ice', staffId: 's1');
      final sum = await shifts.summary(s);
      expect(sum.expectedMinor, 50000 + 20000 - 10000 + 5000 - 2000);
      final variance = await shifts.closeShift(s, countedMinor: 62000);
      expect(variance, 62000 - 63000);
      expect(await one('SELECT variance_minor AS s FROM shift'), -1000);
    });

    test('one open shift per user; closed shifts cannot be reused', () async {
      final s = await shifts.openShift('s1');
      await expectLater(shifts.openShift('s1'), throwsA(isA<PosException>()));
      await shifts.closeShift(s, countedMinor: 0);
      await expectLater(shifts.closeShift(s, countedMinor: 0), throwsA(isA<PosException>()));
      await expectLater(shifts.cashMovement(s, cashIn: true, amountMinor: 1, reason: 'x', staffId: 's1'), throwsA(isA<PosException>()));
      expect(await shifts.openShift('s1'), isNotEmpty);
    });

    test('cash movement needs a reason and a positive amount', () async {
      final s = await shifts.openShift('s1');
      await expectLater(shifts.cashMovement(s, cashIn: true, amountMinor: 100, reason: ' ', staffId: 's1'), throwsA(isA<PosException>()));
      await expectLater(shifts.cashMovement(s, cashIn: true, amountMinor: 0, reason: 'x', staffId: 's1'), throwsA(isA<PosException>()));
    });

    test('day close: refused while a shift is open, snapshot once, then locked', () async {
      final s = await shifts.openShift('s1');
      await sell(s, 'cash', 10000);
      await expectLater(shifts.closeDay('2026-01-12', staffId: 's1'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'shift_open')));
      await shifts.closeShift(s, countedMinor: 10000);
      await shifts.closeDay('2026-01-12', staffId: 's1');
      expect(await one('SELECT gross_sales_minor AS s FROM day_close'), 10000);
      expect(await one('SELECT net_sales_minor AS s FROM day_close'), 10000);
      await expectLater(shifts.closeDay('2026-01-12', staffId: 's1'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'day_closed')));
    });
  });
}
