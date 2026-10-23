import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/providers.dart';
import '../data/db/database.dart';
import '../data/queries.dart';
import '../domain/account_gate.dart';
import 'cloud_gateway.dart';

/// null = cloud is off (tests and local development). main() supplies the Firebase gateway.
final cloudGatewayProvider = Provider<CloudGateway?>((ref) => null);

/// Set when Firebase could not start: the app shows "App setup incomplete" instead of working half-connected.
final cloudInitErrorProvider = Provider<String?>((ref) => null);

final appVersionProvider = Provider<String>((ref) => '0.0.0');

/// A phone id that survives reinstalling the app (main() reads it from Android). null = make a random one.
/// Keeping it stable means an approved phone is not shown again as a new phone after a reinstall.
final platformPhoneIdProvider = Provider<Future<String?> Function()>((ref) => () async => null);

sealed class AccessState {
  const AccessState();
}

class AccessOff extends AccessState {
  const AccessOff();
}

class AccessSetupIncomplete extends AccessState {
  const AccessSetupIncomplete(this.problem);
  final String problem;
}

class AccessChecking extends AccessState {
  const AccessChecking();
}

class AccessSignedOut extends AccessState {
  const AccessSignedOut();
}

class AccessNeedsRegistration extends AccessState {
  const AccessNeedsRegistration(this.user);
  final CloudUser user;
}

class AccessDecided extends AccessState {
  const AccessDecided(this.user, this.decision, this.account, this.control);
  final CloudUser user;
  final AccessDecision decision;
  final AccountSnapshot? account;
  final AppControl control;
}

/// Combines sign-in, the account document and the cached copy of both into one answer for the Gate.
class AccessController extends Notifier<AccessState> {
  CloudGateway? _gw;
  StreamSubscription<CloudUser?>? _authSub;
  StreamSubscription<AccountEvent>? _accSub;
  Timer? _tick;
  Timer? _giveUp;
  CloudUser? _user;
  AccountSnapshot? _account;
  bool _accountMissing = false;
  AppControl _control = const AppControl();
  String? _phoneId;
  bool _phoneRequested = false;

  @override
  AccessState build() {
    final err = ref.watch(cloudInitErrorProvider);
    if (err != null) return AccessSetupIncomplete(err);
    final gw = ref.watch(cloudGatewayProvider);
    if (gw == null) return const AccessOff();
    _gw = gw;
    ref.onDispose(() {
      _authSub?.cancel();
      _accSub?.cancel();
      _tick?.cancel();
      _giveUp?.cancel();
    });
    Future.microtask(_start);
    return const AccessChecking();
  }

  AppDatabase get _db => ref.read(databaseProvider);

  Future<String> phoneId() async {
    if (_phoneId != null) return _phoneId!;
    var id = await getSetting(_db, 'cloud.phone_id');
    if (id == null) {
      id = await ref.read(platformPhoneIdProvider)() ?? const Uuid().v4().replaceAll('-', '').substring(0, 20);
      await setSetting(_db, 'cloud.phone_id', id, ref.read(clockProvider)().millisecondsSinceEpoch);
    }
    return _phoneId = id;
  }

  Future<void> _start() async {
    final gw = _gw!;
    await phoneId();
    _control = _parseControl(await getSetting(_db, 'cloud.control')) ?? _control;
    _authSub = gw.authChanges().listen(_onUser, onError: (_) => state = const AccessSignedOut());
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _evaluate());
    gw.appControl().then((c) async {
      if (c == null) return;
      _control = c;
      await setSetting(_db, 'cloud.control', _controlJson(c), ref.read(clockProvider)().millisecondsSinceEpoch);
      _evaluate();
    }, onError: (_) {});
  }

  Future<void> _onUser(CloudUser? user) async {
    _user = user;
    _accSub?.cancel();
    _account = null;
    _accountMissing = false;
    _phoneRequested = false;
    if (user == null) {
      state = const AccessSignedOut();
      return;
    }
    _account = AccountSnapshot.tryParse(await getSetting(_db, 'cloud.account.${user.uid}'));
    if (_account != null) {
      _evaluate();
    } else {
      state = const AccessChecking();
      // No cached copy and no answer from the server: say "internet needed" instead of spinning forever.
      _giveUp?.cancel();
      _giveUp = Timer(const Duration(seconds: 12), () {
        if (_user != null && _account == null && !_accountMissing) {
          state = AccessDecided(_user!, const AccessDecision(AccessReason.internetNeeded), null, _control);
        }
      });
    }
    _listenAccount(user.uid);
  }

  void _listenAccount(String uid) {
    _accSub?.cancel();
    _accSub = _gw!.watchAccount(uid).listen((e) async {
      if (e.account == null) {
        if (e.fromServer) {
          _accountMissing = true;
          _account = null;
          _evaluate();
        }
        return;
      }
      _accountMissing = false;
      if (e.fromServer) {
        _account = e.account!.copyWith(checkedAt: ref.read(clockProvider)());
        await setSetting(_db, 'cloud.account.$uid', _account!.toJson(), ref.read(clockProvider)().millisecondsSinceEpoch);
      } else if (_account == null) {
        _account = e.account; // the offline copy is usable, but it is not a fresh confirmation (its checkedAt is "now" from the gateway)
        _account = _account!.copyWith(checkedAt: DateTime.fromMillisecondsSinceEpoch(0));
      }
      _evaluate();
    }, onError: (_) {});
  }

  Future<void> _evaluate() async {
    final user = _user;
    if (user == null) return;
    if (_accountMissing) {
      state = AccessNeedsRegistration(user);
      return;
    }
    final account = _account;
    if (account == null) return; // still waiting for the first answer
    final now = ref.read(clockProvider)();
    final highest = DateTime.fromMillisecondsSinceEpoch(int.tryParse(await getSetting(_db, 'cloud.clock') ?? '') ?? 0);
    final version = ref.read(appVersionProvider);
    final id = await phoneId();
    final decision = decideAccess(account: account, control: _control, phoneId: id, appVersion: version, now: now, highestClockSeen: highest);
    if (decision.reason != AccessReason.clockTampered && now.isAfter(highest)) {
      await setSetting(_db, 'cloud.clock', now.millisecondsSinceEpoch.toString(), now.millisecondsSinceEpoch);
    }
    if (decision.reason == AccessReason.newPhone && !_phoneRequested && !account.phoneRequests.contains(id)) {
      _phoneRequested = true;
      _gw!.requestPhone(user.uid, id).catchError((_) {});
    }
    _giveUp?.cancel();
    state = AccessDecided(user, decision, account, _control);
  }

  /// "Check again": ask the server once more (it also refreshes the app-control rules).
  Future<void> refresh() async {
    final gw = _gw, user = _user;
    if (gw == null || user == null) return;
    _listenAccount(user.uid);
    try {
      final c = await gw.appControl();
      if (c != null) {
        _control = c;
        await setSetting(_db, 'cloud.control', _controlJson(c), ref.read(clockProvider)().millisecondsSinceEpoch);
      }
    } catch (_) {}
    await _evaluate();
  }

  Future<void> submitRegistration(RegistrationData data) async {
    final gw = _gw!, user = _user!;
    await gw.register(user.uid, data, await phoneId(), ref.read(appVersionProvider));
    _accountMissing = false;
    state = const AccessChecking();
    _listenAccount(user.uid);
  }

  Future<void> signOut() async {
    await _gw?.signOut();
  }
}


String _controlJson(AppControl c) => jsonEncode({'off': c.offlineDays, 'n': c.notice, 'lv': c.latestVersion, 'mv': c.minVersion, 'ul': c.updateLink});
AppControl? _parseControl(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return AppControl(offlineDays: j['off'] as int, notice: j['n'] as String, latestVersion: j['lv'] as String, minVersion: j['mv'] as String, updateLink: j['ul'] as String);
  } catch (_) {
    return null;
  }
}

final accessProvider = NotifierProvider<AccessController, AccessState>(AccessController.new);
