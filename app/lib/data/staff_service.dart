import 'auth_service.dart';
import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class StaffRow {
  const StaffRow({required this.id, required this.name, required this.roleId, required this.roleName, this.phone, required this.active});
  final String id;
  final String name;
  final String roleId;
  final String roleName;
  final String? phone;
  final bool active;
}

class RoleRow {
  const RoleRow(this.id, this.name);
  final String id;
  final String name;
}

/// Staff accounts. Only holders of `staff.manage` may change them; the last active owner can never be removed.
class StaffService {
  StaffService(this.h, this.auth);
  final DbHelper h;
  final AuthService auth;

  Future<List<RoleRow>> roles() async => [for (final r in await h.q('SELECT id, name FROM role WHERE deleted_at IS NULL ORDER BY is_system DESC, name')) RoleRow(r['id'] as String, r['name'] as String)];

  Future<List<StaffRow>> list() async => [
        for (final r in await h.q('SELECT s.id, s.name, s.phone, s.active, s.role_id, r.name AS role FROM staff s JOIN role r ON r.id = s.role_id WHERE s.deleted_at IS NULL ORDER BY s.active DESC, s.name'))
          StaffRow(id: r['id'] as String, name: r['name'] as String, roleId: r['role_id'] as String, roleName: r['role'] as String, phone: r['phone'] as String?, active: (r['active'] as int) == 1)
      ];

  Future<String> add({required String actor, required String name, required String roleId, required String pin, String? phone}) async {
    await h.require(actor, 'staff.manage');
    if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
    final id = await auth.createStaff(name: name.trim(), roleId: roleId, pin: pin, phone: phone);
    await h.audit('staff.add', staffId: actor, entity: 'staff', entityId: id, after: {'name': name.trim(), 'role': roleId}, critical: true);
    return id;
  }

  Future<int> _activeOwners({String? except}) => h.intValue(
      "SELECT COUNT(*) FROM staff s JOIN role r ON r.id = s.role_id WHERE s.active = 1 AND s.deleted_at IS NULL AND r.permissions LIKE '%\"*\"%' AND s.id <> ?", [except ?? '']);

  Future<void> setActive({required String actor, required String staffId, required bool active}) => h.db.transaction(() async {
        await h.require(actor, 'staff.manage');
        if (!active) {
          if (staffId == actor) throw PosException('self', 'You cannot deactivate yourself');
          if (await _activeOwners(except: staffId) == 0) throw PosException('last_owner', 'There must be at least one active owner');
        }
        await h.exec('UPDATE staff SET active = ?, updated_at = ?, version = version + 1 WHERE id = ?', [active ? 1 : 0, h.ts, staffId]);
        await h.audit(active ? 'staff.activate' : 'staff.deactivate', staffId: actor, entity: 'staff', entityId: staffId, critical: true);
      });

  Future<void> changeRole({required String actor, required String staffId, required String roleId}) => h.db.transaction(() async {
        await h.require(actor, 'staff.manage');
        final role = await h.one('SELECT permissions FROM role WHERE id = ?', [roleId]);
        if (role == null) throw PosException('not_found', 'Role not found');
        final becomesOwner = (role['permissions'] as String).contains('"*"');
        if (!becomesOwner && await _activeOwners(except: staffId) == 0) throw PosException('last_owner', 'There must be at least one active owner');
        await h.exec('UPDATE staff SET role_id = ?, updated_at = ?, version = version + 1 WHERE id = ?', [roleId, h.ts, staffId]);
        await h.audit('staff.role_change', staffId: actor, entity: 'staff', entityId: staffId, after: {'role': roleId}, critical: true);
      });

  Future<void> resetPin({required String actor, required String staffId, required String newPin}) async {
    await h.require(actor, 'staff.manage');
    await auth.changePin(staffId, newPin);
    await h.audit('staff.pin_reset', staffId: actor, entity: 'staff', entityId: staffId, critical: true);
  }
}
