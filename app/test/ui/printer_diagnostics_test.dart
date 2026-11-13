import 'dart:typed_data';

import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/features/settings/printer_diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

class _Recorder implements PrinterTransport {
  _Recorder(this.sent, {this.fail});
  final List<Uint8List> sent;
  final String? fail;
  @override
  Future<void> send(Uint8List bytes) async {
    if (fail != null) throw PrinterException(fail!);
    sent.add(bytes);
  }
}

void main() {
  test('plain text test is only ASCII text and feeds; the graphics test is one bordered picture of the right width', () {
    final text = plainTextTest();
    expect(String.fromCharCodes(text), contains('Printer test'));
    expect(text.length, lessThan(600), reason: 'tiny: any printer buffer can take it');
    for (final mm in [58, 80]) {
      final g = graphicsTest(paperMm: mm);
      final i = g.indexOfSubsequence([0x1D, 0x76, 0x30]);
      expect(i, greaterThanOrEqualTo(0), reason: 'GS v 0 raster command');
      final widthBytes = g[i + 4] + g[i + 5] * 256, heightPx = g[i + 6] + g[i + 7] * 256;
      expect(widthBytes, mm == 80 ? 72 : 48);
      expect(heightPx, 120);
    }
  });

  testWidgets('printer test screen: runs each step on the chosen printer and reports success and failure in words', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO printer(id, name, connection, address, paper_mm, role, updated_at) VALUES ('p1','Counter','lan','10.0.0.9:9100',58,'both',1)");
    final sent = <Uint8List>[];
    var fail = false;
    await pumpApp(t, db: db, transport: (c, a) => _Recorder(sent, fail: fail ? 'Printer $a is offline' : null));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('printer-help-Counter')), 300, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('printer-help-Counter')));
    await t.pumpAndSettle();
    await tapKey(t, 'printer-help-Counter');
    expect(find.text('Printer test'), findsWidgets);

    await tapKey(t, 'diag-text');
    expect(sent, hasLength(1));
    expect(find.textContaining('bytes sent'), findsOneWidget);
    await tapKey(t, 'diag-graphics');
    expect(sent, hasLength(2));
    await t.ensureVisible(find.byKey(const ValueKey('diag-kot')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('diag-kot')));
    for (var i = 0; i < 30 && sent.length < 3; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(sent, hasLength(3));
    expect(String.fromCharCodes(sent.last), contains('Zinger Burger'), reason: 'sample KOT');

    fail = true;
    await tapKey(t, 'diag-text');
    expect(find.textContaining('10.0.0.9:9100 is offline'), findsOneWidget);
  });

  testWidgets('a print that fails is said on screen with the reason and a way to the printer test (never silent)', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO printer(id, name, connection, address, paper_mm, role, updated_at) VALUES ('p1','Counter','lan','10.0.0.9:9100',58,'both',1)");
    await pumpApp(t, db: db, transport: (c, a) => _Recorder(const [], fail: 'Printer $a is offline'));
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('printer-test-Counter')), 300, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('printer-test-Counter')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('printer-test-Counter')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('print-failed')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.byKey(const ValueKey('print-failed')), findsOneWidget);
    expect(find.textContaining('Counter: Printer 10.0.0.9:9100 is offline'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 600)); // the snackbar finishes sliding in
    await t.tap(find.byType(SnackBarAction));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('diag-text')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
    }
    expect(find.byKey(const ValueKey('diag-text')), findsOneWidget, reason: 'the snackbar button opens the printer test');
  });
}

extension on Uint8List {
  int indexOfSubsequence(List<int> seq) {
    for (var i = 0; i <= length - seq.length; i++) {
      var ok = true;
      for (var j = 0; j < seq.length; j++) {
        if (this[i + j] != seq[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }
}
