import 'package:dt_food_pos/app/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every English key has an Urdu and an Arabic translation', () {
    final en = Strings.debugKeys('en');
    for (final lang in ['ur', 'ar']) {
      final keys = Strings.debugKeys(lang);
      final missing = en.where((k) => !keys.contains(k) && !const {'app_name', 'powered_by'}.contains(k)).toList();
      expect(missing, isEmpty, reason: '$lang is missing $missing');
      expect(keys.difference(en), isEmpty, reason: '$lang has unknown keys');
    }
  });

  test('lookup, fallback and RTL', () {
    expect(Strings(const Locale('ur'))['total'], 'کل');
    expect(Strings(const Locale('ar'))['total'], 'الإجمالي');
    expect(Strings(const Locale('ur'))['powered_by'], 'Powered by Digital Target'); // brand line is never translated
    expect(Strings(const Locale('fr'))['total'], 'Total');
    expect(Strings(const Locale('en'))['nope'], 'nope');
    expect(Strings.isRtl(const Locale('ur')), isTrue);
    expect(Strings.isRtl(const Locale('ar')), isTrue);
    expect(Strings.isRtl(const Locale('en')), isFalse);
  });
}
