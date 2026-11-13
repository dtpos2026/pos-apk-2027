import 'dart:convert';

const happyHourSettingKey = 'happyhour.config';

/// A discount that applies by itself during set hours on set days (e.g. 3 PM - 6 PM, Monday to Thursday, 15% off).
/// It is put on a new bill as its bill discount; the cashier can still change or remove it. Off until the owner switches it on.
class HappyHour {
  const HappyHour({this.enabled = false, this.days = const {1, 2, 3, 4, 5, 6, 7}, this.fromMinute = 15 * 60, this.toMinute = 18 * 60, this.percentBp = 1000});
  final bool enabled;

  /// Weekdays it runs on, Monday = 1 ... Sunday = 7.
  final Set<int> days;

  /// Minutes after midnight. When [toMinute] is before [fromMinute] it runs past midnight (e.g. 22:00 - 02:00).
  final int fromMinute;
  final int toMinute;
  final int percentBp;

  bool activeAt(DateTime t) {
    if (!enabled || percentBp <= 0 || fromMinute == toMinute) return false;
    final m = t.hour * 60 + t.minute;
    if (fromMinute < toMinute) return days.contains(t.weekday) && m >= fromMinute && m < toMinute;
    // past midnight: the early part belongs to the day it started on
    if (m >= fromMinute) return days.contains(t.weekday);
    return m < toMinute && days.contains(t.weekday == 1 ? 7 : t.weekday - 1);
  }

  HappyHour copyWith({bool? enabled, Set<int>? days, int? fromMinute, int? toMinute, int? percentBp}) => HappyHour(
        enabled: enabled ?? this.enabled,
        days: days ?? this.days,
        fromMinute: fromMinute ?? this.fromMinute,
        toMinute: toMinute ?? this.toMinute,
        percentBp: percentBp ?? this.percentBp,
      );

  String encode() => jsonEncode({'on': enabled, 'days': (days.toList()..sort()), 'from': fromMinute, 'to': toMinute, 'bp': percentBp});
  static HappyHour decode(String? raw) {
    try {
      final j = jsonDecode(raw ?? '') as Map<String, dynamic>;
      int n(String k, int d, int max) => j[k] is int && (j[k] as int) >= 0 && (j[k] as int) <= max ? j[k] as int : d;
      return HappyHour(
        enabled: j['on'] == true,
        days: {for (final d in (j['days'] as List? ?? const [])) if (d is int && d >= 1 && d <= 7) d},
        fromMinute: n('from', 15 * 60, 1439),
        toMinute: n('to', 18 * 60, 1439),
        percentBp: n('bp', 1000, 10000),
      );
    } catch (_) {
      return const HappyHour();
    }
  }
}
