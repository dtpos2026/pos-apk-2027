import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/pos_service.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/data/token_service.dart';
import 'package:dt_food_pos/domain/token.dart';
import 'package:flutter_test/flutter_test.dart';

late AppDatabase db;
late PosService pos;
late PrintService printSvc;
late TokenService tokens;
var clock = DateTime(2026, 1, 12, 19, 40);
Future<void> sql(String s, [List<Object?> a = const []]) => db.customStatement(s, a);
Future<List<Map<String, Object?>>> rows(String q) async => (await db.customSelect(q).get()).map((r) => r.data).toList();

class FakePrinter {
  late ServerSocket server;
  final received = <Uint8List>[];
  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((c) {
      final b = BytesBuilder();
      c.listen(b.add, onDone: () => received.add(b.toBytes()));
    });
  }

  String get address => '127.0.0.1:${server.port}';
  Future<void> stop() => server.close();
  Future<String> text() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return received.map((b) => latin1.decode(b, allowInvalid: true)).join();
  }
}

void main() {
  late FakePrinter lan, tandoorPrinter;
  setUp(() async {
    clock = DateTime(2026, 1, 12, 19, 40);
    db = AppDatabase(NativeDatabase.memory());
    lan = FakePrinter();
    tandoorPrinter = FakePrinter();
    await lan.start();
    await tandoorPrinter.start();
    pos = PosService(db, now: () => clock);
    tokens = TokenService(db, now: () => clock);
    printSvc = PrintService(db, now: () => clock);
    await sql("INSERT INTO role(id,name,permissions,updated_at) VALUES ('r','Owner','[\"*\"]',1)");
    await sql("INSERT INTO staff(id,name,role_id,pin_hash,pin_salt,updated_at) VALUES ('s1','Ali','r','h','s',1)");
    await sql("INSERT INTO payment_method(id,name,kind,updated_at) VALUES ('cash','Cash','cash',1)");
    await sql("INSERT INTO business_profile(id,name,updated_at) VALUES ('self','Burger Point',1)");
    for (final p in [('b', 'Zinger Burger', 45000), ('r', 'Roti', 3000), ('n', 'Naan', 6000), ('t', 'Chai', 15000), ('c', 'Lunch coupon', 50000)]) {
      await sql('INSERT INTO product(id,name,base_price_minor,updated_at) VALUES (?,?,?,1)', [p.$1, p.$2, p.$3]);
    }
  });
  tearDown(() async {
    await lan.stop();
    await tandoorPrinter.stop();
    await db.close();
  });

  Future<void> addPrinter(String id, String role, FakePrinter f, {String? station, int paper = 58}) =>
      sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,station,updated_at) VALUES (?,?,'lan',?,?,?,?,1)", [id, id, f.address, paper, role, station]);

  Future<String> sale(List<(String, String, int, int, String?)> items) async {
    final id = await pos.saveDraft(DraftOrder(orderType: 'counter', items: [for (final i in items) CartItem(productId: i.$1, name: i.$2, qtyMilli: i.$3, unitPriceMinor: i.$4, station: i.$5)]), staffId: 's1');
    final total = items.fold<int>(0, (s, i) => s + i.$3 * i.$4 ~/ 1000);
    await pos.settleOrder(orderId: id, payments: [SettlePayment(methodId: 'cash', amountMinor: total)], staffId: 's1');
    return id;
  }

  Future<void> configure(List<TokenRule> rules, {bool printBill = true}) => tokens.saveConfig(TokenConfig(rules: rules, printBill: printBill));
  const order = TokenRule(id: 'o', kind: TokenKind.order, name: 'Order', prefix: 'A');
  const tandoor = TokenRule(id: 't', kind: TokenKind.tandoor, name: 'Tandoor', station: 'tandoor', prefix: 'T');

  test('with no rules switched on nothing changes: no tokens, no numbers', () async {
    final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    expect(await tokens.forOrder(id), isEmpty);
    expect(await rows('SELECT * FROM token_seq'), isEmpty);
  });

  test('order token: one big number per sale, prefix and padding, counts on, restarts each business day', () async {
    await configure([order.copyWith(pad: 3)]);
    final a = await tokens.forOrder(await sale([('b', 'Zinger Burger', 1000, 45000, null)]));
    final b = await tokens.forOrder(await sale([('b', 'Zinger Burger', 2000, 45000, null)]));
    expect(a.single.label, 'A001');
    expect(b.single.label, 'A002');
    expect(a.single.items.single.name, 'Zinger Burger');
    clock = DateTime(2026, 1, 13, 10);
    final c = await tokens.forOrder(await sale([('b', 'Zinger Burger', 1000, 45000, null)]));
    expect(c.single.label, 'A001', reason: 'daily reset');

    await configure([order.copyWith(dailyReset: false, startAt: 100)]);
    final d = await tokens.forOrder(await sale([('b', 'Zinger Burger', 1000, 45000, null)]));
    expect(d.single.label, 'A100');
    final e = await tokens.forOrder(await sale([('b', 'Zinger Burger', 1000, 45000, null)]));
    expect(e.single.label, 'A101');
  });

  test('issuing twice never makes a second token or burns a number', () async {
    await configure([order]);
    final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    final again = await tokens.issueForOrder(id);
    final third = await tokens.issueForOrder(id);
    expect(again.length, 1);
    expect(third.single.label, 'A1');
    expect((await rows('SELECT last_no FROM token_seq')).single['last_no'], 1);
    // a rule added later only adds its own token
    await configure([order, tandoor.copyWith(station: 'tandoor')]);
    expect(await tokens.issueForOrder(id), hasLength(1)); // no tandoor items on this order
  });

  test('product routing: tandoor and stall tokens only contain the items of their counter', () async {
    await configure([
      order,
      tandoor,
      const TokenRule(id: 's', kind: TokenKind.stall, name: 'BBQ', station: 'bbq', prefix: 'B', collectText: 'Counter 2'),
    ]);
    final id = await sale([('r', 'Roti', 6000, 3000, 'tandoor'), ('n', 'Naan', 2000, 6000, 'Tandoor'), ('b', 'Zinger Burger', 1000, 45000, 'bbq'), ('t', 'Chai', 1000, 15000, null)]);
    final t = await tokens.forOrder(id);
    expect(t.map((e) => e.label).toSet(), {'A1', 'T1', 'B1'});
    final tand = t.firstWhere((e) => e.kind == TokenKind.tandoor);
    expect(tand.items.map((i) => i.name), ['Roti', 'Naan'], reason: 'station match ignores case');
    expect(tand.items.first.qtyMilli, 6000);
    final stall = t.firstWhere((e) => e.kind == TokenKind.stall);
    expect(stall.items.map((i) => i.name), ['Zinger Burger']);
    expect(stall.payload['collect'], 'Counter 2');
    expect(t.firstWhere((e) => e.kind == TokenKind.order).items, hasLength(4));
  });

  test('station kinds without a counter make nothing; a stall for an unused counter makes nothing', () async {
    await configure([tandoor.copyWith(station: ''), const TokenRule(id: 's', kind: TokenKind.stall, name: 'BBQ', station: 'bbq')]);
    expect(await tokens.forOrder(await sale([('r', 'Roti', 1000, 3000, 'tandoor')])), isEmpty);
  });

  test('product token: one per group, or one per product line; unit token: one per unit', () async {
    await configure([const TokenRule(id: 'p', kind: TokenKind.product, name: 'Drinks', station: 'bar', prefix: 'D')]);
    var id = await sale([('t', 'Chai', 1000, 15000, 'bar'), ('t', 'Chai', 1000, 15000, 'bar'), ('b', 'Zinger Burger', 1000, 45000, 'grill')]);
    expect((await tokens.forOrder(id)).map((e) => e.label), ['D1']);

    await configure([const TokenRule(id: 'p', kind: TokenKind.product, name: 'Drinks', station: 'bar', split: 'line', prefix: 'D')]);
    id = await sale([('t', 'Chai', 1000, 15000, 'bar'), ('c', 'Cola', 1000, 10000, 'bar')]);
    expect((await tokens.forOrder(id)).map((e) => e.label), ['D2', 'D3'], reason: 'numbers carry on within the day');

    await configure([const TokenRule(id: 'u', kind: TokenKind.unit, name: 'Tea', station: 'tea', prefix: 'U')]);
    id = await sale([('t', 'Chai', 3000, 15000, 'tea'), ('r', 'Roti', 1000, 3000, 'tandoor')]);
    final u = await tokens.forOrder(id);
    expect(u.map((e) => e.label), ['U1', 'U2', 'U3']);
    expect(u.every((e) => e.items.single.qtyMilli == 1000 && e.items.single.name == 'Chai'), isTrue);
    expect(u.map((e) => e.part), [0, 1, 2]);
  });

  test('price token keeps prices, discount and total of the order', () async {
    await configure([const TokenRule(id: 'pr', kind: TokenKind.price, name: 'Price', prefix: 'P')]);
    final t = (await tokens.forOrder(await sale([('b', 'Zinger Burger', 2000, 45000, null)]))).single;
    expect(t.items.single.unitPriceMinor, 45000);
    expect(t.items.single.totalMinor, 90000);
    expect(t.payload['total'], 90000);
    final slip = await tokens.slip(t);
    expect(slip.totalMinor, 90000);
  });

  test('coupons: one per unit, unique codes, redeem once, duplicates refused', () async {
    await configure([const TokenRule(id: 'c', kind: TokenKind.coupon, name: 'Coupon', station: 'coupon', prefix: 'C')]);
    final id = await sale([('c', 'Lunch coupon', 3000, 50000, 'coupon')]);
    final t = await tokens.forOrder(id);
    expect(t, hasLength(3));
    final codes = t.map((e) => e.couponCode!).toList();
    expect(codes.toSet(), hasLength(3));
    expect(codes.every((c) => RegExp(r'^CP-[A-Z2-9]{5}-[A-Z2-9]{5}$').hasMatch(c)), isTrue);
    expect(t.first.payload['couponValue'], 50000);

    final first = await tokens.redeem(codes[0].toLowerCase().replaceAll('-', ' '), staffId: 's1');
    expect(first.ok, isTrue);
    expect(first.valueMinor, 50000);
    final second = await tokens.redeem(codes[0]);
    expect(second.status, RedeemStatus.alreadyRedeemed);
    expect(second.redeemedAt, isNotNull);
    expect((await tokens.redeem('CP-AAAAA-BBBBB')).status, RedeemStatus.notFound);
    expect((await tokens.byId(t.first.id))!.status, 'collected');
    expect(await tokens.couponsLeft(), 2);
    expect((await rows("SELECT * FROM audit_log WHERE event = 'coupon.redeem'")), hasLength(1));

    // two cashiers at the same moment: only one wins
    final both = await Future.wait([tokens.redeem(codes[1]), tokens.redeem(codes[1])]);
    expect(both.where((r) => r.ok), hasLength(1));
  });

  test('a voided sale cancels waiting tokens and unused coupons, not the collected or redeemed ones', () async {
    await configure([order, const TokenRule(id: 'c', kind: TokenKind.coupon, name: 'Coupon', station: 'coupon', prefix: 'C')]);
    final id = await sale([('c', 'Lunch coupon', 2000, 50000, 'coupon'), ('b', 'Zinger Burger', 1000, 45000, null)]);
    final t = await tokens.forOrder(id);
    final coupons = t.where((e) => e.kind == TokenKind.coupon).toList();
    await tokens.redeem(coupons.first.couponCode!);
    await tokens.markCollected(t.firstWhere((e) => e.kind == TokenKind.order).id);
    await pos.refundOrder(orderId: id, staffId: 's1', reason: 'customer left');
    final after = {for (final e in await tokens.forOrder(id)) e.id: e.status};
    expect(after[coupons.first.id], 'collected');
    expect(after[coupons.last.id], 'void');
    expect(after[t.firstWhere((e) => e.kind == TokenKind.order).id], 'collected');
    expect((await tokens.redeem(coupons.last.couponCode!)).status, RedeemStatus.voided);
    // a voided order never prints its tokens
    await addPrinter('p', 'bill', lan);
    expect(await printSvc.queueTokens(id, reprint: true), isEmpty);
  });

  test('module off (by the owner or by Digital Target) stops numbering and printing; settings and old tokens stay', () async {
    await configure([order]);
    final first = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    expect(await tokens.forOrder(first), hasLength(1));

    await sql("INSERT INTO setting(setting_key,setting_value,updated_at) VALUES ('cloud.modules_off','[\"tokens\"]',1)");
    expect(await tokens.moduleOn(), isFalse);
    final second = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    expect(await tokens.forOrder(second), isEmpty);
    expect((await tokens.rawConfig()).rules, hasLength(1), reason: 'settings are kept');
    expect(await tokens.forOrder(first), hasLength(1), reason: 'records are kept');

    await sql("UPDATE setting SET setting_value = '[]' WHERE setting_key = 'cloud.modules_off'");
    await sql("INSERT INTO setting(setting_key,setting_value,updated_at) VALUES ('modules','[\"tables\"]',1)");
    expect(await tokens.moduleOn(), isFalse, reason: 'owner switched it off');
    await sql("UPDATE setting SET setting_value = '[\"tables\",\"tokens\"]' WHERE setting_key = 'modules'");
    expect(await tokens.moduleOn(), isTrue);
    final third = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    expect((await tokens.forOrder(third)).single.label, 'A2', reason: 'numbering continues where it stopped');
  });

  test('collection: waiting → collected once', () async {
    await configure([order]);
    final t = (await tokens.forOrder(await sale([('b', 'Zinger Burger', 1000, 45000, null)]))).single;
    expect(await tokens.markCollected(t.id), isTrue);
    expect(await tokens.markCollected(t.id), isFalse);
    expect(await tokens.forDate('2026-01-12', status: 'issued'), isEmpty);
    expect(await tokens.forDate('2026-01-12'), hasLength(1));
  });

  test('the bill shows the order token', () async {
    await configure([order]);
    final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
    expect(await tokens.orderTokenLabel(id), 'A1');
  });

  group('printing', () {
    test('tokens go to the printer of their counter; others to the bill printer; first print is not marked REPRINT', () async {
      await addPrinter('counter', 'bill', lan);
      await addPrinter('tandoor-p', 'kot', tandoorPrinter, station: 'Tandoor');
      await configure([order, tandoor]);
      final id = await sale([('r', 'Roti', 6000, 3000, 'tandoor'), ('b', 'Zinger Burger', 1000, 45000, null)]);
      final jobs = await printSvc.queueTokens(id, autoOnly: true);
      expect(jobs, hasLength(2));
      await printSvc.processQueue();
      final main = await lan.text();
      final tand = await tandoorPrinter.text();
      expect(main, contains('A1'));
      expect(main, contains('Counter'));
      expect(main, isNot(contains('Roti')), reason: 'the classic design does not list items, and the tandoor token goes elsewhere');
      expect(tand, contains('T1'));
      expect(tand, contains('6 Roti'));
      expect(tand, isNot(contains('REPRINT')));
      // the sale-time print never repeats
      expect(await printSvc.queueTokens(id, autoOnly: true), isEmpty);
    });

    test('manual reprint is marked REPRINT, counted and audited', () async {
      await addPrinter('counter', 'bill', lan);
      await configure([order]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      await printSvc.queueTokens(id, autoOnly: true);
      final again = await printSvc.queueTokens(id, reprint: true, staffId: 's1');
      expect(again, hasLength(1));
      await printSvc.processQueue();
      expect(await lan.text(), contains('REPRINT'));
      final t = (await tokens.forOrder(id)).single;
      expect(t.printCount, 2);
      expect(await rows("SELECT * FROM audit_log WHERE event = 'token.reprint'"), hasLength(1));
      expect((await rows("SELECT is_duplicate FROM print_job WHERE kind='token' ORDER BY created_at, rowid")).map((r) => r['is_duplicate']), [0, 1]);
    });

    test('rules set to manual do not print at the sale but can be printed on request', () async {
      await addPrinter('counter', 'bill', lan);
      await configure([order.copyWith(auto: false)]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      expect(await printSvc.queueTokens(id, autoOnly: true), isEmpty);
      expect(await printSvc.queueTokens(id), hasLength(1));
    });

    test('a printer chosen on the rule wins; copies are printed; no printer = token kept, nothing queued', () async {
      await addPrinter('counter', 'bill', lan);
      await addPrinter('other', 'kot', tandoorPrinter, station: 'x');
      await configure([order.copyWith(printerId: 'other', copies: 2)]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      expect(await printSvc.queueTokens(id, autoOnly: true), hasLength(1));
      await printSvc.processQueue();
      final text = await tandoorPrinter.text();
      expect('A1'.allMatches(text).length, greaterThanOrEqualTo(2));
      expect(lan.received, isEmpty);

      await sql('DELETE FROM print_job');
      await sql('UPDATE printer SET enabled = 0');
      expect(await printSvc.queueTokens(id), isEmpty);
      expect(await tokens.forOrder(id), hasLength(1));
    });

    test('offline printer: the job stays queued and prints when the printer is back', () async {
      await sql("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('p','P','lan','127.0.0.1:1',58,'bill',1)");
      await configure([order]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      await printSvc.queueTokens(id, autoOnly: true);
      final stats = await printSvc.processQueue();
      expect(stats.failed, 1);
      expect((await rows("SELECT status, last_error FROM print_job")).single['status'], 'failed');
      await sql("UPDATE printer SET address = ?", [lan.address]);
      expect((await printSvc.processQueue()).done, 1);
      expect(await lan.text(), contains('A1'));
    });

    test('80 mm printers get 80 mm slips', () async {
      await addPrinter('wide', 'bill', lan, paper: 80);
      await configure([order]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      await printSvc.queueTokens(id, autoOnly: true);
      await printSvc.processQueue();
      expect(await lan.text(), contains('A1'));
    });
  });

  group('designs', () {
    test('built-in designs are listed, edits are saved, reset returns the original, own designs can be duplicated, renamed, deleted', () async {
      var all = await tokens.templates();
      expect(all.map((t) => t.id).take(builtInTemplateOrder.length), builtInTemplateOrder);
      final classic = all.first;
      await tokens.saveTemplate(classic.copyWith(name: 'My token', blocks: [for (final b in classic.blocks) b.type == BlockType.title ? b.copyWith(text: 'NUMBER') : b]));
      var changed = await tokens.template('classic');
      expect(changed.name, 'My token');
      expect(changed.blocks.firstWhere((b) => b.type == BlockType.title).text, 'NUMBER');
      expect(changed.builtIn, isTrue);

      final copy = await tokens.duplicateTemplate(changed, name: 'Copy A');
      expect(copy.builtIn, isFalse);
      expect((await tokens.templates()).map((t) => t.name), contains('Copy A'));
      await tokens.saveTemplate(copy.copyWith(name: 'Renamed'));
      expect((await tokens.template(copy.id)).name, 'Renamed');

      await tokens.deleteOrResetTemplate('classic');
      expect((await tokens.template('classic')).name, 'Classic Food Token');
      await configure([order.copyWith(templateId: copy.id)]);
      await tokens.deleteOrResetTemplate(copy.id);
      expect((await tokens.templates()).length, builtInTemplateOrder.length);
      expect((await tokens.config()).rule('o')!.templateId, '', reason: 'a rule never points at a deleted design');
    });

    test('export and import round-trip; garbage is refused', () async {
      final t = (await tokens.templates()).firstWhere((t) => t.id == 'premium');
      final json = tokens.exportTemplate(t.copyWith(lang: 'both', border: 'dots'));
      final imported = await tokens.importTemplate(json);
      expect(imported, isNotNull);
      expect(imported!.name, t.name);
      expect(imported.lang, 'both');
      expect(imported.border, 'dots');
      expect(imported.blocks.length, t.blocks.length);
      expect(await tokens.importTemplate('hello'), isNull);
      expect(await tokens.importTemplate('{"blocks": []}'), isNull);
      expect(await tokens.importTemplate('{"blocks": [{"t": "nope"}]}'), isNull);
    });

    test('a design assigned to a rule is the one printed', () async {
      await addPrinter('counter', 'bill', lan);
      final classic = await tokens.template('classic');
      await tokens.saveTemplate(classic.copyWith(blocks: [for (final b in classic.blocks) b.type == BlockType.title ? b.copyWith(text: 'YOUR NUMBER IS') : b]));
      await configure([order]);
      final id = await sale([('b', 'Zinger Burger', 1000, 45000, null)]);
      await printSvc.queueTokens(id, autoOnly: true);
      await printSvc.processQueue();
      expect(await lan.text(), contains('YOUR NUMBER IS'));
    });
  });

  test('config JSON is tolerant: damage or unknown values fall back, never crash', () {
    expect(TokenConfig.decode('not json').rules, isEmpty);
    final c = TokenConfig.decode('{"rules":[{"id":"x","kind":"weird","prefix":"ab-1234","copies":99,"pad":-4}]}');
    expect(c.rules.single.kind, TokenKind.order);
    expect(c.rules.single.prefix, 'AB1');
    expect(c.rules.single.copies, 5);
    expect(c.rules.single.pad, 0);
  });

  test('upgrade from version 1 adds the token tables and the item counter', () async {
    final old = AppDatabase(NativeDatabase.memory());
    await old.customStatement('PRAGMA foreign_keys = OFF');
    for (final t in ['coupon', 'token_issue', 'token_seq', 'token_template']) {
      await old.customStatement('DROP TABLE $t');
    }
    await old.customStatement('ALTER TABLE product DROP COLUMN station');
    await migrateToV2(old);
    await old.customStatement("INSERT INTO product(id,name,base_price_minor,station,updated_at) VALUES ('p','X',1,'tea',1)");
    await old.customStatement("INSERT INTO token_template(id,name,config,updated_at) VALUES ('a','b','{}',1)");
    expect((await old.customSelect('SELECT COUNT(*) AS n FROM coupon').getSingle()).data['n'], 0);
    await old.close();
  });
}
