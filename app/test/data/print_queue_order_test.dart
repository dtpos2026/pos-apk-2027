import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Slow implements PrinterTransport {
  _Slow(this.sent, {this.fail = false});
  final List<Uint8List> sent;
  final bool fail;
  @override
  Future<void> send(Uint8List bytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (fail) throw PrinterException('Printer is off');
    sent.add(bytes);
  }
}

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement("INSERT INTO printer(id, name, connection, address, paper_mm, role, updated_at) VALUES ('p1','Counter','lan','x',58,'both',1)");
    await db.customStatement("INSERT INTO print_job(id, printer_id, kind, payload, created_at, updated_at) VALUES ('j1','p1','bill',?,1,1)", [Uint8List.fromList([0x41])]);
  });
  tearDown(() => db.close());

  test('two quick "print" taps never send the same job twice', () async {
    final sent = <Uint8List>[];
    final svc = PrintService(db, transport: (c, a) => _Slow(sent));
    final both = await Future.wait([svc.processQueue(), svc.processQueue()]);
    expect(sent, hasLength(1));
    expect(both.map((s) => s.done).reduce((a, b) => a + b), 1);
  });

  test('a failed job is announced with the printer name and the reason', () async {
    final svc = PrintService(db, transport: (c, a) => _Slow(const [], fail: true));
    final heard = <PrintFailure>[];
    final sub = svc.failures.listen(heard.add);
    final stats = await svc.processQueue();
    await Future<void>.delayed(Duration.zero);
    expect(stats.failed, 1);
    expect(heard.single.printer, 'Counter');
    expect(heard.single.message, 'Printer is off');
    await sub.cancel();
    svc.dispose();
  });
}
