import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../data/print_service.dart';

class PairedPrinter {
  const PairedPrinter(this.name, this.address);
  final String name;
  final String address;
}

/// Lists Bluetooth printers already paired in Android settings. Overridden in tests.
abstract class BluetoothPrinterScanner {
  Future<List<PairedPrinter>> paired();
}

/// Asks for the Android 12+ "Nearby devices" permission; older Android grants Bluetooth at install time.
Future<void> _ensurePermission() async {
  final s = await Permission.bluetoothConnect.request();
  if (s.isPermanentlyDenied) throw PrinterException('Bluetooth permission is off. Allow "Nearby devices" for DT Food POS in Android settings.');
  if (!s.isGranted && !s.isLimited) {
    // Android 11 and older report this permission as not applicable; the plugin's own check decides then.
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) throw PrinterException('Bluetooth permission was not given.');
  }
}

class SystemBluetoothScanner implements BluetoothPrinterScanner {
  const SystemBluetoothScanner();
  @override
  Future<List<PairedPrinter>> paired() async {
    await _ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('Bluetooth is off. Turn it on and try again.');
    return [for (final d in await PrintBluetoothThermal.pairedBluetooths) PairedPrinter(d.name, d.macAdress)];
  }
}

/// Classic Bluetooth (SPP) ESC/POS printer, addressed by MAC. Jobs are sent one at a time because the plugin keeps a
/// single connection. NOTE: compiled and wired, but not yet tried on a real printer.
class BluetoothPrinterTransport implements PrinterTransport {
  BluetoothPrinterTransport(this.mac);
  final String mac;
  static Future<void> _chain = Future.value();

  @override
  Future<void> send(Uint8List bytes) {
    final job = _chain.then((_) => _send(bytes));
    _chain = job.catchError((_) {});
    return job;
  }

  Future<void> _send(Uint8List bytes) async {
    await _ensurePermission();
    if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('Bluetooth is off. Turn it on to print.');
    if (!await PrintBluetoothThermal.connect(macPrinterAddress: mac)) {
      throw PrinterException('Bluetooth printer $mac did not connect. Is it on, paired and in range?');
    }
    try {
      // Large logos can overflow small printer buffers; send in chunks.
      const chunk = 2048;
      for (var i = 0; i < bytes.length; i += chunk) {
        final ok = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
        if (!ok) throw PrinterException('Bluetooth printer $mac stopped receiving.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400)); // let the printer drain before the link closes
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
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
