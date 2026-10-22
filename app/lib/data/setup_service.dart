import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'db/database.dart';

const _managerPermissions = '["pos.sell","discount.apply","bill.void","bill.refund","menu.manage","reports.view","inventory.manage","shift.manage","day.close","staff.view","settings.manage"]';

/// First-run setup: business profile, system roles, owner account and default payment methods.
/// Runs once; calling it again on a configured device throws.
class SetupService {
  SetupService(this.db, this.auth, {DateTime Function()? now, String Function()? newId})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final AuthService auth;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<bool> isConfigured() async => (await db.customSelect("SELECT COUNT(*) AS n FROM business_profile").getSingle()).data['n'] == 1;

  /// [country] is 'PK' or 'AE'. Returns the owner's staff id.
  /// Tax rates are deliberately NOT preloaded for Pakistan (rates differ by province and business type: the owner
  /// enters their own). UAE gets the 5% VAT as an editable inclusive rate.
  Future<String> completeSetup({required String businessName, required String ownerName, required String pin, String country = 'PK', String? phone, String? address}) async {
    if (await isConfigured()) throw StateError('This device is already set up');
    if (businessName.trim().isEmpty || ownerName.trim().isEmpty) throw ArgumentError('Business and owner name are required');
    final currency = country == 'AE' ? 'AED' : 'PKR';
    final now = _now().millisecondsSinceEpoch;
    late String ownerId;
    await db.transaction(() async {
      Future<String> role(String name, String perms) async {
        final id = _newId();
        await db.customStatement('INSERT INTO role(id, name, permissions, is_system, updated_at) VALUES (?,?,?,1,?)', [id, name, perms, now]);
        return id;
      }

      final owner = await role('Owner', '["*"]');
      await role('Manager', _managerPermissions);
      await role('Cashier', '["pos.sell","shift.manage"]');
      await role('Waiter', '["pos.sell"]');
      await role('Kitchen', '["kitchen.view"]');

      await db.customStatement(
          "INSERT INTO business_profile(id, name, owner_name, phone, address, currency, language, updated_at) VALUES ('self',?,?,?,?,?,'en',?)",
          [businessName.trim(), ownerName.trim(), phone, address, currency, now]);

      Future<void> method(String name, String kind, int sort) =>
          db.customStatement('INSERT INTO payment_method(id, name, kind, sort, updated_at) VALUES (?,?,?,?,?)', [_newId(), name, kind, sort, now]);
      await method('Cash', 'cash', 0);
      await method('Card', 'card', 1);
      await method('Bank transfer', 'bank', 2);
      if (country == 'AE') {
        await method('Apple Pay / wallet', 'wallet', 3);
      } else {
        await method('Easypaisa', 'wallet', 3);
        await method('JazzCash', 'wallet', 4);
      }
      await method('Credit (udhaar)', 'credit', 9);

      if (country == 'AE') {
        await db.customStatement("INSERT INTO tax_rate(id, name, rate_bp, inclusive, is_default, updated_at) VALUES (?,'VAT 5%',500,1,1,?)", [_newId(), now]);
      }
      ownerId = await _createOwner(owner, ownerName.trim(), pin, phone);
    });
    return ownerId;
  }

  Future<String> _createOwner(String roleId, String name, String pin, String? phone) => auth.createStaff(name: name, roleId: roleId, pin: pin, phone: phone);
}
