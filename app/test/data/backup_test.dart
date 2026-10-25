import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/backup_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/restore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

late AppDatabase db;
late BackupService svc;
late Directory tmp;

void main() {
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    svc = BackupService(db, iterations: 2000);
    tmp = Directory.systemTemp.createTempSync('dtbak');
    await db.customStatement("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('p1','Zinger Burger',45000,1)");
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('backup is encrypted: the data is not readable in the file', () async {
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp);
    final bytes = f.readAsBytesSync();
    expect(String.fromCharCodes(bytes), isNot(contains('Zinger Burger')));
    expect(String.fromCharCodes(bytes), isNot(contains('SQLite format')));
    expect(f.path, endsWith('.dtbak'));
  });

  test('round trip restores the data and passes the integrity check', () async {
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp);
    final out = File('${tmp.path}/restored.db');
    await BackupService.decryptAndVerify(backup: f, passphrase: 'secret123', target: out);
    final r = sqlite.sqlite3.open(out.path);
    expect(r.select('SELECT name, base_price_minor FROM product').single.values, ['Zinger Burger', 45000]);
    r.dispose();
  });

  test('wrong passphrase is refused and nothing is written', () async {
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp);
    final out = File('${tmp.path}/restored.db');
    await expectLater(BackupService.decryptAndVerify(backup: f, passphrase: 'nope-nope', target: out), throwsA(isA<BackupException>()));
    expect(out.existsSync(), isFalse);
  });

  test('a single flipped byte (corruption/tampering) is detected', () async {
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp);
    final b = f.readAsBytesSync();
    b[b.length ~/ 2] ^= 0x01;
    f.writeAsBytesSync(b);
    final out = File('${tmp.path}/restored.db');
    await expectLater(BackupService.decryptAndVerify(backup: f, passphrase: 'secret123', target: out), throwsA(isA<BackupException>()));
    expect(out.existsSync(), isFalse);
  });

  test('foreign files and truncated files are rejected', () async {
    final junk = File('${tmp.path}/junk.dtbak')..writeAsStringSync('hello world, definitely not a backup file at all....');
    final out = File('${tmp.path}/restored.db');
    await expectLater(BackupService.decryptAndVerify(backup: junk, passphrase: 'secret123', target: out), throwsA(isA<BackupException>()));
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp);
    f.writeAsBytesSync(f.readAsBytesSync().sublist(0, 40));
    await expectLater(BackupService.decryptAndVerify(backup: f, passphrase: 'secret123', target: out), throwsA(isA<BackupException>()));
  });

  test('weak passphrase refused; two backups of the same data differ (fresh salt and nonce)', () async {
    await expectLater(svc.createBackup(passphrase: '123', dir: tmp), throwsA(isA<BackupException>()));
    final a = await svc.createBackup(passphrase: 'secret123', dir: tmp, now: DateTime(2026, 1, 12, 1));
    final b = await svc.createBackup(passphrase: 'secret123', dir: tmp, now: DateTime(2026, 1, 12, 2));
    expect(a.readAsBytesSync(), isNot(b.readAsBytesSync()));
  });

  test('prune keeps the newest backups only', () async {
    for (var h = 1; h <= 5; h++) {
      await svc.createBackup(passphrase: 'secret123', dir: tmp, now: DateTime(2026, 1, 12, h));
    }
    expect(BackupService.prune(tmp, keep: 2), 3);
    final left = tmp.listSync().map((e) => e.path.split('/').last).where((n) => n.endsWith('.dtbak')).toList()..sort();
    expect(left, ['dt-backup-20260112-040000.dtbak', 'dt-backup-20260112-050000.dtbak']);
  });

  test('pictures travel with the backup and a restore swaps the database on the next start', () async {
    final docs = Directory('${tmp.path}/docs')..createSync();
    final menu = Directory('${docs.path}/menu_images')..createSync();
    final logo = Directory('${docs.path}/logo')..createSync();
    File('${menu.path}/product-p1-1.jpg').writeAsBytesSync([0xFF, 0xD8, 1, 2, 3]);
    File('${logo.path}/logo-1.png').writeAsBytesSync([0x89, 0x50, 9]);
    // the backup came from another phone whose folders had a different path
    await db.customStatement("UPDATE product SET image_path = '/old/phone/menu_images/product-p1-1.jpg' WHERE id = 'p1'");
    final f = await svc.createBackup(passphrase: 'secret123', dir: tmp, media: {'menu_images': menu, 'logo': logo});
    expect(String.fromCharCodes(f.readAsBytesSync().take(6)), 'DTBAK2');

    // this phone: a different live database, and no pictures
    File('${docs.path}/$dbFileName').writeAsStringSync('old live db');
    menu.deleteSync(recursive: true);
    logo.deleteSync(recursive: true);
    final pending = pendingRestoreDir(docs)..createSync(recursive: true);
    final n = await BackupService.decryptAndVerify(backup: f, passphrase: 'secret123', target: File('${pending.path}/$dbFileName'), mediaRoot: Directory('${pending.path}/media'));
    expect(n, 2);

    expect(applyPendingRestore(docs, media: {'menu_images': menu, 'logo': logo}), isTrue);
    expect(File('${docs.path}/$dbFileName.before-restore').readAsStringSync(), 'old live db', reason: 'the replaced data is kept aside');
    expect(File('${menu.path}/product-p1-1.jpg').readAsBytesSync(), [0xFF, 0xD8, 1, 2, 3]);
    expect(File('${logo.path}/logo-1.png').existsSync(), isTrue);
    expect(pending.existsSync(), isFalse);
    expect(applyPendingRestore(docs, media: {'menu_images': menu, 'logo': logo}), isFalse, reason: 'applied only once');

    final restored = AppDatabase(NativeDatabase(File('${docs.path}/$dbFileName')));
    addTearDown(restored.close);
    await repointPictures(restored, menuImages: menu, logo: logo);
    final path = (await restored.customSelect("SELECT image_path FROM product WHERE id = 'p1'").getSingle()).data['image_path'];
    expect(path, '${menu.path}/product-p1-1.jpg');
  });

  group('no code needed', () {
    test('a backup made without a passphrase restores without one, and any damage is caught', () async {
      final f = await svc.createBackup(dir: tmp);
      expect(BackupService.needsPassphrase(f), isFalse);
      final out = File('${tmp.path}/restored.db');
      await BackupService.decryptAndVerify(backup: f, target: out);
      final check = sqlite.sqlite3.open(out.path);
      expect(check.select("SELECT name FROM product WHERE id='p1'").first['name'], 'Zinger Burger');
      check.dispose();

      final bytes = f.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0x55;
      f.writeAsBytesSync(bytes);
      await expectLater(BackupService.decryptAndVerify(backup: f, target: File('${tmp.path}/x.db')), throwsA(isA<BackupException>()));
    });

    test('older passphrase backups still need theirs, and say so', () async {
      final f = await svc.createBackup(passphrase: '000000', dir: tmp);
      expect(BackupService.needsPassphrase(f), isTrue);
      await expectLater(BackupService.decryptAndVerify(backup: f, passphrase: '1111111', target: File('${tmp.path}/x.db')), throwsA(isA<BackupException>()));
      await BackupService.decryptAndVerify(backup: f, passphrase: '000000', target: File('${tmp.path}/y.db'));
    });

    test('a bare database file or a plain zip with db.sqlite can be restored too', () async {
      final snap = File('${tmp.path}/snap.sqlite');
      await db.customStatement('VACUUM INTO ?', [snap.path]);
      await BackupService.decryptAndVerify(backup: snap, target: File('${tmp.path}/a.db'));
      expect(File('${tmp.path}/a.db').existsSync(), isTrue);

      final zip = File('${tmp.path}/b.zip')..writeAsBytesSync(ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.bytes('db.sqlite', snap.readAsBytesSync()))));
      await BackupService.decryptAndVerify(backup: zip, target: File('${tmp.path}/b.db'));
      expect(File('${tmp.path}/b.db').existsSync(), isTrue);
    });

    test('an empty passphrase is allowed, a short one is not', () async {
      await svc.createBackup(dir: tmp);
      await expectLater(svc.createBackup(passphrase: '123', dir: tmp), throwsA(isA<BackupException>()));
    });

    test('a keyboard that adds a space or a stray character, or types Arabic digits, still opens the backup', () async {
      final f = await svc.createBackup(passphrase: '000000', dir: tmp);
      for (final typed in ['0000000', '000000 ', ' 000000', '٠٠٠٠٠٠', '۰۰۰۰۰۰', '0000x00']) {
        final out = File('${tmp.path}/t${typed.hashCode}.db');
        await BackupService.decryptAndVerify(backup: f, passphrase: typed, target: out);
        expect(out.existsSync(), isTrue, reason: 'typed "$typed"');
      }
      await expectLater(BackupService.decryptAndVerify(backup: f, passphrase: '111111', target: File('${tmp.path}/z.db')), throwsA(isA<BackupException>()));
    });
  });
}
