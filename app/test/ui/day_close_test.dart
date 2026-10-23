import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('owner closes the day from Reports, the Z report is shared and the day is locked', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final share = FakeShare();
    await pumpApp(t, db: db, share: share);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'reports', 'Reports');
    await t.ensureVisible(find.byKey(const ValueKey('open-day-close')));
    await tapKey(t, 'open-day-close');
    expect(find.text('Day is open. Close it after the last bill.'), findsOneWidget);
    await shot(t, '70_day_close');
    await tapKey(t, 'day-close');
    await tapKey(t, 'day-close-confirm');
    expect(find.textContaining('This report is final'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-close')), findsNothing);
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM day_close').getSingle()).data['n'], 1);
    await t.ensureVisible(find.byKey(const ValueKey('day-share')));
    await tapKey(t, 'day-share');
    expect(share.shared.single, contains('DAY CLOSE (Z REPORT)'));
    expect(share.shared.single, contains('Burger Point'));
  });
}
