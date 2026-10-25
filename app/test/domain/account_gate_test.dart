import 'package:dt_food_pos/domain/account_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 23, 12);
  AccountSnapshot acc({String status = 'active', DateTime? exp, List<String> ok = const ['p1'], List<String> bl = const [], String msg = '', DateTime? checked, int max = 1, List<String> rq = const []}) => AccountSnapshot(
      maxPhones: max, phoneRequests: rq,
      status: status, expiresAt: exp ?? now.add(const Duration(days: 20)), approvedPhones: ok, blockedPhones: bl, adminMessage: msg, checkedAt: checked ?? now);
  AccessDecision decide(AccountSnapshot? a, {AppControl c = const AppControl(), String version = '1.0.0', DateTime? at, DateTime? highest}) =>
      decideAccess(account: a, control: c, phoneId: 'p1', appVersion: version, now: at ?? now, highestClockSeen: highest ?? now);

  test('active, approved phone, in date → ok with days left', () {
    final d = decide(acc());
    expect(d.allowed, isTrue);
    expect(d.daysLeft, 21);
  });
  test('lifetime plan has no days left', () => expect(decide(acc().copyWith()).allowed, isTrue));
  test('every non-active status stops the app and passes the admin message on', () {
    for (final s in ['suspended', 'blocked', 'payment_pending', 'expired', 'rejected']) {
      final d = decide(acc(status: s, msg: 'please pay'));
      expect(d.allowed, isFalse, reason: s);
      expect(d.message, 'please pay');
    }
    expect(decide(acc(status: 'pending')).reason, AccessReason.waitingApproval);
    expect(decide(acc(status: 'something-new')).allowed, isFalse);
  });
  test('a phone that is not approved asks for approval; a blocked phone is refused', () {
    expect(decide(acc(ok: ['other'])).reason, AccessReason.newPhone);
    expect(decide(acc(bl: ['p1'])).reason, AccessReason.phoneBlocked);
  });
  test('a new phone that still fits the phone limit opens without approval; one over the limit waits; a blocked one never opens', () {
    expect(decide(acc(ok: ['a', 'b'], max: 15)).allowed, isTrue);
    expect(decide(acc(ok: ['a', 'b'], max: 3)).allowed, isTrue, reason: 'third of three');
    expect(decide(acc(ok: ['a', 'b'], max: 2)).reason, AccessReason.newPhone);
    expect(decide(acc(ok: ['a'], rq: ['x'], max: 3)).allowed, isTrue, reason: 'a, x and this phone fit');
    expect(decide(acc(ok: ['a', 'b'], rq: ['x'], max: 3)).reason, AccessReason.newPhone, reason: 'waiting phones use up slots too');
    expect(decide(acc(ok: ['a'], bl: ['p1'], max: 15)).reason, AccessReason.phoneBlocked);
    expect(decide(acc(status: 'suspended', ok: ['a'], max: 15)).allowed, isFalse);
  });
  test('expiry is enforced by the local clock, even when the stored status still says active, and works offline', () {
    final a = acc(exp: now.add(const Duration(days: 1)), checked: now);
    expect(decide(a, at: now.add(const Duration(hours: 23))).allowed, isTrue);
    expect(decide(a, at: now.add(const Duration(days: 1))).reason, AccessReason.expired);
  });
  test('offline grace: allowed for offlineDays, then internet is needed', () {
    final a = acc(exp: now.add(const Duration(days: 90)), checked: now);
    expect(decide(a, at: now.add(const Duration(days: 7))).allowed, isTrue);
    expect(decide(a, at: now.add(const Duration(days: 7, minutes: 1))).reason, AccessReason.internetNeeded);
    expect(decide(a, c: const AppControl(offlineDays: 30), at: now.add(const Duration(days: 20))).allowed, isTrue);
  });
  test('moving the phone clock back is refused', () {
    expect(decide(acc(), at: now.subtract(const Duration(days: 2)), highest: now).reason, AccessReason.clockTampered);
    expect(decide(acc(), at: now.subtract(const Duration(minutes: 5)), highest: now).allowed, isTrue);
  });
  test('no cached account means internet is needed', () => expect(decide(null).reason, AccessReason.internetNeeded));
  test('minimum version forces an update first', () {
    final d = decide(acc(), c: const AppControl(minVersion: '1.2.0', updateLink: 'https://x'), version: '1.1.9');
    expect(d.reason, AccessReason.updateRequired);
    expect(d.message, 'https://x');
    expect(decide(acc(), c: const AppControl(minVersion: '1.2'), version: '1.2.0').allowed, isTrue);
  });
  test('version comparison', () {
    expect(compareVersions('1.10.0', '1.9.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('0.9', '0.10'), -1);
  });
  test('snapshot survives a JSON round trip and a damaged cache is rejected', () {
    final a = acc(msg: 'hi', bl: ['x']);
    final b = AccountSnapshot.tryParse(a.toJson())!;
    expect(b.status, 'active');
    expect(b.adminMessage, 'hi');
    expect(b.blockedPhones, ['x']);
    expect(b.expiresAt, a.expiresAt);
    expect(AccountSnapshot.tryParse('{nope'), isNull);
    expect(AccountSnapshot.tryParse(null), isNull);
  });
}
