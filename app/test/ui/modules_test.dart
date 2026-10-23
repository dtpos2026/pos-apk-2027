import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:dt_food_pos/domain/modules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';
import '../helpers/harness.dart';

/// Every navigation key currently reachable (bottom bar + "More" sheet + rail).
Future<Set<String>> navKeys(WidgetTester t) async {
  final keys = <String>{};
  for (final e in find.byType(NavigationDestination).evaluate()) {
    final w = e.widget as NavigationDestination;
    keys.add(w.label.toLowerCase());
  }
  if (find.byKey(const ValueKey('nav-more')).evaluate().isNotEmpty) {
    await t.tap(find.byKey(const ValueKey('nav-more')));
    await t.pumpAndSettle();
    for (final e in find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('more-')).evaluate()) {
      keys.add('${(e.widget.key as ValueKey).value}'.substring(5).toLowerCase());
    }
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
  }
  return keys;
}

void main() {
  test('business types pre-select sensible modules; admin switch-offs win', () {
    expect(businessTypeById('stall').modules, isNot(contains('tables')));
    expect(businessTypeById('desi').modules, contains('tables'));
    expect(businessTypeById('enterprise').modules, allModules);
    expect(effectiveModules({'tables', 'staff'}, ['staff']), {'tables'});
  });

  testWidgets('a food stall chosen at setup has no Tables or Staff; switching Tables on in Settings brings it back, data kept', (t) async {
    final h = await pumpApp(t);
    await t.tap(find.byKey(const ValueKey('btype-stall')));
    await t.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await typeInto(t, fields.at(0), 'Chai Khokha');
    await typeInto(t, fields.at(1), 'Bilal');
    await typeInto(t, fields.at(2), '1234');
    await t.ensureVisible(find.text('Finish setup'));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish setup'));
    await t.pumpAndSettle();
    expect(h.container.read(modulesProvider), {'customers', 'expenses'});
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    var keys = await navKeys(t);
    expect(keys, isNot(contains('tables')));
    expect(keys, isNot(contains('staff')));
    expect(keys, contains('customers'));

    await h.container.read(modulesProvider.notifier).toggle('tables', true);
    await t.pumpAndSettle();
    keys = await navKeys(t);
    expect(keys, contains('tables'));
  });

  testWidgets('a module switched off by Digital Target is hidden even if the owner had it on', (t) async {
    final cloud = FakeCloud();
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, cloud: cloud);
    await cloud.signInDirect('owner@cafe.pk');
    final phoneId = await h.container.read(accessProvider.notifier).phoneId();
    cloud.serverAccount(AccountSnapshot(status: 'active', approvedPhones: [phoneId], expiresAt: testNow.add(const Duration(days: 30)), disabledModules: const ['inventory'], checkedAt: testNow));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    await signIn(t, 'Ali', '1234');
    expect(h.container.read(activeModulesProvider), isNot(contains('inventory')));
    final keys = await navKeys(t);
    expect(keys, isNot(contains('inventory')));
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
