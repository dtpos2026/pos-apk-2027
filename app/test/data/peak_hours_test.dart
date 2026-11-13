import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/report_service.dart';
import 'package:dt_food_pos/domain/money.dart';
import 'package:dt_food_pos/domain/receipt_doc.dart';
import 'package:dt_food_pos/domain/report_pdf.dart';
import 'package:dt_food_pos/domain/report_slip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
  });
  tearDown(() => db.close());

  Future<void> sellAt(DateTime at) async {
    final pos = PosService(db, now: () => at);
    final id = await pos.saveDraft(const DraftOrder(orderType: 'counter', items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 1000, unitPriceMinor: 45000)]), staffId: 's1');
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 45000)], staffId: 's1');
  }

  test('peak hours: bills and sales per hour of the day, and the busiest hours on the report slip', () async {
    await sellAt(DateTime(2026, 1, 12, 13, 5));
    await sellAt(DateTime(2026, 1, 12, 13, 40));
    await sellAt(DateTime(2026, 1, 12, 20, 15));
    final hours = await ReportService(DbHelper(db, now: () => DateTime(2026, 1, 12, 22))).hourWise('2026-01-12', '2026-01-12');
    expect([for (final h in hours) (h.hour, h.bills, h.amountMinor)], [(13, 2, 90000), (20, 1, 45000)]);

    final slip = buildReportSlip(
      ReportPdfData(businessName: 'B', from: '2026-01-12', to: '2026-01-12', currency: Currency.pkr, salesMinor: 135000, refundsMinor: 0, taxMinor: 0, expensesMinor: 0, generatedAt: DateTime(2026, 1, 12, 22)),
      hours: hours,
    );
    final text = EscPosRenderer(paperMm: 58).renderSync(slip).previewText;
    expect(text, contains('PEAK HOURS'));
    expect(text.indexOf('1pm-2pm (2)'), lessThan(text.indexOf('8pm-9pm (1)')), reason: 'busiest first');
  });
}
