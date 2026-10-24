import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class ExpenseRow {
  const ExpenseRow({required this.id, required this.amountMinor, this.category, this.note, required this.date, this.method});
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
  Future<String> add({required int amountMinor, required String category, required String methodId, String? note, required String staffId}) => h.db.transaction(() async {
        if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
        final m = await h.one('SELECT kind FROM payment_method WHERE id = ? AND enabled = 1', [methodId]);
        if (m == null) throw PosException('bad_method', 'Choose a payment method');
        final cat = await categoryId(category);
        final id = h.id;
        await h.exec('INSERT INTO expense(id, category_id, amount_minor, method_id, note, business_date, staff_id, created_at) VALUES (?,?,?,?,?,?,?,?)', [id, cat, amountMinor, methodId, note?.trim(), await h.openBusinessDate(), staffId, h.ts]);
        if (m['kind'] == 'cash') {
          final shift = await h.openShiftOf(staffId);
          if (shift != null) {
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'out', amountMinor, 'Expense: ${category.trim()}', staffId, h.ts]);
          }
        }
        await h.audit('expense.add', staffId: staffId, entity: 'expense', entityId: id, after: {'amount': amountMinor, 'category': category.trim()});
        await h.outbox('expense', id, 'append', {'id': id, 'amount_minor': amountMinor, 'category': category.trim(), 'date': await h.openBusinessDate()}, 'expense:$id');
        return id;
      });

  Future<List<ExpenseRow>> forDate(String date) async => [
        for (final r in await h.q(
            'SELECT e.id, e.amount_minor, e.note, e.business_date, c.name AS cat, m.name AS method FROM expense e LEFT JOIN expense_category c ON c.id = e.category_id LEFT JOIN payment_method m ON m.id = e.method_id WHERE e.business_date = ? ORDER BY e.created_at DESC, e.rowid DESC',
            [date]))
          ExpenseRow(id: r['id'] as String, amountMinor: r['amount_minor'] as int, category: r['cat'] as String?, note: r['note'] as String?, date: r['business_date'] as String, method: r['method'] as String?)
      ];

  Future<int> totalFor(String date) => h.intValue('SELECT COALESCE(SUM(amount_minor),0) FROM expense WHERE business_date = ?', [date]);
}
