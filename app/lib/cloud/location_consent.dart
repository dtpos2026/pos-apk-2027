import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/device_channel.dart';
import '../app/providers.dart';
import '../data/queries.dart';

/// Where location comes from. main() supplies Android; null (tests/default) = this build cannot read location.
final locationSourceProvider = Provider<Future<PhoneLocation?> Function()?>((ref) => null);

/// Asks Android for location permission. Returns whether it was given.
final locationPermissionProvider = Provider<Future<bool> Function()>((ref) => () async => false);

/// The owner's choice to show this phone's location to Digital Target. null = not asked yet.
/// Nothing is read or sent unless this is true AND Android permission was given.
class LocationConsentNotifier extends AsyncNotifier<bool?> {
  static const key = 'cloud.share_location';

  @override
  Future<bool?> build() async {
    final v = await getSetting(ref.read(databaseProvider), key);
    return v == null ? null : v == '1';
  }

  /// Turning it on asks for Android permission first; if refused, it stays off. Returns the final value.
  Future<bool> set(bool on) async {
    var value = on;
    if (on) value = await ref.read(locationPermissionProvider)();
    await setSetting(ref.read(databaseProvider), key, value ? '1' : '0', ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(value);
    return value;
  }
}

final locationConsentProvider = AsyncNotifierProvider<LocationConsentNotifier, bool?>(LocationConsentNotifier.new);
