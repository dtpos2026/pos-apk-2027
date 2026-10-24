import 'package:drift/native.dart';
import 'package:dt_food_pos/data/dashboard_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 1, 12, 12);
  late DashboardService svc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    svc = DashboardService(DbHelper(db, now: () => now));
  });
  tearDown(() => db.close());

  Future<void> sale(String id, String date, int total) => db.customStatement(
      "INSERT INTO \"order\"(id, order_type, status, business_date, total_minor, created_at, updated_at) VALUES (?, 'counter', 'paid', ?, ?, 1, 1)", [id, date, total]);

  test('today is compared with yesterday in percent; no sales yesterday means no percentage', () async {
    expect((await svc.load()).vsYesterdayPct, isNull);
    await sale('a', '2026-01-11', 100000);
    await sale('b', '2026-01-12', 125000);
    var d = await svc.load();
    expect(d.yesterdayMinor, 100000);
    expect(d.vsYesterdayPct, 25);
    await sale('c', '2026-01-12', -25000); // a refund-style negative sale brings today level with yesterday
    d = await svc.load();
    expect(d.vsYesterdayPct, 0);
  });
}
