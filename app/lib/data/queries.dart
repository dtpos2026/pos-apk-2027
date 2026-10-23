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
  const MenuCategory(this.id, this.name);
  final String id;
  final String name;
}

class MenuProduct {
  const MenuProduct({required this.id, required this.name, required this.priceMinor, this.categoryId, this.categoryName, this.taxBp = 0, this.taxInclusive = false, this.station, this.available = true, this.unit = 'pc', this.sku});
  final String id;
  final String name;
  final int priceMinor;
  final String? categoryId;
  final String? categoryName;
  final int taxBp;
  final bool taxInclusive;
  final String? station;
  final bool available;
  final String unit;
  final String? sku;
}

class PaymentMethodInfo {
  const PaymentMethodInfo(this.id, this.name, this.kind);
  final String id;
  final String name;
  final String kind;
}

class StaffEntry {
  const StaffEntry(this.id, this.name, this.roleName);
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
      for (final r in await _rows(db, 'SELECT s.id, s.name, r.name AS role FROM staff s JOIN role r ON r.id = s.role_id WHERE s.active = 1 AND s.deleted_at IS NULL ORDER BY s.name'))
        StaffEntry(r['id'] as String, r['name'] as String, r['role'] as String)
    ];

Future<Session?> loadSession(AppDatabase db, String staffId) async {
  final r = (await _rows(db, 'SELECT s.id, s.name, r.name AS role, r.permissions AS perms FROM staff s JOIN role r ON r.id = s.role_id WHERE s.id = ?', [staffId])).firstOrNull;
  if (r == null) return null;
  return Session(staffId: staffId, name: r['name'] as String, roleName: r['role'] as String, permissions: (jsonDecode(r['perms'] as String) as List).cast<String>().toSet());
}

Future<List<MenuCategory>> loadCategories(AppDatabase db) async =>
    [for (final r in await _rows(db, 'SELECT id, name FROM category WHERE deleted_at IS NULL ORDER BY sort, name')) MenuCategory(r['id'] as String, r['name'] as String)];

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
  final rows = await _rows(
      db,
      'SELECT p.*, c.name AS category_name, c.station AS station, t.rate_bp AS tax_bp, t.inclusive AS tax_inclusive '
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
        taxBp: (r['tax_bp'] as int?) ?? 0,
        taxInclusive: ((r['tax_inclusive'] as int?) ?? 0) == 1,
        station: r['station'] as String?,
        available: (r['available'] as int) == 1,
        unit: r['unit'] as String,
        sku: r['sku'] as String?,
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
