import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/queries.dart';
import '../data/sync_engine.dart';
import 'cloud_gateway.dart';

/// The owner's choice to keep a private copy of the restaurant's data in the cloud. OFF unless they switch it on
/// (the app is fully offline by default). Turning it on sends the whole history once, then every change.
class CloudCopyNotifier extends AsyncNotifier<bool> {
  static const key = 'cloud.copy';

  @override
  Future<bool> build() async => await getSetting(ref.read(databaseProvider), key) == '1';

  Future<void> set(bool on) async {
    await setSetting(ref.read(databaseProvider), key, on ? '1' : '0', ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(on);
  }
}

final cloudCopyProvider = AsyncNotifierProvider<CloudCopyNotifier, bool>(CloudCopyNotifier.new);

/// Sends outbox items to the owner's private cloud copy through the gateway.
class CloudOutboxTransport implements SyncTransport {
  CloudOutboxTransport(this.gateway, this.uid);
  final CloudGateway gateway;
  final String uid;

  @override
  Future<Map<String, ItemOutcome>> push(List<OutboxItem> items) async {
    await gateway.pushOps(uid, [for (final i in items) CloudOp(key: i.key, entity: i.entity, entityId: i.entityId, op: i.op, payload: i.payload, version: i.version)]);
    return {for (final i in items) i.key: ItemOutcome.ok};
  }
}
