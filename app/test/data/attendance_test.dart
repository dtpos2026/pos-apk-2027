import 'package:drift/native.dart';
import 'package:dt_food_pos/data/attendance_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  var clock = DateTime(2026, 1, 12, 9, 0);
  late AttendanceService svc;

  setUp(() async {
    clock = DateTime(2026, 1, 12, 9, 0);
    db = AppDatabase(NativeDatabase.memory());
    svc = AttendanceService(DbHelper(db, now: () => clock));
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,daily_wage_minor,updated_at) VALUES ('s1','Ali','r','h','s',150000,1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s2','Sara','r','h','s',1)");
  });
  tearDown(() => db.close());

  test('clock in and out: hours counted, wage taken from the staff member, no double clock-in', () async {
    await svc.clockIn('s1');
    expect((await svc.forDay('2026-01-12')).firstWhere((r) => r.staffId == 's1').atWork, isTrue);
    await expectLater(svc.clockIn('s1'), throwsA(isA<PosException>()));
    clock = DateTime(2026, 1, 12, 17, 30);
    await svc.clockOut('s1');
    final row = (await svc.forDay('2026-01-12')).firstWhere((r) => r.staffId == 's1');
    expect(row.atWork, isFalse);
    expect(row.minutes(clock), 510);
    expect(hoursText(row.minutes(clock)), '8h 30m');
    expect(row.wageMinor, 150000);
    await expectLater(svc.clockOut('s2'), throwsA(isA<PosException>()), reason: 'cannot clock out without being in');
    expect((await svc.forDay('2026-01-12')).firstWhere((r) => r.staffId == 's2').checkIn, isNull);
  });

  test('the month shows days, hours and wages per person', () async {
    for (final day in [12, 13]) {
      clock = DateTime(2026, 1, day, 9);
      await svc.clockIn('s1');
      clock = DateTime(2026, 1, day, 17);
      await svc.clockOut('s1');
    }
    final m = (await svc.month('2026-01', now: clock)).single;
    expect([m.staffName, m.days, m.minutes, m.wageMinor], ['Ali', 2, 960, 300000]);
    expect(await svc.month('2026-02', now: clock), isEmpty);
  });
}
