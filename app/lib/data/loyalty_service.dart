import 'package:drift/drift.dart' show Variable;

import '../domain/loyalty.dart';
import 'db/database.dart';
import 'queries.dart';

/// Loyalty points settings and balances. Earning and spending happen inside the sale (PosService.settleOrder).
class LoyaltyService {
  LoyaltyService(this.db, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() _now;

  Future<LoyaltyConfig> config() async => LoyaltyConfig.decode(await getSetting(db, loyaltySettingKey));

  /// Saves the settings; switching points on also creates the hidden "Loyalty points" payment method they are paid with.
  Future<void> save(LoyaltyConfig c) async {
    final ts = _now().millisecondsSinceEpoch;
    await setSetting(db, loyaltySettingKey, c.encode(), ts);
    await db.customStatement("INSERT OR IGNORE INTO payment_method(id, name, kind, enabled, sort, updated_at) VALUES (?, 'Loyalty points', 'other', 0, 999, ?)", [loyaltyMethodId, ts]);
  }

  Future<int> balance(String customerId) async =>
      (await db.customSelect('SELECT COALESCE(SUM(points),0) AS p FROM loyalty_ledger WHERE customer_id = ?', variables: [Variable.withString(customerId)]).getSingle()).read<int>('p');
}
