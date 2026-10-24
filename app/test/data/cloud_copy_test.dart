import 'package:drift/native.dart';
import 'package:dt_food_pos/cloud/cloud_copy.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cloud.dart';

void main() {
  test('the cloud copy sends each change once, keeps what failed for later, and never sends twice', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final cloud = FakeCloud();
    final engine = SyncEngine(db, CloudOutboxTransport(cloud, 'u1'), now: () => DateTime(2026, 1, 12, 10), baseDelay: Duration.zero, maxDelay: Duration.zero);
    Future<void> add(String key, String id) => db.customStatement("INSERT INTO outbox(idempotency_key, entity, entity_id, op, payload, created_at) VALUES (?,'customer',?,'upsert','{}',1)", [key, id]);

    await add('customer:c1:v1', 'c1');
    await add('customer:c2:v1', 'c2');
    var s = await engine.drainAll();
    expect(s.sent, 2);
    expect(cloud.pushedOps.map((o) => o.key), ['customer:c1:v1', 'customer:c2:v1']);
    expect((await engine.drainAll()).sent, 0, reason: 'already delivered: nothing is sent twice');

    await add('customer:c3:v1', 'c3');
    cloud.failNext = 'no internet';
    s = await engine.drainAll();
    expect(s.networkError, isTrue);
    expect(await engine.pendingCount(), 1);
    cloud.failNext = null;
    await Future<void>.delayed(const Duration(milliseconds: 1100)); // the retry back-off has jitter of up to a second
    final later = SyncEngine(db, CloudOutboxTransport(cloud, 'u1'), now: () => DateTime(2026, 1, 12, 11));
    s = await later.drainAll();
    expect(s.sent, 1);
    expect(cloud.pushedOps.last.key, 'customer:c3:v1');
    await db.close();
  });
}
