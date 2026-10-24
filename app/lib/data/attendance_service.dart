import 'db_helper.dart';
import 'pos_service.dart' show PosException;

/// One staff member's day: when they clocked in and out, and the wage that day carries.
class AttendanceRow {
  const AttendanceRow({required this.staffId, required this.staffName, required this.day, this.checkIn, this.checkOut, this.wageMinor = 0});
  final String staffId;
  final String staffName;
  final String day;
  final int? checkIn;
  final int? checkOut;
  final int wageMinor;

  bool get atWork => checkIn != null && checkOut == null;

  /// Minutes worked; a person still at work counts up to [now].
  int minutes(DateTime now) {
    if (checkIn == null) return 0;
    final end = checkOut ?? now.millisecondsSinceEpoch;
    return ((end - checkIn!) / 60000).floor().clamp(0, 24 * 60);
  }
}

class AttendanceMonth {
  const AttendanceMonth({required this.staffId, required this.staffName, required this.days, required this.minutes, required this.wageMinor});
  final String staffId;
  final String staffName;
  final int days;
  final int minutes;
  final int wageMinor;
}

String hoursText(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

/// Clock in / clock out per staff member and day (one row a day), with the wage the day earns (the staff member's daily wage).
class AttendanceService {
  AttendanceService(this.h);
  final DbHelper h;

  Future<void> clockIn(String staffId) async {
    final day = h.businessDate;
    final staff = await h.one('SELECT daily_wage_minor FROM staff WHERE id = ? AND deleted_at IS NULL', [staffId]);
    if (staff == null) throw PosException('not_found', 'Staff member not found');
    final row = await h.one('SELECT id, check_in, check_out FROM attendance WHERE staff_id = ? AND day = ?', [staffId, day]);
    if (row == null) {
      await h.exec('INSERT INTO attendance(id, staff_id, day, check_in, wage_minor) VALUES (?,?,?,?,?)', [h.id, staffId, day, h.ts, staff['daily_wage_minor']]);
    } else if (row['check_out'] == null && row['check_in'] != null) {
      throw PosException('already_in', 'Already clocked in');
    } else {
      // came back the same day: the day carries on (the time away is not counted twice because check-out is cleared)
      await h.exec('UPDATE attendance SET check_out = NULL WHERE id = ?', [row['id']]);
    }
  }

  Future<void> clockOut(String staffId) async {
    final row = await h.one('SELECT id FROM attendance WHERE staff_id = ? AND check_in IS NOT NULL AND check_out IS NULL ORDER BY day DESC LIMIT 1', [staffId]);
    if (row == null) throw PosException('not_in', 'Not clocked in');
    await h.exec('UPDATE attendance SET check_out = ? WHERE id = ?', [h.ts, row['id']]);
  }

  /// Everyone active, with today's (or [day]'s) record when there is one.
  Future<List<AttendanceRow>> forDay(String day) async => [
        for (final r in await h.q(
            'SELECT s.id AS sid, s.name AS name, a.check_in AS ci, a.check_out AS co, COALESCE(a.wage_minor,0) AS wage FROM staff s LEFT JOIN attendance a ON a.staff_id = s.id AND a.day = ? WHERE s.deleted_at IS NULL AND s.active = 1 ORDER BY s.name',
            [day]))
          AttendanceRow(staffId: r['sid'] as String, staffName: r['name'] as String, day: day, checkIn: r['ci'] as int?, checkOut: r['co'] as int?, wageMinor: r['wage'] as int)
      ];

  /// Days present, hours and wages per person for a month ('YYYY-MM').
  Future<List<AttendanceMonth>> month(String yearMonth, {required DateTime now}) async {
    final rows = await h.q("SELECT a.staff_id AS sid, s.name AS name, a.check_in AS ci, a.check_out AS co, a.wage_minor AS wage FROM attendance a JOIN staff s ON s.id = a.staff_id WHERE substr(a.day,1,7) = ? AND a.check_in IS NOT NULL ORDER BY s.name", [yearMonth]);
    final by = <String, (String, int, int, int)>{};
    for (final r in rows) {
      final row = AttendanceRow(staffId: r['sid'] as String, staffName: r['name'] as String, day: '', checkIn: r['ci'] as int?, checkOut: r['co'] as int?);
      final prev = by[row.staffId] ?? (row.staffName, 0, 0, 0);
      by[row.staffId] = (prev.$1, prev.$2 + 1, prev.$3 + row.minutes(now), prev.$4 + (r['wage'] as int));
    }
    return [for (final e in by.entries) AttendanceMonth(staffId: e.key, staffName: e.value.$1, days: e.value.$2, minutes: e.value.$3, wageMinor: e.value.$4)];
  }
}
