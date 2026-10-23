import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../domain/logo.dart';
import '../domain/receipt_template.dart';
import 'db/database.dart';

/// Loads and saves the bill design (receipt_template table, id 'bill').
class ReceiptTemplateStore {
  ReceiptTemplateStore(this.db, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() _now;

  Future<BillDesign> load() async {
    final r = await db.customSelect("SELECT config FROM receipt_template WHERE id = 'bill'").get();
    return BillDesign.decode(r.isEmpty ? null : r.first.data['config'] as String);
  }

  Future<void> save(BillDesign t) => db.customStatement(
      "INSERT INTO receipt_template(id, kind, config, updated_at) VALUES ('bill','bill',?,?) ON CONFLICT(id) DO UPDATE SET config = excluded.config, version = version + 1, updated_at = excluded.updated_at",
      [t.encode(), _now().millisecondsSinceEpoch]);
}

/// Keeps the business logo: a normalised PNG file in [dir] and its path in business_profile.logo_path.
class LogoStore {
  LogoStore(this.db, this.dir, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final AppDatabase db;
  final Directory dir;
  final DateTime Function() _now;

  Future<String?> path() async {
    final r = await db.customSelect("SELECT logo_path FROM business_profile WHERE id = 'self'").get();
    return r.isEmpty ? null : r.first.data['logo_path'] as String?;
  }

  /// Stores [fileBytes] (any picture) as the logo. Throws [LogoException] if it is not a readable picture.
  Future<void> save(Uint8List fileBytes) async {
    final png = normalizeLogoFile(fileBytes);
    dir.createSync(recursive: true);
    // a new file name each time so the picture widget never shows a cached old logo
    final f = File('${dir.path}/logo-${_now().millisecondsSinceEpoch}.png')..writeAsBytesSync(png, flush: true);
    final old = await path();
    await db.customStatement("UPDATE business_profile SET logo_path = ?, updated_at = ? WHERE id = 'self'", [f.path, _now().millisecondsSinceEpoch]);
    if (old != null && old != f.path) {
      final o = File(old);
      if (o.existsSync()) o.deleteSync();
    }
  }

  Future<void> remove() async {
    final old = await path();
    await db.customStatement("UPDATE business_profile SET logo_path = NULL, updated_at = ? WHERE id = 'self'", [_now().millisecondsSinceEpoch]);
    if (old != null && File(old).existsSync()) File(old).deleteSync();
  }

  Future<Uint8List?> bytes() async {
    final p = await path();
    if (p == null) return null;
    final f = File(p);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }
}

Future<void> updateBusinessProfile(AppDatabase db, {required String name, String? phone, String? address, String? taxLabel, String? taxNumber, required int now}) =>
    db.customStatement(
        "UPDATE business_profile SET name=?, phone=?, address=?, tax_number_label=?, tax_number=?, updated_at=? WHERE id='self'",
        [name.trim(), _nullIfEmpty(phone), _nullIfEmpty(address), _nullIfEmpty(taxLabel), _nullIfEmpty(taxNumber), now]);

String? _nullIfEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
