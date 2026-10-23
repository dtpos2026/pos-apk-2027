import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';
import 'pos_service.dart' show PosException;

/// Small shared toolbox for services: parameterised SQL, audit rows and outbox rows.
class DbHelper {
  DbHelper(this.db, {DateTime Function()? now, String Function()? newId, this.deviceId = 'device'})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final String deviceId;
  final DateTime Function() _now;
  final String Function() _newId;

  int get ts => _now().millisecondsSinceEpoch;
  String get id => _newId();
  String get businessDate {
    final n = _now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Variable _v(Object? o) {
    if (o == null) return const Variable<Object>(null);
    if (o is int) return Variable.withInt(o);
    if (o is String) return Variable.withString(o);
    throw ArgumentError('unsupported variable ${o.runtimeType}');
  }

  Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
      (await db.customSelect(sql, variables: args.map(_v).toList()).get()).map((r) => r.data).toList();

  Future<Map<String, Object?>?> one(String sql, [List<Object?> args = const []]) async => (await q(sql, args)).firstOrNull;

  Future<int> intValue(String sql, [List<Object?> args = const []]) async => ((await one(sql, args))?.values.first as int?) ?? 0;

  Future<void> exec(String sql, [List<Object?> args = const []]) => db.customStatement(sql, args);

  Future<void> audit(String event, {String? staffId, String? entity, String? entityId, Object? before, Object? after, String? reason, bool critical = false}) => exec(
      'INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, before_json, after_json, reason, device_id, critical) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [id, ts, staffId, event, entity, entityId, before == null ? null : jsonEncode(before), after == null ? null : jsonEncode(after), reason, deviceId, critical ? 1 : 0]);

  Future<void> outbox(String entity, String entityId, String op, Map<String, dynamic> payload, String key, {int? version}) => exec(
      'INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,?,?,?,?)',
      [key, entity, entityId, op, jsonEncode(payload), version, ts]);

  /// Throws [PosException] unless [staffId] holds [permission] (or '*').
  Future<void> require(String staffId, String permission) async {
    final r = await one('SELECT r.permissions AS p FROM staff s JOIN role r ON r.id = s.role_id WHERE s.id = ? AND s.active = 1 AND s.deleted_at IS NULL', [staffId]);
    final perms = r == null ? const <String>[] : (jsonDecode(r['p'] as String) as List).cast<String>();
    if (!perms.contains('*') && !perms.contains(permission)) throw PosException('permission_denied', 'Missing permission: $permission');
  }

  Future<String?> openShiftOf(String staffId) async => (await one('SELECT id FROM shift WHERE staff_id = ? AND closed_at IS NULL', [staffId]))?['id'] as String?;
}
