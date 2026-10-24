import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/db_helper.dart';
import 'package:dt_food_pos/data/kitchen_service.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/domain/print_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PosService pos;
  late PrintService print_;
  late KitchenService kitchen;
  final clock = DateTime(2026, 1, 12, 19, 40);
  Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
  Future<int> jobs(String kind) async => (await db.customSelect('SELECT COUNT(*) AS n FROM print_job WHERE kind = ?', variables: [Variable.withString(kind)]).getSingle()).data['n'] as int;
  Future<void> save(PrintSettings s) => sql("INSERT OR REPLACE INTO setting(setting_key, setting_value, updated_at) VALUES ('print.config', ?, 1)", [s.encode()]);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pos = PosService(db, now: () => clock);
    print_ = PrintService(db, now: () => clock);
    kitchen = KitchenService(DbHelper(db, now: () => clock));
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO product(id,name,base_price_minor,updated_at) VALUES ('b','Zinger Burger',45000,1)");
    await sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('k','Kitchen','lan','x:1',58,'kot',1)");
  });
  tearDown(() => db.close());

  Future<String> draft([String type = 'dine_in']) => pos.saveDraft(DraftOrder(orderType: type, items: [CartItem(productId: 'b', name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000)]), staffId: 's1');

  test('settings: everything on by default; damaged data falls back to that; per order type switches', () {
    expect(PrintSettings.decode(null).kotEnabled, isTrue);
    expect(PrintSettings.decode('not json {{').autoToken, isTrue);
    final s = PrintSettings.defaults.withType('counter', const AutoPrint(kot: false, token: true, bill: false));
    expect([s.autoKotFor('counter'), s.autoTokenFor('counter'), s.autoBillFor('counter'), s.autoKotFor('dine_in')], [false, true, false, true]);
    expect(PrintSettings.decode(s.encode()).autoKotFor('counter'), isFalse, reason: 'survives save and load');
    expect(s.copyWith(kotEnabled: false).autoKotFor('dine_in'), isFalse, reason: 'master switch off beats everything');
  });

  test('Send to kitchen WITHOUT printing: the kitchen board has the order, no KOT is printed; Print KOT later by hand', () async {
    final id = await draft();
    final r = await print_.sendToKitchen(id, printKot: false);
    expect([r.sent, r.printed], [true, 0]);
    expect(await jobs('kot'), 0);
    expect((await kitchen.tickets()).single.orderId, id);
    expect((await print_.sendToKitchen(id, printKot: true)).sent, isFalse, reason: 'already sent: a retry or a second tap prints nothing new');
    expect(await jobs('kot'), 0);
    final manual = await print_.queueKot(id, reprint: true);
    expect(manual, hasLength(1), reason: 'Print KOT by hand for the existing order');
    expect((await db.customSelect('SELECT COUNT(*) AS n FROM "order"').getSingle()).data['n'], 1, reason: 'no second order');
  });

  test('Send to kitchen AND print KOT: one ticket, and a repeated tap makes no second one', () async {
    final id = await draft();
    expect((await print_.sendToKitchen(id)).printed, 1);
    await print_.sendToKitchen(id);
    expect(await jobs('kot'), 1);
  });

  test('KOT printing switched off: nothing is printed even when asked, the order still reaches the kitchen board', () async {
    await save(PrintSettings.defaults.copyWith(kotEnabled: false));
    final id = await draft();
    final r = await print_.sendToKitchen(id, printKot: true);
    expect([r.sent, r.printed], [true, 0]);
    expect(await jobs('kot'), 0);
    expect(await kitchen.tickets(), hasLength(1));
    expect((await print_.printSettings()).kotEnabled, isFalse);
  });
}
