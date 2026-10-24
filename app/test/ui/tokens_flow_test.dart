import 'dart:convert';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/domain/token.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Records what each printer address receives.
class Printers {
  final got = <String, List<Uint8List>>{};
  PrinterTransport make(String connection, String? address) => _Rec(got.putIfAbsent(address ?? '', () => []));
  String text(String address) => got[address]?.map((b) => latin1.decode(b, allowInvalid: true)).join('\n') ?? '';
}

class _Rec implements PrinterTransport {
  _Rec(this.sink);
  final List<Uint8List> sink;
  @override
  Future<void> send(Uint8List bytes) async => sink.add(bytes);
}

Future<void> openTokensSettings(WidgetTester t) async {
  await openTab(t, 'settings', 'Settings');
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byKey(const ValueKey('tokens-settings-tile')), 300, scrollable: verticalScroll);
  await t.ensureVisible(find.byKey(const ValueKey('tokens-settings-tile')));
  await t.pumpAndSettle();
  await tapKey(t, 'tokens-settings-tile');
}

Future<void> addType(WidgetTester t, String kind, {void Function()? edit}) async {
  await tapKey(t, 'add-token-type');
  await tapKey(t, 'kind-$kind');
  edit?.call();
  await tapKey(t, 'rule-save');
}

/// Taps a control that may be scrolled out of view.
Future<void> go(WidgetTester t, String key) async {
  await Scrollable.ensureVisible(t.element(find.byKey(ValueKey(key))), alignment: 0.5);
  await t.pumpAndSettle();
  await tapKey(t, key);
}

/// Messages queue up (saved, copied...) and each stays 4 seconds; drop them so they never cover a button.
Future<void> clearSnacks(WidgetTester t) async {
  for (final e in find.byType(ScaffoldMessenger).evaluate()) {
    (e as StatefulElement).state is ScaffoldMessengerState ? ((e.state as ScaffoldMessengerState).clearSnackBars()) : null;
  }
  await t.pumpAndSettle();
}

Future<void> settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await t.pumpAndSettle();
}

Future<void> sellCash(WidgetTester t, List<String> items) async {
  for (final i in items) {
    await tapProduct(t, i);
  }
  await t.pumpAndSettle();
  await tapKey(t, 'charge');
  await tapKey(t, 'method-Cash');
  await tapKey(t, 'confirm-payment');
  await settle(t);
}

void main() {
  testWidgets('owner sets up Order + Tandoor tokens; a sale prints each to its own printer; collect and reprint work', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("UPDATE product SET station = 'Tandoor' WHERE name = 'Fries'");
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('main','Counter','lan','main',58,'bill',1)");
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,station,updated_at) VALUES ('tp','Tandoor printer','lan','tandoor',80,'kot','Tandoor',1)");
    final printers = Printers();
    final h = await pumpApp(t, db: db, tablet: true, transport: printers.make);
    await signIn(t, 'Ali', '1234');

    // nothing set up: no Tokens screen in the navigation
    expect(find.descendant(of: find.byType(NavigationRail), matching: find.text('Tokens')), findsNothing);

    await openTokensSettings(t);
    expect(find.text('No token types yet. Tap "Add token type".'), findsOneWidget);
    await addType(t, 'order');
    await addType(t, 'tandoor');
    expect(find.byKey(const ValueKey('rule-Order token')), findsOneWidget);
    expect(find.byKey(const ValueKey('rule-Tandoor')), findsOneWidget);
    final cfg = await t.runAsync(() => h.container.read(tokenServiceProvider).rawConfig());
    expect(cfg!.rules.map((r) => r.kind), [TokenKind.order, TokenKind.tandoor]);
    expect(cfg.rules.last.station, 'Tandoor');
    expect(cfg.rules.last.prefix, 'T');
    await shot(t, '60_token_types');
    await t.pageBack();
    await t.pumpAndSettle();
    await openTab(t, 'pos', 'POS');

    // sell: roti-like item for the tandoor counter + a burger
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await sellCash(t, ['Fries', 'Zinger Burger']);
    final chips = find.byKey(const ValueKey('receipt-tokens'));
    expect(chips, findsOneWidget);
    expect(find.descendant(of: chips, matching: find.textContaining('A1')), findsOneWidget);
    expect(find.descendant(of: chips, matching: find.textContaining('T1 · Tandoor')), findsOneWidget);
    await shot(t, '61_receipt_with_tokens');
    await tapKey(t, 'new-sale');

    final bill = printers.text('main');
    expect(bill, contains('Burger Point'));
    expect(bill, contains('A1'), reason: 'order token on the bill printer');
    final tandoor = printers.text('tandoor');
    expect(tandoor, contains('T1'));
    expect(tandoor, contains('Fries'));
    expect(tandoor, isNot(contains('Zinger')));
    expect(tandoor, isNot(contains('REPRINT')));

    // Tokens screen
    await openTab(t, 'tokens', 'Tokens');
    expect(find.byKey(const ValueKey('token-A1-INV-20260112-0001')), findsOneWidget);
    expect(find.byKey(const ValueKey('token-T1-INV-20260112-0001')), findsOneWidget);
    await shot(t, '62_tokens_screen');
    await tapKey(t, 'token-collect-A1');
    expect(find.byKey(const ValueKey('token-A1-INV-20260112-0001')), findsNothing, reason: 'collected tokens leave the Waiting list');
    await t.tap(find.text('Collected'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('token-A1-INV-20260112-0001')), findsOneWidget);
    await t.tap(find.text('Waiting'));
    await t.pumpAndSettle();
    await tapKey(t, 'token-print-T1');
    await settle(t);
    expect(printers.text('tandoor'), contains('REPRINT'));
    expect(await t.runAsync(() => db.customSelect("SELECT print_count FROM token_issue WHERE label = 'T1'").getSingle().then((r) => r.data['print_count'])), 2);
  });

  testWidgets('tokens-only food point: bill printing off, token printed alone; module off stops tokens', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('main','Counter','lan','main',58,'bill',1)");
    final printers = Printers();
    final h = await pumpApp(t, db: db, tablet: true, transport: printers.make);
    await signIn(t, 'Ali', '1234');
    await openTokensSettings(t);
    await addType(t, 'order');
    await t.tap(find.byKey(const ValueKey('tab-options')));
    await t.pumpAndSettle();
    await tapKey(t, 'opt-print-bill');
    await t.pageBack();
    await t.pumpAndSettle();
    await openTab(t, 'pos', 'POS');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await sellCash(t, ['Zinger Burger']);
    await tapKey(t, 'new-sale');
    final text = printers.text('main');
    expect(text, contains('A1'));
    expect(text, contains('TOKEN'));
    expect(text, isNot(contains('Invoice')), reason: 'no bill, only the token');

    // the owner switches the module off: no tokens are numbered or printed, records stay
    await t.runAsync(() => h.container.read(modulesProvider.notifier).toggle('tokens', false));
    printers.got.clear();
    await sellCash(t, ['Zinger Burger']);
    await tapKey(t, 'new-sale');
    expect(await t.runAsync(() => db.customSelect('SELECT COUNT(*) AS n FROM token_issue').getSingle().then((r) => r.data['n'])), 1);
    expect(printers.text('main'), contains('Invoice'), reason: 'bill prints again: tokens module is off');
    await t.runAsync(() => h.container.read(modulesProvider.notifier).toggle('tokens', true));
    expect((await t.runAsync(() => h.container.read(tokenServiceProvider).rawConfig()))!.rules, hasLength(1), reason: 'settings are kept');
  });

  testWidgets('designs: seven ready-made designs; edit, reorder, save, reopen, reset, duplicate, rename, export, import, delete', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await openTokensSettings(t);
    await t.tap(find.byKey(const ValueKey('tab-designs')));
    await t.pumpAndSettle();
    for (final id in builtInTemplateOrder) {
      expect(find.byKey(ValueKey('design-$id')), findsOneWidget, reason: id);
    }
    await shot(t, '63_designs');

    // open the classic design: the preview shows the real slip
    await tapKey(t, 'design-classic');
    String preview() => t.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.byType(Text))).map((w) => w.data ?? '').join('\n');
    expect(preview(), allOf(contains('TOKEN'), contains('A17'), contains('Burger Point'), contains('Please wait for your number')));

    await shot(t, '65_designer_classic');
    // hide the free text block, change the heading, rename
    final order = <String>[];
    final blocks = find.byKey(const ValueKey('td-blocks'));
    expect(blocks, findsOneWidget);
    final textIdx = builtInTemplates['classic']!.blocks.indexWhere((b) => b.type == BlockType.text);
    final titleIdx = builtInTemplates['classic']!.blocks.indexWhere((b) => b.type == BlockType.title);
    await t.ensureVisible(find.byKey(ValueKey('block-show-$textIdx')));
    await tapKey(t, 'block-show-$textIdx');
    expect(preview(), isNot(contains('Please wait')));
    await t.ensureVisible(find.byKey(ValueKey('block-open-$titleIdx')));
    await tapKey(t, 'block-open-$titleIdx');
    await typeInto(t, find.byKey(ValueKey('block-text-$titleIdx')), 'YOUR NUMBER');
    expect(preview(), contains('YOUR NUMBER'));
    await typeInto(t, find.byKey(const ValueKey('td-name')), 'Counter token');
    // size and alignment of the title
    await t.ensureVisible(find.byKey(ValueKey('block-size-$titleIdx-inc')));
    await tapKey(t, 'block-size-$titleIdx-inc');
    await go(t, 'td-border-stars');
    expect(preview(), contains('***'));
    // language: bilingual shows Urdu words
    await t.ensureVisible(find.byKey(const ValueKey('td-lang')));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('td-lang')), matching: find.text('English + اردو')));
    await t.pumpAndSettle();
    expect(preview(), contains('تاریخ'));
    await shot(t, '66_designer_bilingual');
    // 80 mm paper
    await t.ensureVisible(find.byKey(const ValueKey('td-paper')));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('td-paper')), matching: find.text('80 mm')));
    await t.pumpAndSettle();
    expect(preview(), contains('A17'));
    await t.ensureVisible(find.byKey(const ValueKey('td-save')));
    await tapKey(t, 'td-save');
    await t.pageBack();
    await t.pumpAndSettle();
    order.add('saved');

    // persisted in the database, listed under the new name, and used by a rule
    var tpl = (await t.runAsync(() => h.container.read(tokenServiceProvider).template('classic')))!;
    expect(tpl.name, 'Counter token');
    expect(tpl.lang, 'both');
    expect(tpl.border, 'stars');
    expect(tpl.blocks[textIdx].show, isFalse);
    expect(tpl.blocks[titleIdx].text, 'YOUR NUMBER');
    expect(tpl.blocks[titleIdx].size, 2);
    expect(find.text('Counter token'), findsOneWidget);

    // reopen: the edits are still there
    await tapKey(t, 'design-classic');
    expect(preview(), contains('YOUR NUMBER'));

    // drag the first block to the end (visual drag and drop)
    final firstKey = find.byKey(const ValueKey('drag-0'));
    await t.ensureVisible(firstKey);
    await t.pumpAndSettle();
    final start = t.getCenter(firstKey);
    final gesture = await t.startGesture(start);
    await t.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 140));
    await t.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 140));
    await t.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('block-0-logo')), findsNothing, reason: 'the logo block moved down');
    await t.ensureVisible(find.byKey(const ValueKey('td-save')));
    await tapKey(t, 'td-save');
    tpl = (await t.runAsync(() => h.container.read(tokenServiceProvider).template('classic')))!;
    expect(tpl.blocks.first.type, isNot(BlockType.logo));
    expect(tpl.blocks.map((b) => b.type).toSet(), builtInTemplates['classic']!.blocks.map((b) => b.type).toSet());

    // reset to original from the editor
    await tapKey(t, 'td-reset');
    await tapKey(t, 'confirm-ok');
    expect(preview(), contains('Please wait for your number'));
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Classic Food Token'), findsOneWidget);

    // duplicate -> own design -> rename -> export -> delete
    await go(t, 'design-menu-premium');
    await t.tap(find.text('Duplicate'));
    await t.pumpAndSettle();
    expect(find.textContaining('Premium Branded Token copy'), findsOneWidget);
    final own = (await t.runAsync(() => h.container.read(tokenServiceProvider).templates()))!.firstWhere((d) => !d.builtIn);
    await go(t, 'design-${own.id}');
    await typeInto(t, find.byKey(const ValueKey('td-name')), 'Eid token');
    await t.ensureVisible(find.byKey(const ValueKey('td-save')));
    await tapKey(t, 'td-save');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Eid token'), findsOneWidget);

    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': copied};
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await go(t, 'design-menu-${own.id}');
    await t.tap(find.text('Copy design (export)'));
    await t.pumpAndSettle();
    expect(copied, contains('dt-token-template-1'));
    expect(copied, contains('Eid token'));

    // import it back as a second copy; garbage is refused
    await clearSnacks(t);
    await go(t, 'design-import');
    await t.enterText(find.byKey(const ValueKey('design-import-field')), 'not a design');
    await tapKey(t, 'design-import-go');
    expect(find.text('This is not a token design.'), findsOneWidget);
    await clearSnacks(t);
    await go(t, 'design-import');
    await t.enterText(find.byKey(const ValueKey('design-import-field')), copied!);
    await tapKey(t, 'design-import-go');
    expect(find.text('Eid token'), findsNWidgets(2));
    expect((await t.runAsync(() => h.container.read(tokenServiceProvider).templates()))!.where((d) => d.name == 'Eid token'), hasLength(2));

    // delete an own design
    await go(t, 'design-menu-${own.id}');
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.text('Eid token'), findsOneWidget);
  });

  testWidgets('a rule can use any design and a chosen printer; its test print and the design test print reach the printer', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('main','Counter','lan','main',58,'bill',1)");
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,station,updated_at) VALUES ('tea','Tea bar','lan','tea',58,'kot','Tea',1)");
    final printers = Printers();
    final h = await pumpApp(t, db: db, tablet: true, transport: printers.make);
    await signIn(t, 'Ali', '1234');
    await openTokensSettings(t);
    await tapKey(t, 'add-token-type');
    await tapKey(t, 'kind-unit');
    await typeInto(t, find.byKey(const ValueKey('rule-station')), 'Tea');
    await typeInto(t, find.byKey(const ValueKey('rule-prefix')), 'u');
    await tapKey(t, 'rule-pad');
    await t.tap(find.descendant(of: find.byKey(const ValueKey('rule-pad')), matching: find.text('001')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('rule-example'))).data, startsWith('Example: U001, U002'));
    await t.tap(find.byKey(const ValueKey('rule-design')));
    await t.pumpAndSettle();
    await t.tap(find.text('Premium Branded Token').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rule-printer')));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Tea bar').last);
    await t.pumpAndSettle();
    await tapKey(t, 'rule-copies-inc');
    await tapKey(t, 'rule-test');
    await settle(t);
    final test = printers.text('tea');
    expect(test, contains('U001'));
    expect(test, contains('YOUR TOKEN'), reason: 'the premium design');
    expect('U001'.allMatches(test).length, 2, reason: 'two copies');
    expect(printers.text('main'), isEmpty);
    await tapKey(t, 'rule-save');
    final r = (await t.runAsync(() => h.container.read(tokenServiceProvider).rawConfig()))!.rules.single;
    expect([r.kind, r.prefix, r.pad, r.station, r.templateId, r.printerId, r.copies], [TokenKind.unit, 'U', 3, 'Tea', 'premium', 'tea', 2]);

    // printers list: test print button
    await t.pageBack();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('printer-test-Counter')), 300, scrollable: verticalScroll);
    await t.drag(verticalScroll, const Offset(0, -160));
    await t.pumpAndSettle();
    await tapKey(t, 'printer-test-Counter');
    await settle(t);
    expect(printers.text('main'), contains('A17'));
    expect(printers.text('main'), contains('Powered by Digital Target'));
  });

  testWidgets('prepaid coupons: sold, printed with a code, redeemed once, a second try is refused', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await db.customStatement("UPDATE product SET station = 'Coupon' WHERE name = 'Fries'");
    await db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('main','Counter','lan','main',58,'bill',1)");
    final printers = Printers();
    final h = await pumpApp(t, db: db, tablet: true, transport: printers.make);
    await signIn(t, 'Ali', '1234');
    await openTokensSettings(t);
    await addType(t, 'coupon');
    await t.pageBack();
    await t.pumpAndSettle();
    await openTab(t, 'pos', 'POS');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await sellCash(t, ['Fries']);
    await tapKey(t, 'new-sale');
    final code = (await t.runAsync(() => db.customSelect('SELECT code FROM coupon').getSingle().then((r) => r.data['code'] as String)))!;
    expect(printers.text('main'), contains(code));
    expect(printers.text('main'), contains('PREPAID COUPON'));

    await openTab(t, 'tokens', 'Tokens');
    await tapKey(t, 'redeem-coupon');
    await t.enterText(find.byType(TextField).last, code.toLowerCase());
    await t.tap(find.text('Redeem').last);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('redeem-result'))).data, startsWith('Coupon accepted: Fries'));
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await tapKey(t, 'redeem-coupon');
    await t.enterText(find.byType(TextField).last, code);
    await t.tap(find.text('Redeem').last);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('redeem-result'))).data, startsWith('Already used'));
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await tapKey(t, 'redeem-coupon');
    await t.enterText(find.byType(TextField).last, 'CP-AAAAA-BBBBB');
    await t.tap(find.text('Redeem').last);
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('redeem-result'))).data, 'No such coupon');
    expect(h.container.read(tokenServiceProvider), isNotNull);
  });

  testWidgets('menu: a category counter and an item counter route items; printers get a counter', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'menu', 'Menu');
    await tapKey(t, 'import-csv'); // sanity: dialogs open
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu-Fries')));
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('item-counter')), 'Tandoor');
    await tapKey(t, 'item-save');
    var products = (await t.runAsync(() => db.customSelect("SELECT station FROM product WHERE name = 'Fries'").getSingle()))!;
    expect(products.data['station'], 'Tandoor');
    // the item keeps following its category when the counter is cleared
    await t.tap(find.byKey(const ValueKey('menu-Fries')));
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('item-counter')), '');
    await tapKey(t, 'item-save');
    products = (await t.runAsync(() => db.customSelect("SELECT station FROM product WHERE name = 'Fries'").getSingle()))!;
    expect(products.data['station'], isNull);

    await tapKey(t, 'categories');
    await tapKey(t, 'category-counter-Burgers');
    await typeInto(t, find.byKey(const ValueKey('category-counter-field')), 'BBQ');
    await tapKey(t, 'category-counter-save');
    expect((await t.runAsync(() => db.customSelect("SELECT station FROM category WHERE name = 'Burgers'").getSingle()))!.data['station'], 'BBQ');
    final burger = (await t.runAsync(() => h.container.read(productsProvider(const ProductFilter()).future)))!.firstWhere((p) => p.name == 'Zinger Burger');
    expect(burger.station, 'BBQ');
    expect(burger.ownStation, isNull);
  });

  testWidgets('bill designer: choose a ready-made 58 mm style; it previews, saves and prints', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final h = await pumpApp(t, db: db, tablet: true);
    await signIn(t, 'Ali', '1234');
    await openTab(t, 'settings', 'Settings');
    await t.scrollUntilVisible(find.byKey(const ValueKey('receipt-design-tile')), 250, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('receipt-design-tile')));
    await t.pumpAndSettle();
    await tapKey(t, 'receipt-design-tile');
    String preview() => t.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.byType(Text))).map((w) => w.data ?? '').join('\n');
    expect(preview(), isNot(contains('PRE-PAYMENT BILL')));
    await go(t, 'bill-style-boxed');
    expect(preview(), allOf(contains('PRE-PAYMENT BILL'), contains('Rate'), contains('ONLY'), contains('A17')));
    await shot(t, '64_bill_boxed');
    await go(t, 'bill-style-modern');
    expect(preview(), contains('- Burger Point -'));
    await go(t, 'bill-style-compact');
    await t.ensureVisible(find.byKey(const ValueKey('sw-token')));
    await go(t, 'sw-token');
    expect(preview(), isNot(contains('A17')));
    await go(t, 'bill-style-boxed');
    await typeInto(t, find.byKey(const ValueKey('rd-title')), 'TAX INVOICE');
    expect(preview(), contains('TAX INVOICE'));
    await t.ensureVisible(find.byKey(const ValueKey('rd-save')));
    await tapKey(t, 'rd-save');
    final d = (await t.runAsync(() => h.container.read(receiptTemplateStoreProvider).load()))!;
    expect([d.style, d.title, d.amountInWords, d.showItemCount], ['boxed', 'TAX INVOICE', true, true]);
  });
}
