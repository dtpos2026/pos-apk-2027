import 'dart:typed_data';

import 'package:dt_food_pos/app/device_channel.dart';
import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/app/theme.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

class FakeScanner implements BluetoothPrinterScanner {
  FakeScanner(this.devices, {this.error});
  final List<PairedPrinter> devices;
  final String? error;
  @override
  Future<List<PairedPrinter>> paired() async {
    if (error != null) throw PrinterException(error!);
    return devices;
  }
}

class RecordingTransport implements PrinterTransport {
  RecordingTransport(this.sent, this.key);
  final Map<String, List<int>> sent;
  final String key;
  @override
  Future<void> send(Uint8List bytes) async => sent[key] = bytes;
}

void main() {
  test('brand colour is Restaurant Red #C92A2A (no purple)', () => expect(brandRed.toARGB32(), 0xFFC92A2A));

  testWidgets('a paired Bluetooth printer can be added and bills are sent to it by its address', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final sent = <String, List<int>>{};
    final h = await pumpApp(t, db: db, btScanner: FakeScanner(const [PairedPrinter('BlueTooth Printer', '86:67:7A:11:22:33')]),
        transport: (connection, address) => RecordingTransport(sent, '$connection|$address'));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('add-printer')), 300, scrollable: verticalScroll);
    await t.drag(verticalScroll, const Offset(0, -160));
    await t.pumpAndSettle();
    await tapKey(t, 'add-printer');
    await t.tap(find.text('Bluetooth'));
    await t.pumpAndSettle();
    await tapKey(t, 'printer-choose-bt');
    await tapKey(t, 'bt-86:67:7A:11:22:33');
    expect(find.textContaining('86:67:7A:11:22:33'), findsOneWidget);
    await tapKey(t, 'printer-save');
    final row = (await db.customSelect('SELECT connection, address FROM printer').getSingle()).data;
    expect(row, {'connection': 'bluetooth', 'address': '86:67:7A:11:22:33'});

    final print_ = h.container.read(printServiceProvider);
    await t.runAsync(() async {
      final pid = (await db.customSelect('SELECT id FROM printer').getSingle()).data['id'];
      await db.customStatement("INSERT INTO print_job(id, printer_id, kind, payload, created_at, updated_at) VALUES ('j1', ?, 'bill', ?, 1, 1)", [pid, Uint8List.fromList([0x1B, 0x40, 0x41])]);
      final stats = await print_.processQueue();
      expect(stats.done, 1);
    });
    expect(sent.keys, ['bluetooth|86:67:7A:11:22:33']);
    expect(sent.values.single, isNotEmpty);
  });

  testWidgets('Bluetooth problems are shown in plain words, nothing is saved', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db, btScanner: FakeScanner(const [], error: 'Bluetooth is off. Turn it on and try again.'));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('add-printer')), 300, scrollable: verticalScroll);
    await t.drag(verticalScroll, const Offset(0, -160));
    await t.pumpAndSettle();
    await tapKey(t, 'add-printer');
    await t.tap(find.text('Bluetooth'));
    await t.pumpAndSettle();
    await tapKey(t, 'printer-choose-bt');
    expect(find.text('Bluetooth is off. Turn it on and try again.'), findsOneWidget);
    await tapKey(t, 'printer-save');
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM printer').getSingle()).data['n'], 0);
  });

  test('appTransport routes Bluetooth by MAC and refuses a missing address', () {
    expect(appTransport('bluetooth', 'AA:BB'), isA<BluetoothPrinterTransport>());
    expect(() => appTransport('bluetooth', ''), throwsA(isA<PrinterException>()));
    expect(appTransport('lan', '10.0.0.5:9100'), isA<TcpPrinterTransport>());
  });
}
