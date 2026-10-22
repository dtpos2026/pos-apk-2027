import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dt_food_pos/domain/license.dart';
import 'package:flutter_test/flutter_test.dart';

final ed = Ed25519();
late SimpleKeyPair keyPair;
late List<int> publicKey;
late LicenseVerifier verifier;

String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

Future<String> sign(Map<String, dynamic> payload, {SimpleKeyPair? with_}) async {
  final bytes = utf8.encode(jsonEncode(payload));
  final sig = await ed.sign(bytes, keyPair: with_ ?? keyPair);
  return '${b64(bytes)}.${b64(sig.bytes)}';
}

Map<String, dynamic> payload({String st = 'active', int? exp, int grace = 7, List<String> dev = const ['dev-1']}) => {
      'bid': 'biz-1',
      'dev': dev,
      'mod': ['pos', 'inventory'],
      'plan': 'monthly',
      'st': st,
      'grace': grace,
      'ver': 3,
      'iat': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      'exp': exp,
    };

final t0 = DateTime.utc(2026, 1, 10, 12);

Future<LicenseDecision> check(String token, {DateTime? now, DateTime? validated, DateTime? seen, String device = 'dev-1'}) =>
    verifier.evaluate(
      token: token,
      deviceId: device,
      now: now ?? t0,
      lastValidatedAt: validated ?? t0,
      highestWallClockSeen: seen ?? t0,
    );

void main() {
  setUpAll(() async {
    keyPair = await ed.newKeyPair();
    publicKey = (await keyPair.extractPublicKey()).bytes;
    verifier = LicenseVerifier(publicKey);
  });

  test('valid licence', () async {
    final d = await check(await sign(payload()));
    expect(d.status, LicenseStatus.valid);
    expect(d.canSell, isTrue);
    expect(d.graceDaysLeft, 7);
    expect(d.hasModule('inventory'), isTrue);
    expect(d.hasModule('kds'), isFalse);
  });

  test('tampered payload is rejected', () async {
    final token = await sign(payload());
    final parts = token.split('.');
    final forged = utf8.encode(jsonEncode({...payload(), 'mod': ['pos', 'inventory', 'kds'], 'grace': 9999}));
    final d = await check('${b64(forged)}.${parts[1]}');
    expect(d.status, LicenseStatus.invalid);
    expect(d.canSell, isFalse);
  });

  test('token signed by another key is rejected', () async {
    final other = await ed.newKeyPair();
    final d = await check(await sign(payload(), with_: other));
    expect(d.status, LicenseStatus.invalid);
  });

  test('garbage tokens are rejected, not thrown', () async {
    for (final t in ['', 'abc', 'a.b.c', '!!.!!']) {
      expect((await check(t)).status, LicenseStatus.invalid);
    }
  });

  test('wrong device', () async {
    expect((await check(await sign(payload()), device: 'dev-2')).status, LicenseStatus.wrongDevice);
  });

  test('suspended and blocked stop sales but still allow export', () async {
    final s = await check(await sign(payload(st: 'suspended')));
    expect(s.status, LicenseStatus.suspended);
    expect(s.canSell, isFalse);
    expect(s.canExport, isTrue);
    final b = await check(await sign(payload(st: 'blocked')));
    expect(b.status, LicenseStatus.blocked);
    expect(b.canSell, isFalse);
  });

  test('expiry', () async {
    final exp = t0.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
    final d = await check(await sign(payload(exp: exp)));
    expect(d.status, LicenseStatus.expired);
    expect(d.canSell, isFalse);
    expect(d.canExport, isTrue);
  });

  test('offline grace: warning, then locked', () async {
    final token = await sign(payload(grace: 7));
    final warn = await check(token, now: t0.add(const Duration(days: 5)), validated: t0, seen: t0);
    expect(warn.status, LicenseStatus.graceWarning);
    expect(warn.canSell, isTrue);
    final locked = await check(token, now: t0.add(const Duration(days: 7)), validated: t0, seen: t0);
    expect(locked.status, LicenseStatus.graceExpired);
    expect(locked.canSell, isFalse);
  });

  test('grace restarts after a new online validation', () async {
    final token = await sign(payload(grace: 7));
    final now = t0.add(const Duration(days: 20));
    expect((await check(token, now: now, validated: t0, seen: now)).status, LicenseStatus.graceExpired);
    expect((await check(token, now: now, validated: now, seen: now)).status, LicenseStatus.valid);
  });

  test('clock rollback is detected', () async {
    final token = await sign(payload(grace: 7));
    final d = await check(token, now: t0.subtract(const Duration(days: 3)), validated: t0, seen: t0);
    expect(d.status, LicenseStatus.clockTampered);
    expect(d.canSell, isFalse);
  });

  test('small clock adjustments are tolerated', () async {
    final token = await sign(payload());
    final d = await check(token, now: t0.subtract(const Duration(minutes: 5)), seen: t0);
    expect(d.status, LicenseStatus.valid);
  });

  test('no expiry means one-time licence', () async {
    final d = await check(await sign(payload(exp: null)), now: t0.add(const Duration(days: 1)), validated: t0.add(const Duration(days: 1)), seen: t0);
    expect(d.status, LicenseStatus.valid);
  });
}
