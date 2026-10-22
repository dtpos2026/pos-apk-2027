import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for the server: applies each idempotency key at most once, like the real applied_operation table.
class FakeServer implements SyncTransport {
  final applied = <String>{};
  final appliedOrder = <String>[];
  bool online = true;
  bool loseNextAck = false; // server applies the batch, but the response never reaches the device
  final reject = <String>{};
  final retry = <String>{};
  int calls = 0;

  @override
  Future<Map<String, ItemOutcome>> push(List<OutboxItem> items) async {
    calls++;
    if (!online) throw Exception('no network');
    final out = <String, ItemOutcome>{};
    for (final i in items) {
      if (reject.contains(i.key)) {
        out[i.key] = ItemOutcome.rejected;
      } else if (retry.contains(i.key)) {
        out[i.key] = ItemOutcome.retry;
      } else {
        if (applied.add(i.key)) appliedOrder.add(i.key);
        out[i.key] = ItemOutcome.ok; // duplicates are acknowledged but not applied twice
      }
    }
    if (loseNextAck) {
      loseNextAck = false;
      throw Exception('connection reset after server applied the batch');
    }
    return out;
  }
}

late AppDatabase db;
late FakeServer server;
late SyncEngine engine;
var clock = DateTime(2026, 1, 12, 10);

Future<void> enqueue(String key, {String entity = 'order', String? id, int? version}) => db.customStatement(
    "INSERT INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,'upsert','{}',?,1)", [key, entity, id ?? key, version]);
Future<Map<String, Object?>> row(String key) async => (await db.customSelect('SELECT * FROM outbox WHERE idempotency_key = ?', variables: [Variable.withString(key)]).getSingle()).data;

void main() {
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeServer();
    clock = DateTime(2026, 1, 12, 10);
    engine = SyncEngine(db, server, now: () => clock, random: Random(1), batchSize: 2);
  });
  tearDown(() => db.close());

  test('drains everything in order across batches', () async {
    for (final k in ['a', 'b', 'c', 'd', 'e']) {
      await enqueue(k);
    }
    final s = await engine.drainAll();
    expect(s.sent, 5);
    expect(server.appliedOrder, ['a', 'b', 'c', 'd', 'e']);
    expect(await engine.pendingCount(), 0);
  });

  test('offline: nothing is lost, items back off, and sync resumes when the network returns', () async {
    await enqueue('a');
    server.online = false;
    final s = await engine.drainOnce();
    expect(s.networkError, isTrue);
    expect(await engine.pendingCount(), 1);
    expect((await row('a'))['attempts'], 1);
    // still inside the backoff window: not retried yet
    final calls = server.calls;
    await engine.drainOnce();
    expect(server.calls, calls);
    // network back + backoff elapsed
    server.online = true;
    clock = clock.add(const Duration(minutes: 1));
    expect((await engine.drainOnce()).sent, 1);
  });

  test('backoff grows exponentially and is capped', () {
    final e = SyncEngine(db, server, random: Random(0));
    final d = [for (var n = 1; n <= 12; n++) e.backoff(n).inSeconds];
    expect(d[1], greaterThan(d[0]));
    expect(d[3], greaterThan(d[1]));
    expect(d.last, lessThanOrEqualTo(15 * 60 + 1));
  });

  test('ACK LOST after the server applied the batch: the retry creates NO duplicate', () async {
    await enqueue('sale-1');
    await enqueue('sale-2');
    server.loseNextAck = true;
    final first = await engine.drainOnce();
    expect(first.networkError, isTrue);
    expect(server.applied, {'sale-1', 'sale-2'}); // applied on the server
    expect(await engine.pendingCount(), 2); // but the device doesn't know
    clock = clock.add(const Duration(minutes: 1));
    final second = await engine.drainOnce();
    expect(second.sent, 2);
    expect(server.applied.length, 2);
    expect(server.appliedOrder, ['sale-1', 'sale-2']); // each applied exactly once
  });

  test('a crash/restart mid-sync resumes from the database (new engine instance)', () async {
    for (final k in ['a', 'b', 'c']) {
      await enqueue(k);
    }
    await engine.drainOnce(); // a, b delivered
    final engine2 = SyncEngine(db, server, now: () => clock, batchSize: 2); // "app restarted"
    final s = await engine2.drainAll();
    expect(s.sent, 1);
    expect(server.appliedOrder, ['a', 'b', 'c']);
  });

  test('changes to one record stay in order even if an earlier one is waiting', () async {
    await enqueue('p1-v1', entity: 'product', id: 'p1', version: 1);
    await enqueue('p1-v2', entity: 'product', id: 'p1', version: 2);
    await enqueue('o1', entity: 'order', id: 'o1');
    server.retry.add('p1-v1');
    await engine.drainOnce();
    expect(server.applied, {'o1'}); // v2 was NOT sent ahead of v1
    server.retry.clear();
    clock = clock.add(const Duration(minutes: 1));
    await engine.drainAll();
    expect(server.appliedOrder, ['o1', 'p1-v1', 'p1-v2']);
  });

  test('rejected items are parked and do not block other records', () async {
    await enqueue('bad');
    await enqueue('good');
    server.reject.add('bad');
    final s = await engine.drainAll();
    expect(s.sent, 1);
    expect(s.rejected, 1);
    expect((await row('bad'))['last_error'], 'rejected by server');
    final calls = server.calls;
    clock = clock.add(const Duration(hours: 1));
    await engine.drainAll();
    expect(server.calls, calls); // still parked after an hour
    clock = clock.add(const Duration(hours: 25));
    server.reject.clear();
    expect((await engine.drainAll()).sent, 1);
  });

  test('duplicate idempotency keys cannot even be queued twice', () async {
    await enqueue('x');
    await expectLater(enqueue('x'), throwsA(anything));
  });
}
