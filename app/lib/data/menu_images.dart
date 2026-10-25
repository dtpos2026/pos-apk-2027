import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:drift/drift.dart' show Variable;

import 'db/database.dart';

class MenuImageException implements Exception {
  MenuImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Item and category pictures, kept on the phone (works offline). Every picture is cut to a square and saved as
/// a small JPEG (480 px), so a menu of hundreds of items stays a few MB and scrolls fast.
class MenuImageStore {
  MenuImageStore(this.db, this.dir, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final AppDatabase db;
  final Directory dir;
  final DateTime Function() _now;
  static const side = 480;

  /// Square-cropped, resized JPEG. Throws [MenuImageException] for anything that is not a picture.
  static Uint8List normalize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw MenuImageException('This file is not a picture. Choose a JPG or PNG photo.');
    final s = decoded.width < decoded.height ? decoded.width : decoded.height;
    final square = img.copyCrop(decoded, x: (decoded.width - s) ~/ 2, y: (decoded.height - s) ~/ 2, width: s, height: s);
    final small = s > side ? img.copyResize(square, width: side, height: side, interpolation: img.Interpolation.average) : square;
    return Uint8List.fromList(img.encodeJpg(small, quality: 82));
  }

  Future<String> setProduct(String productId, Uint8List bytes) => _set('product', productId, bytes);
  Future<String> setCategory(String categoryId, Uint8List bytes) => _set('category', categoryId, bytes);
  Future<String> setCustomer(String id, Uint8List bytes) => _set('customer', id, bytes);
  Future<void> removeCustomer(String id) => _remove('customer', id);
  Future<String> setStaff(String id, Uint8List bytes) => _set('staff', id, bytes);
  Future<void> removeStaff(String id) => _remove('staff', id);
  Future<String> setMember(String id, Uint8List bytes) => _set('team_member', id, bytes);
  Future<void> removeMember(String id) => _remove('team_member', id);
  Future<String> setPaymentMethod(String id, Uint8List bytes) => _set('payment_method', id, bytes);
  Future<void> removePaymentMethod(String id) => _remove('payment_method', id);
  Future<void> removeProduct(String productId) => _remove('product', productId);
  Future<void> removeCategory(String categoryId) => _remove('category', categoryId);

  Future<String?> _current(String table, String id) async {
    final r = await db.customSelect('SELECT image_path FROM $table WHERE id = ?', variables: [Variable.withString(id)]).get();
    return r.isEmpty ? null : r.first.data['image_path'] as String?;
  }

  Future<String> _set(String table, String id, Uint8List bytes) async {
    final jpg = normalize(bytes);
    dir.createSync(recursive: true);
    // a new name each time, so the screen never shows a cached old picture
    final f = File('${dir.path}/$table-$id-${_now().millisecondsSinceEpoch}.jpg')..writeAsBytesSync(jpg, flush: true);
    final old = await _current(table, id);
    await db.customStatement('UPDATE $table SET image_path = ?, version = version + 1, updated_at = ? WHERE id = ?', [f.path, _now().millisecondsSinceEpoch, id]);
    if (old != null && old != f.path && File(old).existsSync()) File(old).deleteSync();
    return f.path;
  }

  Future<void> _remove(String table, String id) async {
    final old = await _current(table, id);
    await db.customStatement('UPDATE $table SET image_path = NULL, version = version + 1, updated_at = ? WHERE id = ?', [_now().millisecondsSinceEpoch, id]);
    if (old != null && File(old).existsSync()) File(old).deleteSync();
  }
}
