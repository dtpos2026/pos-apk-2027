import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/queries.dart';
import '../domain/modules.dart';
import 'providers.dart';

/// Quick counter: for a food point / stall. Only Counter and Takeaway are offered, and after "Complete Order" the bill (and the token,
/// when tokens are on) print by themselves and the screen is ready for the next customer, with no receipt window in between.
class QuickCounterNotifier extends AsyncNotifier<bool> {
  static const key = 'ui.quick_counter';
  @override
  Future<bool> build() async => (await getSetting(ref.read(databaseProvider), key)) == '1';

  Future<void> set(bool on) async {
    await setSetting(ref.read(databaseProvider), key, on ? '1' : '0', ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(on);
  }
}

final quickCounterProvider = AsyncNotifierProvider<QuickCounterNotifier, bool>(QuickCounterNotifier.new);

/// What the cashier chose to print for the sale being paid right now (null = follow the print settings).
class PrintChoice {
  const PrintChoice({this.bill, this.token});
  final bool? bill;
  final bool? token;
}

class PrintChoiceNotifier extends Notifier<PrintChoice> {
  @override
  PrintChoice build() => const PrintChoice();
  void set({bool? bill, bool? token}) => state = PrintChoice(bill: bill ?? state.bill, token: token ?? state.token);
  void reset() => state = const PrintChoice();
}

final printChoiceProvider = NotifierProvider<PrintChoiceNotifier, PrintChoice>(PrintChoiceNotifier.new);

/// Business types that sell over the counter and want the quick flow.
const quickCounterTypes = {'foodpoint', 'stall'};

/// Sets everything a business type needs in one go (features, quick counter, what prints). The owner can still change each part
/// afterwards in Settings: modules, Quick counter, Print settings.
Future<void> applyBusinessType(WidgetRef ref, String id) async {
  final type = businessTypeById(id);
  final db = ref.read(databaseProvider);
  await ref.read(modulesProvider.notifier).setAll(type.modules);
  await setSetting(db, 'business_type', type.id, ref.read(clockProvider)().millisecondsSinceEpoch);
  final quick = quickCounterTypes.contains(type.id);
  await ref.read(quickCounterProvider.notifier).set(quick);
  if (quick) {
    final cur = await ref.read(printSettingsProvider.future);
    await ref.read(printSettingsProvider.notifier).save(cur.copyWith(
          autoKot: false,
          autoBill: true,
          billEnabled: true,
          tokenEnabled: type.modules.contains('tokens'),
          autoToken: type.modules.contains('tokens'),
        ));
  }
}
