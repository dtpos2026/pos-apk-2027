import 'dart:convert';

import 'auth_service.dart';
import 'db_helper.dart';
import 'pos_service.dart' show PosException;

/// The screens an owner can switch on for one staff member, and the things they may do. Staff and Settings are never offered:
/// they stay with the Owner and Manager roles, so nobody can give themselves more power.
const accessScreens = ['pos', 'dashboard', 'tables', 'kitchen', 'online', 'tokens', 'bills', 'reports', 'customers', 'expenses', 'inventory', 'menu'];
const accessActions = ['discount.apply', 'bill.void', 'bill.refund', 'shift.manage', 'day.close'];

/// What a screen needs besides being listed: the old-style permission the rest of the app checks.
const _screenImplies = {'pos': 'pos.sell', 'dashboard': 'reports.view', 'reports': 'reports.view', 'inventory': 'inventory.manage', 'menu': 'menu.manage'};

/// A staff member's access as the owner sees it: screens and actions.
class StaffAccess {
  const StaffAccess({required this.screens, required this.actions, required this.custom});
  final Set<String> screens;
  final Set<String> actions;

  /// false = access comes from the role (everything the role normally has).
  final bool custom;
}

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

  Future<List<RoleRow>> roles() async => [for (final r in await h.q('SELECT id, name FROM role WHERE deleted_at IS NULL AND is_system = 1 ORDER BY name')) RoleRow(r['id'] as String, r['name'] as String)];

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

  /// The screens and actions of a staff member. A role with no screen list shows what it always showed (see [Session.canOpen]).
  Future<StaffAccess> accessOf(String staffId) async {
    final r = await h.one('SELECT r.permissions AS p, r.is_system AS sys FROM staff s JOIN role r ON r.id = s.role_id WHERE s.id = ?', [staffId]);
    final perms = r == null ? <String>[] : (jsonDecode(r['p'] as String) as List).cast<String>();
    final screens = {for (final p in perms) if (p.startsWith('screen.')) p.substring(7)};
    if (screens.isNotEmpty) return StaffAccess(screens: screens, actions: perms.where(accessActions.contains).toSet(), custom: true);
    if (perms.contains('*')) return StaffAccess(screens: {...accessScreens}, actions: {...accessActions}, custom: false);
    // a normal role: show it as the screens it opens today
    final legacy = <String>{
      if (perms.contains('pos.sell')) ...['pos', 'tables', 'kitchen', 'online', 'tokens', 'bills', 'customers', 'expenses'],
      if (perms.contains('reports.view')) ...['dashboard', 'reports'],
      if (perms.contains('inventory.manage')) 'inventory',
      if (perms.contains('menu.manage')) 'menu',
    };
    return StaffAccess(screens: legacy, actions: perms.where(accessActions.contains).toSet(), custom: false);
  }

  /// Gives one staff member their own list of screens and actions (their own private role). Staff and Settings can't be chosen.
  Future<void> setAccess({required String actor, required String staffId, required Set<String> screens, required Set<String> actions}) => h.db.transaction(() async {
        await h.require(actor, 'staff.manage');
        final cleanScreens = screens.where(accessScreens.contains).toSet();
        final cleanActions = actions.where(accessActions.contains).toSet();
        if (cleanScreens.isEmpty) throw PosException('no_screens', 'Choose at least one screen');
        final st = await h.one('SELECT name, role_id FROM staff WHERE id = ?', [staffId]);
        if (st == null) throw PosException('not_found', 'Staff member not found');
        final current = await h.one('SELECT permissions, is_system FROM role WHERE id = ?', [st['role_id']]);
        if (current != null && (current['permissions'] as String).contains('"*"')) throw PosException('owner', 'An owner always has full access');
        final perms = <String>[
          for (final sc in accessScreens) if (cleanScreens.contains(sc)) 'screen.$sc',
          ...{for (final sc in cleanScreens) if (_screenImplies[sc] != null) _screenImplies[sc]!},
          ...cleanActions,
        ];
        final name = 'Custom · ${st['name']}';
        final mine = await h.one('SELECT id FROM role WHERE id = ? AND is_system = 0', [st['role_id']]);
        if (mine != null) {
          await h.exec('UPDATE role SET permissions = ?, updated_at = ?, version = version + 1 WHERE id = ?', [jsonEncode(perms), h.ts, mine['id']]);
        } else {
          final rid = h.id;
          // names are unique: a second custom role for the same name gets a number
          var unique = name;
          for (var n = 2; await h.one('SELECT 1 AS x FROM role WHERE name = ?', [unique]) != null; n++) {
            unique = '$name ($n)';
          }
          await h.exec('INSERT INTO role(id, name, permissions, is_system, updated_at) VALUES (?,?,?,0,?)', [rid, unique, jsonEncode(perms), h.ts]);
          await h.exec('UPDATE staff SET role_id = ?, updated_at = ?, version = version + 1 WHERE id = ?', [rid, h.ts, staffId]);
        }
        await h.audit('staff.access', staffId: actor, entity: 'staff', entityId: staffId, after: {'screens': cleanScreens.toList(), 'actions': cleanActions.toList()}, critical: true);
      });

  Future<int> _activeOwners({String? except}) => h.intValue(
      "SELECT COUNT(*) FROM staff s JOIN role r ON r.id = s.role_id WHERE s.active = 1 AND s.deleted_at IS NULL AND r.permissions LIKE '%\"*\"%' AND s.id <> ?", [except ?? '']);

  Future<int> dailyWage(String staffId) async => ((await h.one('SELECT daily_wage_minor AS w FROM staff WHERE id = ?', [staffId]))?['w'] as int?) ?? 0;

  Future<void> setDailyWage({required String actor, required String staffId, required int wageMinor}) => h.db.transaction(() async {
        await h.require(actor, 'staff.manage');
        if (wageMinor < 0) throw PosException('invalid', 'Wage cannot be negative');
        await h.exec('UPDATE staff SET daily_wage_minor = ?, updated_at = ?, version = version + 1 WHERE id = ?', [wageMinor, h.ts, staffId]);
        await h.audit('staff.wage', staffId: actor, entity: 'staff', entityId: staffId);
      });

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
