import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Signed licence token: `base64url(payloadJson).base64url(ed25519Signature)`.
/// The private key exists only on the server; the app ships the public key.
class LicensePayload {
  const LicensePayload({
    required this.businessId,
    required this.deviceIds,
    required this.modules,
    required this.plan,
    required this.status,
    required this.graceDays,
    required this.version,
    required this.issuedAt,
    this.expiresAt,
  });

  final String businessId;
  final List<String> deviceIds;
  final List<String> modules;
  final String plan;

  /// 'active' | 'suspended' | 'blocked'
  final String status;
  final int graceDays;
  final int version;
  final DateTime issuedAt;

  /// null = no fixed expiry (one-time licence).
  final DateTime? expiresAt;

  factory LicensePayload.fromJson(Map<String, dynamic> j) => LicensePayload(
        businessId: j['bid'] as String,
        deviceIds: (j['dev'] as List).cast<String>(),
        modules: (j['mod'] as List).cast<String>(),
        plan: j['plan'] as String,
        status: j['st'] as String,
        graceDays: j['grace'] as int,
        version: j['ver'] as int,
        issuedAt: DateTime.fromMillisecondsSinceEpoch((j['iat'] as int) * 1000, isUtc: true),
        expiresAt: j['exp'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['exp'] as int) * 1000, isUtc: true),
      );
}

enum LicenseStatus {
  valid,
  graceWarning, // still works, must reconnect soon
  graceExpired, // offline too long: sales locked until the next successful online check
  expired,
  suspended,
  blocked,
  wrongDevice,
  clockTampered,
  invalid,
}

class LicenseDecision {
  const LicenseDecision(this.status, {this.payload, this.graceDaysLeft, required this.message});
  final LicenseStatus status;
  final LicensePayload? payload;

  /// Whole days until the offline grace runs out (only for valid / graceWarning).
  final int? graceDaysLeft;
  final String message;

  bool get canSell => status == LicenseStatus.valid || status == LicenseStatus.graceWarning;

  /// Expiry or suspension never deletes data: the owner can always export and back up.
  bool get canExport => true;

  bool hasModule(String m) => canSell && (payload?.modules.contains(m) ?? false);
}

class LicenseVerifier {
  LicenseVerifier(this.publicKeyBytes, {this.warnDays = 3, this.clockSkew = const Duration(minutes: 10)});

  /// Raw 32-byte Ed25519 public key bundled with the app.
  final List<int> publicKeyBytes;
  final int warnDays;
  final Duration clockSkew;
  final _ed = Ed25519();

  Future<LicensePayload?> verifySignature(String token) async {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
      final sig = base64Url.decode(base64Url.normalize(parts[1]));
      final ok = await _ed.verify(
        payloadBytes,
        signature: Signature(sig, publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519)),
      );
      if (!ok) return null;
      return LicensePayload.fromJson(jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Decides whether this device may trade right now.
  ///
  /// [lastValidatedAt]: server time of the last successful online check.
  /// [highestWallClockSeen]: the latest device clock ever observed (persisted), used to detect rollback.
  /// Important: a suspension or block is only known after the device has been online; an offline device
  /// keeps its last known state until it reconnects.
  Future<LicenseDecision> evaluate({
    required String token,
    required String deviceId,
    required DateTime now,
    required DateTime lastValidatedAt,
    required DateTime highestWallClockSeen,
  }) async {
    final p = await verifySignature(token);
    if (p == null) return const LicenseDecision(LicenseStatus.invalid, message: 'Licence is not valid. Contact Digital Target.');
    if (!p.deviceIds.contains(deviceId)) {
      return LicenseDecision(LicenseStatus.wrongDevice, payload: p, message: 'This device is not authorised for the licence.');
    }
    if (p.status == 'blocked') {
      return LicenseDecision(LicenseStatus.blocked, payload: p, message: 'Licence blocked. Contact Digital Target.');
    }
    if (p.status == 'suspended') {
      return LicenseDecision(LicenseStatus.suspended, payload: p, message: 'Licence suspended. Contact Digital Target.');
    }
    if (now.isBefore(highestWallClockSeen.subtract(clockSkew))) {
      return LicenseDecision(LicenseStatus.clockTampered, payload: p, message: 'Device clock moved backwards. Connect to the internet to continue.');
    }
    if (p.expiresAt != null && !now.isBefore(p.expiresAt!)) {
      return LicenseDecision(LicenseStatus.expired, payload: p, message: 'Licence expired. Your data is safe; you can still export it.');
    }
    final deadline = lastValidatedAt.add(Duration(days: p.graceDays));
    if (!now.isBefore(deadline)) {
      return LicenseDecision(LicenseStatus.graceExpired, payload: p, message: 'Offline for too long. Connect to the internet to continue selling.');
    }
    final left = deadline.difference(now).inDays;
    if (left < warnDays) {
      return LicenseDecision(LicenseStatus.graceWarning, payload: p, graceDaysLeft: left,
          message: 'Connect to the internet within ${left + 1} day(s) to keep selling.');
    }
    return LicenseDecision(LicenseStatus.valid, payload: p, graceDaysLeft: left, message: 'Licence active.');
  }
}
