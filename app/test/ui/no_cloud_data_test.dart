import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('Settings has no "cloud copy" option: the restaurant data stays on the phone', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    expect(find.byKey(const ValueKey('cloud-copy')), findsNothing);
    expect(find.textContaining('Cloud copy'), findsNothing);
  });
}
