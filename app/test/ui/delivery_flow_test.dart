import 'package:dt_food_pos/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

Finder _byPrefix(String p) => find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith(p));

void main() {
  testWidgets('delivery orders: sources, a Foodpanda order with its reference, confirm, prepare, ready, dispatch with a rider, deliver, messages, history and the source report', (t) async {
    final db = newDb();
    final owner = await seedBusiness(db);
    final share = FakeShare();
    final h = await pumpApp(t, db: db, share: share);
    await db.customStatement("INSERT INTO team_member(id,kind,name,phone,updated_at) VALUES ('rd','rider','Kamran','03111111111',1)");
    await db.customStatement("INSERT INTO payment_method(id,name,kind,provider,account_no,holder,updated_at) VALUES ('bk','Meezan Bank','bank','Meezan','0123-4567','Burger Point',1)");
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await openTab(t, 'online', 'Delivery Orders');
    expect(find.text('No delivery orders'), findsOneWidget);

    // sources: add one of our own
    await tapKey(t, 'open-sources');
    expect(find.byKey(const ValueKey('source-Foodpanda')), findsOneWidget);
    await tapKey(t, 'add-source');
    await t.enterText(find.byKey(const ValueKey('f-name')), 'Cheetay');
    await tapKey(t, 'src-platform');
    await tapKey(t, 'form-ok');
    expect(find.byKey(const ValueKey('source-Cheetay')), findsOneWidget);
    await shot(t, '99_order_sources');
    await t.pageBack();
    await t.pumpAndSettle();

    // a Foodpanda order: reference, new customer with city, items, charge and discount
    await tapKey(t, 'new-online');
    await tapKey(t, 'on-source');
    await t.tap(find.text('Foodpanda').last);
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('on-ref')), 'FP-1001');
    await typeInto(t, find.byKey(const ValueKey('on-name')), 'Ahmed');
    await typeInto(t, find.byKey(const ValueKey('on-phone')), '03001234567');
    await typeInto(t, find.byKey(const ValueKey('on-address')), 'House 5, Narang');
    await typeInto(t, find.byKey(const ValueKey('on-city')), 'Burewala');
    await t.scrollUntilVisible(find.byKey(const ValueKey('on-plus-Zinger Burger')), 200, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('on-plus-Zinger Burger')));
    await tapKey(t, 'on-plus-Zinger Burger');
    await tapKey(t, 'on-plus-Zinger Burger');
    await t.ensureVisible(find.byKey(const ValueKey('on-charge')));
    await typeInto(t, find.byKey(const ValueKey('on-charge')), '100');
    await typeInto(t, find.byKey(const ValueKey('on-discount')), '50');
    await shot(t, '100_new_delivery');
    await tapKey(t, 'on-save');
    expect(find.text('Waiting (1)'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && (w.key as ValueKey).value.toString().startsWith('src-') && w is Text && w.data == 'Foodpanda'), findsOneWidget);
    expect(find.text('#FP-1001'), findsOneWidget);
    expect(find.textContaining('Burewala'), findsOneWidget);
    expect((await db.customSelect("SELECT city FROM customer WHERE phone = '03001234567'").getSingle()).data['city'], 'Burewala');

    // the same platform order again is refused
    await tapKey(t, 'new-online');
    await tapKey(t, 'on-source');
    await t.tap(find.text('Foodpanda').last);
    await t.pumpAndSettle();
    await typeInto(t, find.byKey(const ValueKey('on-ref')), 'fp-1001');
    await typeInto(t, find.byKey(const ValueKey('on-name')), 'Ahmed');
    await t.scrollUntilVisible(find.byKey(const ValueKey('on-plus-Zinger Burger')), 200, scrollable: verticalScroll);
    await t.ensureVisible(find.byKey(const ValueKey('on-plus-Zinger Burger')));
    await tapKey(t, 'on-plus-Zinger Burger');
    await tapKey(t, 'on-save');
    expect(find.byKey(const ValueKey('on-error')), findsOneWidget);
    expect((t.widget<Text>(find.byKey(const ValueKey('on-error')))).data, contains('already entered'));
    await t.pageBack();
    await t.pumpAndSettle();

    // confirm (goes to the kitchen), then walk it through
    await t.tap(_byPrefix('accept-'));
    await t.pumpAndSettle();
    expect(find.text('Confirmed'), findsWidgets);
    await t.tap(_byPrefix('next-')); // preparing
    await t.pumpAndSettle();
    await t.tap(_byPrefix('next-')); // ready
    await t.pumpAndSettle();
    expect(find.text('Ready'), findsWidgets);
    await t.tap(_byPrefix('next-')); // dispatched: asks for the rider
    await t.pumpAndSettle();
    await tapKey(t, 'rider-pick-Kamran');
    expect(find.text('Dispatched'), findsWidgets);
    expect(find.textContaining('Kamran'), findsWidgets);

    // messages: the dispatch message names the rider; the bill carries the bank details
    await t.tap(_byPrefix('tell-'));
    await t.pumpAndSettle();
    await tapKey(t, 'msg-dispatch');
    expect(share.shared.last, allOf(contains('Kamran'), contains('on its way')));
    await t.tap(_byPrefix('tell-'));
    await t.pumpAndSettle();
    await tapKey(t, 'msg-bill');
    expect(share.shared.last, allOf(contains('Burger Point'), contains('0123-4567'), contains('Meezan Bank'), contains('Delivery charge')));

    // delivered, then it leaves the active list; history shows every step
    await t.tap(_byPrefix('next-'));
    await t.pumpAndSettle();
    expect(find.text('No delivery orders'), findsOneWidget);
    final id = (await db.customSelect('SELECT order_id FROM delivery_info').getSingle()).data['order_id'] as String;
    expect((await h.container.read(onlineOrderServiceProvider).history(id)).map((s) => s.status), ['pending', 'confirmed', 'preparing', 'ready', 'dispatched', 'delivered']);

    // the report: the platform shows apart from direct
    await tapKey(t, 'tab-report');
    expect(find.byKey(const ValueKey('tot-platforms-sales')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('tot-platforms-sales'))).data, 'PKR 950.00', reason: '2 burgers + 100 delivery - 50 discount');
    expect(find.byKey(const ValueKey('tot-Foodpanda')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-count')), findsOneWidget);
    expect(owner, isNotEmpty);
    await t.pumpWidget(const SizedBox());
    h.container.dispose();
  });
}
