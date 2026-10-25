import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class ExpenseRow {
  const ExpenseRow({required this.id, required this.amountMinor, this.category, this.note, required this.date, this.method, this.methodId});
  final String? methodId;
  final String id;
  final int amountMinor;
  final String? category;
  final String? note;
  final String date;
  final String? method;
}

class ExpenseService {
  ExpenseService(this.h);
  final DbHelper h;

  /// Categories the owner can pick with one tap. Deleting one hides it from the list; old expenses keep its name.
  Future<List<({String id, String name})>> categories() async => [
        for (final r in await h.q('SELECT id, name FROM expense_category WHERE deleted_at IS NULL ORDER BY name')) (id: r['id'] as String, name: r['name'] as String)
      ];

  Future<void> deleteCategory(String id) => h.exec('UPDATE expense_category SET deleted_at = ? WHERE id = ?', [h.ts, id]);

  Future<String> categoryId(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw PosException('name_required', 'Category is required');
    final f = await h.one('SELECT id FROM expense_category WHERE lower(name) = lower(?) AND deleted_at IS NULL', [n]);
    if (f != null) return f['id'] as String;
    final id = h.id;
    await h.exec('INSERT INTO expense_category(id, name) VALUES (?,?)', [id, n]);
    return id;
  }

  /// Records an expense. Paid in cash while a shift is open: it also leaves the cash drawer, so the shift's
  /// expected cash and the Z report agree.
  /// The category is optional: an expense with only an amount is saved as it is (shown as "No category").
  Future<String> add({required int amountMinor, String? category, required String methodId, String? note, required String staffId}) => h.db.transaction(() async {
        if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
        final m = await h.one('SELECT kind FROM payment_method WHERE id = ? AND enabled = 1', [methodId]);
        if (m == null) throw PosException('bad_method', 'Choose a payment method');
        final catName = (category ?? '').trim();
        final cat = catName.isEmpty ? null : await categoryId(catName);
        final id = h.id;
        await h.exec('INSERT INTO expense(id, category_id, amount_minor, method_id, note, business_date, staff_id, created_at) VALUES (?,?,?,?,?,?,?,?)', [id, cat, amountMinor, methodId, note?.trim(), await h.openBusinessDate(), staffId, h.ts]);
        if (m['kind'] == 'cash') {
          final shift = await h.openShiftOf(staffId);
          if (shift != null) {
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'out', amountMinor, catName.isEmpty ? 'Expense' : 'Expense: $catName', staffId, h.ts]);
          }
        }
        await h.audit('expense.add', staffId: staffId, entity: 'expense', entityId: id, after: {'amount': amountMinor, 'category': catName});
        await h.outbox('expense', id, 'append', {'id': id, 'amount_minor': amountMinor, 'category': catName, 'date': await h.openBusinessDate()}, 'expense:$id');
        return id;
      });

  /// Corrects an expense entered wrongly (amount, category, how it was paid, note). A cash expense that left the drawer is put back and the
  /// corrected one taken out, so the shift's cash agrees; the audit trail keeps what it was before. Returns false when it does not exist.
  Future<bool> update(String id, {required int amountMinor, String? category, required String methodId, String? note, required String staffId}) => h.db.transaction(() async {
        if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
        final old = await h.one('SELECT e.amount_minor, e.note, e.method_id, c.name AS cat, m.kind AS kind FROM expense e LEFT JOIN expense_category c ON c.id = e.category_id LEFT JOIN payment_method m ON m.id = e.method_id WHERE e.id = ?', [id]);
        if (old == null) return false;
        final m = await h.one('SELECT kind FROM payment_method WHERE id = ? AND enabled = 1', [methodId]);
        if (m == null) throw PosException('bad_method', 'Choose a payment method');
        final catName = (category ?? '').trim();
        final cat = catName.isEmpty ? null : await categoryId(catName);
        await h.exec('UPDATE expense SET category_id = ?, amount_minor = ?, method_id = ?, note = ? WHERE id = ?', [cat, amountMinor, methodId, note?.trim(), id]);
        final shift = await h.openShiftOf(staffId);
        if (shift != null) {
          if (old['kind'] == 'cash') {
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'in', old['amount_minor'], 'Expense corrected (back)', staffId, h.ts]);
          }
          if (m['kind'] == 'cash') {
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'out', amountMinor, catName.isEmpty ? 'Expense corrected' : 'Expense corrected: $catName', staffId, h.ts]);
          }
        }
        await h.audit('expense.update', staffId: staffId, entity: 'expense', entityId: id, before: {'amount': old['amount_minor'], 'category': old['cat'], 'note': old['note'], 'method': old['method_id']}, after: {'amount': amountMinor, 'category': catName, 'note': note, 'method': methodId});
        return true;
      });

  /// Saves a category on its own (no expense yet), so the usual ones (Gas, Rent, Electricity...) are ready to tap. Returns its id; an existing name is reused.
  Future<String> addCategory(String name) => categoryId(name);

  Future<List<ExpenseRow>> forDate(String date) async => [
        for (final r in await h.q(
            'SELECT e.id, e.amount_minor, e.note, e.business_date, c.name AS cat, m.name AS method, e.method_id FROM expense e LEFT JOIN expense_category c ON c.id = e.category_id LEFT JOIN payment_method m ON m.id = e.method_id WHERE e.business_date = ? ORDER BY e.created_at DESC, e.rowid DESC',
            [date]))
          ExpenseRow(id: r['id'] as String, amountMinor: r['amount_minor'] as int, category: r['cat'] as String?, note: r['note'] as String?, date: r['business_date'] as String, method: r['method'] as String?, methodId: r['method_id'] as String?)
      ];

  Future<int> totalFor(String date) => h.intValue('SELECT COALESCE(SUM(amount_minor),0) FROM expense WHERE business_date = ?', [date]);

  /// Removes an expense that was entered by mistake. The row goes (the audit trail keeps what it was). If it was paid in cash and the
  /// cashier has a shift open, the money is put back in the drawer, so the shift's cash agrees. Returns false when it does not exist.
  Future<bool> delete(String id, {required String staffId}) => h.db.transaction(() async {
        final e = await h.one('SELECT e.amount_minor, e.note, e.business_date, e.method_id, c.name AS cat, m.kind AS kind FROM expense e LEFT JOIN expense_category c ON c.id = e.category_id LEFT JOIN payment_method m ON m.id = e.method_id WHERE e.id = ?', [id]);
        if (e == null) return false;
        await h.exec('DELETE FROM expense WHERE id = ?', [id]);
        if (e['kind'] == 'cash') {
          final shift = await h.openShiftOf(staffId);
          if (shift != null) {
            final cat = (e['cat'] as String?) ?? '';
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'in', e['amount_minor'], cat.isEmpty ? 'Expense deleted' : 'Expense deleted: $cat', staffId, h.ts]);
          }
        }
        await h.audit('expense.delete', staffId: staffId, entity: 'expense', entityId: id, before: {'amount': e['amount_minor'], 'category': e['cat'], 'note': e['note'], 'date': e['business_date'], 'method': e['method_id']}, critical: true);
        return true;
      });
}
