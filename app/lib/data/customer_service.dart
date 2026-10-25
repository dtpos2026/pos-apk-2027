import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class CustomerRow {
  const CustomerRow({required this.id, required this.name, this.phone, this.address, this.imagePath, required this.creditLimitMinor, required this.balanceMinor});
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? imagePath;
  final int creditLimitMinor;

  /// Positive = the customer owes us (udhaar).
  final int balanceMinor;
}

class LedgerEntry {
  const LedgerEntry({required this.kind, required this.amountMinor, required this.at, this.note, this.orderId, this.invoiceNo, this.balanceAfterMinor = 0});

  /// The bill number of a credit sale, and the customer's balance after this entry (oldest to newest).
  final String? invoiceNo;
  final int balanceAfterMinor;
  final String kind;
  final int amountMinor;
  final int at;
  final String? note;
  final String? orderId;
}

/// Customers and their credit (udhaar) account. The balance is always the sum of an append-only ledger.
class CustomerService {
  CustomerService(this.h);
  final DbHelper h;

  Future<String> save({String? id, required String name, String? phone, String? address, int creditLimitMinor = 0, required String staffId}) => h.db.transaction(() async {
        if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
        if (creditLimitMinor < 0) throw PosException('bad_amount', 'Credit limit cannot be negative');
        final p = phone?.trim().isEmpty ?? true ? null : phone!.trim();
        if (p != null) {
          final dup = await h.one('SELECT id FROM customer WHERE phone = ? AND deleted_at IS NULL AND id <> ?', [p, id ?? '']);
          if (dup != null) throw PosException('duplicate_phone', 'A customer with this phone number already exists');
        }
        final cid = id ?? h.id;
        if (id == null) {
          await h.exec('INSERT INTO customer(id, name, phone, address, credit_limit_minor, updated_at) VALUES (?,?,?,?,?,?)', [cid, name.trim(), p, address?.trim(), creditLimitMinor, h.ts]);
        } else {
          await h.exec('UPDATE customer SET name=?, phone=?, address=?, credit_limit_minor=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), p, address?.trim(), creditLimitMinor, h.ts, id]);
        }
        final v = await h.intValue('SELECT version FROM customer WHERE id = ?', [cid]);
        await h.outbox('customer', cid, 'upsert', {'id': cid, 'name': name.trim(), 'phone': p}, 'customer:$cid:v$v', version: v);
        return cid;
      });

  Future<int> balance(String customerId) => h.intValue('SELECT COALESCE(SUM(amount_minor),0) FROM customer_ledger WHERE customer_id = ?', [customerId]);

  Future<List<CustomerRow>> list({String search = ''}) async {
    final like = '%${search.trim()}%';
    final rows = await h.q(
        'SELECT c.id, c.name, c.phone, c.address, c.image_path, c.credit_limit_minor, COALESCE((SELECT SUM(amount_minor) FROM customer_ledger WHERE customer_id = c.id),0) AS bal '
        'FROM customer c WHERE c.deleted_at IS NULL AND (c.name LIKE ? OR c.phone LIKE ?) ORDER BY c.name',
        [like, like]);
    return [for (final r in rows) CustomerRow(id: r['id'] as String, name: r['name'] as String, phone: r['phone'] as String?, address: r['address'] as String?, imagePath: r['image_path'] as String?, creditLimitMinor: r['credit_limit_minor'] as int, balanceMinor: r['bal'] as int)];
  }

  /// Newest first, each entry with its bill number and the balance after it (so the list can show a running balance).
  Future<List<LedgerEntry>> ledger(String customerId) async {
    final rows = await h.q(
        'SELECT l.kind, l.amount_minor, l.created_at, l.note, l.order_id, o.invoice_no FROM customer_ledger l LEFT JOIN "order" o ON o.id = l.order_id WHERE l.customer_id = ? ORDER BY l.created_at ASC, l.rowid ASC',
        [customerId]);
    var bal = 0;
    final out = <LedgerEntry>[];
    for (final r in rows) {
      bal += r['amount_minor'] as int;
      out.add(LedgerEntry(kind: r['kind'] as String, amountMinor: r['amount_minor'] as int, at: r['created_at'] as int, note: r['note'] as String?, orderId: r['order_id'] as String?, invoiceNo: r['invoice_no'] as String?, balanceAfterMinor: bal));
    }
    return out.reversed.toList();
  }

  /// Total owed to the business and how many customers owe something.
  Future<({int totalMinor, int customers})> outstanding() async {
    final r = (await h.q('SELECT COUNT(*) AS n, COALESCE(SUM(b),0) AS s FROM (SELECT SUM(amount_minor) AS b FROM customer_ledger GROUP BY customer_id HAVING SUM(amount_minor) > 0)')).first;
    return (totalMinor: r['s'] as int, customers: r['n'] as int);
  }

  /// The account used when a credit sale has no named customer: one fixed "Walk-in credit" customer, created on first use. The sale is
  /// never lost and the money owed shows under one clear name; its limit can be changed like any customer's.
  Future<String> walkInCreditId({required String staffId}) async {
    final saved = await h.one("SELECT setting_value AS v FROM setting WHERE setting_key = 'walkin.customer_id'");
    final id = saved?['v'] as String?;
    if (id != null && await h.one('SELECT id FROM customer WHERE id = ? AND deleted_at IS NULL', [id]) != null) return id;
    final cid = await save(name: 'Walk-in credit', creditLimitMinor: 5000000, staffId: staffId);
    await h.exec("INSERT OR REPLACE INTO setting(setting_key, setting_value, updated_at) VALUES ('walkin.customer_id', ?, ?)", [cid, h.ts]);
    return cid;
  }

  /// The customer pays back part or all of what they owe. Cash received goes into the open shift's drawer.
  /// Paying more than is owed is refused (advance balances are not supported).
  Future<void> receivePayment({required String customerId, required int amountMinor, required String methodId, required String staffId, String? note}) => h.db.transaction(() async {
        if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
        final owed = await balance(customerId);
        if (amountMinor > owed) throw PosException('overpay', 'The customer only owes $owed');
        final m = await h.one('SELECT kind FROM payment_method WHERE id = ? AND enabled = 1', [methodId]);
        if (m == null || m['kind'] == 'credit') throw PosException('bad_method', 'Choose how the money was received');
        await h.exec('INSERT INTO customer_ledger(id, customer_id, kind, amount_minor, note, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, customerId, 'recovery', -amountMinor, note, staffId, h.ts]);
        if (m['kind'] == 'cash') {
          final shift = await h.openShiftOf(staffId);
          if (shift != null) {
            await h.exec('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, shift, 'in', amountMinor, 'Udhaar recovery', staffId, h.ts]);
          }
        }
        await h.audit('udhaar.recovery', staffId: staffId, entity: 'customer', entityId: customerId, after: {'amount': amountMinor, 'method': m['kind']});
        await h.outbox('customer_ledger', customerId, 'append', {'customer_id': customerId, 'amount_minor': -amountMinor, 'kind': 'recovery'}, 'recovery:$customerId:${h.ts}:$amountMinor');
      });
}
