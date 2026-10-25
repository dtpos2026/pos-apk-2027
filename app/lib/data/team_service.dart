import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class RiderRow {
  const RiderRow({required this.id, required this.name, this.phone, this.bikeNo, required this.active, this.deliveries = 0, this.totalMinor = 0});
  final String id;
  final String name;
  final String? phone;
  final String? bikeNo;
  final bool active;

  /// Delivery bills given to this rider on the day asked for, and what they add up to (cancelled and void bills are left out).
  final int deliveries;
  final int totalMinor;
}

/// Delivery riders: a simple list (they do not sign in) that cashiers pick from on a delivery order.
class TeamService {
  TeamService(this.h);
  final DbHelper h;

  Future<List<RiderRow>> riders({String? day, bool activeOnly = false}) => members('rider', day: day, activeOnly: activeOnly);

  /// Dine-in waiters (a simple list, no sign-in). Same shape as riders; the bill count is the orders they served that day.
  Future<List<RiderRow>> waiters({String? day, bool activeOnly = false}) => members('waiter', day: day, activeOnly: activeOnly);

  Future<List<RiderRow>> members(String kind, {String? day, bool activeOnly = false}) async {
    final col = kind == 'waiter' ? 'waiter_member_id' : 'rider_id';
    final rows = await h.q(
        'SELECT m.id, m.name, m.phone, m.bike_no, m.active, '
        "(SELECT COUNT(*) FROM \"order\" o WHERE o.$col = m.id AND o.business_date = ? AND o.status NOT IN ('void','cancelled')) AS n, "
        "(SELECT COALESCE(SUM(o.total_minor),0) FROM \"order\" o WHERE o.$col = m.id AND o.business_date = ? AND o.status NOT IN ('void','cancelled')) AS total "
        "FROM team_member m WHERE m.deleted_at IS NULL AND m.kind = '$kind' ${activeOnly ? 'AND m.active = 1' : ''} ORDER BY m.active DESC, m.name",
        [day ?? '', day ?? '']);
    return [
      for (final r in rows)
        RiderRow(id: r['id'] as String, name: r['name'] as String, phone: r['phone'] as String?, bikeNo: r['bike_no'] as String?, active: (r['active'] as int) == 1, deliveries: r['n'] as int, totalMinor: r['total'] as int),
    ];
  }

  Future<String> saveRider({String? id, required String name, String? phone, String? bikeNo, required String staffId}) => saveMember('rider', id: id, name: name, phone: phone, bikeNo: bikeNo, staffId: staffId);

  Future<String> saveWaiter({String? id, required String name, String? phone, required String staffId}) => saveMember('waiter', id: id, name: name, phone: phone, staffId: staffId);

  Future<String> saveMember(String kind, {String? id, required String name, String? phone, String? bikeNo, required String staffId}) async {
    if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
    final p = (phone ?? '').trim().isEmpty ? null : phone!.trim();
    final b = (bikeNo ?? '').trim().isEmpty ? null : bikeNo!.trim();
    final dup = await h.one("SELECT id FROM team_member WHERE kind = ? AND deleted_at IS NULL AND lower(name) = lower(?) AND id <> ?", [kind, name.trim(), id ?? '']);
    if (dup != null) throw PosException('duplicate', kind == 'waiter' ? 'A waiter with this name already exists' : 'A rider with this name already exists');
    final rid = id ?? h.id;
    if (id == null) {
      await h.exec("INSERT INTO team_member(id, kind, name, phone, bike_no, updated_at) VALUES (?,?,?,?,?,?)", [rid, kind, name.trim(), p, b, h.ts]);
    } else {
      await h.exec('UPDATE team_member SET name=?, phone=?, bike_no=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), p, b, h.ts, id]);
    }
    await h.audit(id == null ? '$kind.add' : '$kind.edit', staffId: staffId, entity: 'team_member', entityId: rid, after: {'name': name.trim()});
    return rid;
  }

  Future<void> setActive(String id, bool active, {required String staffId}) async {
    await h.exec('UPDATE team_member SET active=?, updated_at=?, version=version+1 WHERE id=?', [active ? 1 : 0, h.ts, id]);
    await h.audit(active ? 'member.activate' : 'member.deactivate', staffId: staffId, entity: 'team_member', entityId: id);
  }

  /// A rider is only hidden, never erased: bills they delivered keep their name.
  Future<void> delete(String id, {required String staffId}) async {
    await h.exec('UPDATE team_member SET deleted_at=?, active=0, updated_at=?, version=version+1 WHERE id=?', [h.ts, h.ts, id]);
    await h.audit('member.delete', staffId: staffId, entity: 'team_member', entityId: id);
  }
}
