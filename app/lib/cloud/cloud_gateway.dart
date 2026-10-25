import '../domain/account_gate.dart';

class CloudUser {
  const CloudUser(this.uid, this.email);
  final String uid;
  final String email;
}

class RegistrationData {
  const RegistrationData({required this.businessName, required this.ownerName, required this.phone, required this.city, required this.country, required this.email});
  final String businessName;
  final String ownerName;
  final String phone;
  final String city;
  final String country;
  final String email;
}

/// One reading of the account document. [fromServer] is false when Firestore answered from its offline cache.
class AccountEvent {
  const AccountEvent(this.account, {required this.fromServer, this.pinReset});

  /// null = the user has signed in but never submitted a registration.
  final AccountSnapshot? account;
  final bool fromServer;

  /// A new owner PIN Digital Target set from the panel, waiting for this phone to apply it.
  final PinResetRequest? pinReset;
}

class PinResetRequest {
  const PinResetRequest({required this.id, required this.pin});
  final String id;
  final String pin;
}

class SupportMessage {
  const SupportMessage({required this.id, required this.fromAdmin, required this.text, this.at});
  final String id;
  final bool fromAdmin;
  final String text;
  final DateTime? at;
}

/// A notice from Digital Target (payment reminder, new version...) shown in the bell.
class AppNotice {
  const AppNotice({required this.id, required this.title, required this.body, required this.kind, this.at});
  final String id;
  final String title;
  final String body;

  /// info | payment | update | warning | offer
  final String kind;
  final DateTime? at;
}

class Branding {
  const Branding({this.appName = '', this.contact = '', this.whatsapp = '', this.email = '', this.supportMessage = ''});
  final String appName;
  final String contact;
  final String whatsapp;
  final String email;
  final String supportMessage;
}

/// Totals only. Customer names, bill contents and prices never leave the phone.
class DayTotals {
  const DayTotals({required this.date, required this.netMinor, required this.grossMinor, required this.refundsMinor, required this.bills, required this.customers, required this.currency});
  final String date;
  final int netMinor;
  final int grossMinor;
  final int refundsMinor;
  final int bills;
  final int customers;
  final String currency;
}

class DeviceInfoReport {
  const DeviceInfoReport({required this.phoneId, required this.model, required this.android, required this.appVersion, this.locationAllowed = false, this.lat, this.lng, this.accuracyM, this.locationAt, this.ip});
  final String phoneId;

  /// The phone's own network address (Wi-Fi / mobile), shown in the panel next to the model and version.
  final String? ip;
  final String model;
  final String android;
  final String appVersion;

  /// Only true when the owner switched location sharing on and Android permission was given.
  final bool locationAllowed;
  final double? lat;
  final double? lng;
  final double? accuracyM;
  final DateTime? locationAt;
}

/// A problem with a human-readable message, already in plain words.
class CloudException implements Exception {
  const CloudException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything the app needs from Digital Target's servers. The Firebase implementation lives in firebase_gateway.dart;
/// tests use a fake. The app works the same offline: callers must expect these calls to fail without internet.
abstract class CloudGateway {
  CloudUser? get currentUser;
  Stream<CloudUser?> authChanges();
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
  Future<void> resetPassword(String email);

  Stream<AccountEvent> watchAccount(String uid);
  Future<void> register(String uid, RegistrationData data, String phoneId, String appVersion);
  Future<void> requestPhone(String uid, String phoneId);

  Future<void> reportDevice(String uid, DeviceInfoReport device);
  /// A small picture of the restaurant's logo (a data URL) for the map pin in the panel.
  Future<void> reportLogo(String uid, String dataUrl);
  /// The app has applied a PIN reset: remove the PIN from the account document and record that it was done.
  Future<void> finishPinReset(String uid, String id);

  Future<void> reportSales(String uid, DayTotals today, String appVersion);

  /// Re-sends earlier days (one document per date, so repeating it never double-counts). Covers days the phone
  /// was offline and refunds made after the day ended.
  Future<void> reportPastDays(String uid, List<DayTotals> days);


  Stream<List<SupportMessage>> watchSupport(String uid);

  /// Notices for everyone and for this restaurant, newest first. Live: a new one arrives at once while online.
  Stream<List<AppNotice>> watchNotices(String uid);
  Future<void> sendSupport(String uid, String businessName, String text);

  Future<Branding?> branding();
  Future<AppControl?> appControl();
}
