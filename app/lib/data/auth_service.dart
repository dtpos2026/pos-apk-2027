import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';

enum PinResult { ok, wrong, locked, unknown }

/// Staff PIN storage and checking. PINs are never stored: only a salted PBKDF2-HMAC-SHA256 hash.
/// After [maxFailures] wrong PINs the account is locked for [lockFor].
class AuthService {
  AuthService(this.db, {DateTime Function()? now, this.iterations = 120000, this.maxFailures = 5, this.lockFor = const Duration(minutes: 5), Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();
  final AppDatabase db;
  final DateTime Function() _now;
  final int iterations;
  final int maxFailures;
  final Duration lockFor;
  final Random _random;

  static final _pinFormat = RegExp(r'^\d{4,8}$');

  Future<String> _hash(String pin, List<int> salt) async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return base64.encode(await key.extractBytes());
  }

  List<int> _newSalt() => List<int>.generate(16, (_) => _random.nextInt(256));

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<String> createStaff({required String name, required String roleId, required String pin, String? phone}) async {
    if (!_pinFormat.hasMatch(pin)) throw ArgumentError('PIN must be 4 to 8 digits');
    final salt = _newSalt();
    final id = const Uuid().v4();
    await db.customStatement(
        'INSERT INTO staff(id, name, phone, role_id, pin_hash, pin_salt, updated_at) VALUES (?,?,?,?,?,?,?)',
        [id, name, phone, roleId, await _hash(pin, salt), base64.encode(salt), _now().millisecondsSinceEpoch]);
    return id;
  }

  Future<void> changePin(String staffId, String newPin) async {
    if (!_pinFormat.hasMatch(newPin)) throw ArgumentError('PIN must be 4 to 8 digits');
    final salt = _newSalt();
    await db.customStatement('UPDATE staff SET pin_hash=?, pin_salt=?, failed_pins=0, locked_until=NULL, updated_at=?, version=version+1 WHERE id=?',
        [await _hash(newPin, salt), base64.encode(salt), _now().millisecondsSinceEpoch, staffId]);
  }

  Future<PinResult> verifyPin(String staffId, String pin) async {
    final rows = await db.customSelect('SELECT pin_hash, pin_salt, failed_pins, locked_until FROM staff WHERE id = ? AND active = 1 AND deleted_at IS NULL',
        variables: [Variable.withString(staffId)]).get();
    if (rows.isEmpty) return PinResult.unknown;
    final r = rows.first.data;
    final now = _now().millisecondsSinceEpoch;
    final lockedUntil = r['locked_until'] as int?;
    if (lockedUntil != null && lockedUntil > now) return PinResult.locked;

    final ok = _pinFormat.hasMatch(pin) && _constantTimeEquals(await _hash(pin, base64.decode(r['pin_salt'] as String)), r['pin_hash'] as String);
    if (ok) {
      await db.customStatement('UPDATE staff SET failed_pins=0, locked_until=NULL WHERE id=?', [staffId]);
      return PinResult.ok;
    }
    final failed = (r['failed_pins'] as int) + 1;
    final lock = failed >= maxFailures ? now + lockFor.inMilliseconds : null;
    await db.customStatement('UPDATE staff SET failed_pins=?, locked_until=? WHERE id=?', [lock != null ? 0 : failed, lock, staffId]);
    await db.customStatement(
        'INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, critical) VALUES (?,?,?,?,?,?,?)',
        [const Uuid().v4(), now, staffId, lock != null ? 'auth.locked' : 'auth.pin_failed', 'staff', staffId, lock != null ? 1 : 0]);
    return lock != null ? PinResult.locked : PinResult.wrong;
  }
}
