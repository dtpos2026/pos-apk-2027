import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';
import 'pos_service.dart';

class ShiftSummary {
  const ShiftSummary({required this.openingMinor, required this.cashSalesMinor, required this.cashRefundsMinor, required this.cashInMinor, required this.cashOutMinor});
  final int openingMinor;
  final int cashSalesMinor;
  final int cashRefundsMinor;
  final int cashInMinor;
  final int cashOutMinor;
  int get expectedMinor => openingMinor + cashSalesMinor - cashRefundsMinor + cashInMinor - cashOutMinor;
}

/// Cash drawer shifts and the end-of-day (Z) report.
class ShiftService {
  ShiftService(this.db, this.pos, {DateTime Function()? now, String Function()? newId})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final PosService pos;
  final DateTime Function() _now;
  final String Function() _newId;

  int get _ts => _now().millisecondsSinceEpoch;

  Future<List<Map<String, Object?>>> _select(String sql, [List<Object?> args = const []]) async =>
      (await db.customSelect(sql, variables: args.map((a) => a is int ? Variable.withInt(a) : Variable.withString(a as String)).toList()).get()).map((r) => r.data).toList();

  Future<String> openShift(String staffId, {int openingCashMinor = 0}) async {
    if (openingCashMinor < 0) throw PosException('bad_amount', 'Opening cash cannot be negative');
    final open = await _select('SELECT id FROM shift WHERE staff_id = ? AND closed_at IS NULL', [staffId]);
    if (open.isNotEmpty) throw PosException('shift_open', 'A shift is already open for this user');
    final id = _newId();
    await db.customStatement('INSERT INTO shift(id, staff_id, opened_at, opening_cash_minor) VALUES (?,?,?,?)', [id, staffId, _ts, openingCashMinor]);
    return id;
  }

  Future<void> cashMovement(String shiftId, {required bool cashIn, required int amountMinor, required String reason, required String staffId}) async {
    if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
    if (reason.trim().isEmpty) throw PosException('reason_required', 'A reason is required');
    final s = await _select('SELECT closed_at FROM shift WHERE id = ?', [shiftId]);
    if (s.isEmpty || s.first['closed_at'] != null) throw PosException('shift_closed', 'Shift is not open');
    await db.customStatement('INSERT INTO cash_movement(id, shift_id, direction, amount_minor, reason, staff_id, created_at) VALUES (?,?,?,?,?,?,?)',
        [_newId(), shiftId, cashIn ? 'in' : 'out', amountMinor, reason.trim(), staffId, _ts]);
  }

  Future<ShiftSummary> summary(String shiftId) async {
    final s = await _select('SELECT opening_cash_minor FROM shift WHERE id = ?', [shiftId]);
    if (s.isEmpty) throw PosException('not_found', 'Shift not found');
    int one(List<Map<String, Object?>> r) => r.first['s'] as int;
    final sales = one(await _select("SELECT COALESCE(SUM(amount_minor),0) AS s FROM payment WHERE shift_id = ? AND method_kind = 'cash'", [shiftId]));
    final refunds = one(await _select("SELECT COALESCE(SUM(r.amount_minor),0) AS s FROM refund r JOIN payment_method m ON m.id = r.method_id WHERE r.shift_id = ? AND m.kind = 'cash'", [shiftId]));
    final cin = one(await _select("SELECT COALESCE(SUM(amount_minor),0) AS s FROM cash_movement WHERE shift_id = ? AND direction = 'in'", [shiftId]));
    final cout = one(await _select("SELECT COALESCE(SUM(amount_minor),0) AS s FROM cash_movement WHERE shift_id = ? AND direction = 'out'", [shiftId]));
    return ShiftSummary(openingMinor: s.first['opening_cash_minor'] as int, cashSalesMinor: sales, cashRefundsMinor: refunds, cashInMinor: cin, cashOutMinor: cout);
  }

  /// Closes the shift with the counted cash. Returns variance = counted - expected (negative = short).
  Future<int> closeShift(String shiftId, {required int countedMinor, String? note}) => db.transaction(() async {
        if (countedMinor < 0) throw PosException('bad_amount', 'Counted cash cannot be negative');
        final s = await _select('SELECT closed_at FROM shift WHERE id = ?', [shiftId]);
        if (s.isEmpty) throw PosException('not_found', 'Shift not found');
        if (s.first['closed_at'] != null) throw PosException('shift_closed', 'Shift already closed');
        final sum = await summary(shiftId);
        final variance = countedMinor - sum.expectedMinor;
        await db.customStatement('UPDATE shift SET closed_at=?, closing_cash_counted_minor=?, expected_cash_minor=?, variance_minor=?, note=? WHERE id=?',
            [_ts, countedMinor, sum.expectedMinor, variance, note, shiftId]);
        return variance;
      });

  /// Z report. Refuses while any shift is still open; stores an immutable snapshot (one per business date).
  Future<void> closeDay(String businessDate, {required String staffId}) => db.transaction(() async {
        if ((await _select('SELECT id FROM day_close WHERE business_date = ?', [businessDate])).isNotEmpty) {
          throw PosException('day_closed', 'Day $businessDate is already closed');
        }
        if ((await _select('SELECT id FROM shift WHERE closed_at IS NULL', [])).isNotEmpty) {
          throw PosException('shift_open', 'Close all open shifts first');
        }
        final r = await pos.salesReport(businessDate);
        await db.customStatement(
            'INSERT INTO day_close(id, business_date, closed_at, staff_id, gross_sales_minor, refunds_minor, net_sales_minor, tax_minor, payload) VALUES (?,?,?,?,?,?,?,?,?)',
            [_newId(), businessDate, _ts, staffId, r.grossMinor, r.refundsMinor, r.netMinor, r.taxMinor, jsonEncode({'bills': r.bills, 'byMethod': r.byMethod})]);
        await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, critical) VALUES (?,?,?,?,?,?,1)',
            [_newId(), _ts, staffId, 'day.close', 'day_close', businessDate]);
      });
}
