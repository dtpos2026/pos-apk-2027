import 'dart:async';

import 'package:dt_food_pos/cloud/cloud_gateway.dart';
import 'package:dt_food_pos/domain/account_gate.dart';

/// In-memory stand-in for Digital Target's servers. Tests push account changes the way the admin panel would.
class FakeCloud implements CloudGateway {
  FakeCloud({this.signedIn = false});
  bool signedIn;
  CloudUser? _user;
  final _auth = StreamController<CloudUser?>.broadcast();
  final _acc = StreamController<AccountEvent>.broadcast();
  AccountEvent? _last;
  final registered = <RegistrationData>[];
  final requestedPhones = <String>[];
  final devices = <DeviceInfoReport>[];
  final sales = <DayTotals>[];
  final support = <SupportMessage>[];
  final _supportCtl = StreamController<List<SupportMessage>>.broadcast();
  AppControl? control;
  Branding? brand;
  final supportNames = <String>[];
  Object? failNext;

  @override
  CloudUser? get currentUser => _user;

  @override
  Stream<CloudUser?> authChanges() async* {
    yield _user;
    yield* _auth.stream;
  }

  void _emitUser(CloudUser? u) {
    _user = u;
    _auth.add(u);
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (failNext != null) throw CloudException(failNext.toString());
    if (password == 'wrongpw') throw const CloudException('Wrong email or password.');
    _emitUser(CloudUser('uid-1', email));
  }

  @override
  Future<void> signUp(String email, String password) async => _emitUser(CloudUser('uid-1', email));
  @override
  Future<void> signOut() async => _emitUser(null);
  @override
  Future<void> resetPassword(String email) async {}

  /// The account document as the server holds it; null = never registered.
  void serverAccount(AccountSnapshot? a) {
    _last = AccountEvent(a, fromServer: true);
    _acc.add(_last!);
  }

  @override
  Stream<AccountEvent> watchAccount(String uid) async* {
    if (_last != null) yield _last!;
    yield* _acc.stream;
  }

  @override
  Future<void> register(String uid, RegistrationData data, String phoneId, String appVersion) async {
    registered.add(data);
    serverAccount(AccountSnapshot(status: 'pending', phoneRequests: [phoneId], businessName: data.businessName, checkedAt: DateTime.now()));
  }

  @override
  Future<void> requestPhone(String uid, String phoneId) async => requestedPhones.add(phoneId);
  @override
  Future<void> reportDevice(String uid, DeviceInfoReport device) async {
    if (offline) throw const CloudException('No internet connection.');
    devices.add(device);
  }
  final logos = <String>[];
  @override
  Future<void> reportLogo(String uid, String dataUrl) async => logos.add(dataUrl);
  @override
  Future<void> reportSales(String uid, DayTotals today, String appVersion) async => sales.add(today);

  final pastDays = <DayTotals>[];
  bool offline = false;
  @override
  Future<void> reportPastDays(String uid, List<DayTotals> days) async {
    if (offline) throw const CloudException('No internet connection.');
    pastDays.addAll(days);
  }

  final notices = <AppNotice>[];
  final _noticeCtl = StreamController<List<AppNotice>>.broadcast();
  @override
  Stream<List<AppNotice>> watchNotices(String uid) async* {
    yield List.of(notices);
    yield* _noticeCtl.stream;
  }

  /// The panel sends a notice: it reaches the open app at once.
  void pushNotice(String title, String body, {String kind = 'info', DateTime? at}) {
    notices.insert(0, AppNotice(id: 'n${notices.length}', title: title, body: body, kind: kind, at: at ?? DateTime.now()));
    _noticeCtl.add(List.of(notices));
  }

  @override
  Stream<List<SupportMessage>> watchSupport(String uid) async* {
    yield List.of(support);
    yield* _supportCtl.stream;
  }

  @override
  Future<void> sendSupport(String uid, String businessName, String text) async {
    supportNames.add(businessName);
    support.add(SupportMessage(id: '${support.length}', fromAdmin: false, text: text));
    _supportCtl.add(List.of(support));
  }

  void adminReplies(String text) {
    support.add(SupportMessage(id: '${support.length}', fromAdmin: true, text: text));
    _supportCtl.add(List.of(support));
  }

  @override
  Future<Branding?> branding() async => brand;
  @override
  Future<AppControl?> appControl() async => control;

  Future<void> signInDirect(String email) async => _emitUser(CloudUser('uid-1', email));
}
