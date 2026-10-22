import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/data/receipt_loader.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late PosService pos;
late PrintService print_;
Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
Future<List<Map<String, Object?>>> rows(String q) async => (await db.customSelect(q).get()).map((r) => r.data).toList();

/// A fake LAN printer: accepts connections on a loopback port and records every byte received.
class FakePrinter {
  late ServerSocket server;
  final received = <Uint8List>[];
  Future<void> start([int port = 0]) async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    server.listen((c) {
      final b = BytesBuilder();
      c.listen(b.add, onDone: () => received.add(b.toBytes()));
    });
  }

  int get port => server.port;
  Future<void> stop() => server.close();
  String get text => received.map((b) => latin1.decode(b, allowInvalid: true)).join();
}

void main() {
  late FakePrinter lan;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    lan = FakePrinter();
    await lan.start();
    pos = PosService(db, now: () => DateTime(2026, 1, 12, 19, 40));
    print_ = PrintService(db, now: () => DateTime(2026, 1, 12, 19, 41));
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO business_profile(id,name,address,phone,tax_number_label,tax_number,updated_at) VALUES ('self','Burger Point','Main Bazaar, Burewala','0300-0000000','NTN','1234567-8',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('d','Cola',10000,1)");
  });
  tearDown(() async {
    await lan.stop();
    await db.close();
  });

  Future<void> addPrinter(String id, String role, {String? station, int? port}) =>
      sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,station,updated_at) VALUES (?,?,'lan',?,58,?,?,1)", [id, id, '127.0.0.1:${port ?? lan.port}', role, station]);

  Future<String> sale() async {
    final id = await pos.saveDraft(const DraftOrder(orderType: 'counter', items: [
      CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, station: 'grill'),
      CartItem(productId: 'd', name: 'Cola', qtyMilli: 1000, unitPriceMinor: 10000, station: 'bar'),
    ]), staffId: 's1');
    await pos.settleOrder(orderId: id, payments: [const SettlePayment(methodId: 'cash', amountMinor: 100000)], staffId: 's1');
    return id;
  }

  test('receipt is built from the database snapshot', () async {
    final id = await sale();
    final r = await loadReceipt(db, id);
    expect(r.businessName, 'Burger Point');
    expect(r.invoiceNo, 'INV-20260112-0001');
    expect(r.lines.map((l) => l.name), ['Zinger Burger', 'Cola']);
    expect(r.totalMinor, 100000);
    expect(r.cashier, 'Ali');
    expect(r.payments.single.amountMinor, 100000);
  });

  test('bill reaches a real LAN printer over TCP, with the right content', () async {
    await addPrinter('counter', 'bill');
    final id = await sale();
    await print_.queueBill(id);
    final s = await print_.processQueue();
    expect(s.done, 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lan.text, contains('Burger Point'));
    expect(lan.text, contains('INV-20260112-0001'));
    expect(lan.text, contains('2 x Zinger Burger'));
    expect(lan.text, isNot(contains('DUPLICATE')));
    expect((await rows('SELECT status FROM print_job')).single['status'], 'done');
  });

  test('printing never blocks the sale: with no printer or an offline printer the order is still saved', () async {
    final noPrinter = await sale();
    expect(await print_.queueBill(noPrinter), isEmpty);
    await addPrinter('dead', 'bill', port: 1); // nothing listens on port 1
    final id = await sale();
    await print_.queueBill(id);
    final s = await print_.processQueue();
    expect(s.failed, 1);
    final job = (await rows('SELECT * FROM print_job')).single;
    expect(job['status'], 'failed');
    expect(job['last_error'], contains('offline'));
    expect((await rows("SELECT status FROM \"order\" WHERE id = '$id'")).single['status'], 'paid');
  });

  test('a failed job is retried and succeeds when the printer comes back', () async {
    final port = lan.port;
    await lan.stop();
    await addPrinter('p', 'bill', port: port);
    final id = await sale();
    await print_.queueBill(id);
    expect((await print_.processQueue()).failed, 1);
    await lan.start(port); // printer powered on again
    expect((await print_.processQueue()).done, 1);
    expect((await rows('SELECT attempts, status FROM print_job')).single, {'attempts': 2, 'status': 'done'});
  });

  test('gives up after maxAttempts instead of retrying forever', () async {
    await addPrinter('dead', 'bill', port: 1);
    final id = await sale();
    await print_.queueBill(id);
    for (var i = 0; i < 8; i++) {
      await print_.processQueue();
    }
    expect((await rows('SELECT attempts FROM print_job')).single['attempts'], 5);
  });

  test('reprint carries the DUPLICATE marker and is audited', () async {
    await addPrinter('counter', 'bill');
    final id = await sale();
    await print_.queueBill(id, duplicate: true, staffId: 's1');
    await print_.processQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lan.text, contains('*** DUPLICATE ***'));
    expect(await rows("SELECT id FROM audit_log WHERE event='bill.reprint'"), hasLength(1));
  });

  test('KOT routing: each station printer gets only its own items; no prices', () async {
    final grill = FakePrinter(), bar = FakePrinter();
    await grill.start();
    await bar.start();
    await addPrinter('grill-p', 'kot', station: 'grill', port: grill.port);
    await addPrinter('bar-p', 'kot', station: 'bar', port: bar.port);
    final id = await sale();
    expect(await print_.queueKot(id), hasLength(2));
    await print_.processQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(grill.text, contains('2 x Zinger Burger'));
    expect(grill.text, isNot(contains('Cola')));
    expect(bar.text, contains('1 x Cola'));
    expect(bar.text, isNot(contains('Burger')));
    expect(grill.text, isNot(contains('1,000.00')));
    await grill.stop();
    await bar.stop();
  });

  test('jobs left in "printing" by a crash are picked up again', () async {
    await addPrinter('p', 'bill');
    final id = await sale();
    await print_.queueBill(id);
    await sql("UPDATE print_job SET status='printing'");
    expect((await print_.processQueue()).done, 1);
  });

  test('unsupported connection types fail clearly instead of silently', () async {
    await sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('bt','bt','bluetooth','AA:BB',58,'bill',1)");
    final id = await sale();
    await print_.queueBill(id);
    await print_.processQueue();
    expect((await rows('SELECT last_error FROM print_job')).single['last_error'], contains('not supported yet'));
  });
}
