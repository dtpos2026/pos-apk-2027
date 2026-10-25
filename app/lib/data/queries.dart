import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/money.dart';
import 'db/database.dart';

class Business {
  const Business({required this.name, required this.currency, required this.language, this.ownerName, this.address, this.phone, this.taxLabel, this.taxNumber, this.logoPath});
  final String name;
  final String? ownerName;
  final Currency currency;
  final String language;
  final String? address;
  final String? phone;
  final String? taxLabel;
  final String? taxNumber;
  final String? logoPath;
}

class MenuCategory {
  const MenuCategory(this.id, this.name, {this.imagePath, this.station});
  final String id;
  final String name;
  final String? imagePath;

  /// Counter/station the items of this category go to (kitchen ticket, tokens).
  final String? station;
}

class MenuProduct {
  const MenuProduct({required this.id, required this.name, required this.priceMinor, this.categoryId, this.categoryName, this.taxBp = 0, this.taxInclusive = false, this.station, this.ownStation, this.available = true, this.unit = 'pc', this.sku, this.imagePath, this.categoryImagePath, this.description, this.askPrice = false, this.hasVariants = false});
  final String id;
  final String name;
  final int priceMinor;
  final String? categoryId;
  final String? categoryName;
  final int taxBp;
  final bool taxInclusive;
  final String? station;

  /// The counter set on the item itself (null = it follows its category). [station] is the one that applies.
  final String? ownStation;
  final bool available;
  final String unit;
  final String? sku;

  /// Local file of the item picture (null = none); categoryImagePath is used when the item has no picture.
  final String? imagePath;
  final String? categoryImagePath;

  /// A line about the dish, shown on the shared menu picture.
  final String? description;

  /// The cashier types the price when selling it (open price).
  final bool askPrice;

  /// Sold in sizes: the price shown is the lowest one ("from").
  final bool hasVariants;
}

class PaymentMethodInfo {
  const PaymentMethodInfo(this.id, this.name, this.kind);
  final String id;
  final String name;
  final String kind;
}

class StaffEntry {
  const StaffEntry(this.id, this.name, this.roleName, [this.imagePath]);
  final String? imagePath;
  final String id;
  final String name;
  final String roleName;
}

class Session {
  const Session({required this.staffId, required this.name, required this.roleName, required this.permissions});
  final String staffId;
  final String name;
  final String roleName;
  final Set<String> permissions;
  bool can(String p) => permissions.contains('*') || permissions.contains(p);

  /// May this person open [screen]? A role with its own screen list (set per staff member) opens exactly those screens; every other
  /// role keeps the permission each screen always needed ([legacy]).
  bool canOpen(String screen, String legacy) {
    if (permissions.contains('*')) return true;
    if (permissions.any((p) => p.startsWith('screen.'))) return permissions.contains('screen.$screen');
    return permissions.contains(legacy);
  }
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String sql, [List<Object?> args = const []]) async =>
    (await db.customSelect(sql, variables: args.map((a) => a is int ? Variable.withInt(a) : Variable.withString(a as String)).toList()).get()).map((r) => r.data).toList();

Future<Business?> loadBusiness(AppDatabase db) async {
  final r = (await _rows(db, "SELECT * FROM business_profile WHERE id = 'self'")).firstOrNull;
  if (r == null) return null;
  return Business(
    name: r['name'] as String,
    ownerName: r['owner_name'] as String?,
    currency: Currency(r['currency'] as String, minorDigits: r['currency_minor_digits'] as int),
    language: r['language'] as String,
    address: r['address'] as String?,
    phone: r['phone'] as String?,
    taxLabel: r['tax_number_label'] as String?,
    taxNumber: r['tax_number'] as String?,
    logoPath: r['logo_path'] as String?,
  );
}

Future<List<StaffEntry>> loadStaff(AppDatabase db) async => [
      for (final r in await _rows(db, 'SELECT s.id, s.name, s.image_path, r.name AS role FROM staff s JOIN role r ON r.id = s.role_id WHERE s.active = 1 AND s.deleted_at IS NULL ORDER BY s.name'))
        StaffEntry(r['id'] as String, r['name'] as String, r['role'] as String, r['image_path'] as String?)
    ];

Future<Session?> loadSession(AppDatabase db, String staffId) async {
  final r = (await _rows(db, 'SELECT s.id, s.name, r.name AS role, r.permissions AS perms FROM staff s JOIN role r ON r.id = s.role_id WHERE s.id = ?', [staffId])).firstOrNull;
  if (r == null) return null;
  return Session(staffId: staffId, name: r['name'] as String, roleName: r['role'] as String, permissions: (jsonDecode(r['perms'] as String) as List).cast<String>().toSet());
}

Future<List<MenuCategory>> loadCategories(AppDatabase db) async =>
    [for (final r in await _rows(db, 'SELECT id, name, image_path, station FROM category WHERE deleted_at IS NULL ORDER BY sort, name')) MenuCategory(r['id'] as String, r['name'] as String, imagePath: r['image_path'] as String?, station: r['station'] as String?)];

/// The shop's tax choice (Settings > Tax & service charge). Off unless the owner switches it on: then NO bill carries any tax.
/// On: one rate for every item, either added on top or already inside the prices.
class TaxPolicy {
  const TaxPolicy({this.enabled = false, this.rateBp = 0, this.inclusive = false});
  final bool enabled;
  final int rateBp;
  final bool inclusive;
  static const keyOn = 'tax.enabled', keyRate = 'tax.rate_bp', keyInclusive = 'tax.inclusive';
}

Future<TaxPolicy> loadTaxPolicy(AppDatabase db) async => TaxPolicy(
      enabled: (await getSetting(db, TaxPolicy.keyOn)) == '1',
      rateBp: int.tryParse(await getSetting(db, TaxPolicy.keyRate) ?? '') ?? 0,
      inclusive: (await getSetting(db, TaxPolicy.keyInclusive)) == '1',
    );

Future<List<MenuProduct>> loadProducts(AppDatabase db, {String? categoryId, String search = '', bool includeUnavailable = true}) async {
  final where = <String>['p.deleted_at IS NULL'];
  final args = <Object?>[];
  if (categoryId != null) {
    where.add('p.category_id = ?');
    args.add(categoryId);
  }
  if (search.trim().isNotEmpty) {
    where.add('(p.name LIKE ? OR p.sku LIKE ? OR p.barcode = ?)');
    args..add('%${search.trim()}%')..add('%${search.trim()}%')..add(search.trim());
  }
  if (!includeUnavailable) where.add('p.available = 1');
  final tax = await loadTaxPolicy(db);
  final rows = await _rows(
      db,
      'SELECT p.*, c.name AS category_name, COALESCE(p.station, c.station) AS station, p.station AS own_station, EXISTS(SELECT 1 FROM product_variant v WHERE v.product_id = p.id AND v.deleted_at IS NULL) AS has_variants, c.image_path AS category_image, t.rate_bp AS tax_bp, t.inclusive AS tax_inclusive '
      'FROM product p LEFT JOIN category c ON c.id = p.category_id LEFT JOIN tax_rate t ON t.id = p.tax_rate_id '
      'WHERE ${where.join(' AND ')} ORDER BY p.name',
      args);
  return [
    for (final r in rows)
      MenuProduct(
        id: r['id'] as String,
        name: r['name'] as String,
        priceMinor: r['base_price_minor'] as int,
        categoryId: r['category_id'] as String?,
        categoryName: r['category_name'] as String?,
        taxBp: tax.enabled ? tax.rateBp : 0,
        taxInclusive: tax.enabled && tax.inclusive,
        station: r['station'] as String?,
        ownStation: r['own_station'] as String?,
        available: (r['available'] as int) == 1,
        unit: r['unit'] as String,
        sku: r['sku'] as String?,
        imagePath: r['image_path'] as String?,
        categoryImagePath: r['category_image'] as String?,
        description: r['description'] as String?,
        askPrice: ((r['ask_price'] as int?) ?? 0) == 1,
        hasVariants: ((r['has_variants'] as int?) ?? 0) == 1,
      )
  ];
}

Future<List<PaymentMethodInfo>> loadPaymentMethods(AppDatabase db) async =>
    [for (final r in await _rows(db, 'SELECT id, name, kind FROM payment_method WHERE enabled = 1 AND deleted_at IS NULL ORDER BY sort, name')) PaymentMethodInfo(r['id'] as String, r['name'] as String, r['kind'] as String)];

Future<String?> openShiftId(AppDatabase db, String staffId) async =>
    (await _rows(db, 'SELECT id FROM shift WHERE staff_id = ? AND closed_at IS NULL', [staffId])).firstOrNull?['id'] as String?;

Future<void> setSetting(AppDatabase db, String key, String value, int now) =>
    db.customStatement('INSERT INTO setting(setting_key, setting_value, updated_at) VALUES (?,?,?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at', [key, value, now]);

Future<String?> getSetting(AppDatabase db, String key) async =>
    (await _rows(db, 'SELECT setting_value FROM setting WHERE setting_key = ?', [key])).firstOrNull?['setting_value'] as String?;
