import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/money.dart';
import 'providers.dart';

extension MoneyFormat on WidgetRef {
  Currency get currency => watch(businessProvider).value?.currency ?? Currency.pkr;
  String money(int minor, {bool symbol = true}) => formatMinor(minor, currency: currency, symbol: symbol);
}
