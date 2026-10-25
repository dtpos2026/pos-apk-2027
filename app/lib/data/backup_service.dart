import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'db/database.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

/// Encrypted, verifiable backups of the whole database and the pictures (item/category photos, logo).
/// File layout: "DTBAK2" | iterations (u32 BE) | salt (16) | nonce (12) | ciphertext | GCM tag (16).
/// The plaintext of DTBAK2 is a zip: `db.sqlite` + `media/<folder>/<file>`. Older DTBAK1 files hold the bare database.
/// DTBAK3 (the default, no passphrase to remember): "DTBAK3" | zip | SHA-256 of the zip, so damage is still detected.
/// A plain .zip with db.sqlite, or a bare SQLite database file, can be restored as well.
/// Key = PBKDF2-HMAC-SHA256(passphrase, salt). AES-256-GCM authenticates the data, so a wrong passphrase or any
/// modification is detected before anything is restored.
class BackupService {
  BackupService(this.db, {this.iterations = 150000});
  final AppDatabase db;
  final int iterations;

  static const _magicV1 = [0x44, 0x54, 0x42, 0x41, 0x4B, 0x31]; // DTBAK1
  static const _magic = [0x44, 0x54, 0x42, 0x41, 0x4B, 0x32]; // DTBAK2
  static const _magicV3 = [0x44, 0x54, 0x42, 0x41, 0x4B, 0x33]; // DTBAK3
  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> _key(String pass, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: pass, nonce: salt);

  String _stamp(DateTime t) => '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}-${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}';

  /// Writes `dt-backup-<timestamp>.dtbak` into [dir] and returns it.
  /// [media] = picture folders to include, by name (e.g. {'menu_images': dir, 'logo': dir}).
  Future<File> createBackup({String passphrase = '', required Directory dir, DateTime? now, Map<String, Directory> media = const {}}) async {
    if (passphrase.isNotEmpty && passphrase.length < 6) throw BackupException('Passphrase must be at least 6 characters (or leave it empty for none)');
    dir.createSync(recursive: true);
    final tmp = File('${dir.path}/.snapshot-${DateTime.now().microsecondsSinceEpoch}.db');
    try {
      await db.customStatement('VACUUM INTO ?', [tmp.path]); // consistent snapshot even while the app is writing
      final zip = Archive()..addFile(ArchiveFile.bytes('db.sqlite', tmp.readAsBytesSync()));
      for (final e in media.entries) {
        if (!e.value.existsSync()) continue;
        for (final f in e.value.listSync().whereType<File>()) {
          zip.addFile(ArchiveFile.bytes('media/${e.key}/${f.uri.pathSegments.last}', f.readAsBytesSync()));
        }
      }
      final plain = ZipEncoder().encodeBytes(zip);
      final out = BytesBuilder();
      if (passphrase.isEmpty) {
        out
          ..add(_magicV3)
          ..add(plain)
          ..add((await Sha256().hash(plain)).bytes);
      } else {
        final rnd = Random.secure();
        final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
        final nonce = _aes.newNonce();
        final box = await _aes.encrypt(plain, secretKey: await _key(passphrase, salt, iterations), nonce: nonce);
        out
          ..add(_magic)
          ..add([(iterations >> 24) & 0xFF, (iterations >> 16) & 0xFF, (iterations >> 8) & 0xFF, iterations & 0xFF])
          ..add(salt)
          ..add(nonce)
          ..add(box.cipherText)
          ..add(box.mac.bytes);
      }
      final file = File('${dir.path}/dt-backup-${_stamp(now ?? DateTime.now())}.dtbak');
      file.writeAsBytesSync(out.toBytes(), flush: true);
      return file;
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  /// True when [backup] was made with a passphrase (DTBAK1/DTBAK2); newer backups, plain zips and database files need none.
  static bool needsPassphrase(File backup) {
    final head = backup.openSync()..setPositionSync(0);
    try {
      final b = head.readSync(6);
      return _listEq(b, _magic) || _listEq(b, _magicV1);
    } finally {
      head.closeSync();
    }
  }

  /// Decrypts [backup] into [target], then checks it is a healthy SQLite database with our schema.
  /// Pictures are written under `mediaRoot/folder/` when [mediaRoot] is given. Returns how many pictures were restored.
  /// Throws [BackupException] on a wrong passphrase, corruption or a foreign file. Nothing is touched on failure.
  static Future<int> decryptAndVerify({required File backup, String passphrase = '', required File target, Directory? mediaRoot}) async {
    final bytes = backup.readAsBytesSync();
    final head = bytes.length >= 6 ? bytes.sublist(0, 6) : const <int>[];
    final v3 = _listEq(head, _magicV3);
    final v2 = _listEq(head, _magic);
    final v1 = _listEq(head, _magicV1);
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 3 && bytes[3] == 4;
    final isSqlite = bytes.length > 16 && String.fromCharCodes(bytes.sublist(0, 15)) == 'SQLite format 3';
    if (!(v3 || v2 || v1 || isZip || isSqlite)) throw BackupException('Not a DT Food POS backup');

    List<int> plain;
    if (v3) {
      if (bytes.length < 6 + 32 + 4) throw BackupException('The backup file is damaged');
      plain = bytes.sublist(6, bytes.length - 32);
      final sum = (await Sha256().hash(plain)).bytes;
      if (!_listEq(sum, bytes.sublist(bytes.length - 32))) throw BackupException('The backup file is damaged (it may not have been copied completely). Copy it again from where it was saved.');
    } else if (v2 || v1) {
      const header = 6 + 4 + 16 + 12;
      if (bytes.length < header + 16) throw BackupException('The backup file is damaged');
      final iterations = ByteData.sublistView(bytes, 6, 10).getUint32(0);
      if (iterations < 1000 || iterations > 5000000) throw BackupException('Corrupted backup header');
      final salt = bytes.sublist(10, 26);
      final nonce = bytes.sublist(26, 38);
      final cipher = bytes.sublist(38, bytes.length - 16);
      final mac = bytes.sublist(bytes.length - 16);
      try {
        plain = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: await _key(passphrase, salt, iterations));
      } on SecretBoxAuthenticationError {
        throw BackupException('Wrong passphrase. Type exactly the one used when this backup was made (check every character), or the file is damaged.');
      }
    } else {
      plain = bytes;
    }
    var dbBytes = plain;
    final pictures = <String, List<int>>{};
    if (v3 || v2 || isZip) {
      final Archive zip;
      try {
        zip = ZipDecoder().decodeBytes(plain);
      } catch (_) {
        throw BackupException('The backup file is damaged');
      }
      final db = zip.findFile('db.sqlite');
      if (db == null) throw BackupException('The backup has no database');
      dbBytes = db.content;
      for (final f in zip.files) {
        if (f.isFile && f.name.startsWith('media/') && !f.name.contains('..')) pictures[f.name.substring(6)] = f.content;
      }
    }
    final tmp = File('${target.path}.partial');
    tmp.writeAsBytesSync(dbBytes, flush: true);
    try {
      final check = sqlite.sqlite3.open(tmp.path, mode: sqlite.OpenMode.readOnly);
      try {
        final integrity = check.select('PRAGMA integrity_check').first.values.first;
        if (integrity != 'ok') throw BackupException('Database integrity check failed: $integrity');
        final tables = check.select("SELECT name FROM sqlite_master WHERE type='table'").map((r) => r['name']).toSet();
        for (final t in ['order', 'payment', 'product', 'outbox']) {
          if (!tables.contains(t)) throw BackupException('Backup does not look like a DT Food POS database (missing $t)');
        }
      } finally {
        check.dispose();
      }
      tmp.renameSync(target.path);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
    if (mediaRoot != null) {
      for (final e in pictures.entries) {
        File('${mediaRoot.path}/${e.key}')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(e.value, flush: true);
      }
    }
    return pictures.length;
  }

  /// Keeps the newest [keep] backups in [dir], deletes older ones. Returns how many were removed.
  static int prune(Directory dir, {int keep = 14}) {
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dtbak')).toList()..sort((a, b) => b.path.compareTo(a.path));
    var removed = 0;
    for (final f in files.skip(keep)) {
      f.deleteSync();
      removed++;
    }
    return removed;
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
