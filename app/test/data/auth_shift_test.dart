import 'package:drift/drift.dart' show Variable;
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

    test('day close does not depend on a cash shift being closed by hand: the open shift is closed WITH the day, uncounted, nothing invented', () async {
      final s = await shifts.openShift('s1', openingCashMinor: 20000);
      await sell(s, 'cash', 10000);
      final z = await shifts.closeDay('2026-01-12', staffId: 's1');
      expect(z.closedAt, isNotNull);
      final sh = (await db.customSelect('SELECT * FROM shift').getSingle()).data;
      expect(sh['closed_at'], isNotNull, reason: 'the shift was closed by the day close');
      expect(sh['expected_cash_minor'], 30000, reason: 'opening 200 + cash sale 100');
      expect(sh['closing_cash_counted_minor'], isNull, reason: 'nobody counted: no count is made up');
      expect(sh['variance_minor'], isNull);
      expect(sh['note'], startsWith('Closed by day close'));
      expect(z.shifts.single.autoClosed, isTrue);
      expect(await one('SELECT gross_sales_minor AS s FROM day_close'), 10000);
      expect(await one('SELECT net_sales_minor AS s FROM day_close'), 10000);
      await expectLater(shifts.closeDay('2026-01-12', staffId: 's1'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'day_closed')));
    });

    test('a cash count entered at day close is kept with its variance', () async {
      final s = await shifts.openShift('s1', openingCashMinor: 20000);
      await sell(s, 'cash', 10000);
      await shifts.closeDay('2026-01-12', staffId: 's1', countedByShift: {s: 29500});
      final sh = (await db.customSelect('SELECT * FROM shift').getSingle()).data;
      expect([sh['closing_cash_counted_minor'], sh['variance_minor']], [29500, -500]);
    });

    test('the stale-shift case: a shift left open from an earlier day, and another user\'s shift, no longer block closing', () async {
      await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s2','Sara','r','h','s',1)");
      clock = DateTime(2026, 1, 10, 22);
      final stale = await shifts.openShift('s2', openingCashMinor: 5000); // opened two days ago, never closed
      clock = DateTime(2026, 1, 12, 9);
      final mine = await shifts.openShift('s1');
      await sell(mine, 'cash', 10000);
      await shifts.closeDay('2026-01-12', staffId: 's1');
      expect(await one('SELECT COUNT(*) AS s FROM shift WHERE closed_at IS NULL'), 0);
      expect((await db.customSelect('SELECT closed_at FROM shift WHERE id = ?', variables: [Variable.withString(stale)]).getSingle()).data['closed_at'], isNotNull);
    });

    test('a shift that starts AFTER the closed day is left alone', () async {
      await shifts.closeDay('2026-01-11', staffId: 's1');
      final today = await shifts.openShift('s1');
      expect((await db.customSelect('SELECT closed_at FROM shift WHERE id = ?', variables: [Variable.withString(today)]).getSingle()).data['closed_at'], isNull);
    });

    test('the figures must add up: a bill whose payments do not cover it blocks the close, with a plain explanation', () async {
      final s = await shifts.openShift('s1');
      final o = await sell(s, 'cash', 10000);
      await sql("UPDATE \"order\" SET total_minor = 99999 WHERE id = '$o'"); // e.g. damaged data: the bill says 999.99, the payments say 100
      final z = await shifts.zReport('2026-01-12');
      expect(z.problems, isNotEmpty);
      await expectLater(shifts.closeDay('2026-01-12', staffId: 's1'), throwsA(isA<PosException>().having((e) => e.code, 'code', 'reconcile_failed')));
      expect(await one('SELECT COUNT(*) AS s FROM day_close'), 0, reason: 'nothing half-saved');
      expect(await one('SELECT COUNT(*) AS s FROM shift WHERE closed_at IS NULL'), 1, reason: 'the shift was not touched either: all or nothing');
    });

    test('the saved Z report is permanent: a refund made later does not change the closed day', () async {
      final s = await shifts.openShift('s1');
      final o = await sell(s, 'cash', 10000);
      await shifts.closeDay('2026-01-12', staffId: 's1');
      clock = DateTime(2026, 1, 13, 10);
      final s2 = await shifts.openShift('s1');
      await pos.refundOrder(orderId: o, staffId: 's1', reason: 'Late refund', methodId: 'cash', shiftId: s2);
      final z = await shifts.zReport('2026-01-12');
      expect([z.grossMinor, z.refundsMinor, z.netMinor, z.bills], [10000, 0, 10000, 1], reason: 'shows what was closed, not a recalculation');
    });

    test('next business day: after closing, new sales and expenses belong to the next day, numbered from 1', () async {
      final s = await shifts.openShift('s1');
      await sell(s, 'cash', 10000);
      await shifts.closeDay('2026-01-12', staffId: 's1');
      final s2 = await shifts.openShift('s1');
      final o2 = await sell(s2, 'cash', 10000); // same calendar day, after the Z report
      final row = (await db.customSelect('SELECT business_date, invoice_no FROM "order" WHERE id = ?', variables: [Variable.withString(o2)]).getSingle()).data;
      expect(row['business_date'], '2026-01-13');
      expect(row['invoice_no'], 'INV-20260113-0001');
      expect((await shifts.zReport('2026-01-12')).bills, 1, reason: 'the closed day did not grow');
      expect((await shifts.zReport('2026-01-13')).bills, 1);
    });

    test('an order held before the close and paid after it is that next day\'s sale', () async {
      final s = await shifts.openShift('s1');
      final held = await pos.saveDraft(const DraftOrder(orderType: 'counter', items: [CartItem(productId: 'p', name: 'Tea', qtyMilli: 1000, unitPriceMinor: 10000)], held: true), staffId: 's1');
      await shifts.closeDay('2026-01-12', staffId: 's1');
      final s2 = await shifts.openShift('s1');
      await pos.settleOrder(orderId: held, payments: [const SettlePayment(methodId: 'cash', amountMinor: 10000)], staffId: 's1', shiftId: s2);
      expect((await db.customSelect('SELECT business_date FROM "order" WHERE id = ?', variables: [Variable.withString(held)]).getSingle()).data['business_date'], '2026-01-13');
      expect(s, isNotEmpty);
    });
  });
}
