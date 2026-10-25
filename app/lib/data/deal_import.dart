import '../domain/csv.dart';
import '../domain/money.dart';
import 'db/database.dart';
import 'deal_service.dart';
import 'package:drift/drift.dart' show Variable;

/// Header names accepted for each column (compared in lower case, letters and digits only).
const _aliases = <String, List<String>>{
  'deal': ['dealname', 'deal', 'combo', 'comboname', 'dealtitle'],
  'price': ['dealprice', 'price', 'comboprice', 'dealrate'],
  'item': ['itemname', 'item', 'menuitem', 'product', 'productname'],
  'qty': ['quantity', 'qty'],
  'variant': ['variant', 'size', 'variantname', 'inch', 'sizeinch'],
  'category': ['category', 'itemcategory', 'categoryname'],
  'code': ['itemcode', 'itemid', 'sku', 'code'],
  'active': ['active', 'status', 'isactive'],
  'dealcode': ['dealcode', 'dealid'],
};

/// Downloadable template: two deals, five rows.
String dealCsvTemplate() => [
      'Deal Name,Deal Price,Item Name,Quantity,Variant,Category,Active',
      'Family Deal 1,2499,Zinger Burger,2,,Burgers,Yes',
      'Family Deal 1,2499,Chicken Pizza,1,Large,Pizza,Yes',
      'Family Deal 1,2499,1.5 Liter Drink,1,,Drinks,Yes',
      'Student Deal,799,Zinger Burger,1,,Burgers,Yes',
      'Student Deal,799,Cola 500ml,1,,Drinks,Yes',
    ].join('\n');

class DealIssue {
  const DealIssue(this.message, {this.row});

  /// 1-based line in the file (the header is line 1).
  final int? row;
  final String message;
  @override
  String toString() => row == null ? message : 'row $row: $message';
}

enum DealStatus { create, update, duplicate, invalid }

class ParsedDeal {
  ParsedDeal(this.name);
  final String name;
  int priceMinor = 0;
  bool active = true;
  String? existingId;
  final items = <DealPick>[];
  final issues = <DealIssue>[];
  DealStatus status = DealStatus.create;
}

class DealImportReport {
  const DealImportReport({required this.deals, required this.fileIssues, required this.committed});
  final List<ParsedDeal> deals;

  /// Problems with the file as a whole (missing columns, empty file).
  final List<DealIssue> fileIssues;
  final bool committed;
  int get created => deals.where((d) => d.status == DealStatus.create).length;
  int get updated => deals.where((d) => d.status == DealStatus.update).length;
  int get skipped => deals.where((d) => d.status == DealStatus.duplicate).length;
  int get invalid => deals.where((d) => d.status == DealStatus.invalid).length;
  List<DealIssue> get allIssues => [...fileIssues, for (final d in deals) for (final i in d.issues) DealIssue('${d.name}: ${i.message}', row: i.row)];
}

/// Bulk deals from a CSV / Excel sheet. One row per item; rows are grouped into deals by Deal Name (a blank name continues the
/// deal above). Every item must already be on the menu; an item with sizes must say which one. A deal with any problem is not
/// imported at all (no half deals); the other deals still are. An existing deal is only changed when [update] is chosen.
class DealImporter {
  DealImporter(this.db, this.deals, {this.currency = Currency.pkr});
  final AppDatabase db;
  final DealService deals;
  final Currency currency;

  Future<List<Map<String, Object?>>> _q(String sql, [List<Object?> a = const []]) async =>
      (await db.customSelect(sql, variables: a.map((x) => x is int ? Variable.withInt(x) : Variable.withString(x as String)).toList()).get()).map((r) => r.data).toList();

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]'), '');
  static String _nameKey(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<DealImportReport> import(String csv, {bool dryRun = false, bool update = false, required String staffId}) async {
    final rows = parseCsv(csv);
    if (rows.isEmpty) return const DealImportReport(deals: [], fileIssues: [DealIssue('The file is empty')], committed: false);
    final header = [for (final h in rows.first) _norm(h)];
    final col = <String, int>{};
    for (final e in _aliases.entries) {
      final i = header.indexWhere((h) => e.value.contains(h));
      if (i >= 0) col[e.key] = i;
    }
    final missing = [
      if (!col.containsKey('deal')) 'Deal Name',
      if (!col.containsKey('price')) 'Deal Price',
      if (!col.containsKey('item')) 'Item Name',
      if (!col.containsKey('qty')) 'Quantity',
    ];
    if (missing.isNotEmpty) return DealImportReport(deals: const [], fileIssues: [DealIssue('Missing column: ${missing.join(', ')}')], committed: false);

    String cell(List<String> r, String k) => col[k] == null || col[k]! >= r.length ? '' : r[col[k]!].trim();

    final products = await _q("SELECT p.id, p.name, p.sku, p.kind, c.name AS cat FROM product p LEFT JOIN category c ON c.id = p.category_id WHERE p.deleted_at IS NULL");
    final variants = await _q('SELECT id, product_id, name FROM product_variant WHERE deleted_at IS NULL');
    final existing = await _q("SELECT id, name FROM product WHERE kind = 'combo' AND deleted_at IS NULL");

    final parsed = <String, ParsedDeal>{};
    String? current;
    final prices = <String, Set<int>>{};
    for (var n = 1; n < rows.length; n++) {
      final r = rows[n];
      final line = n + 1;
      if (r.every((c) => c.trim().isEmpty)) continue;
      var dealName = cell(r, 'deal');
      final dealCode = cell(r, 'dealcode');
      if (dealName.isEmpty && dealCode.isEmpty) {
        if (current == null) continue;
        dealName = current;
      }
      final key = dealCode.isNotEmpty ? 'code:${_nameKey(dealCode)}' : 'name:${_nameKey(dealName)}';
      current = dealName.isEmpty ? current : dealName;
      final d = parsed.putIfAbsent(key, () => ParsedDeal(dealName.isEmpty ? dealCode : dealName));

      final priceText = cell(r, 'price').replaceAll(RegExp(r'rs\.?|pkr|,', caseSensitive: false), '').trim();
      if (priceText.isNotEmpty) {
        final p = parseMinor(priceText, currency: currency);
        if (p == null || p <= 0) {
          d.issues.add(DealIssue('"${cell(r, 'price')}" is not a valid price', row: line));
        } else {
          prices.putIfAbsent(key, () => {}).add(p);
          d.priceMinor = p;
        }
      }
      final act = cell(r, 'active').toLowerCase();
      if (act.isNotEmpty) d.active = !const ['no', 'n', 'false', '0', 'inactive'].contains(act);

      final itemName = cell(r, 'item');
      final code = cell(r, 'code');
      if (itemName.isEmpty && code.isEmpty) {
        d.issues.add(DealIssue('item name is empty', row: line));
        continue;
      }
      final qty = int.tryParse(cell(r, 'qty'));
      if (qty == null || qty < 1 || qty > 999) {
        d.issues.add(DealIssue('quantity must be a whole number from 1 to 999', row: line));
        continue;
      }
      var found = code.isNotEmpty
          ? products.where((p) => (p['sku'] as String?)?.toLowerCase() == code.toLowerCase()).toList()
          : products.where((p) => _nameKey(p['name'] as String) == _nameKey(itemName)).toList();
      final cat = cell(r, 'category');
      if (found.length > 1 && cat.isNotEmpty) found = found.where((p) => _nameKey((p['cat'] as String?) ?? '') == _nameKey(cat)).toList();
      if (found.isEmpty) {
        d.issues.add(DealIssue('"${code.isNotEmpty ? code : itemName}" is not on the menu', row: line));
        continue;
      }
      if (found.length > 1) {
        d.issues.add(DealIssue('"$itemName" matches more than one menu item: add its Category', row: line));
        continue;
      }
      final p = found.single;
      if (p['kind'] == 'combo') {
        d.issues.add(DealIssue('"${p['name']}" is a deal; a deal cannot contain a deal', row: line));
        continue;
      }
      final own = variants.where((v) => v['product_id'] == p['id']).toList();
      final vName = cell(r, 'variant');
      String? variantId;
      if (own.isNotEmpty) {
        if (vName.isEmpty) {
          d.issues.add(DealIssue('"${p['name']}" has sizes (${own.map((v) => v['name']).join(', ')}): fill in the Variant', row: line));
          continue;
        }
        final v = own.where((x) => _nameKey(x['name'] as String) == _nameKey(vName)).toList();
        if (v.isEmpty) {
          d.issues.add(DealIssue('"${p['name']}" has no size "$vName" (it has ${own.map((v) => v['name']).join(', ')})', row: line));
          continue;
        }
        variantId = v.first['id'] as String;
      } else if (vName.isNotEmpty) {
        d.issues.add(DealIssue('"${p['name']}" has no sizes, but the Variant says "$vName"', row: line));
        continue;
      }
      final same = d.items.indexWhere((x) => x.productId == p['id'] && x.variantId == variantId);
      if (same >= 0) {
        d.items[same] = DealPick(productId: d.items[same].productId, variantId: variantId, qtyMilli: d.items[same].qtyMilli + qty * 1000);
      } else {
        d.items.add(DealPick(productId: p['id'] as String, variantId: variantId, qtyMilli: qty * 1000));
      }
    }

    for (final e in parsed.entries) {
      final d = e.value;
      if ((prices[e.key] ?? {}).length > 1) d.issues.add(const DealIssue('the Deal Price differs between rows of the same deal'));
      if (d.priceMinor <= 0 && (prices[e.key] ?? {}).isEmpty && !d.issues.any((i) => i.message.contains('valid price'))) d.issues.add(const DealIssue('the deal has no price'));
      if (d.items.isEmpty && d.issues.isEmpty) d.issues.add(const DealIssue('the deal has no items'));
      final dup = existing.where((x) => _nameKey(x['name'] as String) == _nameKey(d.name)).toList();
      if (dup.isNotEmpty) d.existingId = dup.first['id'] as String;
      d.status = d.issues.isNotEmpty
          ? DealStatus.invalid
          : d.existingId == null
              ? DealStatus.create
              : (update ? DealStatus.update : DealStatus.duplicate);
    }

    final list = parsed.values.toList();
    if (dryRun) return DealImportReport(deals: list, fileIssues: const [], committed: false);
    await db.transaction(() async {
      for (final d in list) {
        if (d.status == DealStatus.create || d.status == DealStatus.update) {
          await deals.save(id: d.status == DealStatus.update ? d.existingId : null, name: d.name, priceMinor: d.priceMinor, active: d.active, items: d.items, staffId: staffId);
        }
      }
    });
    return DealImportReport(deals: list, fileIssues: const [], committed: true);
  }
}

