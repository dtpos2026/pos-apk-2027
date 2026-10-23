import 'dart:io';

import 'db/database.dart';

const dbFileName = 'dt_food_pos.sqlite';

/// Folder where a verified backup waits until the next app start (the live database cannot be swapped while open).
Directory pendingRestoreDir(Directory docs) => Directory('${docs.path}/restore_pending');

/// Called in main() BEFORE the database is opened. If a restore is waiting, the current database is kept as
/// `dt_food_pos.sqlite.before-restore` and the restored one takes its place; pictures replace the current ones.
/// Returns true when a restore was applied.
bool applyPendingRestore(Directory docs, {required Map<String, Directory> media}) {
  final pending = pendingRestoreDir(docs);
  final db = File('${pending.path}/$dbFileName');
  if (!db.existsSync()) return false;
  final live = File('${docs.path}/$dbFileName');
  if (live.existsSync()) live.renameSync('${live.path}.before-restore');
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final f = File('${live.path}$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  db.renameSync(live.path);
  for (final e in media.entries) {
    final src = Directory('${pending.path}/media/${e.key}');
    if (!src.existsSync()) continue;
    if (e.value.existsSync()) e.value.deleteSync(recursive: true);
    e.value.createSync(recursive: true);
    for (final f in src.listSync().whereType<File>()) {
      f.copySync('${e.value.path}/${f.uri.pathSegments.last}');
    }
  }
  pending.deleteSync(recursive: true);
  return true;
}

/// After a restore (possibly from another phone) picture paths point to the old phone's folders: point them at
/// the same file names in this phone's folders, or clear them when the file is missing.
Future<void> repointPictures(AppDatabase db, {required Directory menuImages, required Directory logo}) async {
  Future<void> fix(String table, String column, Directory dir, String where) async {
    final rows = await db.customSelect('SELECT id, $column AS p FROM $table WHERE $column IS NOT NULL $where').get();
    for (final r in rows) {
      final old = r.data['p'] as String;
      if (File(old).existsSync()) continue;
      final candidate = File('${dir.path}/${old.split('/').last}');
      await db.customStatement('UPDATE $table SET $column = ? WHERE id = ?', [candidate.existsSync() ? candidate.path : null, r.data['id']]);
    }
  }

  await fix('product', 'image_path', menuImages, '');
  await fix('category', 'image_path', menuImages, '');
  await fix('business_profile', 'logo_path', logo, '');
}

