import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/csv.dart';
import '../domain/money.dart';
import 'db/database.dart';

const menuCsvHeader = ['category', 'name', 'price', 'sku', 'barcode', 'unit', 'tax_percent', 'available', 'track_stock'];

/// Downloadable template (header + two example rows).
String menuCsvTemplate() => [
      menuCsvHeader.join(','),
      'Burgers,Zinger Burger,450.00,BRG-001,,pc,16,yes,no',
      'Drinks,Cola 500ml,100,DRK-001,6281000000000,pc,16,yes,yes',
    ].join('\n');

class ImportIssue {
  const ImportIssue(this.row, this.field, this.message);

  /// 1-based CSV line number (header is line 1).
  final int row;
  final String field;
  final String message;
  @override
  String toString() => 'row $row, $field: $message';
}

class ImportReport {
  const ImportReport({required this.totalRows, required this.creates, required this.updates, required this.issues, required this.committed});
  final int totalRows;
  final int creates;
  final int updates;
  final List<ImportIssue> issues;
  final bool committed;
  bool get ok => issues.isEmpty;
}

class _Row {
  _Row(this.line, this.category, this.name, this.priceMinor, this.sku, this.barcode, this.unit, this.taxBp, this.available, this.trackStock);
  final int line;
  final String? category;
  final String name;
  final int priceMinor;
  final String? sku;
  final String? barcode;
  final String unit;
  final int? taxBp;
  final bool available;
  final bool trackStock;
}

/// Bulk menu import from CSV. [dryRun] validates and reports without touching the database.
/// A real run is all-or-nothing: if any row has an error, nothing is written.
/// Rows whose SKU already exists update that product; rows without a SKU always create.
class MenuImporter {
  MenuImporter(this.db, {DateTime Function()? now, String Function()? newId, this.currency = Currency.pkr})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final DateTime Function() _now;
  final String Function() _newId;
  final Currency currency;

  static const _units = {'pc', 'kg', 'g', 'l', 'ml'};

  /// The whole menu as CSV in the same columns the importer reads (without deals), so it can be edited in Excel and imported back.
  /// Items without a SKU are exported with an empty SKU; importing those again creates new items, so give them a SKU first.
  Future<String> exportCsv() async {
    final rows = await db.customSelect(
        "SELECT c.name AS cat, p.name, p.base_price_minor, p.sku, p.barcode, p.unit, p.available, p.track_stock, (SELECT t.rate_bp FROM tax_rate t WHERE t.id = p.tax_rate_id) AS tax "
        "FROM product p LEFT JOIN category c ON c.id = p.category_id WHERE p.deleted_at IS NULL AND p.kind <> 'combo' ORDER BY c.name, p.name").get();
    String money(int minor) => (minor / currency.factor).toStringAsFixed(currency.minorDigits);
    final out = <String>[menuCsvHeader.join(',')];
    for (final r in rows) {
      final d = r.data;
      final tax = d['tax'] as int?;
      out.add([
        d['cat'] as String? ?? '',
        d['name'] as String,
        money(d['base_price_minor'] as int),
        d['sku'] as String? ?? '',
        d['barcode'] as String? ?? '',
        d['unit'] as String? ?? 'pc',
        tax == null ? '' : (tax / 100).toStringAsFixed(2),
        (d['available'] as int) == 1 ? 'yes' : 'no',
        (d['track_stock'] as int) == 1 ? 'yes' : 'no',
      ].map(csvEscape).join(','));
    }
    return out.join('\n');
  }

  bool? _bool(String v, {required bool fallback}) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return fallback;
    if (const {'yes', 'y', 'true', '1'}.contains(s)) return true;
    if (const {'no', 'n', 'false', '0'}.contains(s)) return false;
    return null;
  }

  Future<ImportReport> import(String csv, {bool dryRun = true, String? staffId}) async {
    List<List<String>> table;
    try {
      table = parseCsv(csv);
    } on FormatException catch (e) {
      return ImportReport(totalRows: 0, creates: 0, updates: 0, issues: [ImportIssue(0, 'file', e.message)], committed: false);
    }
    if (table.isEmpty) return const ImportReport(totalRows: 0, creates: 0, updates: 0, issues: [ImportIssue(0, 'file', 'File is empty')], committed: false);

    final header = table.first.map((h) => h.trim().toLowerCase()).toList();
    final issues = <ImportIssue>[];
    for (final required in ['name', 'price']) {
      if (!header.contains(required)) issues.add(ImportIssue(1, required, 'Missing required column'));
    }
    if (issues.isNotEmpty) return ImportReport(totalRows: table.length - 1, creates: 0, updates: 0, issues: issues, committed: false);

    String cell(List<String> r, String col) {
      final i = header.indexOf(col);
      return i < 0 || i >= r.length ? '' : r[i].trim();
    }

    final existing = {
      for (final r in await db.customSelect('SELECT id, sku FROM product WHERE sku IS NOT NULL AND deleted_at IS NULL').get()) r.data['sku'] as String: r.data['id'] as String
    };
    final seenSkus = <String, int>{};
    final rows = <_Row>[];
    for (var i = 1; i < table.length; i++) {
      final line = i + 1;
      final r = table[i];
      final before = issues.length;
      final name = cell(r, 'name');
      if (name.isEmpty) issues.add(ImportIssue(line, 'name', 'Name is required'));
      final price = parseMinor(cell(r, 'price'), currency: currency);
      if (price == null) issues.add(ImportIssue(line, 'price', 'Invalid price "${cell(r, 'price')}"'));
      final unit = cell(r, 'unit').isEmpty ? 'pc' : cell(r, 'unit').toLowerCase();
      if (!_units.contains(unit)) issues.add(ImportIssue(line, 'unit', 'Unit must be one of ${_units.join(', ')}'));
      int? taxBp;
      if (cell(r, 'tax_percent').isNotEmpty) {
        final t = parseMinor(cell(r, 'tax_percent'));
        if (t == null || t > 10000) {
          issues.add(ImportIssue(line, 'tax_percent', 'Tax must be between 0 and 100'));
        } else {
          taxBp = t; // percent with 2 decimals == basis points
        }
      }
      final available = _bool(cell(r, 'available'), fallback: true);
      if (available == null) issues.add(ImportIssue(line, 'available', 'Use yes or no'));
      final track = _bool(cell(r, 'track_stock'), fallback: false);
      if (track == null) issues.add(ImportIssue(line, 'track_stock', 'Use yes or no'));
      final sku = cell(r, 'sku').isEmpty ? null : cell(r, 'sku');
      if (sku != null) {
        final dup = seenSkus[sku];
        if (dup != null) {
          issues.add(ImportIssue(line, 'sku', 'Duplicate SKU "$sku" (also on row $dup)'));
        } else {
          seenSkus[sku] = line;
        }
      }
      if (issues.length == before) {
        rows.add(_Row(line, cell(r, 'category').isEmpty ? null : cell(r, 'category'), name, price!, sku, cell(r, 'barcode').isEmpty ? null : cell(r, 'barcode'), unit, taxBp, available!, track!));
      }
    }

    final updates = rows.where((r) => r.sku != null && existing.containsKey(r.sku)).length;
    final creates = rows.length - updates;
    if (issues.isNotEmpty || dryRun) {
      return ImportReport(totalRows: table.length - 1, creates: creates, updates: updates, issues: issues, committed: false);
    }

    await db.transaction(() async {
      final now = _now().millisecondsSinceEpoch;
      final categories = {
        for (final r in await db.customSelect('SELECT id, name FROM category WHERE deleted_at IS NULL').get()) (r.data['name'] as String).toLowerCase(): r.data['id'] as String
      };
      for (final row in rows) {
        String? categoryId;
        if (row.category != null) {
          categoryId = categories[row.category!.toLowerCase()];
          if (categoryId == null) {
            categoryId = _newId();
            categories[row.category!.toLowerCase()] = categoryId;
            await db.customStatement('INSERT INTO category(id, name, updated_at) VALUES (?,?,?)', [categoryId, row.category, now]);
          }
        }
        // tax: reuse or create a tax_rate row for this percentage
        String? taxId;
        if (row.taxBp != null) {
          final t = await db.customSelect('SELECT id FROM tax_rate WHERE rate_bp = ? AND deleted_at IS NULL LIMIT 1', variables: [Variable.withInt(row.taxBp!)]).get();
          if (t.isNotEmpty) {
            taxId = t.first.data['id'] as String;
          } else {
            taxId = _newId();
            await db.customStatement('INSERT INTO tax_rate(id, name, rate_bp, updated_at) VALUES (?,?,?,?)', [taxId, 'Tax ${formatMinor(row.taxBp!, symbol: false)}%', row.taxBp, now]);
          }
        }
        final existingId = row.sku == null ? null : existing[row.sku];
        final id = existingId ?? _newId();
        if (existingId == null) {
          await db.customStatement(
              'INSERT INTO product(id, category_id, name, sku, barcode, base_price_minor, tax_rate_id, unit, available, track_stock, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
              [id, categoryId, row.name, row.sku, row.barcode, row.priceMinor, taxId, row.unit, row.available ? 1 : 0, row.trackStock ? 1 : 0, now]);
        } else {
          await db.customStatement(
              'UPDATE product SET category_id=?, name=?, barcode=?, base_price_minor=?, tax_rate_id=?, unit=?, available=?, track_stock=?, updated_at=?, version=version+1 WHERE id=?',
              [categoryId, row.name, row.barcode, row.priceMinor, taxId, row.unit, row.available ? 1 : 0, row.trackStock ? 1 : 0, now, id]);
        }
        final version = (await db.customSelect('SELECT version FROM product WHERE id = ?', variables: [Variable.withString(id)]).getSingle()).data['version'] as int;
        await db.customStatement(
            'INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, entity_version, created_at) VALUES (?,?,?,?,?,?,?)',
            ['product:$id:v$version', 'product', id, 'upsert', jsonEncode({'id': id, 'name': row.name, 'sku': row.sku, 'base_price_minor': row.priceMinor}), version, now]);
      }
      await db.customStatement('INSERT INTO audit_log(id, at, staff_id, event, entity, after_json, device_id, critical) VALUES (?,?,?,?,?,?,?,0)',
          [_newId(), now, staffId, 'menu.import', 'product', jsonEncode({'creates': creates, 'updates': updates}), 'device']);
    });
    return ImportReport(totalRows: table.length - 1, creates: creates, updates: updates, issues: const [], committed: true);
  }
}
