import 'package:dt_food_pos/domain/tutorials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  test('every topic has the same number of steps in all three languages, none empty', () {
    for (final x in tutorials) {
      final n = x.steps[TutorialLang.en]!.length;
      expect(n, greaterThan(2), reason: x.id);
      for (final l in TutorialLang.values) {
        expect(x.title[l], isNotEmpty, reason: '${x.id} title $l');
        expect(x.steps[l]!.length, n, reason: '${x.id} steps $l');
        expect(x.steps[l]!.every((s) => s.trim().length > 10), isTrue, reason: '${x.id} $l');
      }
    }
    expect(tutorials.map((x) => x.id).toSet().length, tutorials.length);
  });

  testWidgets('help: open from the side menu, read in English, Urdu (two styles) and Roman Urdu, and search', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    await signIn(t, 'Ali', '1234');
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    await tapKey(t, 'drawer-help');
    expect(find.text('Help & Tutorials'), findsOneWidget);
    await tapKey(t, 'help-topic-sell');
    expect(find.textContaining('Tap an item to add it'), findsOneWidget);
    await shot(t, '99_help_en');

    await t.ensureVisible(find.byKey(const ValueKey('help-ro')));
    await tapKey(t, 'help-ro');
    expect(find.textContaining('Item par tap karein'), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('help-urNastaliq')));
    await tapKey(t, 'help-urNastaliq');
    final urdu = t.widget<Text>(find.textContaining('آئٹم پر ٹیپ کریں'));
    expect(urdu.style!.fontFamily, 'NotoNastaliqUrdu');
    await t.ensureVisible(find.byKey(const ValueKey('help-urNaskh')));
    await tapKey(t, 'help-urNaskh');
    expect(t.widget<Text>(find.textContaining('آئٹم پر ٹیپ کریں')).style!.fontFamily, 'NotoNaskhArabic');

    await t.ensureVisible(find.byKey(const ValueKey('help-en')));
    await tapKey(t, 'help-en');
    await t.enterText(find.byKey(const ValueKey('help-search')), 'rider');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-topic-delivery')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-topic-backup')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('help-search')), 'zzzz');
    await t.pumpAndSettle();
    expect(find.text('Nothing found'), findsOneWidget);
  });
}
