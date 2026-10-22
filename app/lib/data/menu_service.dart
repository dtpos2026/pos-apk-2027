import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';

class MenuException implements Exception {
  MenuException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Create/edit menu items. Every change bumps the version, writes an outbox row (sync) and an audit row.
class MenuService {
  MenuService(this.db, {DateTime Function()? now, String Function()? newId})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> a = const []]) async =>
      (await db.customSelect(sql, variables: a.map((x) => x is int ? Variable.withInt(x) : Variable.withString(x as String)).toList()).get()).map((r) => r.data).toList();

  Future<String?> categoryId(String? name) async {
    if (name == null || name.trim().isEmpty) return null;
    final found = await _q('SELECT id FROM category WHERE lower(name) = lower(?) AND deleted_at IS NULL', [name.trim()]);
    if (found.isNotEmpty) return found.first['id'] as String;
    final id = _newId();
    await db.customStatement('INSERT INTO category(id, name, updated_at) VALUES (?,?,?)', [id, name.trim(), _now().millisecondsSinceEpoch]);
    return id;
  }

  Future<String> saveProduct({String? id, required String name, required int priceMinor, String? categoryName, String? sku, bool available = true, required String staffId}) =>
      db.transaction(() async {
        if (name.trim().isEmpty) throw MenuException('Name is required');
        if (priceMinor < 0) throw MenuException('Price cannot be negative');
        if (sku != null && sku.trim().isNotEmpty) {
          final dup = await _q('SELECT id FROM product WHERE sku = ? AND deleted_at IS NULL AND id <> ?', [sku.trim(), id ?? '']);
          if (dup.isNotEmpty) throw MenuException('SKU "${sku.trim()}" is already used');
        }
        final now = _now().millisecondsSinceEpoch;
        final cat = await categoryId(categoryName);
        final pid = id ?? _newId();
        if (id == null) {
          await db.customStatement('INSERT INTO product(id, category_id, name, sku, base_price_minor, available, updated_at) VALUES (?,?,?,?,?,?,?)',
              [pid, cat, name.trim(), sku?.trim().isEmpty ?? true ? null : sku!.trim(), priceMinor, available ? 1 : 0, now]);
        } else {
          final before = await _q('SELECT name, base_price_minor FROM product WHERE id = ?', [id]);
          if (before.isEmpty) throw MenuException('Item not found');
          await db.customStatement('UPDATE product SET category_id=?, name=?, sku=?, base_price_minor=?, available=?, updated_at=?, version=version+1 WHERE id=?',
              [cat, name.trim(), sku?.trim().isEmpty ?? true ? null : sku!.trim(), priceMinor, available ? 1 : 0, now, id]);
          if (before.first['base_price_minor'] != priceMinor) {
            await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, before_json, after_json, device_id, critical) VALUES (?,?,?,?,?,?,?,?,?,0)',
                [_newId(), now, staffId, 'product.price_change', 'product', id, jsonEncode({'price': before.first['base_price_minor']}), jsonEncode({'price': priceMinor}), 'device']);
          }
        }
        final version = (await _q('SELECT version FROM product WHERE id = ?', [pid])).first['version'] as int;
        await db.customStatement('INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,?,?,?,?)',
            ['product:$pid:v$version', 'product', pid, 'upsert', jsonEncode({'id': pid, 'name': name.trim(), 'base_price_minor': priceMinor, 'available': available}), version, now]);
        return pid;
      });

  Future<void> setAvailable(String id, bool available, {required String staffId}) async {
    final r = await _q('SELECT name, base_price_minor, sku, category_id FROM product WHERE id = ?', [id]);
    if (r.isEmpty) throw MenuException('Item not found');
    final now = _now().millisecondsSinceEpoch;
    await db.customStatement('UPDATE product SET available=?, updated_at=?, version=version+1 WHERE id=?', [available ? 1 : 0, now, id]);
    final version = (await _q('SELECT version FROM product WHERE id = ?', [id])).first['version'] as int;
    await db.customStatement('INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,?,?,?,?)',
        ['product:$id:v$version', 'product', id, 'upsert', jsonEncode({'id': id, 'available': available}), version, now]);
  }

  /// Soft delete (tombstone): old receipts keep their snapshot, sync learns about the deletion.
  Future<void> deleteProduct(String id, {required String staffId}) async {
    final now = _now().millisecondsSinceEpoch;
    await db.transaction(() async {
      await db.customStatement('UPDATE product SET deleted_at=?, updated_at=?, version=version+1 WHERE id=? AND deleted_at IS NULL', [now, now, id]);
      final version = (await _q('SELECT version FROM product WHERE id = ?', [id])).first['version'] as int;
      await db.customStatement('INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,?,?,?,?)',
          ['product:$id:v$version', 'product', id, 'delete', '{}', version, now]);
      await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, device_id, critical) VALUES (?,?,?,?,?,?,?,1)', [_newId(), now, staffId, 'product.delete', 'product', id, 'device']);
    });
  }
}
