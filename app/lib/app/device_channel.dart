import 'package:flutter/services.dart';

import '../data/print_service.dart';

class PairedPrinter {
  const PairedPrinter(this.name, this.address);
  final String name;
  final String address;
}

class PhoneLocation {
  const PhoneLocation(this.lat, this.lng, this.accuracyM, this.at);
  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime at;
}

/// Lists Bluetooth printers already paired in Android settings. Overridden in tests.
abstract class BluetoothPrinterScanner {
  Future<List<PairedPrinter>> paired();
}

/// Android features implemented in MainActivity.kt (no third-party plugins): stable phone id, Bluetooth printing,
/// permissions, one location fix. Errors come back as plain sentences.
class DeviceChannel {
  const DeviceChannel();
  static const _c = MethodChannel('digital.target/device');

  static const bluetoothPermissions = ['android.permission.BLUETOOTH_CONNECT'];
  static const locationPermissions = ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION'];

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _c.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw PrinterException(e.message ?? e.code);
    }
  }

  /// Same value after reinstalling the app on the same phone (with the same signing key); null if unavailable.
  Future<String?> phoneId() async {
    try {
      return await _c.invokeMethod<String>('phoneId');
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPermissions(List<String> p) async => await _call<bool>('hasPermissions', {'permissions': p}) ?? false;
  Future<bool> requestPermissions(List<String> p) async => await _call<bool>('requestPermissions', {'permissions': p}) ?? false;

  Future<List<PairedPrinter>> bluetoothPaired() async {
    if (!await requestPermissions(bluetoothPermissions)) {
      throw PrinterException('Bluetooth permission was not given. Allow "Nearby devices" for DT Food POS in Android settings.');
    }
    final list = await _call<List<Object?>>('bluetoothPaired') ?? const [];
    return [for (final m in list.cast<Map<Object?, Object?>>()) PairedPrinter('${m['name']}', '${m['address']}')];
  }

  Future<void> bluetoothPrint(String address, Uint8List bytes) async {
    if (!await requestPermissions(bluetoothPermissions)) {
      throw PrinterException('Bluetooth permission was not given. Allow "Nearby devices" for DT Food POS in Android settings.');
    }
    await _call<bool>('bluetoothPrint', {'address': address, 'bytes': bytes});
  }

  /// Saves a file where the person can find it (Downloads/DT Food POS, or Pictures/DT Food POS when [gallery] so it shows in the
  /// gallery). Returns the place it was saved. Throws [PrinterException] with a plain sentence on failure.
  Future<String> saveFile({required String path, required String name, required String mime, required bool gallery}) async {
    Future<String?> once() => _c.invokeMethod<String>('saveFile', {'path': path, 'name': name, 'mime': mime, 'gallery': gallery});
    try {
      return (await once()) ?? name;
    } on PlatformException catch (e) {
      if (e.code == 'permission' && await requestPermissions(const ['android.permission.WRITE_EXTERNAL_STORAGE'])) {
        try {
          return (await once()) ?? name;
        } on PlatformException catch (e2) {
          throw PrinterException(e2.message ?? e2.code);
        }
      }
      throw PrinterException(e.message ?? e.code);
    }
  }

  /// Opens WhatsApp with [text] ready to send to [phoneIntl] (digits with country code). false = no app could open it.
  Future<bool> openWhatsApp(String phoneIntl, String text) async {
    try {
      return await _c.invokeMethod<bool>('openWhatsApp', {'phone': phoneIntl, 'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static const notificationPermissions = ['android.permission.POST_NOTIFICATIONS'];

  /// A tone ('tap', 'success' or 'error'). Returns what happened: ok, fallback, silent, volume0 or failed. Never throws.
  /// [force] plays it even when the phone is on silent (the Settings test buttons).
  Future<String> tone(String kind, {bool force = false}) async {
    try {
      final r = await _c.invokeMethod<Object>('tone', {'kind': kind, 'force': force});
      return r is String ? r : 'ok';
    } catch (_) {
      return 'failed';
    }
  }

  /// A notice in the phone's status bar; false when Android permission is missing or notifications are off for the app.
  Future<bool> notify(String title, String body, int id) async {
    try {
      return await _c.invokeMethod<bool>('notify', {'title': title, 'body': body, 'id': id}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearNotifications() async {
    try {
      await _c.invokeMethod<bool>('clearNotifications');
    } catch (_) {}
  }

  /// null when permission is missing or no fix arrived in time.
  Future<PhoneLocation?> location() async {
    final m = await _call<Map<Object?, Object?>>('location');
    if (m == null) return null;
    return PhoneLocation((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble(), (m['accuracy'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()));
  }
}

class SystemBluetoothScanner implements BluetoothPrinterScanner {
  const SystemBluetoothScanner();
  @override
  Future<List<PairedPrinter>> paired() => const DeviceChannel().bluetoothPaired();
}

/// Classic Bluetooth (SPP) ESC/POS printer addressed by MAC. Jobs go one at a time.
/// Compiled and wired; not yet tried on a real printer.
class BluetoothPrinterTransport implements PrinterTransport {
  BluetoothPrinterTransport(this.mac);
  final String mac;
  static Future<void> _chain = Future.value();

  @override
  Future<void> send(Uint8List bytes) {
    final job = _chain.then((_) => const DeviceChannel().bluetoothPrint(mac, bytes));
    _chain = job.catchError((_) {});
    return job;
  }
}

/// The app's transport choice: Bluetooth by MAC address, everything else through the shared default (LAN).
PrinterTransport appTransport(String connection, String? address) {
  if (connection == 'bluetooth') {
    if (address == null || address.isEmpty) throw PrinterException('Choose the Bluetooth printer again in Settings');
    return BluetoothPrinterTransport(address);
  }
  return defaultTransport(connection, address);
}

/// Puts a file in the phone's Downloads or gallery. A seam so tests do not need Android.
abstract class PhoneFileSaver {
  Future<String> save({required String path, required String name, required String mime, bool gallery = false});
}

class AndroidFileSaver implements PhoneFileSaver {
  const AndroidFileSaver();
  @override
  Future<String> save({required String path, required String name, required String mime, bool gallery = false}) => const DeviceChannel().saveFile(path: path, name: name, mime: mime, gallery: gallery);
}
