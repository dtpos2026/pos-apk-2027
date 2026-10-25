import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../domain/account_gate.dart';
import 'cloud_gateway.dart';

/// The Firebase web/app identifiers are public by design (they only say which project to talk to); what protects
/// the data is firebase/firestore.rules. They can be replaced at build time with --dart-define=FIREBASE_*.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyDN6KrB3xn3ZjHx5unddzEXSw4Wh8SBDJo');
const _appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:77324870935:web:685439c05deaad59ba8352');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'dt-food-app');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '77324870935');

Future<FirebaseGateway> initFirebaseGateway() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, projectId: _projectId, messagingSenderId: _senderId, storageBucket: 'dt-food-app.firebasestorage.app'),
  );
  final db = FirebaseFirestore.instance;
  db.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: 20 * 1024 * 1024);
  return FirebaseGateway(FirebaseAuth.instance, db);
}

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
List<String> _list(Object? v) => v is List ? v.whereType<String>().toList() : const [];

class FirebaseGateway implements CloudGateway {
  FirebaseGateway(this._auth, this._db);
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  @override
  CloudUser? get currentUser => _user(_auth.currentUser);
  CloudUser? _user(User? u) => u == null ? null : CloudUser(u.uid, u.email ?? '');

  @override
  Stream<CloudUser?> authChanges() => _auth.authStateChanges().map(_user);

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FirebaseAuthException catch (e) {
      throw CloudException(_authMessage(e.code));
    } on FirebaseException catch (e) {
      throw CloudException(_storeMessage(e.code));
    }
  }

  @override
  Future<void> signIn(String email, String password) => _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));
  @override
  Future<void> signUp(String email, String password) => _guard(() => _auth.createUserWithEmailAndPassword(email: email.trim(), password: password));
  @override
  Future<void> signOut() => _auth.signOut();
  @override
  Future<void> resetPassword(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Stream<AccountEvent> watchAccount(String uid) =>
      _db.collection('accounts').doc(uid).snapshots(includeMetadataChanges: true).map((s) {
        if (!s.exists) return AccountEvent(null, fromServer: !s.metadata.isFromCache);
        final d = s.data()!;
        return AccountEvent(
          AccountSnapshot(
            status: (d['status'] as String?) ?? 'pending',
            plan: d['plan'] as String?,
            expiresAt: _date(d['expiresAt']),
            adminMessage: (d['adminMessage'] as String?) ?? '',
            approvedPhones: _list(d['approvedPhones']),
            blockedPhones: _list(d['blockedPhones']),
            phoneRequests: _list(d['phoneRequests']),
            customerId: d['customerId'] as String?,
            businessName: (d['businessName'] as String?) ?? '',
            disabledModules: _list(d['disabledModules']),
            themeId: (d['themeId'] as String?) ?? '',
            themeLocked: d['themeLocked'] == true,
            maxPhones: d['maxPhones'] is int ? d['maxPhones'] as int : 1,
            checkedAt: DateTime.now(),
          ),
          fromServer: !s.metadata.isFromCache,
          pinReset: _pinReset(d['pinReset']),
        );
      });

  @override
  Future<void> register(String uid, RegistrationData d, String phoneId, String appVersion) => _guard(() => _db.collection('accounts').doc(uid).set({
        'businessName': d.businessName, 'ownerName': d.ownerName, 'phone': d.phone, 'city': d.city, 'country': d.country, 'email': d.email,
        'status': 'pending', 'phoneRequests': [phoneId], 'createdAt': FieldValue.serverTimestamp(), 'appVersion': appVersion,
      }));

  @override
  Future<void> requestPhone(String uid, String phoneId) =>
      _guard(() => _db.collection('accounts').doc(uid).update({'phoneRequests': FieldValue.arrayUnion([phoneId])}));

  @override
  Future<void> reportDevice(String uid, DeviceInfoReport d) => _guard(() => _db.collection('devices').doc('${uid}__${d.phoneId}').set({
        'uid': uid, 'phoneId': d.phoneId, 'model': d.model, 'android': d.android, 'appVersion': d.appVersion,
        'lastSeenAt': FieldValue.serverTimestamp(), 'locationAllowed': d.locationAllowed, if (d.ip != null) 'ip': d.ip,
        if (d.locationAllowed && d.lat != null && d.lng != null) ...{
          'lat': d.lat, 'lng': d.lng, 'accuracyM': d.accuracyM ?? 0, 'locationAt': Timestamp.fromDate(d.locationAt ?? DateTime.now()),
        },
      }));

  static PinResetRequest? _pinReset(Object? v) {
    if (v is! Map) return null;
    final id = v['id'], pin = v['pin'];
    return id is String && pin is String ? PinResetRequest(id: id, pin: pin) : null;
  }

  @override
  Future<void> finishPinReset(String uid, String id) => _guard(() => _db.collection('accounts').doc(uid).update({
        'pinReset': FieldValue.delete(),
        'pinResetDone': {'id': id, 'at': FieldValue.serverTimestamp()},
      }));

  @override
  Future<void> reportLogo(String uid, String dataUrl) => _guard(() => _db.collection('accounts').doc(uid).update({'logo': dataUrl}));

  @override
  Future<void> reportProfile(String uid, String name, String address) => _guard(() => _db.collection('accounts').doc(uid).update({'businessName': name, 'address': address}));

  @override
  Future<void> reportSales(String uid, DayTotals t, String appVersion) => _guard(() async {
        final batch = _db.batch();
        batch.set(_db.collection('stats').doc(uid), {'updatedAt': FieldValue.serverTimestamp(), 'todayNetMinor': t.netMinor, 'todayBills': t.bills, 'currency': t.currency, 'appVersion': appVersion});
        batch.set(_db.collection('stats').doc(uid).collection('days').doc(t.date), {
          'date': t.date, 'netMinor': t.netMinor, 'grossMinor': t.grossMinor, 'refundsMinor': t.refundsMinor, 'bills': t.bills, 'customers': t.customers, 'updatedAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      });

  @override
  Future<void> reportPastDays(String uid, List<DayTotals> days) => _guard(() async {
        if (days.isEmpty) return;
        final batch = _db.batch();
        for (final t in days) {
          batch.set(_db.collection('stats').doc(uid).collection('days').doc(t.date), {
            'date': t.date, 'netMinor': t.netMinor, 'grossMinor': t.grossMinor, 'refundsMinor': t.refundsMinor, 'bills': t.bills, 'customers': t.customers, 'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      });

  @override
  Future<void> cleanDays(String uid, List<String> emptyDates, String keepFrom) => _guard(() async {
        final days = _db.collection('stats').doc(uid).collection('days');
        final batch = _db.batch();
        for (final d in emptyDates) {
          batch.delete(days.doc(d));
        }
        final old = await days.where('date', isLessThan: keepFrom).get();
        for (final d in old.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      });

  @override
  Stream<List<SupportMessage>> watchSupport(String uid) => _db.collection('support').doc(uid).collection('messages').orderBy('at').snapshots().map((q) => [
        for (final d in q.docs) SupportMessage(id: d.id, fromAdmin: d.data()['sender'] == 'admin', text: (d.data()['text'] as String?) ?? '', at: _date(d.data()['at'])),
      ]);

  @override
  Stream<List<AppNotice>> watchNotices(String uid) => _db.collection('notifications').where('target', whereIn: ['all', uid]).snapshots().map((q) {
        final list = [
          for (final d in q.docs)
            AppNotice(id: d.id, title: (d.data()['title'] as String?) ?? '', body: (d.data()['body'] as String?) ?? '', kind: (d.data()['kind'] as String?) ?? 'info', at: _date(d.data()['createdAt'])),
        ]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
        return list;
      });

  @override
  Future<void> sendSupport(String uid, String businessName, String text) => _guard(() async {
        final b = _db.batch();
        b.set(_db.collection('support').doc(uid).collection('messages').doc(), {'sender': 'business', 'text': text, 'at': FieldValue.serverTimestamp()});
        b.set(_db.collection('support').doc(uid), {'businessName': businessName, 'lastMessage': text, 'lastAt': FieldValue.serverTimestamp(), 'unreadForAdmin': true});
        await b.commit();
      });

  @override
  Future<Branding?> branding() async {
    try {
      final d = (await _db.collection('config').doc('branding').get()).data();
      if (d == null) return null;
      String s(String k) => (d[k] as String?) ?? '';
      return Branding(appName: s('appName'), contact: s('contact'), whatsapp: s('whatsapp'), email: s('email'), supportMessage: s('supportMessage'));
    } on FirebaseException {
      return null;
    }
  }

  @override
  Future<AppControl?> appControl() async {
    try {
      final d = (await _db.collection('config').doc('app').get()).data();
      if (d == null) return null;
      String s(String k) => (d[k] as String?) ?? '';
      return AppControl(offlineDays: (d['offlineDays'] as num?)?.toInt() ?? 7, notice: s('notice'), latestVersion: s('latestVersion'), minVersion: s('minVersion'), updateLink: s('updateLink'));
    } on FirebaseException {
      return null;
    }
  }
}

String _authMessage(String code) => switch (code) {
      'invalid-email' => 'That email address is not valid.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' || 'invalid-login-credentials' => 'Wrong email or password.',
      'email-already-in-use' => 'This email already has an account. Sign in instead.',
      'weak-password' => 'Choose a longer password (at least 6 characters).',
      'network-request-failed' => 'No internet connection. Try again when you are online.',
      'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
      'operation-not-allowed' => 'Email login is not switched on yet in Firebase (Authentication > Sign-in method > Email/Password).',
      'user-disabled' => 'This account has been disabled. Contact Digital Target.',
      _ => 'Sign-in problem ($code).',
    };

String _storeMessage(String code) => switch (code) {
      'permission-denied' => 'Not allowed by the server. Contact Digital Target.',
      'unavailable' || 'deadline-exceeded' => 'No internet connection. Try again when you are online.',
      _ => 'Server problem ($code).',
    };
