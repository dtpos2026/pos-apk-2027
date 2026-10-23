import 'pos_service.dart';
import 'db_helper.dart';

class PaymentMethodRow {
  const PaymentMethodRow(this.id, this.name, this.kind, this.enabled);
  final String id;
  final String name;
  final String kind;
  final bool enabled;
}

/// Payment accounts shown at checkout (Cash, Card, JazzCash, EasyPaisa, bank accounts, Udhaar...).
/// Methods are never deleted (old bills point to them); they are switched off instead. Cash always stays on.
class PaymentMethodService {
  PaymentMethodService(this.h);
  final DbHelper h;
  static const kinds = ['cash', 'card', 'bank', 'wallet', 'credit', 'other'];

  Future<List<PaymentMethodRow>> all() async => [
        for (final r in await h.q('SELECT id, name, kind, enabled FROM payment_method WHERE deleted_at IS NULL ORDER BY sort, name'))
          PaymentMethodRow(r['id'] as String, r['name'] as String, r['kind'] as String, (r['enabled'] as int) == 1),
      ];

  Future<String> add({required String name, required String kind, required String staffId}) => h.db.transaction(() async {
        final n = name.trim();
        if (n.isEmpty) throw PosException('name_required', 'Enter a name');
        if (!kinds.contains(kind) || kind == 'cash' || kind == 'credit') throw PosException('bad_kind', 'Choose card, bank, wallet or other');
        if ((await h.q('SELECT id FROM payment_method WHERE lower(name) = lower(?) AND deleted_at IS NULL', [n])).isNotEmpty) {
          throw PosException('duplicate', 'A payment method with this name already exists');
        }
        final sort = await h.intValue('SELECT COALESCE(MAX(sort),0) + 1 FROM payment_method');
        final id = h.id;
        await h.exec('INSERT INTO payment_method(id, name, kind, sort, updated_at) VALUES (?,?,?,?,?)', [id, n, kind, sort, h.ts]);
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
}
