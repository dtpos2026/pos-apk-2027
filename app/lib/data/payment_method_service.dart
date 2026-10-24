import 'pos_service.dart';
import 'db_helper.dart';

class PaymentMethodRow {
  const PaymentMethodRow(this.id, this.name, this.kind, this.enabled, {this.provider, this.accountNo, this.holder, this.imagePath});
  final String id;
  final String name;
  final String kind;
  final bool enabled;

  /// Bank or wallet company (e.g. "Meezan Bank"), account number or IBAN, and the name on the account.
  final String? provider;
  final String? accountNo;
  final String? holder;
  final String? imagePath;

  /// Cash and Credit (udhaar) are part of the system: they can be neither deleted nor switched off (cash) / renamed away.
  bool get isSystem => kind == 'cash' || kind == 'credit';

  /// "•••• 4567": enough to recognise the account on a screen anyone can see.
  String? get maskedNumber {
    final n = accountNo?.replaceAll(RegExp(r'\s'), '');
    if (n == null || n.isEmpty) return null;
    return n.length <= 4 ? n : '•••• ${n.substring(n.length - 4)}';
  }
}

/// Payment accounts shown at checkout (Cash, Card, JazzCash, EasyPaisa, bank accounts, Udhaar...).
/// Methods are never deleted (old bills point to them); they are switched off instead. Cash always stays on.
class PaymentMethodService {
  PaymentMethodService(this.h);
  final DbHelper h;
  static const kinds = ['cash', 'card', 'bank', 'wallet', 'credit', 'other'];

  Future<List<PaymentMethodRow>> all() async => [
        for (final r in await h.q('SELECT id, name, kind, enabled, provider, account_no, holder, image_path FROM payment_method WHERE deleted_at IS NULL ORDER BY sort, name'))
          PaymentMethodRow(r['id'] as String, r['name'] as String, r['kind'] as String, (r['enabled'] as int) == 1, provider: r['provider'] as String?, accountNo: r['account_no'] as String?, holder: r['holder'] as String?, imagePath: r['image_path'] as String?),
      ];

  /// A bank account must say whose it is and its number before it can be saved; wallets may leave them out.
  void _checkDetails(String kind, String? accountNo, String? holder) {
    if (kind == 'bank') {
      if ((holder ?? '').trim().isEmpty) throw PosException('holder_required', 'Enter the account holder name');
      if ((accountNo ?? '').trim().isEmpty) throw PosException('account_required', 'Enter the account number or IBAN');
    }
  }

  static String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  Future<String> add({required String name, required String kind, required String staffId, String? provider, String? accountNo, String? holder}) => h.db.transaction(() async {
        final n = name.trim();
        _checkDetails(kind, accountNo, holder);
        if (n.isEmpty) throw PosException('name_required', 'Enter a name');
        if (!kinds.contains(kind) || kind == 'cash' || kind == 'credit') throw PosException('bad_kind', 'Choose card, bank, wallet or other');
        if ((await h.q('SELECT id FROM payment_method WHERE lower(name) = lower(?) AND deleted_at IS NULL', [n])).isNotEmpty) {
          throw PosException('duplicate', 'A payment method with this name already exists');
        }
        final sort = await h.intValue('SELECT COALESCE(MAX(sort),0) + 1 FROM payment_method');
        final id = h.id;
        await h.exec('INSERT INTO payment_method(id, name, kind, sort, provider, account_no, holder, updated_at) VALUES (?,?,?,?,?,?,?,?)', [id, n, kind, sort, _clean(provider), _clean(accountNo), _clean(holder), h.ts]);
        await h.audit('payment_method.add', staffId: staffId, entity: 'payment_method', entityId: id, after: {'name': n, 'kind': kind});
        return id;
      });

  Future<void> rename(String id, String name, {required String staffId}) => h.db.transaction(() async {
        final n = name.trim();
        if (n.isEmpty) throw PosException('name_required', 'Enter a name');
        if ((await h.q('SELECT id FROM payment_method WHERE lower(name) = lower(?) AND id <> ? AND deleted_at IS NULL', [n, id])).isNotEmpty) {
          throw PosException('duplicate', 'A payment method with this name already exists');
        }
        await h.exec('UPDATE payment_method SET name = ?, version = version + 1, updated_at = ? WHERE id = ?', [n, h.ts, id]);
        await h.audit('payment_method.rename', staffId: staffId, entity: 'payment_method', entityId: id, after: {'name': n});
      });

  Future<void> setEnabled(String id, bool on, {required String staffId}) => h.db.transaction(() async {
        final r = await h.q('SELECT kind FROM payment_method WHERE id = ?', [id]);
        if (r.isEmpty) throw PosException('not_found', 'Payment method not found');
        if (!on && r.first['kind'] == 'cash') throw PosException('cash_required', 'Cash cannot be switched off');
        await h.exec('UPDATE payment_method SET enabled = ?, version = version + 1, updated_at = ? WHERE id = ?', [on ? 1 : 0, h.ts, id]);
        await h.audit(on ? 'payment_method.on' : 'payment_method.off', staffId: staffId, entity: 'payment_method', entityId: id);
      });

  /// Edits the name and the account details (kind stays: old bills depend on it).
  Future<void> update(String id, {required String name, String? provider, String? accountNo, String? holder, required String staffId}) => h.db.transaction(() async {
        final r = await h.one('SELECT kind FROM payment_method WHERE id = ? AND deleted_at IS NULL', [id]);
        if (r == null) throw PosException('not_found', 'Payment method not found');
        final kind = r['kind'] as String;
        _checkDetails(kind, accountNo, holder);
        final n = name.trim();
        if (n.isEmpty) throw PosException('name_required', 'Enter a name');
        if ((await h.q('SELECT id FROM payment_method WHERE lower(name) = lower(?) AND id <> ? AND deleted_at IS NULL', [n, id])).isNotEmpty) {
          throw PosException('duplicate', 'A payment method with this name already exists');
        }
        await h.exec('UPDATE payment_method SET name = ?, provider = ?, account_no = ?, holder = ?, version = version + 1, updated_at = ? WHERE id = ?', [n, _clean(provider), _clean(accountNo), _clean(holder), h.ts, id]);
        await h.audit('payment_method.update', staffId: staffId, entity: 'payment_method', entityId: id, after: {'name': n, 'provider': _clean(provider)});
      });

  /// Removes an account the owner added. Cash and Credit are required by the system, and an account that already took
  /// payments is kept (switch it off instead) so old bills, reports and the ledger still name it.
  Future<void> remove(String id, {required String staffId}) => h.db.transaction(() async {
        final r = await h.one('SELECT kind, name FROM payment_method WHERE id = ? AND deleted_at IS NULL', [id]);
        if (r == null) throw PosException('not_found', 'Payment method not found');
        if (r['kind'] == 'cash' || r['kind'] == 'credit') throw PosException('system_method', 'Cash and Credit are part of the system and cannot be deleted');
        final used = await h.intValue('SELECT COUNT(*) FROM payment WHERE method_id = ?', [id]) +
            await h.intValue('SELECT COUNT(*) FROM refund WHERE method_id = ?', [id]) +
            await h.intValue('SELECT COUNT(*) FROM expense WHERE method_id = ?', [id]);
        if (used > 0) throw PosException('has_history', 'This account has transactions. Switch it off instead of deleting it.');
        await h.exec('UPDATE payment_method SET deleted_at = ?, enabled = 0, version = version + 1, updated_at = ? WHERE id = ?', [h.ts, h.ts, id]);
        await h.audit('payment_method.delete', staffId: staffId, entity: 'payment_method', entityId: id, after: {'name': r['name']}, critical: true);
      });
}
