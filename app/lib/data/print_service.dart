import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/receipt.dart';
import '../domain/receipt_doc.dart';
import '../domain/receipt_template.dart';
import 'receipt_settings.dart';
import 'db/database.dart';
import 'receipt_loader.dart';

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One way of getting bytes to a printer. LAN (raw TCP 9100) is implemented and tested.
/// Bluetooth classic (SPP), BLE and USB need native plugins and a real printer, and are NOT implemented yet.
abstract class PrinterTransport {
  Future<void> send(Uint8List bytes);
}

class TcpPrinterTransport implements PrinterTransport {
  TcpPrinterTransport(this.host, {this.port = 9100, this.timeout = const Duration(seconds: 5)});
  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<void> send(Uint8List bytes) async {
    Socket? s;
    try {
      s = await Socket.connect(host, port, timeout: timeout);
      s.add(bytes);
      await s.flush();
    } on SocketException catch (e) {
      throw PrinterException('Printer $host:$port is offline (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw PrinterException('Printer $host:$port did not respond');
    } finally {
      await s?.close();
    }
  }
}

typedef TransportFactory = PrinterTransport Function(String connection, String? address);

PrinterTransport defaultTransport(String connection, String? address) {
  if (connection == 'lan' && address != null) {
    final parts = address.split(':');
    return TcpPrinterTransport(parts[0], port: parts.length > 1 ? int.parse(parts[1]) : 9100);
  }
  throw PrinterException('Connection type "$connection" is not supported yet');
}

class PrintStats {
  const PrintStats({this.done = 0, this.failed = 0});
  final int done;
  final int failed;
}

/// Print queue. Saving an order only ever INSERTs `print_job` rows; sending happens in [processQueue], so a
/// missing or offline printer can never block or undo a sale. Failed jobs stay queued with the error for retry.
class PrintService {
  PrintService(this.db, {TransportFactory? transport, DateTime Function()? now, this.maxAttempts = 5, this.rasterizer})
      : _transport = transport ?? defaultTransport,
        _now = now ?? DateTime.now;
  final AppDatabase db;

  /// Prints Urdu/Arabic lines as bitmaps. null = such lines come out as '?' (the app supplies one).
  final TextRasterizer? rasterizer;
  final TransportFactory _transport;
  final DateTime Function() _now;
  final int maxAttempts;

  int get _ts => _now().millisecondsSinceEpoch;

  Future<List<Map<String, Object?>>> _select(String sql, [List<Object?> args = const []]) async =>
      (await db.customSelect(sql, variables: args.map((a) => a is int ? Variable.withInt(a) : Variable.withString(a as String)).toList()).get()).map((r) => r.data).toList();

  /// Queues the customer bill for every enabled bill printer. Returns the job ids (empty if none configured).
  Future<List<String>> queueBill(String orderId, {bool duplicate = false, String? staffId}) async {
    final printers = await _select("SELECT * FROM printer WHERE enabled = 1 AND deleted_at IS NULL AND role IN ('bill','both') ORDER BY name");
    if (printers.isEmpty) return [];
    final template = await ReceiptTemplateStore(db).load();
    final ids = <String>[];
    for (final p in printers) {
      final paper = p['paper_mm'] as int;
      // per printer: the logo bitmap and the text columns depend on the paper width
      final data = await loadReceipt(db, orderId, duplicate: duplicate, paperMm: paper);
      final bytes = await buildBillBytes(data, paperMm: paper, template: template, rasterizer: rasterizer);
      ids.add(await _enqueue(p['id'] as String, 'bill', orderId, bytes, duplicate));
    }
    if (duplicate) {
      await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, critical) VALUES (?,?,?,?,?,?,0)',
          [const Uuid().v4(), _ts, staffId, 'bill.reprint', 'order', orderId]);
    }
    return ids;
  }

  /// Queues a TEST bill built by [build] (called per printer, because the logo bitmap and columns depend on the paper
  /// width) on every enabled bill printer. Used by the receipt designer so the owner can see the real print.
  Future<List<String>> queueTestBill(ReceiptData Function(int paperMm) build, BillDesign template) async {
    final printers = await _select("SELECT * FROM printer WHERE enabled = 1 AND deleted_at IS NULL AND role IN ('bill','both') ORDER BY name");
    final ids = <String>[];
    for (final p in printers) {
      final paper = p['paper_mm'] as int;
      final bytes = await buildBillBytes(build(paper), paperMm: paper, template: template, rasterizer: rasterizer);
      ids.add(await _enqueue(p['id'] as String, 'bill', null, bytes, false));
    }
    return ids;
  }

  /// Queues kitchen tickets: items are grouped by station and sent to the printer for that station
  /// (a kot printer with no station receives everything not claimed by a station printer).
  Future<List<String>> queueKot(String orderId, {bool reprint = false, bool onlyNew = false}) async {
    final printers = await _select("SELECT * FROM printer WHERE enabled = 1 AND deleted_at IS NULL AND role IN ('kot','both') ORDER BY name");
    if (printers.isEmpty) return [];
    final o = (await _select('SELECT * FROM "order" WHERE id = ?', [orderId])).first;
    var items = await _select("SELECT * FROM order_item WHERE order_id = ? AND status = 'active' ${onlyNew ? 'AND qty_milli > kot_qty_milli' : ''} ORDER BY rowid", [orderId]);
    if (items.isEmpty) return [];
    // only what the kitchen does not have yet: 2 burgers sent, 3 now on the order -> print 1
    if (onlyNew) items = [for (final i in items) {...i, 'qty_milli': (i['qty_milli'] as int) - (i['kot_qty_milli'] as int)}];
    final byStation = <String, List<Map<String, Object?>>>{};
    final claimed = {for (final p in printers) if (p['station'] != null) p['station'] as String};
    for (final i in items) {
      final st = i['station'] as String?;
      byStation.putIfAbsent(st != null && claimed.contains(st) ? st : '', () => []).add(i);
    }
    final table = o['table_id'] == null ? null : (await _select('SELECT label FROM dining_table WHERE id = ?', [o['table_id'] as String])).firstOrNull?['label'] as String?;
    final ids = <String>[];
    for (final p in printers) {
      final station = (p['station'] as String?) ?? '';
      final lines = byStation[station];
      if (lines == null || lines.isEmpty) continue;
      final kotLines = <KotLine>[];
      for (final i in lines) {
        final mods = await _select('SELECT name FROM order_item_modifier WHERE order_item_id = ?', [i['id'] as String]);
        kotLines.add(KotLine(i['name'] as String, i['qty_milli'] as int, modifiers: [for (final m in mods) m['name'] as String], note: i['note'] as String?));
      }
      final bytes = buildKot(
        station: station.isEmpty ? 'Kitchen' : station,
        orderLabel: (o['invoice_no'] as String?) ?? '#${(o['id'] as String).substring(0, 4)}',
        orderTypeLabel: orderTypeLabels[o['order_type']] ?? '${o['order_type']}',
        tableLabel: table,
        dateTime: formatDateTime(_now()),
        lines: kotLines,
        paperMm: p['paper_mm'] as int,
        isReprint: reprint,
      );
      ids.add(await _enqueue(p['id'] as String, 'kot', orderId, bytes, reprint));
    }
    if (onlyNew && ids.isNotEmpty) {
      // remember what the kitchen already has, so the next "send" only prints what was added since
      await db.customStatement("UPDATE order_item SET kot_qty_milli = qty_milli, kot_sent_at = ? WHERE order_id = ? AND status = 'active' AND qty_milli > kot_qty_milli", [_ts, orderId]);
    }
    return ids;
  }

  Future<String> _enqueue(String printerId, String kind, String? orderId, Uint8List bytes, bool dup) async {
    final id = const Uuid().v4();
    await db.customStatement('INSERT INTO print_job(id, printer_id, kind, order_id, payload, is_duplicate, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)',
        [id, printerId, kind, orderId, bytes, dup ? 1 : 0, _ts, _ts]);
    return id;
  }

  /// Sends every queued/failed job that has attempts left. Jobs stuck in 'printing' (app died mid-print) are retried.
  Future<PrintStats> processQueue() async {
    await db.customStatement("UPDATE print_job SET status = 'queued' WHERE status = 'printing'");
    final jobs = await _select(
        "SELECT j.*, p.connection AS connection, p.address AS address FROM print_job j JOIN printer p ON p.id = j.printer_id WHERE j.status IN ('queued','failed') AND j.attempts < ? ORDER BY j.created_at, j.rowid",
        [maxAttempts]);
    var done = 0, failed = 0;
    for (final j in jobs) {
      await db.customStatement("UPDATE print_job SET status = 'printing', updated_at = ? WHERE id = ?", [_ts, j['id']]);
      try {
        await _transport(j['connection'] as String, j['address'] as String?).send(j['payload'] as Uint8List);
        await db.customStatement("UPDATE print_job SET status = 'done', last_error = NULL, attempts = attempts + 1, updated_at = ? WHERE id = ?", [_ts, j['id']]);
        done++;
      } catch (e) {
        await db.customStatement("UPDATE print_job SET status = 'failed', last_error = ?, attempts = attempts + 1, updated_at = ? WHERE id = ?", ['$e', _ts, j['id']]);
        failed++;
      }
    }
    return PrintStats(done: done, failed: failed);
  }
}
