import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../cloud/cloud_gateway.dart';
import '../../cloud/firebase_gateway.dart';

/// Notices that arrived since [pushed] (milliseconds), oldest first. With no baseline yet nothing is announced.
List<AppNotice> freshNotices(List<AppNotice> all, int? pushed) {
  if (pushed == null) return const [];
  return [for (final n in all) if (n.at != null && n.at!.millisecondsSinceEpoch > pushed) n]..sort((a, b) => a.at!.compareTo(b.at!));
}

/// What the closed-app check needs to know, kept in a small file because the check runs apart from the app:
/// whether notices are on, and the newest notice already shown (so none is shown twice).
class NoticeMarker {
  const NoticeMarker({this.enabled = false, this.pushed});
  final bool enabled;
  final int? pushed;

  String encode() => jsonEncode({'enabled': enabled, if (pushed != null) 'pushed': pushed});
  static NoticeMarker decode(String? s) {
    try {
      final m = jsonDecode(s ?? '') as Map<String, dynamic>;
      return NoticeMarker(enabled: m['enabled'] == true, pushed: m['pushed'] is int ? m['pushed'] as int : null);
    } catch (_) {
      return const NoticeMarker();
    }
  }
}

const _uniqueName = 'dt.notices.check';
const _taskName = 'dt.notices';
const _channel = 'dt_notices';

/// Shows Digital Target notices while the app is closed. Android runs a short check about every 15 minutes
/// (or later when the phone saves battery), so a notice can arrive some minutes after it is sent; it is not instant.
class BackgroundNotices {
  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/notice_marker.json');

  static Future<NoticeMarker> read() async {
    try {
      final f = await _file();
      return NoticeMarker.decode(await f.exists() ? await f.readAsString() : null);
    } catch (_) {
      return const NoticeMarker();
    }
  }

  static Future<void> _write(NoticeMarker m) async => (await _file()).writeAsString(m.encode());

  /// Called while the app is open: turns the closed-app check on or off to match the owner's choice and sign-in.
  /// Never throws; where the plugins are missing (tests, other platforms) it does nothing.
  static bool? _last;
  static Future<void> sync({required bool enabled}) async {
    if (_last == enabled) return;
    _last = enabled;
    try {
      if (!Platform.isAndroid) return;
      final old = await read();
      await _write(NoticeMarker(enabled: enabled, pushed: old.pushed));
      await Workmanager().initialize(noticeCallbackDispatcher);
      if (enabled) {
        await Workmanager().registerPeriodicTask(
          _uniqueName,
          _taskName,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await Workmanager().cancelByUniqueName(_uniqueName);
      }
    } catch (_) {}
  }

  /// The app has shown everything up to [newest] itself.
  static Future<void> markPushed(int newest) async {
    try {
      if (!Platform.isAndroid) return;
      final old = await read();
      if (old.pushed != null && old.pushed! >= newest) return;
      await _write(NoticeMarker(enabled: old.enabled, pushed: newest));
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void noticeCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await checkNoticesInBackground();
    } catch (_) {}
    return true;
  });
}

/// Runs apart from the app: reads the signed-in account's notices from the server and shows the new ones.
Future<void> checkNoticesInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final marker = await BackgroundNotices.read();
  if (!marker.enabled) return;
  final gw = await initFirebaseGateway();
  final user = await gw.authChanges().first.timeout(const Duration(seconds: 20));
  if (user == null) return;
  final all = await gw.fetchNotices(user.uid);
  final newest = all.fold<int>(0, (m, n) => (n.at?.millisecondsSinceEpoch ?? 0) > m ? n.at!.millisecondsSinceEpoch : m);
  final fresh = freshNotices(all, marker.pushed);
  if (fresh.isNotEmpty) {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    for (final n in fresh) {
      await plugin.show(
        id: n.at!.millisecondsSinceEpoch & 0x7fffffff,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(_channel, 'Digital Target notices', importance: Importance.high, priority: Priority.high, styleInformation: BigTextStyleInformation(n.body)),
        ),
      );
    }
  }
  if (marker.pushed == null || newest > marker.pushed!) await BackgroundNotices.markPushed(newest);
}
