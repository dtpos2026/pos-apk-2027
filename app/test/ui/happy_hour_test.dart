import 'package:dt_food_pos/data/queries.dart';
import 'package:dt_food_pos/domain/bill.dart';
import 'package:dt_food_pos/domain/happy_hour.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  test('happy hour: only on its days and hours, also past midnight', () {
    const hh = HappyHour(enabled: true, days: {1, 2, 3, 4}, fromMinute: 15 * 60, toMinute: 18 * 60, percentBp: 1500);
    expect(hh.activeAt(DateTime(2026, 1, 12, 15, 0)), isTrue, reason: 'Monday 3 PM');
    expect(hh.activeAt(DateTime(2026, 1, 12, 18, 0)), isFalse, reason: '6 PM is the end');
    expect(hh.activeAt(DateTime(2026, 1, 16, 16, 0)), isFalse, reason: 'Friday is not chosen');
    const late = HappyHour(enabled: true, days: {5}, fromMinute: 22 * 60, toMinute: 2 * 60);
    expect(late.activeAt(DateTime(2026, 1, 16, 23, 30)), isTrue, reason: 'Friday 11:30 PM');
    expect(late.activeAt(DateTime(2026, 1, 17, 1, 0)), isTrue, reason: 'Saturday 1 AM still counts as Friday night');
    expect(late.activeAt(DateTime(2026, 1, 18, 1, 0)), isFalse);
    expect(const HappyHour(days: {1}).activeAt(DateTime(2026, 1, 12, 16)), isFalse, reason: 'off by default');
    final back = HappyHour.decode(hh.encode());
    expect((back.enabled, back.fromMinute, back.toMinute, back.percentBp), (true, 900, 1080, 1500));
    expect(back.days, {1, 2, 3, 4});
  });

  testWidgets('during happy hour a new bill gets the discount by itself', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final now = testNow;
    final from = now.hour * 60, to = (now.hour * 60 + 120) % 1440;
    await setSetting(db, happyHourSettingKey, HappyHour(enabled: true, days: {now.weekday}, fromMinute: from, toMinute: to, percentBp: 1000).encode(), 1);
    final h = await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await tapProduct(t, 'Zinger Burger');
    final d = h.container.read(cartProvider).config.billDiscount;
    expect(d?.kind, DiscountKind.percent);
    expect(d?.value, 1000);
  });
}
