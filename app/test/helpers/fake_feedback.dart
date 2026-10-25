import 'package:dt_food_pos/app/feedback.dart';

/// Records what the phone was asked to do (sounds, vibration, status-bar notices).
class FakeFeedback extends FeedbackPlayer {
  FakeFeedback({this.permission = true});
  bool permission;
  int clicks = 0, vibrations = 0, strongVibrations = 0, cleared = 0;
  final tones = <String>[];
  final shown = <String>[];
  @override
  Future<void> click() async => clicks++;
  @override
  Future<void> tone(String kind) async => tones.add(kind);
  @override
  Future<void> vibrate({bool strong = false}) async => strong ? strongVibrations++ : vibrations++;
  @override
  Future<bool> askNotificationPermission() async => permission;
  @override
  Future<bool> notificationsAllowed() async => permission;
  @override
  Future<bool> notify(String title, String body, int id) async {
    if (!permission) return false;
    shown.add(title);
    return true;
  }

  @override
  Future<void> clearNotifications() async => cleared++;
}
