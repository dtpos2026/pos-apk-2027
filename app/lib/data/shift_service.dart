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

class ShiftLine {
  const ShiftLine({this.id = '', this.autoClosed = false, required this.staff, required this.openedAt, this.closedAt, required this.openingMinor, this.expectedMinor, this.countedMinor, this.varianceMinor});

  /// The shift id (empty in a saved snapshot where it is no longer needed) and whether the day close closed it without a count.
  final String id;
  final bool autoClosed;
  Map<String, Object?> toJson() => {'staff': staff, 'openedAt': openedAt, 'closedAt': closedAt, 'opening': openingMinor, 'expected': expectedMinor, 'counted': countedMinor, 'variance': varianceMinor, 'auto': autoClosed};
  factory ShiftLine.fromJson(Map<String, dynamic> j) => ShiftLine(
      staff: j['staff'] as String? ?? '-', openedAt: (j['openedAt'] as num).toInt(), closedAt: (j['closedAt'] as num?)?.toInt(), openingMinor: (j['opening'] as num).toInt(),
      expectedMinor: (j['expected'] as num?)?.toInt(), countedMinor: (j['counted'] as num?)?.toInt(), varianceMinor: (j['variance'] as num?)?.toInt(), autoClosed: j['auto'] as bool? ?? false);
  final String staff;
  final int openedAt;
  final int? closedAt;
  final int openingMinor;
  final int? expectedMinor;
  final int? countedMinor;
  final int? varianceMinor;
}

/// End-of-day (Z) report figures. Gross = settled bills incl. tax; net = gross - refunds.
class ZReport {
  const ZReport({
    required this.date, required this.bills, required this.grossMinor, required this.discountMinor, required this.refundsMinor,
    required this.taxMinor, required this.byMethod, required this.creditGivenMinor, required this.creditRecoveredMinor,
    required this.expensesMinor, required this.shifts, this.closedAt, this.openOrders = 0, this.problems = const [],
  });

  /// Unpaid orders still open (held, or in the kitchen): not part of this report; they carry on to the next day.
  final int openOrders;

  /// Figures that do not add up (live report only). While there are any, the day cannot be closed.
  final List<String> problems;
  final String date;
  final int bills;
  final int grossMinor;
  final int discountMinor;
  final int refundsMinor;
  final int taxMinor;
  final Map<String, int> byMethod;
  final int creditGivenMinor;
  final int creditRecoveredMinor;
  final int expensesMinor;
  final List<ShiftLine> shifts;

  /// When the day was closed; null = still open.
  final int? closedAt;
  int get netMinor => grossMinor - refundsMinor;
  int get cashVarianceMinor => shifts.fold(0, (s, x) => s + (x.varianceMinor ?? 0));
  bool get anyShiftOpen => shifts.any((x) => x.closedAt == null);

  /// The saved snapshot: closing the day stores exactly this, so a closed day always shows the figures it was closed with.
  Map<String, Object?> toJson() => {
        'v': 2, 'bills': bills, 'gross': grossMinor, 'discount': discountMinor, 'refunds': refundsMinor, 'tax': taxMinor, 'byMethod': byMethod,
        'creditGiven': creditGivenMinor, 'creditRecovered': creditRecoveredMinor, 'expenses': expensesMinor, 'shifts': [for (final x in shifts) x.toJson()], 'openOrders': openOrders,
      };
  factory ZReport.fromJson(String date, Map<String, dynamic> j, {int? closedAt}) => ZReport(
        date: date, bills: (j['bills'] as num).toInt(), grossMinor: (j['gross'] as num).toInt(), discountMinor: (j['discount'] as num).toInt(), refundsMinor: (j['refunds'] as num).toInt(),
        taxMinor: (j['tax'] as num).toInt(), byMethod: {for (final e in (j['byMethod'] as Map).entries) e.key as String: (e.value as num).toInt()},
        creditGivenMinor: (j['creditGiven'] as num).toInt(), creditRecoveredMinor: (j['creditRecovered'] as num).toInt(), expensesMinor: (j['expenses'] as num).toInt(),
        shifts: [for (final x in (j['shifts'] as List)) ShiftLine.fromJson((x as Map).cast<String, dynamic>())], closedAt: closedAt, openOrders: (j['openOrders'] as num?)?.toInt() ?? 0,
      );
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

  /// Figures for one business date ('YYYY-MM-DD'), whether or not the day has been closed.
  Future<ZReport> zReport(String businessDate) async {
    // a closed day shows the snapshot saved when it was closed (not a recalculation, which later refunds could change)
    final saved = await _select('SELECT closed_at, payload FROM day_close WHERE business_date = ?', [businessDate]);
    if (saved.isNotEmpty) {
      try {
        final j = jsonDecode(saved.first['payload'] as String) as Map<String, dynamic>;
        if (j['v'] == 2) return ZReport.fromJson(businessDate, j, closedAt: saved.first['closed_at'] as int);
      } catch (_) {
        // an older or damaged snapshot: fall back to the live figures below
      }
    }
    final r = await pos.salesReport(businessDate);
    final p = businessDate.split('-').map(int.parse).toList();
    final from = DateTime(p[0], p[1], p[2]).millisecondsSinceEpoch, to = DateTime(p[0], p[1], p[2] + 1).millisecondsSinceEpoch;
    int one(List<Map<String, Object?>> rows) => (rows.first.values.first as int?) ?? 0;
    final discount = one(await _select("SELECT COALESCE(SUM(discount_minor),0) AS v FROM \"order\" WHERE business_date = ? AND status IN ('paid','void','refunded')", [businessDate]));
    final credit = one(await _select("SELECT COALESCE(SUM(p.amount_minor),0) AS v FROM payment p JOIN \"order\" o ON o.id = p.order_id WHERE o.business_date = ? AND p.method_kind = 'credit'", [businessDate]));
    final recovered = -one(await _select("SELECT COALESCE(SUM(amount_minor),0) AS v FROM customer_ledger WHERE kind = 'recovery' AND created_at >= ? AND created_at < ?", [from, to]));
    final expenses = one(await _select('SELECT COALESCE(SUM(amount_minor),0) AS v FROM expense WHERE business_date = ?', [businessDate]));
    final shifts = [
      for (final s in await _select(
          'SELECT s.*, st.name AS staff_name FROM shift s LEFT JOIN staff st ON st.id = s.staff_id WHERE (s.opened_at >= ? AND s.opened_at < ?) OR (s.closed_at >= ? AND s.closed_at < ?) OR (s.closed_at IS NULL AND s.opened_at < ?) ORDER BY s.opened_at',
          [from, to, from, to, to]))
        ShiftLine(
          id: s['id'] as String, autoClosed: ((s['note'] as String?) ?? '').startsWith('Closed by day close'), staff: (s['staff_name'] as String?) ?? '-', openedAt: s['opened_at'] as int, closedAt: s['closed_at'] as int?, openingMinor: s['opening_cash_minor'] as int,
          expectedMinor: s['expected_cash_minor'] as int?, countedMinor: s['closing_cash_counted_minor'] as int?, varianceMinor: s['variance_minor'] as int?,
        ),
    ];
    final closed = await _select('SELECT closed_at FROM day_close WHERE business_date = ?', [businessDate]);
    final openOrders = (await _select("SELECT COUNT(*) AS n FROM \"order\" WHERE status IN ('held','new','preparing','ready','served') AND EXISTS (SELECT 1 FROM order_item i WHERE i.order_id = \"order\".id)")).first['n'] as int;
    return ZReport(
      openOrders: openOrders, problems: closed.isEmpty ? await integrityProblems(businessDate) : const [],
      date: businessDate, bills: r.bills, grossMinor: r.grossMinor, discountMinor: discount, refundsMinor: r.refundsMinor, taxMinor: r.taxMinor,
      byMethod: r.byMethod, creditGivenMinor: credit, creditRecoveredMinor: recovered, expensesMinor: expenses, shifts: shifts,
      closedAt: closed.isEmpty ? null : closed.first['closed_at'] as int,
    );
  }

  /// Checks that the day's money adds up before it is closed. Returns plain-language problems; empty = fine.
  ///  * every settled bill is covered exactly by its payments,
  ///  * no payment belongs to a bill that is not settled,
  ///  * refunds never exceed what was paid for the bill.
  Future<List<String>> integrityProblems(String businessDate) async {
    final out = <String>[];
    final mismatched = await _select(
        "SELECT COALESCE(o.invoice_no, o.id) AS ref, o.total_minor AS total, COALESCE((SELECT SUM(amount_minor) FROM payment WHERE order_id = o.id),0) AS paid FROM \"order\" o WHERE o.business_date = ? AND o.status IN ('paid','void','refunded') AND o.total_minor <> COALESCE((SELECT SUM(amount_minor) FROM payment WHERE order_id = o.id),0) LIMIT 5",
        [businessDate]);
    for (final m in mismatched) {
      out.add('Bill ${m['ref']}: total ${m['total']} but payments add up to ${m['paid']}');
    }
    final orphan = await _select(
        "SELECT COUNT(*) AS n FROM payment p JOIN \"order\" o ON o.id = p.order_id WHERE o.business_date = ? AND o.status NOT IN ('paid','void','refunded')", [businessDate]);
    if ((orphan.first['n'] as int) > 0) out.add('${orphan.first['n']} payment(s) belong to a bill that is not settled');
    final over = await _select(
        "SELECT COALESCE(o.invoice_no, o.id) AS ref FROM \"order\" o WHERE o.business_date = ? AND (SELECT COALESCE(SUM(amount_minor),0) FROM refund WHERE order_id = o.id) > COALESCE((SELECT SUM(amount_minor) FROM payment WHERE order_id = o.id),0) LIMIT 5",
        [businessDate]);
    for (final m in over) {
      out.add('Bill ${m['ref']}: refunds are more than the amount paid');
    }
    return out;
  }

  /// Closes the business day in ONE transaction: checks the figures add up, closes the cash shifts that belong to the day
  /// (counted cash per shift can be given in [countedByShift]; a shift left without a count is closed with its expected cash and
  /// marked "not counted", never with an invented count), saves the full Z report snapshot, and records the audit entry.
  /// Open shifts do not block closing: they are part of the day being closed. Closing twice is refused. After this, new sales
  /// belong to the next business day. Unpaid open orders are not touched (they are counted in the report as carried over).
  Future<ZReport> closeDay(String businessDate, {required String staffId, Map<String, int> countedByShift = const {}}) => db.transaction(() async {
        if ((await _select('SELECT id FROM day_close WHERE business_date = ?', [businessDate])).isNotEmpty) {
          throw PosException('day_closed', 'Day $businessDate is already closed');
        }
        final problems = await integrityProblems(businessDate);
        if (problems.isNotEmpty) throw PosException('reconcile_failed', 'The figures do not add up yet: ${problems.join('; ')}');
        final p = businessDate.split('-').map(int.parse).toList();
        final end = DateTime(p[0], p[1], p[2] + 1).millisecondsSinceEpoch;
        final open = await _select('SELECT id FROM shift WHERE closed_at IS NULL AND opened_at < ?', [end]);
        for (final sh in open) {
          final id = sh['id'] as String;
          final sum = await summary(id);
          final counted = countedByShift[id];
          if (counted != null && counted < 0) throw PosException('bad_amount', 'Counted cash cannot be negative');
          await db.customStatement(
              'UPDATE shift SET closed_at = ?, closing_cash_counted_minor = ?, expected_cash_minor = ?, variance_minor = ?, note = ? WHERE id = ?',
              [_ts, counted, sum.expectedMinor, counted == null ? null : counted - sum.expectedMinor, counted == null ? 'Closed by day close; cash not counted' : 'Closed by day close', id]);
        }
        final report = await zReport(businessDate);
        await db.customStatement(
            'INSERT INTO day_close(id, business_date, closed_at, staff_id, gross_sales_minor, refunds_minor, net_sales_minor, tax_minor, payload) VALUES (?,?,?,?,?,?,?,?,?)',
            [_newId(), businessDate, _ts, staffId, report.grossMinor, report.refundsMinor, report.netMinor, report.taxMinor, jsonEncode(report.toJson())]);
        await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, critical) VALUES (?,?,?,?,?,?,1)',
            [_newId(), _ts, staffId, 'day.close', 'day_close', businessDate]);
        return zReport(businessDate);
      });
}
