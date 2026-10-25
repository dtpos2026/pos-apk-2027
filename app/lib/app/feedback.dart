import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/queries.dart';
import 'device_channel.dart';
import 'providers.dart';

/// What the phone can do to be heard or felt. main() supplies Android; tests supply a recorder; the default does nothing.
abstract class FeedbackPlayer {
  const FeedbackPlayer();

  /// false when this build cannot show status-bar notices at all (then nothing is asked).
  bool get supportsNotices => true;
  Future<void> click();
  Future<void> tone(String kind);

  /// Plays [kind] for the Settings test buttons and says what happened: ok, silent, volume0, failed.
  Future<String> test(String kind) async {
    kind == 'tap' ? await click() : await tone(kind);
    return 'ok';
  }

  Future<void> vibrate({bool strong = false});
  Future<bool> askNotificationPermission();
  Future<bool> notificationsAllowed();
  Future<bool> notify(String title, String body, int id);
  Future<void> clearNotifications();
}

class SilentFeedback extends FeedbackPlayer {
  const SilentFeedback();
  @override
  bool get supportsNotices => false;
  @override
  Future<void> click() async {}
  @override
  Future<void> tone(String kind) async {}
  @override
  Future<void> vibrate({bool strong = false}) async {}
  @override
  Future<bool> askNotificationPermission() async => false;
  @override
  Future<bool> notificationsAllowed() async => false;
  @override
  Future<bool> notify(String title, String body, int id) async => false;
  @override
  Future<void> clearNotifications() async {}
}

final feedbackPlayerProvider = Provider<FeedbackPlayer>((ref) => const SilentFeedback());

/// The owner's choices: sound, vibration, status-bar notices. All on until switched off.
class FeedbackPrefs {
  const FeedbackPrefs({this.sound = true, this.vibrate = true, this.notices = true});
  final bool sound;
  final bool vibrate;
  final bool notices;
}

class FeedbackPrefsNotifier extends AsyncNotifier<FeedbackPrefs> {
  static const soundKey = 'ui.sound', vibrateKey = 'ui.vibrate', noticesKey = 'ui.notices';

  @override
  Future<FeedbackPrefs> build() async {
    final db = ref.read(databaseProvider);
    Future<bool> on(String k) async => (await getSetting(db, k)) != '0';
    return FeedbackPrefs(sound: await on(soundKey), vibrate: await on(vibrateKey), notices: await on(noticesKey));
  }

  Future<void> _save(String key, bool v, FeedbackPrefs next) async {
    await setSetting(ref.read(databaseProvider), key, v ? '1' : '0', ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(next);
  }

  Future<void> setSound(bool v) async {
    final p = state.value ?? const FeedbackPrefs();
    await _save(soundKey, v, FeedbackPrefs(sound: v, vibrate: p.vibrate, notices: p.notices));
  }

  Future<void> setVibrate(bool v) async {
    final p = state.value ?? const FeedbackPrefs();
    await _save(vibrateKey, v, FeedbackPrefs(sound: p.sound, vibrate: v, notices: p.notices));
  }

  /// Switching on asks Android for permission first; without it the switch stays off. Returns the final value.
  Future<bool> setNotices(bool v) async {
    final p = state.value ?? const FeedbackPrefs();
    final on = v && await ref.read(feedbackPlayerProvider).askNotificationPermission();
    await _save(noticesKey, on, FeedbackPrefs(sound: p.sound, vibrate: p.vibrate, notices: on));
    return on;
  }
}

final feedbackPrefsProvider = AsyncNotifierProvider<FeedbackPrefsNotifier, FeedbackPrefs>(FeedbackPrefsNotifier.new);

/// Plays the tap / success / error feedback, honouring the owner's sound and vibration switches.
class AppFeedback {
  AppFeedback(this._ref);
  final Ref _ref;
  FeedbackPrefs get _p => _ref.read(feedbackPrefsProvider).value ?? const FeedbackPrefs();
  FeedbackPlayer get _out => _ref.read(feedbackPlayerProvider);

  Future<void> tap() async {
    if (_p.sound) await _out.click();
    if (_p.vibrate) await _out.vibrate();
  }

  /// The bill was paid.
  Future<void> success() async {
    if (_p.sound) await _out.tone('success');
    if (_p.vibrate) await _out.vibrate(strong: true);
  }

  Future<void> failure() async {
    if (_p.sound) await _out.tone('error');
    if (_p.vibrate) await _out.vibrate(strong: true);
  }
}

final appFeedbackProvider = Provider<AppFeedback>(AppFeedback.new);

/// Plays the tap sound / vibration for every touch that is a tap (not a scroll), anywhere in the app.
class TapFeedback extends ConsumerStatefulWidget {
  const TapFeedback({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends ConsumerState<TapFeedback> {
  final _down = <int, Offset>{};

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _down[e.pointer] = e.position,
        onPointerCancel: (e) => _down.remove(e.pointer),
        onPointerUp: (e) {
          final start = _down.remove(e.pointer);
          if (start != null && (e.position - start).distance < 12) ref.read(appFeedbackProvider).tap();
        },
        child: widget.child,
      );
}

/// Android implementation: the system click, haptics, and the Kotlin tone / notification calls.
class AndroidFeedback extends FeedbackPlayer {
  const AndroidFeedback(this.channel);
  final DeviceChannel channel;
  @override
  Future<void> click() => channel.tone('tap');
  @override
  Future<void> tone(String kind) => channel.tone(kind);
  @override
  Future<String> test(String kind) => channel.tone(kind, force: true);
  @override
  Future<void> vibrate({bool strong = false}) => strong ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
  @override
  Future<bool> askNotificationPermission() => channel.requestPermissions(DeviceChannel.notificationPermissions);
  @override
  Future<bool> notificationsAllowed() => channel.hasPermissions(DeviceChannel.notificationPermissions);
  @override
  Future<bool> notify(String title, String body, int id) => channel.notify(title, body, id);
  @override
  Future<void> clearNotifications() => channel.clearNotifications();
}
