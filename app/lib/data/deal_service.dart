import 'package:drift/drift.dart' show Variable;
import 'package:uuid/uuid.dart';

import 'db/database.dart';
import 'menu_service.dart';

/// What a deal asks for: this item (in this size, if it has sizes) this many times.
class DealPick {
  const DealPick({required this.productId, this.variantId, this.qtyMilli = 1000});
  final String productId;
  final String? variantId;
  final int qtyMilli;
}

/// One item of a saved deal, with the names and prices as they are on the menu now.
class DealComponent {
  const DealComponent({required this.productId, required this.productName, this.variantId, this.variantName, required this.qtyMilli, required this.unitPriceMinor});
  final String productId;
  final String productName;
  final String? variantId;
  final String? variantName;
  final int qtyMilli;
  final int unitPriceMinor;

  String get label => variantName == null ? productName : '$productName ($variantName)';
  int get totalMinor => unitPriceMinor * qtyMilli ~/ 1000;
}

class DealInfo {
  const DealInfo({required this.id, required this.name, required this.priceMinor, required this.active, required this.items});
  final String id;
  final String name;
  final int priceMinor;
  final bool active;
  final List<DealComponent> items;

  /// What the same items cost when bought one by one.
  int get regularMinor => items.fold(0, (s, i) => s + i.totalMinor);
  int get savingMinor => regularMinor - priceMinor;
}

/// A menu item that can go inside a deal, with its sizes (if any).
class DealItemOption {
  const DealItemOption({required this.id, required this.name, required this.priceMinor, this.categoryName, this.sizes = const []});
  final String id;
  final String name;
  final int priceMinor;
  final String? categoryName;
  final List<({String id, String name, int priceMinor})> sizes;
}

/// Deals / combos: one price for a set of menu items (like "Family Deal: 2 burgers + 1 large pizza + a drink").
/// A deal is a menu item of kind 'combo' in the "Deals" category, so selling it, printing it, reports and taxes all work the
/// normal way; this service keeps what is inside it, so the kitchen ticket can list it and stock is taken from the real items.
class DealService {
  DealService(this.db, this.menu, {String Function()? newId}) : _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final MenuService menu;
  final String Function() _newId;

  static const categoryName = 'Deals';

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> a = const []]) async =>
      (await db.customSelect(sql, variables: a.map((x) => x is int ? Variable.withInt(x) : Variable.withString(x as String)).toList()).get()).map((r) => r.data).toList();

  Future<List<DealInfo>> deals({bool activeOnly = false}) async {
    final rows = await _q("SELECT id, name, base_price_minor, available FROM product WHERE kind = 'combo' AND deleted_at IS NULL ${activeOnly ? 'AND available = 1' : ''} ORDER BY name");
    return [for (final r in rows) await _load(r)];
  }

  Future<DealInfo?> get(String id) async {
    final rows = await _q("SELECT id, name, base_price_minor, available FROM product WHERE id = ? AND kind = 'combo' AND deleted_at IS NULL", [id]);
    return rows.isEmpty ? null : _load(rows.first);
  }

  Future<DealInfo> _load(Map<String, Object?> r) async {
    final items = await _q(
        'SELECT d.product_id, p.name AS pname, d.variant_id, v.name AS vname, d.qty_milli, COALESCE(v.price_minor, p.base_price_minor) AS price '
        'FROM deal_item d JOIN product p ON p.id = d.product_id LEFT JOIN product_variant v ON v.id = d.variant_id WHERE d.deal_id = ? ORDER BY d.rowid',
        [r['id']]);
    return DealInfo(
      id: r['id'] as String,
      name: r['name'] as String,
      priceMinor: r['base_price_minor'] as int,
      active: (r['available'] as int) == 1,
      items: [
        for (final i in items)
          DealComponent(productId: i['product_id'] as String, productName: i['pname'] as String, variantId: i['variant_id'] as String?, variantName: i['vname'] as String?, qtyMilli: i['qty_milli'] as int, unitPriceMinor: i['price'] as int),
      ],
    );
  }

  /// Menu items that can be put in a deal (everything except deals), filtered by [search].
  Future<List<DealItemOption>> options(String search) async {
    final like = '%${search.trim()}%';
    final rows = await _q(
        "SELECT p.id, p.name, p.base_price_minor, c.name AS cat FROM product p LEFT JOIN category c ON c.id = p.category_id WHERE p.deleted_at IS NULL AND p.kind <> 'combo' AND p.name LIKE ? ORDER BY c.name, p.name",
        [like]);
    final out = <DealItemOption>[];
    for (final r in rows) {
      final v = await _q('SELECT id, name, price_minor FROM product_variant WHERE product_id = ? AND deleted_at IS NULL ORDER BY price_minor', [r['id']]);
      out.add(DealItemOption(id: r['id'] as String, name: r['name'] as String, priceMinor: r['base_price_minor'] as int, categoryName: r['cat'] as String?, sizes: [for (final x in v) (id: x['id'] as String, name: x['name'] as String, priceMinor: x['price_minor'] as int)]));
    }
    return out;
  }

  /// Checks a deal and returns a plain-words problem, or null when it is fine. Used by the editor and by the bulk import.
  Future<String?> check({required String name, required int priceMinor, required List<DealPick> items}) async {
    if (name.trim().isEmpty) return 'The deal needs a name';
    if (priceMinor <= 0) return 'The deal price must be more than zero';
    if (items.isEmpty) return 'Add at least one item to the deal';
    for (final it in items) {
      if (it.qtyMilli <= 0) return 'Quantities must be more than zero';
      final p = await _q('SELECT name, kind FROM product WHERE id = ? AND deleted_at IS NULL', [it.productId]);
      if (p.isEmpty) return 'An item of this deal is no longer on the menu';
      if (p.first['kind'] == 'combo') return '"${p.first['name']}" is a deal itself; a deal cannot contain another deal';
      final variants = await _q('SELECT id FROM product_variant WHERE product_id = ? AND deleted_at IS NULL', [it.productId]);
      if (variants.isNotEmpty && it.variantId == null) return '"${p.first['name']}" has sizes: choose which one the deal contains';
      if (it.variantId != null && !variants.any((v) => v['id'] == it.variantId)) return 'That size does not belong to "${p.first['name']}"';
    }
    return null;
  }

  /// Creates or updates a deal. Throws [MenuException] with a plain message when something is wrong.
  Future<String> save({String? id, required String name, required int priceMinor, bool active = true, required List<DealPick> items, required String staffId}) async {
    final problem = await check(name: name, priceMinor: priceMinor, items: items);
    if (problem != null) throw MenuException(problem);
    if (id != null && await get(id) == null) throw MenuException('Deal not found');
    final dup = await _q("SELECT id FROM product WHERE kind = 'combo' AND deleted_at IS NULL AND lower(name) = lower(?) AND id <> ?", [name.trim(), id ?? '']);
    if (dup.isNotEmpty) throw MenuException('A deal named "${name.trim()}" already exists');
    return db.transaction(() async {
      final pid = await menu.saveProduct(id: id, name: name, priceMinor: priceMinor, categoryName: categoryName, available: active, staffId: staffId);
      await db.customStatement("UPDATE product SET kind = 'combo' WHERE id = ?", [pid]);
      await db.customStatement('DELETE FROM deal_item WHERE deal_id = ?', [pid]);
      for (final it in items) {
        await db.customStatement('INSERT INTO deal_item(id, deal_id, product_id, variant_id, qty_milli) VALUES (?,?,?,?,?)', [_newId(), pid, it.productId, it.variantId, it.qtyMilli]);
      }
      return pid;
    });
  }

  Future<void> delete(String id, {required String staffId}) => menu.deleteProduct(id, staffId: staffId);
}
