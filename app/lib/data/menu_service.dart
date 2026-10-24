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

  /// Sets the counter/station of a whole category (blank = none).
  Future<void> setCategoryStation(String categoryId, String? station) => db.customStatement(
      'UPDATE category SET station = ?, updated_at = ?, version = version + 1 WHERE id = ?', [station == null || station.trim().isEmpty ? null : station.trim(), _now().millisecondsSinceEpoch, categoryId]);

  Future<String> saveProduct({String? id, required String name, required int priceMinor, String? categoryName, String? sku, bool available = true, String? station, bool updateStation = false, required String staffId}) =>
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
        if (updateStation || (id == null && station != null)) {
          await db.customStatement('UPDATE product SET station = ? WHERE id = ?', [station == null || station.trim().isEmpty ? null : station.trim(), pid]);
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

class VariantInfo {
  const VariantInfo(this.id, this.name, this.priceMinor);
  final String id;
  final String name;
  final int priceMinor;
}

class ModOptionInfo {
  const ModOptionInfo(this.id, this.name, this.priceMinor);
  final String id;
  final String name;
  final int priceMinor;
}

class ModGroupInfo {
  const ModGroupInfo({required this.id, required this.name, required this.minSelect, required this.maxSelect, required this.options});
  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<ModOptionInfo> options;
  bool get required => minSelect > 0;
}

class ProductOptions {
  const ProductOptions({this.variants = const [], this.groups = const []});
  final List<VariantInfo> variants;
  final List<ModGroupInfo> groups;
  bool get isEmpty => variants.isEmpty && groups.isEmpty;
}

/// Sizes/variants (half/full, small/large...) and add-on groups (extra cheese, sauces) of a product.
extension MenuOptions on MenuService {
  Future<ProductOptions> optionsFor(String productId) async {
    final variants = [
      for (final r in await _q('SELECT id, name, price_minor FROM product_variant WHERE product_id = ? AND deleted_at IS NULL ORDER BY price_minor, name', [productId])) VariantInfo(r['id'] as String, r['name'] as String, r['price_minor'] as int)
    ];
    final groups = <ModGroupInfo>[];
    for (final g in await _q('SELECT g.id, g.name, g.min_select, g.max_select FROM modifier_group g JOIN product_modifier_group l ON l.group_id = g.id WHERE l.product_id = ? AND g.deleted_at IS NULL ORDER BY g.name', [productId])) {
      groups.add(await _group(g));
    }
    return ProductOptions(variants: variants, groups: groups);
  }

  Future<ModGroupInfo> _group(Map<String, Object?> g) async => ModGroupInfo(
        id: g['id'] as String,
        name: g['name'] as String,
        minSelect: g['min_select'] as int,
        maxSelect: g['max_select'] as int,
        options: [
          for (final o in await _q('SELECT id, name, price_minor FROM modifier_option WHERE group_id = ? AND deleted_at IS NULL ORDER BY sort, name', [g['id']])) ModOptionInfo(o['id'] as String, o['name'] as String, o['price_minor'] as int)
        ],
      );

  Future<List<ModGroupInfo>> allGroups() async => [for (final g in await _q('SELECT id, name, min_select, max_select FROM modifier_group WHERE deleted_at IS NULL ORDER BY name')) await _group(g)];

  /// Replaces the variants of a product. Old ones are soft-deleted (past bills keep pointing at them).
  Future<void> saveVariants(String productId, List<({String name, int priceMinor})> variants) => db.transaction(() async {
        final names = <String>{};
        for (final v in variants) {
          if (v.name.trim().isEmpty) throw MenuException('Variant name is required');
          if (v.priceMinor < 0) throw MenuException('Price cannot be negative');
          if (!names.add(v.name.trim().toLowerCase())) throw MenuException('Two variants are called "${v.name.trim()}"');
        }
        final now = _now().millisecondsSinceEpoch;
        await db.customStatement('UPDATE product_variant SET deleted_at = ?, updated_at = ? WHERE product_id = ? AND deleted_at IS NULL', [now, now, productId]);
        for (final v in variants) {
          final old = await _q('SELECT id FROM product_variant WHERE product_id = ? AND lower(name) = lower(?) ORDER BY deleted_at IS NULL DESC LIMIT 1', [productId, v.name.trim()]);
          if (old.isNotEmpty) {
            await db.customStatement('UPDATE product_variant SET name = ?, price_minor = ?, deleted_at = NULL, updated_at = ?, version = version + 1 WHERE id = ?', [v.name.trim(), v.priceMinor, now, old.first['id']]);
          } else {
            await db.customStatement('INSERT INTO product_variant(id, product_id, name, price_minor, updated_at) VALUES (?,?,?,?,?)', [_newId(), productId, v.name.trim(), v.priceMinor, now]);
          }
        }
      });

  /// Creates or updates an add-on group with its options (name + price per option).
  Future<String> saveGroup({String? id, required String name, int minSelect = 0, int maxSelect = 1, required List<({String name, int priceMinor})> options}) => db.transaction(() async {
        if (name.trim().isEmpty) throw MenuException('Group name is required');
        if (minSelect < 0 || maxSelect < 1 || maxSelect < minSelect) throw MenuException('Check the minimum and maximum choices');
        if (options.isEmpty) throw MenuException('Add at least one option');
        if (maxSelect > options.length) maxSelect = options.length;
        if (minSelect > options.length) throw MenuException('Minimum choices is more than the options available');
        final now = _now().millisecondsSinceEpoch;
        final gid = id ?? _newId();
        if (id == null) {
          await db.customStatement('INSERT INTO modifier_group(id, name, min_select, max_select, updated_at) VALUES (?,?,?,?,?)', [gid, name.trim(), minSelect, maxSelect, now]);
        } else {
          await db.customStatement('UPDATE modifier_group SET name=?, min_select=?, max_select=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), minSelect, maxSelect, now, id]);
          await db.customStatement('UPDATE modifier_option SET deleted_at = ?, updated_at = ? WHERE group_id = ? AND deleted_at IS NULL', [now, now, id]);
        }
        var sort = 0;
        for (final o in options) {
          if (o.name.trim().isEmpty) throw MenuException('Option name is required');
          if (o.priceMinor < 0) throw MenuException('Price cannot be negative');
          final old = await _q('SELECT id FROM modifier_option WHERE group_id = ? AND lower(name) = lower(?) LIMIT 1', [gid, o.name.trim()]);
          if (old.isNotEmpty) {
            await db.customStatement('UPDATE modifier_option SET name=?, price_minor=?, sort=?, deleted_at=NULL, updated_at=?, version=version+1 WHERE id=?', [o.name.trim(), o.priceMinor, sort++, now, old.first['id']]);
          } else {
            await db.customStatement('INSERT INTO modifier_option(id, group_id, name, price_minor, sort, updated_at) VALUES (?,?,?,?,?,?)', [_newId(), gid, o.name.trim(), o.priceMinor, sort++, now]);
          }
        }
        return gid;
      });

  Future<void> setProductGroups(String productId, List<String> groupIds) => db.transaction(() async {
        await db.customStatement('DELETE FROM product_modifier_group WHERE product_id = ?', [productId]);
        for (final g in groupIds.toSet()) {
          await db.customStatement('INSERT INTO product_modifier_group(product_id, group_id) VALUES (?,?)', [productId, g]);
        }
      });
}
