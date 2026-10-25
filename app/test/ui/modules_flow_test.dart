import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/features/pos/cart.dart';
import 'package:dt_food_pos/app/whatsapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

final waSent = <(String, String)>[];

Future<Harness> start(WidgetTester t, {bool tablet = false, FakeShare? share}) async {
  final db = newDb();
  await seedBusiness(db);
  waSent.clear();
  final h = await pumpApp(t, db: db, tablet: tablet, share: share, extra: [
    whatsAppOpenerProvider.overrideWithValue((phone, text) async {
      waSent.add((phone, text));
      return true;
    }),
  ]);
  await signIn(t, 'Ali', '1234');
  await tapKey(t, 'open-shift');
  await tapKey(t, 'amount-ok');
  return h;
}

Future<void> add(WidgetTester t, String product, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tapProduct(t, product);
  }
  await t.pumpAndSettle();
}

Future<void> form(WidgetTester t, Map<String, String> values) async {
  for (final e in values.entries) {
    await typeInto(t, find.byKey(ValueKey('f-${e.key}')), e.value);
  }
}

Future<void> pay(WidgetTester t, String method, {String? amount}) async {
  await tapKey(t, 'open-cart');
  await tapKey(t, 'charge');
  await tapKey(t, 'method-$method');
  if (amount != null) await typeInto(t, find.byKey(const ValueKey('pay-0')), amount);
  await tapKey(t, 'confirm-payment');
  await tapKey(t, 'new-sale');
}

Text text(WidgetTester t, String key) => t.widget<Text>(find.byKey(ValueKey(key)));

Future<int> n(Harness h, String q) async => (await h.db.customSelect(q).getSingle()).data['n'] as int;

void main() {
  reportUiTests();
  testWidgets('tables: build a floor, start an order on a table, come back to it, settle frees it', (t) async {
    final h = await start(t);
    await openTab(t, 'tables', 'Tables');
    expect(find.text('No tables yet. Add an area and tables.'), findsOneWidget);
    await tapKey(t, 'add-area');
    await form(t, {'name': 'Hall'});
    await tapKey(t, 'form-ok');
    await tapKey(t, 'add-table');
    await form(t, {'label': 'T1', 'seats': '4'});
    await tapKey(t, 'form-ok');
    await tapKey(t, 'add-table');
    await form(t, {'label': 'T2'});
    await tapKey(t, 'form-ok');
    await shot(t, '40_tables');
    expect(find.byKey(const ValueKey('table-T1')), findsOneWidget);

    // duplicate label is refused inside the dialog
    await tapKey(t, 'add-table');
    await form(t, {'label': 't1'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('form-error')), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    await tapKey(t, 'table-T1'); // free table: goes to Sell with the table attached
    expect(find.byKey(const ValueKey('pick-table')), findsNothing); // narrow: cart bar, not the cart panel
    await add(t, 'Zinger Burger', times: 2);
    expect(h.container.read(cartProvider).tableId, isNotNull);
    expect(h.container.read(cartProvider).orderType, 'dine_in');
    await openTab(t, 'tables', 'Tables');
    expect(text(t, 'table-total-T1').data, 'PKR 900.00');
    expect(find.descendant(of: find.byKey(const ValueKey('table-T1')), matching: find.text('Occupied')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('count-occupied')), matching: find.text('1')), findsOneWidget);

    // restart from the table: the order is still there
    await tapKey(t, 'table-T1');
    expect(h.container.read(cartProvider).items.single.qtyMilli, 2000);
    await pay(t, 'Cash', amount: '900');
    await openTab(t, 'tables', 'Tables');
    expect(find.byKey(const ValueKey('table-total-T1')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('table-T1')), matching: find.text('Occupied')), findsNothing);
  });

  testWidgets('hold an order, serve someone else, resume the held one', (t) async {
    final h = await start(t, tablet: true);
    await add(t, 'Fries', times: 2);
    await tapKey(t, 'hold');
    expect(h.container.read(cartProvider).isEmpty, isTrue);
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'held'"), 1);
    await add(t, 'Cola 500ml');
    await tapKey(t, 'held');
    await shot(t, '41_held');
    final heldTile = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('held-'));
    await t.tap(heldTile);
    await t.pumpAndSettle();
    // the held order is back; the cola order we were in the middle of was put on hold, not lost
    expect(h.container.read(cartProvider).items.single.name, 'Fries');
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'held'"), 1);
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'draft'"), 1);
  });

  testWidgets('bills: search, reprint marked DUPLICATE on the printer, share, partial refund with a reason, void', (t) async {
    final share = FakeShare();
    final h = await start(t, share: share);
    // a LAN printer that records what it gets
    final server = await t.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    addTearDown(() => server!.close());
    final got = <Uint8List>[];
    server!.listen((c) {
      final b = BytesBuilder();
      c.listen(b.add, onDone: () => got.add(b.toBytes()));
    });
    await h.db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('p','P','lan','127.0.0.1:${server.port}',58,'bill',1)");

    await add(t, 'Zinger Burger', times: 2);
    await pay(t, 'Cash', amount: '900');
    await add(t, 'Fries');
    await pay(t, 'Card');

    await openTab(t, 'bills', 'Bills');
    expect(find.byKey(const ValueKey('bill-INV-20260112-0001')), findsOneWidget);
    expect(find.byKey(const ValueKey('bill-INV-20260112-0002')), findsOneWidget);
    await typeInto(t, find.byKey(const ValueKey('bill-search')), '0002');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('bill-INV-20260112-0001')), findsNothing);
    await typeInto(t, find.byKey(const ValueKey('bill-search')), '');
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('bill-INV-20260112-0001')));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.textContaining('2 x Zinger Burger')), findsOneWidget);
    await shot(t, '42_bill_detail');

    await tapKey(t, 'bill-share');
    expect(share.shared.single, contains('INV-20260112-0001'));

    // WhatsApp: number typed as a local number goes out in international form, message = the receipt
    await tapKey(t, 'bill-whatsapp');
    await t.enterText(find.byKey(const ValueKey('wa-phone')), '0300-1234567');
    await tapKey(t, 'wa-phone-ok');
    expect(waSent.single.$1, '923001234567');
    expect(waSent.single.$2, contains('2 x Zinger Burger'));

    // the receipt as a picture
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('bill-image')));
      for (var i = 0; i < 40 && share.files.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    expect(share.files.single, endsWith('.png'));
    expect(File(share.files.single).readAsBytesSync().take(4), [0x89, 0x50, 0x4E, 0x47]);

    got.clear(); // the two sales above were also printed automatically; only look at the reprint
    await tapKey(t, 'bill-reprint');
    bool hasDuplicate() => got.any((b) => latin1.decode(b, allowInvalid: true).contains('*** DUPLICATE ***'));
    for (var i = 0; i < 40 && !hasDuplicate(); i++) {
      await t.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(hasDuplicate(), isTrue);
    expect(await n(h, "SELECT COUNT(*) AS n FROM audit_log WHERE event = 'bill.reprint'"), 1);

    // partial refund needs a reason
    await tapKey(t, 'bill-refund');
    await form(t, {'amount': '100'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('form-error')), findsOneWidget); // reason missing
    await form(t, {'reason': 'Cold food'});
    await tapKey(t, 'form-ok');
    expect(await n(h, 'SELECT COUNT(*) AS n FROM refund'), 1);
    expect((await h.db.customSelect('SELECT amount_minor FROM refund').getSingle()).data['amount_minor'], 10000);

    // void the other (card) bill entirely
    await t.tap(find.byKey(const ValueKey('bill-INV-20260112-0002')));
    await t.pumpAndSettle();
    await tapKey(t, 'bill-void');
    await form(t, {'reason': 'Customer left'});
    await tapKey(t, 'form-ok');
    expect((await h.db.customSelect("SELECT status FROM \"order\" WHERE invoice_no = 'INV-20260112-0002'").getSingle()).data['status'], 'void');
    await shot(t, '43_bills');
  });

  testWidgets('udhaar: add a customer, sell on credit, see what they owe, receive payment', (t) async {
    final h = await start(t);
    await openTab(t, 'customers', 'Customers');
    await tapKey(t, 'add-customer');
    await form(t, {'name': 'Ahmed', 'phone': '0300-1111111', 'limit': '2000'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('customer-Ahmed')), findsOneWidget);

    await openTab(t, 'pos', 'POS');
    await add(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    // credit is always offered; with no customer chosen the cashier is asked (customer, or the Walk-in credit account): never silently lost
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Credit (udhaar)');
    await tapKey(t, 'confirm-payment');
    expect(find.byKey(const ValueKey('credit-walkin')), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'paid'"), 0, reason: 'cancelled: nothing was sold');
    await t.tapAt(const Offset(10, 10)); // dismiss the sheet
    await t.pumpAndSettle();
    await tapKey(t, 'pick-customer');
    await tapKey(t, 'pick-Ahmed');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Credit (udhaar)');
    await tapKey(t, 'confirm-payment');
    await tapKey(t, 'new-sale');
    expect(h.container.read(cartProvider).isEmpty, isTrue);

    await openTab(t, 'customers', 'Customers');
    expect(text(t, 'udhaar-total').data, 'PKR 450.00', reason: 'the summary strip shows the total owed');
    await t.tap(find.byKey(const ValueKey('customer-Ahmed')));
    await t.pumpAndSettle();
    expect(text(t, 'cust-balance').data, contains('PKR 450.00'));
    await tapKey(t, 'receive-payment');
    await form(t, {'amount': '200'});
    await tapKey(t, 'form-ok');
    expect(text(t, 'cust-balance').data, contains('PKR 250.00'));
    await shot(t, '44_udhaar');
    await tapKey(t, 'udhaar-reminder');
    if (find.byKey(const ValueKey('wa-phone')).evaluate().isNotEmpty) {
      await t.enterText(find.byKey(const ValueKey('wa-phone')), '03001112223');
      await tapKey(t, 'wa-phone-ok');
    }
    expect(waSent.last.$1, startsWith('92'));
    expect(waSent.last.$2, allOf(contains('Ahmed'), contains('PKR 250.00'), contains('Burger Point')));
    // paying more than owed is refused
    await tapKey(t, 'receive-payment');
    await form(t, {'amount': '999'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('form-error')), findsOneWidget);
  });

  testWidgets('udhaar: a credit sale with no customer goes to the Walk-in credit account; the statement shows bills and payments with a running balance', (t) async {
    final h = await start(t);
    await openTab(t, 'pos', 'POS');
    await add(t, 'Zinger Burger');
    await tapKey(t, 'open-cart');
    await tapKey(t, 'charge');
    await tapKey(t, 'method-Credit (udhaar)');
    await tapKey(t, 'confirm-payment');
    await tapKey(t, 'credit-walkin');
    await tapKey(t, 'new-sale');
    expect(await n(h, "SELECT COUNT(*) AS n FROM customer WHERE name = 'Walk-in credit'"), 1);
    expect(await n(h, "SELECT SUM(amount_minor) AS n FROM customer_ledger"), 45000, reason: 'the credit is on the ledger, not lost');

    await openTab(t, 'customers', 'Customers');
    await tapKey(t, 'owing-only');
    await t.tap(find.byKey(const ValueKey('customer-Walk-in credit')));
    await t.pumpAndSettle();
    expect(find.textContaining('INV-'), findsWidgets, reason: 'the ledger shows the bill number of the credit sale');
    await tapKey(t, 'receive-payment');
    await form(t, {'amount': '150'});
    await tapKey(t, 'form-ok');
    await tapKey(t, 'customer-statement');
    expect(find.byKey(const ValueKey('receipt-paper')), findsOneWidget);
    final paper = receiptPaperText(t);
    expect(paper, allOf(contains('CREDIT STATEMENT'), contains('Walk-in credit'), contains('450.00'), contains('-150.00'), contains('BALANCE DUE'), contains('300.00')));
    expect(find.byKey(const ValueKey('slip-csv')), findsOneWidget, reason: 'the statement can be exported for Excel');
  });

  testWidgets('expenses: a cash expense is added and shows in the total', (t) async {
    final h = await start(t);
    await openTab(t, 'expenses', 'Expenses');
    await tapKey(t, 'add-expense');
    await form(t, {'amount': '300', 'category': 'Gas'});
    await tapKey(t, 'form-ok');
    expect(text(t, 'exp-total').data, 'PKR 300.00');
    expect(find.text('Gas'), findsOneWidget);
    // the cash left the drawer: closing the shift with 0 counted is short by exactly 300
    expect(await n(h, "SELECT COUNT(*) AS n FROM cash_movement WHERE direction = 'out' AND amount_minor = 30000"), 1);
  });

  testWidgets('print settings: KOT, token and bill have separate switches; the choices are saved and the Send to kitchen menu follows them', (t) async {
    final h = await start(t);
    await openTab(t, 'settings', 'Settings');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('print-settings-tile')), 300, scrollable: verticalScroll);
    await Scrollable.ensureVisible(t.element(find.byKey(const ValueKey('print-settings-tile'))), alignment: 0.4);
    await t.pumpAndSettle();
    await tapKey(t, 'print-settings-tile');
    expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('ps-kot-enabled'))).value, isTrue);

    await tapKey(t, 'ps-token-auto'); // token: only by hand
    await tapKey(t, 'ps-kot-enabled'); // KOT: never
    var cfg = h.container.read(printSettingsProvider).value!;
    expect([cfg.kotEnabled, cfg.autoToken, cfg.tokenEnabled, cfg.billEnabled], [false, false, true, true]);
    expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('ps-kot-auto'))).onChanged, isNull, reason: 'automatic KOT cannot be on while KOT is off');
    final saved = await t.runAsync(() => h.db.customSelect("SELECT setting_value AS v FROM setting WHERE setting_key = 'print.config'").getSingle());
    expect(saved!.data['v'], contains('"kotEnabled":false'));

    await tapKey(t, 'ps-kot-enabled');
    await t.scrollUntilVisible(find.byKey(const ValueKey('ps-counter-bill')), 200, scrollable: verticalScroll);
    await Scrollable.ensureVisible(t.element(find.byKey(const ValueKey('ps-counter-bill'))), alignment: 0.4);
    await t.pumpAndSettle();
    await tapKey(t, 'ps-counter-bill'); // counter sales: no automatic bill
    cfg = h.container.read(printSettingsProvider).value!;
    expect([cfg.autoKotFor('counter'), cfg.autoBillFor('counter'), cfg.autoBillFor('takeaway')], [true, false, true]);
  });

  testWidgets('online orders: type in a WhatsApp order, accept it into the kitchen, then take payment in Sell', (t) async {
    final h = await start(t);
    await openTab(t, 'online', 'Online orders');
    expect(find.text('No online orders'), findsOneWidget);
    await tapKey(t, 'new-online');
    await t.enterText(find.byKey(const ValueKey('on-name')), 'Ahmed');
    await t.enterText(find.byKey(const ValueKey('on-phone')), '03001234567');
    await t.enterText(find.byKey(const ValueKey('on-address')), 'House 5');
    await tapKey(t, 'on-save');
    expect(find.byKey(const ValueKey('on-error')), findsOneWidget, reason: 'an order needs at least one item');
    await Scrollable.ensureVisible(t.element(find.byKey(const ValueKey('on-plus-Zinger Burger'))), alignment: 0.3);
    await t.pumpAndSettle();
    await tapKey(t, 'on-plus-Zinger Burger');
    await tapKey(t, 'on-plus-Zinger Burger');
    await tapKey(t, 'on-save');
    expect(find.text('Waiting (1)'), findsOneWidget);
    expect(find.textContaining('2 x Zinger Burger'), findsOneWidget);
    expect(find.textContaining('House 5'), findsOneWidget);
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE source = 'online' AND status = 'held'"), 1);

    final accept = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('accept-'));
    await t.tap(accept);
    await t.pumpAndSettle();
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE source = 'online' AND status = 'new'"), 1, reason: 'accepted = in the kitchen');
    expect(find.text('Accepted'), findsOneWidget);

    final pay = find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('pay-'));
    await t.tap(pay);
    await t.pumpAndSettle();
    expect(h.container.read(cartProvider).items.single.qtyMilli, 2000);
    expect(h.container.read(cartProvider).orderType, 'delivery');
  });

  testWidgets('purchase orders: order from a supplier, receive it, stock goes up; a received order has no more actions', (t) async {
    final h = await start(t);
    await openTab(t, 'inventory', 'Inventory');
    await tapKey(t, 'add-stock');
    await form(t, {'name': 'Flour', 'open': '0', 'cost': '100', 'reorder': '5'});
    await tapKey(t, 'form-ok');
    await t.tap(find.byKey(const ValueKey('tab-po')));
    await t.pumpAndSettle();
    expect(find.text('No purchase orders yet'), findsOneWidget);
    await tapKey(t, 'add-po');
    final qtyField = find.byWidgetPredicate((w) => w is TextField && (w.decoration?.labelText ?? '').startsWith('Flour'));
    await t.enterText(qtyField, '20');
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('po-PO-0001')), findsOneWidget);
    expect(text(t, 'po-status-PO-0001').data, 'Draft');
    expect(await n(h, "SELECT COUNT(*) AS n FROM stock_movement WHERE reason = 'purchase'"), 0);

    await tapKey(t, 'po-menu-PO-0001');
    await t.tap(find.text('Goods received').last);
    await t.pumpAndSettle();
    await form(t, {'paid': '2000'});
    await tapKey(t, 'form-ok');
    expect(text(t, 'po-status-PO-0001').data, 'Received');
    expect(find.byKey(const ValueKey('po-menu-PO-0001')), findsNothing);
    expect(await n(h, "SELECT COUNT(*) AS n FROM stock_movement WHERE reason = 'purchase'"), 1);
  });

  testWidgets('expenses: the category is optional (amount only is enough), saved categories are one tap, and they can be deleted', (t) async {
    final h = await start(t);
    await openTab(t, 'expenses', 'Expenses');
    await tapKey(t, 'add-expense');
    await t.enterText(find.byKey(const ValueKey('f-amount')), '120');
    await tapKey(t, 'form-ok'); // no category, no note
    expect(text(t, 'exp-total').data, 'PKR 120.00');
    expect(find.text('No category'), findsOneWidget);
    expect(await n(h, 'SELECT COUNT(*) AS n FROM expense WHERE category_id IS NULL'), 1);

    await tapKey(t, 'add-expense');
    await t.enterText(find.byKey(const ValueKey('f-amount')), '80');
    await t.enterText(find.byKey(const ValueKey('f-category')), 'Gas');
    await tapKey(t, 'form-ok');
    expect(text(t, 'exp-total').data, 'PKR 200.00');

    await tapKey(t, 'add-expense');
    expect(find.byKey(const ValueKey('exp-cat-Gas')), findsOneWidget, reason: 'the saved category is one tap');
    await tapKey(t, 'exp-cat-Gas');
    expect(t.widget<TextField>(find.byKey(const ValueKey('f-category'))).controller!.text, 'Gas');
    await t.tapAt(const Offset(10, 10)); // close the sheet
    await t.pumpAndSettle();

    await tapKey(t, 'manage-categories');
    await tapKey(t, 'cat-delete-Gas');
    expect(find.byKey(const ValueKey('cat-Gas')), findsNothing);
    expect(await n(h, 'SELECT COUNT(*) AS n FROM expense_category WHERE deleted_at IS NULL'), 0);
    expect(await n(h, 'SELECT COUNT(*) AS n FROM expense'), 2, reason: 'old expenses are untouched');
  });

  testWidgets('inventory: add stock, buy, waste, count, low-stock filter and stock value', (t) async {
    final h = await start(t);
    await openTab(t, 'inventory', 'Inventory');
    await tapKey(t, 'add-stock');
    await form(t, {'name': 'Flour', 'open': '10', 'cost': '100', 'reorder': '5'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('stock-Flour')), findsOneWidget);
    expect(text(t, 'stock-value').data, contains('PKR 1,000.00'));

    await tapKey(t, 'stock-menu-Flour');
    await t.tap(find.text('Purchase').last);
    await t.pumpAndSettle();
    await form(t, {'qty': '10', 'cost': '140'});
    await tapKey(t, 'form-ok');
    expect(text(t, 'stock-value').data, contains('PKR 2,400.00')); // 20 kg at the new average cost of 120

    await tapKey(t, 'stock-menu-Flour');
    await t.tap(find.text('Wastage').last);
    await t.pumpAndSettle();
    await form(t, {'qty': '12'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('form-error')), findsOneWidget); // reason required
    await form(t, {'reason': 'Spoiled'});
    await tapKey(t, 'form-ok');
    expect(find.textContaining('On hand: 8'), findsOneWidget);
    expect(find.textContaining('Low stock'), findsWidgets);
    await shot(t, '45_inventory');

    await tapKey(t, 'low-filter');
    expect(find.byKey(const ValueKey('stock-Flour')), findsNothing); // 8 kg is above the reorder level of 5
    await tapKey(t, 'low-filter');
    await tapKey(t, 'stock-menu-Flour');
    await t.tap(find.text('Stock count').last);
    await t.pumpAndSettle();
    await form(t, {'qty': '3'});
    await tapKey(t, 'form-ok');
    await tapKey(t, 'low-filter');
    expect(find.byKey(const ValueKey('stock-Flour')), findsOneWidget);
    expect(await n(h, "SELECT COUNT(*) AS n FROM stock_movement WHERE reason = 'adjustment'"), 1);
  });

  testWidgets('staff: the owner adds a cashier who can then sign in; a cashier never sees Staff', (t) async {
    final h = await start(t);
    await openTab(t, 'staff', 'Staff');
    await tapKey(t, 'add-staff');
    await form(t, {'name': 'Sara', 'pin': '5555'});
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('staff-row-Sara')), findsOneWidget);
    await tapKey(t, 'sign-out');
    h.container.invalidate(staffListProvider);
    await t.pumpAndSettle();
    await signIn(t, 'Sara', '5555');
    expect(find.byKey(const ValueKey('open-shift')), findsOneWidget);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Staff')), findsNothing);
  });

  testWidgets('kitchen: send to kitchen prints only what was added since the last send', (t) async {
    final h = await start(t, tablet: true);
    final server = await t.runAsync(() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    addTearDown(() => server!.close());
    final got = <String>[];
    server!.listen((c) {
      final b = BytesBuilder();
      c.listen(b.add, onDone: () => got.add(latin1.decode(b.toBytes(), allowInvalid: true)));
    });
    await h.db.customStatement("INSERT INTO printer(id,name,connection,address,paper_mm,role,updated_at) VALUES ('k','K','lan','127.0.0.1:${server.port}',58,'kot',1)");

    await h.db.customStatement("INSERT INTO area(id,name,updated_at) VALUES ('ka','Hall',1)");
    await h.db.customStatement("INSERT INTO dining_table(id,area_id,label,seats,status,updated_at) VALUES ('kt','ka','K1',4,'free',1)");
    Future<void> send(int expected) async {
      await tapKey(t, 'send-kitchen');
      if (find.byKey(const ValueKey('dinein-table')).evaluate().isNotEmpty) {
        // a dine-in order asks for its table before it goes to the kitchen
        await tapKey(t, 'dinein-table');
        await t.tap(find.text('K1').last);
        await t.pumpAndSettle();
        await tapKey(t, 'dinein-ok');
      }
      for (var i = 0; i < 30 && got.length < expected; i++) {
        await t.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await t.tap(find.text('Dine-in'));
    await t.pumpAndSettle();
    await add(t, 'Zinger Burger', times: 2);
    await send(1);
    expect(got.single, contains('2 x Zinger Burger'));
    // sent: the cart is clear for the next customer, and the order is RUNNING (same order as its bill), in the kitchen exactly once
    expect(h.container.read(cartProvider).items, isEmpty);
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\" WHERE status = 'new'"), 1);
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\""), 1, reason: 'one order, not a bill plus a separate kitchen copy');

    Future<void> continueRunning() async {
      await openTab(t, 'bills', 'Bills');
      await tapKey(t, 'billtab-running');
      await t.tap(find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('bill-#')));
      await t.pumpAndSettle();
      await tapKey(t, 'running-resume');
    }

    // continue the running order, add Fries: only the new item goes to the kitchen
    await continueRunning();
    expect(h.container.read(cartProvider).items.single.qtyMilli, 2000);
    await add(t, 'Fries');
    await send(2);
    expect(got.last, contains('1 x Fries'));
    expect(got.last, isNot(contains('Zinger')));
    expect(await n(h, "SELECT COUNT(*) AS n FROM \"order\""), 1, reason: 'still the same single order');

    // more of an item already sent: only the extra portion is printed
    await continueRunning();
    await add(t, 'Zinger Burger');
    await send(3);
    expect(got.last, contains('1 x Zinger Burger'));
    expect(got.last, isNot(contains('2 x Zinger')));
    expect(got.last, isNot(contains('Fries')));

    // nothing new on a resumed order: nothing is printed (a double tap or retry never makes a second ticket)
    await continueRunning();
    await tapKey(t, 'send-kitchen');
    await t.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 50));
    expect(got.length, 3);
    expect(find.text('Nothing new to send to the kitchen'), findsOneWidget);
  });
}

void reportUiTests() {
  testWidgets('reports: item, category and cashier tabs, expenses and result, CSV export to the share sheet', (t) async {
    final share = FakeShare();
    final h = await start(t, share: share);
    await add(t, 'Zinger Burger', times: 2);
    await add(t, 'Cola 500ml');
    await pay(t, 'Cash', amount: '1000');
    await openTab(t, 'expenses', 'Expenses');
    await tapKey(t, 'add-expense');
    await form(t, {'amount': '200', 'category': 'Gas'});
    await tapKey(t, 'form-ok');

    await openTab(t, 'reports', 'Reports');
    expect(text(t, 'stat-gross').data, 'PKR 1,000.00');
    expect(text(t, 'stat-expenses').data, 'PKR 200.00');
    expect(text(t, 'stat-result').data, 'PKR 800.00');
    await shot(t, '52_report_summary');

    await t.tap(find.text('Items'));
    await t.pumpAndSettle();
    expect(find.text('Zinger Burger'), findsOneWidget);
    expect(find.textContaining('Qty: 2'), findsOneWidget);
    await tapKey(t, 'export-Items');
    final csv = File(share.files.single).readAsStringSync();
    expect(csv, contains('Item,Quantity,Bills,Amount'));
    expect(csv, contains('Zinger Burger,2,1,900.00'));

    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('export-pdf')));
      for (var i = 0; i < 50 && share.files.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
    });
    final pdf = File(share.files.last).readAsBytesSync();
    expect(share.files.last, endsWith('.pdf'));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(2000));

    await t.tap(find.text('Categories'));
    await t.pumpAndSettle();
    expect(find.text('Burgers'), findsOneWidget);
    await t.tap(find.text('Cashiers'));
    await t.pumpAndSettle();
    expect(find.text('Ali'), findsWidgets);
    expect(h.container.read(cartProvider).isEmpty, isTrue);
  });
}
