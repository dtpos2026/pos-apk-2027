import 'dart:math';

import 'package:drift/drift.dart';

import 'db/database.dart';

class OutboxItem {
  const OutboxItem({required this.seq, required this.key, required this.entity, required this.entityId, required this.op, required this.payload, this.version});
  final int seq;
  final String key;
  final String entity;
  final String entityId;
  final String op;
  final String payload;
  final int? version;
}

enum ItemOutcome {
  /// Server applied it (or had already applied this idempotency key).
  ok,

  /// Temporary problem for this item: try again later.
  retry,

  /// Server refused it permanently (validation, tenant mismatch...). Parked, not hammered.
  rejected,
}

/// Network side of sync. [push] returns an outcome per idempotency key and throws when the network or server is
/// unreachable (every item in the batch is then treated as not delivered).
abstract class SyncTransport {
  Future<Map<String, ItemOutcome>> push(List<OutboxItem> items);
}

class SyncStats {
  const SyncStats({this.sent = 0, this.retried = 0, this.rejected = 0, this.networkError = false});
  final int sent;
  final int retried;
  final int rejected;
  final bool networkError;
}

/// Drains the outbox. Guarantees:
///  * at-least-once delivery with a unique idempotency key per change, so the server can apply each exactly once;
///  * an item is only marked acknowledged after the server confirmed it, so a crash mid-sync just re-sends;
///  * changes to the same record are sent in order (a later change waits for an earlier one still in backoff);
///  * exponential backoff with jitter, capped, so a dead network is not hammered.
class SyncEngine {
  SyncEngine(this.db, this.transport, {DateTime Function()? now, Random? random, this.batchSize = 50, this.baseDelay = const Duration(seconds: 2), this.maxDelay = const Duration(minutes: 15), this.rejectedParkFor = const Duration(hours: 24)})
      : _now = now ?? DateTime.now,
        _random = random ?? Random();
  final AppDatabase db;
  final SyncTransport transport;
  final DateTime Function() _now;
  final Random _random;
  final int batchSize;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration rejectedParkFor;

  Duration backoff(int attempts) {
    final exp = baseDelay.inMilliseconds * pow(2, min(attempts, 20)).toInt();
    final capped = min(exp, maxDelay.inMilliseconds);
    return Duration(milliseconds: capped + _random.nextInt(1000));
  }

  Future<int> pendingCount() async => (await db.customSelect('SELECT COUNT(*) AS n FROM outbox WHERE acked_at IS NULL').getSingle()).data['n'] as int;

  Future<List<OutboxItem>> _due(int now) async {
    final rows = await db.customSelect(
        'SELECT o.* FROM outbox o WHERE o.acked_at IS NULL AND o.next_attempt_at <= ? '
        'AND NOT EXISTS (SELECT 1 FROM outbox e WHERE e.acked_at IS NULL AND e.entity = o.entity AND e.entity_id = o.entity_id AND e.seq < o.seq) '
        'ORDER BY o.seq LIMIT ?',
        variables: [Variable.withInt(now), Variable.withInt(batchSize)]).get();
    return [
      for (final r in rows.map((r) => r.data))
        OutboxItem(seq: r['seq'] as int, key: r['idempotency_key'] as String, entity: r['entity'] as String, entityId: r['entity_id'] as String, op: r['op'] as String, payload: r['payload'] as String, version: r['entity_version'] as int?)
    ];
  }

  /// Sends one batch of due items. Call repeatedly (or when connectivity returns) until it reports nothing sent.
  Future<SyncStats> drainOnce() async {
    final now = _now().millisecondsSinceEpoch;
    final batch = await _due(now);
    if (batch.isEmpty) return const SyncStats();

    Map<String, ItemOutcome> outcomes;
    try {
      outcomes = await transport.push(batch);
    } catch (e) {
      for (final i in batch) {
        await _fail(i, now, '$e', backoff: true);
      }
      return SyncStats(retried: batch.length, networkError: true);
    }
    var sent = 0, retried = 0, rejected = 0;
    for (final i in batch) {
      switch (outcomes[i.key] ?? ItemOutcome.retry) {
        case ItemOutcome.ok:
          await db.customStatement('UPDATE outbox SET acked_at = ?, last_error = NULL WHERE seq = ?', [now, i.seq]);
          sent++;
        case ItemOutcome.retry:
          await _fail(i, now, 'server asked to retry', backoff: true);
          retried++;
        case ItemOutcome.rejected:
          await _fail(i, now, 'rejected by server', backoff: false);
          rejected++;
      }
    }
    return SyncStats(sent: sent, retried: retried, rejected: rejected);
  }

  Future<void> _fail(OutboxItem i, int now, String error, {required bool backoff}) async {
    final attempts = ((await db.customSelect('SELECT attempts FROM outbox WHERE seq = ?', variables: [Variable.withInt(i.seq)]).getSingle()).data['attempts'] as int) + 1;
    final next = now + (backoff ? this.backoff(attempts).inMilliseconds : rejectedParkFor.inMilliseconds);
    await db.customStatement('UPDATE outbox SET attempts = ?, next_attempt_at = ?, last_error = ? WHERE seq = ?', [attempts, next, error, i.seq]);
  }

  /// Drains until the outbox has nothing due or the network fails.
  Future<SyncStats> drainAll({int maxBatches = 100}) async {
    var sent = 0, retried = 0, rejected = 0;
    for (var b = 0; b < maxBatches; b++) {
      final s = await drainOnce();
      sent += s.sent;
      retried += s.retried;
      rejected += s.rejected;
      if (s.networkError) return SyncStats(sent: sent, retried: retried, rejected: rejected, networkError: true);
      if (s.sent + s.retried + s.rejected == 0) break;
    }
    return SyncStats(sent: sent, retried: retried, rejected: rejected);
  }
}
