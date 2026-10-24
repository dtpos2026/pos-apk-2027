import 'dart:convert';

/// What Digital Target's server says about a restaurant account. The app keeps the last copy it saw, so the
/// decision below also works offline, up to `offlineDays` since the last time the server confirmed it.
class AccountSnapshot {
  const AccountSnapshot({
    required this.status,
    this.plan,
    this.expiresAt,
    this.adminMessage = '',
    this.approvedPhones = const [],
    this.blockedPhones = const [],
    this.phoneRequests = const [],
    this.customerId,
    this.businessName = '',
    this.disabledModules = const [],
    this.themeId = '',
    this.themeLocked = false,
    required this.checkedAt,
  });

  /// pending | active | payment_pending | suspended | blocked | expired | rejected
  final String status;
  final String? plan;
  final DateTime? expiresAt;
  final String adminMessage;
  final List<String> approvedPhones;
  final List<String> blockedPhones;
  final List<String> phoneRequests;
  final String? customerId;
  final String businessName;

  /// Modules Digital Target switched off for this restaurant (see domain/modules.dart).
  final List<String> disabledModules;

  /// Theme Digital Target assigned to this business (a preset id or 'custom:…'); '' = none.
  final String themeId;

  /// True = the owner cannot change the theme in Settings.
  final bool themeLocked;

  /// When the server last confirmed this copy (never the time of an offline cache read).
  final DateTime checkedAt;

  AccountSnapshot copyWith({DateTime? checkedAt}) => AccountSnapshot(
        status: status, plan: plan, expiresAt: expiresAt, adminMessage: adminMessage, approvedPhones: approvedPhones,
        blockedPhones: blockedPhones, phoneRequests: phoneRequests, customerId: customerId, businessName: businessName, disabledModules: disabledModules, themeId: themeId, themeLocked: themeLocked, checkedAt: checkedAt ?? this.checkedAt,
      );

  String toJson() => jsonEncode({
        'status': status, 'plan': plan, 'exp': expiresAt?.millisecondsSinceEpoch, 'msg': adminMessage, 'ok': approvedPhones, 'bl': blockedPhones,
        'rq': phoneRequests, 'cid': customerId, 'name': businessName, 'off': disabledModules, 'th': themeId, 'tl': themeLocked, 'chk': checkedAt.millisecondsSinceEpoch,
      });

  static AccountSnapshot? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AccountSnapshot(
        status: j['status'] as String,
        plan: j['plan'] as String?,
        expiresAt: j['exp'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['exp'] as int),
        adminMessage: j['msg'] as String? ?? '',
        approvedPhones: (j['ok'] as List).cast<String>(),
        blockedPhones: (j['bl'] as List).cast<String>(),
        phoneRequests: (j['rq'] as List).cast<String>(),
        customerId: j['cid'] as String?,
        businessName: j['name'] as String? ?? '',
        disabledModules: ((j['off'] as List?) ?? const []).cast<String>(),
        themeId: j['th'] as String? ?? '',
        themeLocked: j['tl'] as bool? ?? false,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(j['chk'] as int),
      );
    } catch (_) {
      return null; // a damaged cache is treated as "never checked", which asks for internet
    }
  }
}

/// Rules the owner of the project sets in the panel (Settings > App control).
class AppControl {
  const AppControl({this.offlineDays = 7, this.notice = '', this.latestVersion = '', this.minVersion = '', this.updateLink = ''});
  final int offlineDays;
  final String notice;
  final String latestVersion;
  final String minVersion;
  final String updateLink;
}

enum AccessReason {
  ok, waitingApproval, rejected, suspended, blocked, paymentPending, expired, phoneBlocked, newPhone, internetNeeded, clockTampered, updateRequired,
}

class AccessDecision {
  const AccessDecision(this.reason, {this.message = '', this.daysLeft});
  final AccessReason reason;

  /// The note written in the panel, shown to the restaurant.
  final String message;

  /// Days until expiry; null for lifetime plans.
  final int? daysLeft;
  bool get allowed => reason == AccessReason.ok;
}

/// -1, 0 or 1. Missing parts count as 0 ("1.2" == "1.2.0"); non-numeric parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+\-]')).map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p < q ? -1 : 1;
  }
  return 0;
}

/// The single place that decides whether this phone may sell right now. Pure, so every case is unit tested.
/// [highestClockSeen] is the latest wall-clock time this phone has ever seen; moving the clock back is refused.
AccessDecision decideAccess({
  required AccountSnapshot? account,
  required AppControl control,
  required String phoneId,
  required String appVersion,
  required DateTime now,
  required DateTime highestClockSeen,
}) {
  if (control.minVersion.isNotEmpty && compareVersions(appVersion, control.minVersion) < 0) {
    return AccessDecision(AccessReason.updateRequired, message: control.updateLink);
  }
  if (account == null) return const AccessDecision(AccessReason.internetNeeded);
  final msg = account.adminMessage;
  switch (account.status) {
    case 'pending':
      return const AccessDecision(AccessReason.waitingApproval);
    case 'rejected':
      return AccessDecision(AccessReason.rejected, message: msg);
    case 'suspended':
      return AccessDecision(AccessReason.suspended, message: msg);
    case 'blocked':
      return AccessDecision(AccessReason.blocked, message: msg);
    case 'payment_pending':
      return AccessDecision(AccessReason.paymentPending, message: msg);
    case 'expired':
      return AccessDecision(AccessReason.expired, message: msg);
    case 'active':
      break;
    default:
      return AccessDecision(AccessReason.blocked, message: msg);
  }
  if (account.blockedPhones.contains(phoneId)) return AccessDecision(AccessReason.phoneBlocked, message: msg);
  if (!account.approvedPhones.contains(phoneId)) return const AccessDecision(AccessReason.newPhone);
  if (now.isBefore(highestClockSeen.subtract(const Duration(minutes: 10)))) return const AccessDecision(AccessReason.clockTampered);
  final exp = account.expiresAt;
  if (exp != null && !now.isBefore(exp)) return AccessDecision(AccessReason.expired, message: msg);
  final offlineFor = now.difference(account.checkedAt);
  if (offlineFor > Duration(days: control.offlineDays)) return const AccessDecision(AccessReason.internetNeeded);
  return AccessDecision(AccessReason.ok, daysLeft: exp == null ? null : exp.difference(now).inDays + 1);
}
