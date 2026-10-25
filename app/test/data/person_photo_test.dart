import 'dart:io';

import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/menu_images.dart';
import 'package:dt_food_pos/data/queries.dart';
import 'package:dt_food_pos/data/team_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('staff, riders and waiters can have a profile picture: it shows in the lists, can be replaced and removed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Cashier','[]',1)");
    await db.customStatement("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await db.customStatement("INSERT INTO team_member(id,kind,name,updated_at) VALUES ('rd','rider','Kamran',1), ('w1','waiter','Bilal',1)");
    final dir = Directory.systemTemp.createTempSync('people');
    final store = MenuImageStore(db, dir);
    final bytes = img.encodeJpg(img.Image(width: 300, height: 200)..clear(img.ColorRgb8(10, 120, 200)));

    expect((await loadStaff(db)).single.imagePath, isNull);
    final p1 = await store.setStaff('s1', bytes);
    expect((await loadStaff(db)).single.imagePath, p1);
    expect(File(p1).existsSync(), isTrue);
    final p2 = await store.setStaff('s1', bytes); // a new picture replaces the old file
    expect(File(p1).existsSync() && p1 != p2, isFalse);

    final team = TeamService(DbHelper(db));
    await store.setMember('rd', bytes);
    await store.setMember('w1', bytes);
    expect((await team.riders()).single.imagePath, isNotNull);
    expect((await team.waiters()).single.imagePath, isNotNull);

    await store.removeStaff('s1');
    await store.removeMember('rd');
    expect((await loadStaff(db)).single.imagePath, isNull);
    expect((await team.riders()).single.imagePath, isNull);
  });
}
