import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/bill.dart';
import '../domain/payments.dart';
import 'db/database.dart';
import 'token_service.dart';

class PosException implements Exception {
  PosException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PosException($code): $message';
}

class CartModifier {
  const CartModifier({this.optionId, required this.name, required this.priceMinor});
  final String? optionId;
  final String name;
  final int priceMinor;
}

class CartItem {
  const CartItem({
    required this.productId,
    required this.name,
    required this.qtyMilli,
    required this.unitPriceMinor,
    this.variantId,
    this.modifiers = const [],
    this.lineDiscountMinor = 0,
    this.taxRateBp = 0,
    this.taxInclusive = false,
    this.note,
    this.station,
    this.kotSentMilli = 0,
  });
  final String productId;
  final String? variantId;
  final String name;
  final int qtyMilli;
  final int unitPriceMinor;
  final List<CartModifier> modifiers;
  final int lineDiscountMinor;
  final int taxRateBp;
  final bool taxInclusive;
  final String? note;
  final String? station;

  /// Quantity already sent to the kitchen (see KOT printing).
  final int kotSentMilli;
  int get modifiersMinor => modifiers.fold(0, (s, m) => s + m.priceMinor);
}

class DraftOrder {
  const DraftOrder({
    this.id,
    required this.orderType,
    required this.items,
    this.config = const BillConfig(),
    this.tableId,
    this.customerId,
    this.waiterId,
    this.guests,
    this.note,
    this.held = false,
    this.source = 'pos',
    this.deliveryAddress,
    this.riderId,
  });
  final String? id;
  final String orderType;
  final List<CartItem> items;
  final BillConfig config;
  final String? tableId;
  final String? customerId;
  final String? waiterId;
  final int? guests;
  final String? note;
  final bool held;

  /// Where the order came from: 'pos' (taken at the counter) or 'online' (WhatsApp / phone / delivery app, typed in by staff).
  final String source;
  final String? deliveryAddress;
  final String? riderId;
}

class SettlePayment {
  const SettlePayment({required this.methodId, required this.amountMinor, this.reference});
  final String methodId;
  final int amountMinor;
  final String? reference;
}

class SettledOrder {
  const SettledOrder({required this.orderId, required this.invoiceNo, required this.totalMinor, required this.changeMinor, required this.alreadySettled});
  final String orderId;
  final String invoiceNo;
  final int totalMinor;
  final int changeMinor;

  /// True when the call hit an already-settled order and returned the existing result (safe retry).
  final bool alreadySettled;
}

class HeldOrder {
  const HeldOrder({required this.id, required this.totalMinor, required this.updatedAt, required this.orderType, this.table, required this.itemCount});
  final String id;
  final int totalMinor;
  final int updatedAt;
  final String orderType;
  final String? table;
  final int itemCount;
}

class SalesReport {
  const SalesReport({required this.date, required this.bills, required this.grossMinor, required this.refundsMinor, required this.taxMinor, required this.byMethod});
  final String date;
  final int bills;
  final int grossMinor;
  final int refundsMinor;
  final int taxMinor;
  int get netMinor => grossMinor - refundsMinor;

  /// Money received per payment method name (before refunds).
  final Map<String, int> byMethod;
}

Map<String, dynamic> _configToJson(BillConfig c) => {
      'discountKind': c.billDiscount?.kind.name,
      'discountValue': c.billDiscount?.value,
      'serviceBp': c.serviceChargeBp,
      'serviceTaxBp': c.serviceChargeTaxBp,
      'delivery': c.deliveryChargeMinor,
      'tip': c.tipMinor,
      'rounding': c.rounding.name,
    };

BillConfig _configFromJson(String? raw) {
  if (raw == null) return const BillConfig();
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final kind = j['discountKind'] as String?;
  return BillConfig(
    billDiscount: kind == null
        ? null
        : (kind == 'percent' ? Discount.percent(j['discountValue'] as int) : Discount.fixed(j['discountValue'] as int)),
    serviceChargeBp: j['serviceBp'] as int,
    serviceChargeTaxBp: j['serviceTaxBp'] as int,
    deliveryChargeMinor: j['delivery'] as int,
    tipMinor: j['tip'] as int,
    rounding: RoundingMode.values.byName(j['rounding'] as String),
  );
}

/// All money-moving operations. Every public method that writes runs in ONE database transaction, so a crash,
/// kill or power loss leaves either the complete result or nothing.
class PosService {
  PosService(this.db, {DateTime Function()? now, String Function()? newId, this.deviceId = 'device'})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final String deviceId;
  final DateTime Function() _now;
  final String Function() _newId;
  late final TokenService _tokens = TokenService(db, now: _now, newId: _newId);

  int get _ts => _now().millisecondsSinceEpoch;
  String get _businessDate {
    final n = _now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Today, or the day after the last closed day when today was already closed (see [DbHelper.openBusinessDate]).
  Future<String> _openBusinessDate() async {
    final today = _businessDate;
    final last = (await _select('SELECT MAX(business_date) AS d FROM day_close')).first['d'] as String?;
    if (last == null || last.compareTo(today) < 0) return today;
    final p = last.split('-').map(int.parse).toList();
    final next = DateTime(p[0], p[1], p[2] + 1);
    return '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
  }

  // ---- low level helpers ----
  Variable _v(Object? o) {
    if (o == null) return const Variable<Object>(null);
    if (o is int) return Variable.withInt(o);
    if (o is String) return Variable.withString(o);
    throw ArgumentError('unsupported variable ${o.runtimeType}');
  }

  Future<List<Map<String, Object?>>> _select(String sql, [List<Object?> args = const []]) async =>
      (await db.customSelect(sql, variables: args.map(_v).toList()).get()).map((r) => r.data).toList();

  Future<void> _exec(String sql, [List<Object?> args = const []]) =>
      db.customStatement(sql, args.map((a) => a is String || a is int || a == null ? a : throw ArgumentError('bad arg')).toList());

  Future<void> _audit(String event, {String? staffId, String? entity, String? entityId, Object? before, Object? after, String? reason, bool critical = false}) =>
      _exec(
          'INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, before_json, after_json, reason, device_id, critical) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [_newId(), _ts, staffId, event, entity, entityId, before == null ? null : jsonEncode(before), after == null ? null : jsonEncode(after), reason, deviceId, critical ? 1 : 0]);

  Future<void> _outbox(String entity, String entityId, String op, Map<String, dynamic> payload, String key) => _exec(
      'INSERT OR IGNORE INTO outbox(idempotency_key, entity, entity_id, op, payload, created_at) VALUES (?,?,?,?,?,?)',
      [key, entity, entityId, op, jsonEncode(payload), _ts]);

  Future<bool> hasPermission(String staffId, String permission) async {
    final rows = await _select('SELECT r.permissions AS p FROM staff s JOIN role r ON r.id = s.role_id WHERE s.id = ? AND s.active = 1 AND s.deleted_at IS NULL', [staffId]);
    if (rows.isEmpty) return false;
    final perms = (jsonDecode(rows.first['p'] as String) as List).cast<String>();
    return perms.contains(permission) || perms.contains('*');
  }

  Future<void> _require(String staffId, String permission) async {
    if (!await hasPermission(staffId, permission)) throw PosException('permission_denied', 'Missing permission: $permission');
  }

  // ---- drafts (persisted on every change so a crash loses nothing) ----
  Future<String> saveDraft(DraftOrder d, {String? staffId}) => db.transaction(() async {
        final id = d.id ?? _newId();
        final existing = await _select('SELECT status FROM "order" WHERE id = ?', [id]);
        // an order already sent to the kitchen (new/preparing/ready/served) can still get more items until it is paid
        const editable = {'draft', 'held', 'new', 'preparing', 'ready', 'served'};
        if (existing.isNotEmpty && !editable.contains(existing.first['status'])) {
          throw PosException('not_editable', 'Order ${existing.first['status']} can no longer be edited');
        }
        final hasDiscount = d.config.billDiscount != null || d.items.any((i) => i.lineDiscountMinor > 0);
        if (hasDiscount) {
          if (staffId == null) throw PosException('permission_denied', 'Discounts need a signed-in staff member');
          await _require(staffId, 'discount.apply');
        }
        final bill = calculateBill(d.items.map(_toInput).toList(), d.config);
        final now = _ts;
        final prior = existing.isEmpty ? null : existing.first['status'] as String;
        final status = d.held ? 'held' : (prior != null && const {'new', 'preparing', 'ready', 'served'}.contains(prior) ? prior : 'draft');
        if (existing.isEmpty) {
          await _exec(
              'INSERT INTO "order"(id, order_type, status, table_id, customer_id, waiter_id, guests, note, bill_config, subtotal_minor, discount_minor, service_charge_minor, delivery_charge_minor, tax_minor, tip_minor, rounding_minor, total_minor, business_date, created_at, updated_at, source, delivery_address, rider_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
              [id, d.orderType, status, d.tableId, d.customerId, d.waiterId, d.guests, d.note, jsonEncode(_configToJson(d.config)), bill.subtotalMinor, bill.discountMinor, bill.serviceChargeMinor, bill.deliveryChargeMinor, bill.taxMinor, bill.tipMinor, bill.roundingMinor, bill.totalMinor, await _openBusinessDate(), now, now, d.source, d.deliveryAddress, d.riderId]);
        } else {
          await _exec(
              'UPDATE "order" SET order_type=?, status=?, table_id=?, customer_id=?, waiter_id=?, guests=?, note=COALESCE(?, note), delivery_address=COALESCE(?, delivery_address), rider_id=COALESCE(?, rider_id), bill_config=?, subtotal_minor=?, discount_minor=?, service_charge_minor=?, delivery_charge_minor=?, tax_minor=?, tip_minor=?, rounding_minor=?, total_minor=?, updated_at=?, version=version+1 WHERE id=?',
              [d.orderType, status, d.tableId, d.customerId, d.waiterId, d.guests, d.note, d.deliveryAddress, d.riderId, jsonEncode(_configToJson(d.config)), bill.subtotalMinor, bill.discountMinor, bill.serviceChargeMinor, bill.deliveryChargeMinor, bill.taxMinor, bill.tipMinor, bill.roundingMinor, bill.totalMinor, now, id]);
          await _exec('DELETE FROM order_item_modifier WHERE order_item_id IN (SELECT id FROM order_item WHERE order_id = ?)', [id]);
          await _exec('DELETE FROM order_item WHERE order_id = ?', [id]);
        }
        for (var i = 0; i < d.items.length; i++) {
          final it = d.items[i];
          final r = bill.lines[i];
          final itemId = _newId();
          await _exec(
              'INSERT INTO order_item(id, order_id, product_id, variant_id, name, qty_milli, unit_price_minor, discount_minor, tax_rate_bp, tax_inclusive, tax_minor, line_total_minor, note, station, kot_qty_milli) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
              [itemId, id, it.productId, it.variantId, it.name, it.qtyMilli, it.unitPriceMinor, it.lineDiscountMinor, it.taxRateBp, it.taxInclusive ? 1 : 0, r.taxMinor, r.totalMinor, it.note, it.station, it.kotSentMilli > it.qtyMilli ? it.qtyMilli : it.kotSentMilli]);
          for (final m in it.modifiers) {
            await _exec('INSERT INTO order_item_modifier(id, order_item_id, option_id, name, price_minor) VALUES (?,?,?,?,?)', [_newId(), itemId, m.optionId, m.name, m.priceMinor]);
          }
        }
        if (d.tableId != null && !d.held) {
          await _exec("UPDATE dining_table SET status='occupied', waiter_id=COALESCE(?, waiter_id), updated_at=?, version=version+1 WHERE id=?", [d.waiterId, now, d.tableId]);
        }
        return id;
      });

  BillLineInput _toInput(CartItem i) => BillLineInput(
        id: i.productId,
        unitPriceMinor: i.unitPriceMinor,
        qtyMilli: i.qtyMilli,
        modifiersMinor: i.modifiersMinor,
        lineDiscountMinor: i.lineDiscountMinor,
        taxRateBp: i.taxRateBp,
        taxInclusive: i.taxInclusive,
      );

  /// Latest unsettled draft (for crash recovery on the next launch), or null.
  Future<String?> latestDraftId() async {
    final r = await _select("SELECT id FROM \"order\" WHERE status = 'draft' ORDER BY updated_at DESC LIMIT 1");
    return r.isEmpty ? null : r.first['id'] as String;
  }

  Future<DraftOrder?> loadDraft(String id) async {
    final rows = await _select('SELECT * FROM "order" WHERE id = ? AND status IN (\'draft\', \'held\', \'new\', \'preparing\', \'ready\', \'served\')', [id]);
    if (rows.isEmpty) return null;
    final o = rows.first;
    final items = <CartItem>[];
    for (final r in await _select('SELECT * FROM order_item WHERE order_id = ? ORDER BY rowid', [id])) {
      final mods = await _select('SELECT * FROM order_item_modifier WHERE order_item_id = ?', [r['id']]);
      items.add(CartItem(
        productId: r['product_id'] as String,
        variantId: r['variant_id'] as String?,
        name: r['name'] as String,
        qtyMilli: r['qty_milli'] as int,
        unitPriceMinor: r['unit_price_minor'] as int,
        modifiers: [for (final m in mods) CartModifier(optionId: m['option_id'] as String?, name: m['name'] as String, priceMinor: m['price_minor'] as int)],
        lineDiscountMinor: r['discount_minor'] as int,
        taxRateBp: r['tax_rate_bp'] as int,
        taxInclusive: (r['tax_inclusive'] as int) == 1,
        note: r['note'] as String?,
        station: r['station'] as String?,
        kotSentMilli: r['kot_qty_milli'] as int,
      ));
    }
    return DraftOrder(
      id: id,
      orderType: o['order_type'] as String,
      items: items,
      config: _configFromJson(o['bill_config'] as String?),
      tableId: o['table_id'] as String?,
      customerId: o['customer_id'] as String?,
      waiterId: o['waiter_id'] as String?,
      guests: o['guests'] as int?,
      note: o['note'] as String?,
      held: o['status'] == 'held',
      deliveryAddress: o['delivery_address'] as String?,
      riderId: o['rider_id'] as String?,
    );
  }

  /// Orders put on hold, newest first.
  Future<List<HeldOrder>> listHeld() async => [
        for (final r in await _select("SELECT o.id, o.total_minor, o.updated_at, o.order_type, t.label AS tbl, (SELECT COUNT(*) FROM order_item i WHERE i.order_id = o.id) AS items FROM \"order\" o LEFT JOIN dining_table t ON t.id = o.table_id WHERE o.status = 'held' ORDER BY o.updated_at DESC"))
          HeldOrder(id: r['id'] as String, totalMinor: r['total_minor'] as int, updatedAt: r['updated_at'] as int, orderType: r['order_type'] as String, table: r['tbl'] as String?, itemCount: r['items'] as int)
      ];

  /// Removes an unsettled draft (cart emptied or cancelled). Settled orders can never be deleted.
  Future<void> discardDraft(String id) => db.transaction(() async {
        final rows = await _select('SELECT status, table_id FROM "order" WHERE id = ?', [id]);
        if (rows.isEmpty) return;
        if (!{'draft', 'held', 'new', 'preparing', 'ready', 'served'}.contains(rows.first['status'])) throw PosException('not_editable', 'Only unsettled orders can be discarded');
        // what the kitchen has been sent is history: such an order is cancelled (kept), never deleted
        if ((await _select('SELECT 1 AS x FROM order_item WHERE order_id = ? AND kot_sent_at IS NOT NULL LIMIT 1', [id])).isNotEmpty) {
          throw PosException('sent_to_kitchen', 'This order was sent to the kitchen: cancel it instead of deleting it');
        }
        await _exec('DELETE FROM order_item_modifier WHERE order_item_id IN (SELECT id FROM order_item WHERE order_id = ?)', [id]);
        await _exec('DELETE FROM order_item WHERE order_id = ?', [id]);
        await _exec('DELETE FROM "order" WHERE id = ?', [id]);
        if (rows.first['table_id'] != null) {
          await _exec("UPDATE dining_table SET status='free', updated_at=?, version=version+1 WHERE id=? AND NOT EXISTS (SELECT 1 FROM \"order\" WHERE table_id = ? AND status IN ('draft','held','new','preparing','ready','served'))",
              [_ts, rows.first['table_id'], rows.first['table_id']]);
        }
      });

  /// Calls off an UNPAID order. Never sent to the kitchen: it is simply removed. Sent to the kitchen: it is kept with the
  /// status 'cancelled' (the kitchen history stays; it is never counted as a sale) and its table is freed.
  Future<void> cancelOrder(String id, {required String staffId, String? reason}) => db.transaction(() async {
        await _require(staffId, 'bill.void');
        final rows = await _select('SELECT status, table_id FROM "order" WHERE id = ?', [id]);
        if (rows.isEmpty) return;
        if (!{'draft', 'held', 'new', 'preparing', 'ready', 'served'}.contains(rows.first['status'])) throw PosException('not_editable', 'Only an unpaid order can be cancelled');
        final sent = (await _select('SELECT 1 AS x FROM order_item WHERE order_id = ? AND kot_sent_at IS NOT NULL LIMIT 1', [id])).isNotEmpty;
        if (!sent) {
          await discardDraft(id);
          return;
        }
        await _exec("UPDATE \"order\" SET status = 'cancelled', updated_at = ?, version = version + 1 WHERE id = ?", [_ts, id]);
        final table = rows.first['table_id'];
        if (table != null) {
          await _exec("UPDATE dining_table SET status='free', updated_at=?, version=version+1 WHERE id=? AND NOT EXISTS (SELECT 1 FROM \"order\" WHERE table_id = ? AND status IN ('draft','held','new','preparing','ready','served'))", [_ts, table, table]);
        }
        await _audit('order.cancel', staffId: staffId, entity: 'order', entityId: id, reason: reason, critical: true);
      });

  // ---- settlement ----
  Future<String> _nextInvoiceNo(String businessDate) async {
    final period = businessDate.replaceAll('-', '');
    await _exec('INSERT OR IGNORE INTO invoice_sequence(prefix, period, last_no) VALUES (?,?,0)', ['INV', period]);
    await _exec('UPDATE invoice_sequence SET last_no = last_no + 1 WHERE prefix = ? AND period = ?', ['INV', period]);
    final n = (await _select('SELECT last_no FROM invoice_sequence WHERE prefix = ? AND period = ?', ['INV', period])).first['last_no'] as int;
    return 'INV-$period-${n.toString().padLeft(4, '0')}';
  }

  /// Settles a draft: assigns the next gap-free invoice number, records payments, deducts stock, posts udhaar,
  /// writes audit + outbox, frees the table. All or nothing. Calling it again on a settled order returns the
  /// existing result (safe to retry after a crash).
  Future<SettledOrder> settleOrder({
    required String orderId,
    required List<SettlePayment> payments,
    required String staffId,
    String? shiftId,
  }) =>
      db.transaction(() async {
        final rows = await _select('SELECT * FROM "order" WHERE id = ?', [orderId]);
        if (rows.isEmpty) throw PosException('not_found', 'Order not found');
        final o = rows.first;
        if (o['status'] == 'paid') {
          return SettledOrder(orderId: orderId, invoiceNo: o['invoice_no'] as String, totalMinor: o['total_minor'] as int, changeMinor: 0, alreadySettled: true);
        }
        if (!{'draft', 'held', 'new', 'preparing', 'ready', 'served'}.contains(o['status'])) {
          throw PosException('not_settleable', 'Order is ${o['status']}');
        }
        final itemRows = await _select("SELECT * FROM order_item WHERE order_id = ? AND status = 'active'", [orderId]);
        if (itemRows.isEmpty) throw PosException('empty_order', 'Nothing to settle');

        final inputs = <BillLineInput>[];
        for (final r in itemRows) {
          final mods = await _select('SELECT COALESCE(SUM(price_minor),0) AS s FROM order_item_modifier WHERE order_item_id = ?', [r['id']]);
          inputs.add(BillLineInput(
            id: r['id'] as String,
            unitPriceMinor: r['unit_price_minor'] as int,
            qtyMilli: r['qty_milli'] as int,
            modifiersMinor: mods.first['s'] as int,
            lineDiscountMinor: r['discount_minor'] as int,
            taxRateBp: r['tax_rate_bp'] as int,
            taxInclusive: (r['tax_inclusive'] as int) == 1,
          ));
        }
        final bill = calculateBill(inputs, _configFromJson(o['bill_config'] as String?));

        // payments -> methods
        final methods = <String, Map<String, Object?>>{};
        for (final p in payments) {
          final m = await _select('SELECT * FROM payment_method WHERE id = ? AND enabled = 1 AND deleted_at IS NULL', [p.methodId]);
          if (m.isEmpty) throw PosException('bad_method', 'Payment method unavailable');
          methods[p.methodId] = m.first;
        }
        PaymentKind kindOf(String kind) => PaymentKind.values.firstWhere((k) => k.name == kind, orElse: () => PaymentKind.other);
        final result = settle(bill.totalMinor, [for (final p in payments) PaymentInput(kindOf(methods[p.methodId]!['kind'] as String), p.amountMinor)]);
        if (!result.isSettled) throw PosException('underpaid', 'Short by ${result.dueMinor} minor units');

        // credit (udhaar) needs a customer and headroom under the limit
        final creditTotal = [
          for (var i = 0; i < payments.length; i++)
            if (methods[payments[i].methodId]!['kind'] == 'credit') result.appliedMinor[i]
        ].fold<int>(0, (a, b) => a + b);
        final customerId = o['customer_id'] as String?;
        if (creditTotal > 0) {
          if (customerId == null) throw PosException('credit_needs_customer', 'Select a customer for credit sales');
          final c = (await _select('SELECT credit_limit_minor FROM customer WHERE id = ? AND deleted_at IS NULL', [customerId])).firstOrNull;
          if (c == null) throw PosException('not_found', 'Customer not found');
          final bal = (await _select('SELECT COALESCE(SUM(amount_minor),0) AS b FROM customer_ledger WHERE customer_id = ?', [customerId])).first['b'] as int;
          if (bal + creditTotal > (c['credit_limit_minor'] as int)) {
            throw PosException('credit_limit', 'Credit limit exceeded');
          }
        }

        // a sale belongs to the day it is PAID (an order held yesterday and paid today is today's sale), and never to a closed day
        final saleDate = await _openBusinessDate();
        final invoiceNo = await _nextInvoiceNo(saleDate);
        final now = _ts;
        for (var i = 0; i < itemRows.length; i++) {
          await _exec('UPDATE order_item SET tax_minor = ?, line_total_minor = ? WHERE id = ?', [bill.lines[i].taxMinor, bill.lines[i].totalMinor, itemRows[i]['id']]);
        }
        for (var i = 0; i < payments.length; i++) {
          final p = payments[i];
          final isCash = methods[p.methodId]!['kind'] == 'cash';
          final applied = result.appliedMinor[i];
          await _exec(
              'INSERT INTO payment(id, order_id, method_id, method_kind, amount_minor, reference, tendered_minor, change_minor, staff_id, shift_id, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
              [_newId(), orderId, p.methodId, methods[p.methodId]!['kind'], applied, p.reference, isCash ? p.amountMinor : null, isCash ? p.amountMinor - applied : null, staffId, shiftId, now]);
        }
        await _exec(
            "UPDATE \"order\" SET status='paid', business_date=?, invoice_no=?, subtotal_minor=?, discount_minor=?, service_charge_minor=?, delivery_charge_minor=?, tax_minor=?, tip_minor=?, rounding_minor=?, total_minor=?, paid_minor=?, cashier_id=?, shift_id=?, settled_at=?, updated_at=?, version=version+1 WHERE id=?",
            [saleDate, invoiceNo, bill.subtotalMinor, bill.discountMinor, bill.serviceChargeMinor, bill.deliveryChargeMinor, bill.taxMinor, bill.tipMinor, bill.roundingMinor, bill.totalMinor, result.paidMinor, staffId, shiftId, now, now, orderId]);

        await _applyStock(orderId, itemRows, sign: -1, reason: 'sale', staffId: staffId);
        if (creditTotal > 0) {
          await _exec('INSERT INTO customer_ledger(id, customer_id, kind, amount_minor, order_id, staff_id, created_at) VALUES (?,?,?,?,?,?,?)',
              [_newId(), customerId, 'sale_credit', creditTotal, orderId, staffId, now]);
        }
        if (o['table_id'] != null) {
          await _exec("UPDATE dining_table SET status='free', updated_at=?, version=version+1 WHERE id=?", [now, o['table_id']]);
        }
        await _audit('bill.settle', staffId: staffId, entity: 'order', entityId: orderId, after: {'invoice': invoiceNo, 'total': bill.totalMinor});
        await _outbox('order', orderId, 'append', {'id': orderId, 'invoice_no': invoiceNo, 'total_minor': bill.totalMinor, 'tax_minor': bill.taxMinor, 'business_date': saleDate, 'status': 'paid'}, 'order:$orderId:settle');
        // food tokens (if the owner switched any on) are numbered in the same transaction as the sale: all or nothing
        await _tokens.issueForOrder(orderId);
        return SettledOrder(orderId: orderId, invoiceNo: invoiceNo, totalMinor: bill.totalMinor, changeMinor: result.changeMinor, alreadySettled: false);
      });

  /// A deal takes stock from the items inside it: one row per component, quantity = per-deal quantity x deals sold.
  Future<List<Map<String, Object?>>> _expandDeals(List<Map<String, Object?>> rows) async {
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final kind = (await _select('SELECT kind FROM product WHERE id = ?', [r['product_id']])).firstOrNull?['kind'];
      if (kind != 'combo') {
        out.add(r);
        continue;
      }
      for (final c in await _select('SELECT product_id, variant_id, qty_milli FROM deal_item WHERE deal_id = ?', [r['product_id']])) {
        out.add({...r, 'product_id': c['product_id'], 'variant_id': c['variant_id'], 'qty_milli': (c['qty_milli'] as int) * (r['qty_milli'] as int) ~/ 1000});
      }
    }
    return out;
  }

  /// Writes stock ledger rows for an order. Recipe lines win; otherwise a stock item linked straight to the product.
  /// Stock may go negative: a sale is never blocked by an out-of-date count.
  Future<void> _applyStock(String orderId, List<Map<String, Object?>> soldRows, {required int sign, required String reason, String? staffId}) async {
    final now = _ts;
    final itemRows = await _expandDeals(soldRows);
    for (final r in itemRows) {
      final qty = r['qty_milli'] as int;
      final recipe = await _select(
          'SELECT stock_item_id, qty_milli FROM recipe_line WHERE product_id = ? AND (variant_id IS NULL OR variant_id = ?)', [r['product_id'], r['variant_id']]);
      if (recipe.isNotEmpty) {
        for (final line in recipe) {
          final delta = sign * ((line['qty_milli'] as int) * qty ~/ 1000);
          if (delta == 0) continue;
          await _exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, order_id, staff_id, created_at) VALUES (?,?,?,?,?,?,?)',
              [_newId(), line['stock_item_id'], delta, sign < 0 ? 'recipe' : 'return', orderId, staffId, now]);
        }
        continue;
      }
      final direct = await _select('SELECT s.id AS id FROM stock_item s JOIN product p ON p.id = s.product_id WHERE s.product_id = ? AND p.track_stock = 1 AND s.deleted_at IS NULL', [r['product_id']]);
      for (final s in direct) {
        await _exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, order_id, staff_id, created_at) VALUES (?,?,?,?,?,?,?)',
            [_newId(), s['id'], sign * qty, sign < 0 ? reason : 'return', orderId, staffId, now]);
      }
    }
  }

  // ---- void / refund ----
  /// Reverses a paid bill. [amountMinor] null = whole bill (a void). Needs `bill.void` / `bill.refund`; a reason is mandatory.
  Future<String> refundOrder({
    required String orderId,
    required String staffId,
    required String reason,
    String? methodId,
    int? amountMinor,
    String? approvedBy,
    String? shiftId,
  }) =>
      db.transaction(() async {
        if (reason.trim().isEmpty) throw PosException('reason_required', 'A reason is required');
        final full = amountMinor == null;
        await _require(staffId, full ? 'bill.void' : 'bill.refund');
        final rows = await _select('SELECT * FROM "order" WHERE id = ?', [orderId]);
        if (rows.isEmpty) throw PosException('not_found', 'Order not found');
        final o = rows.first;
        if (o['status'] != 'paid') throw PosException('not_refundable', 'Order is ${o['status']}');
        final refunded = (await _select('SELECT COALESCE(SUM(amount_minor),0) AS s FROM refund WHERE order_id = ?', [orderId])).first['s'] as int;
        final paid = o['paid_minor'] as int;
        final amount = amountMinor ?? (paid - refunded);
        if (amount <= 0 || amount > paid - refunded) throw PosException('bad_amount', 'Refund exceeds what was paid');
        final id = _newId();
        final now = _ts;
        final becomesFull = refunded + amount == paid;
        await _exec('INSERT INTO refund(id, order_id, kind, amount_minor, method_id, reason, approved_by, staff_id, shift_id, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
            [id, orderId, full ? 'void' : 'refund', amount, methodId, reason.trim(), approvedBy, staffId, shiftId, now]);
        if (becomesFull) {
          await _exec("UPDATE \"order\" SET status=?, updated_at=?, version=version+1 WHERE id=?", [full ? 'void' : 'refunded', now, orderId]);
          final items = await _select("SELECT * FROM order_item WHERE order_id = ? AND status = 'active'", [orderId]);
          await _applyStock(orderId, items, sign: 1, reason: 'return', staffId: staffId);
          await _tokens.voidForOrder(orderId); // waiting tokens and unused coupons of a cancelled sale stop working
          final credit = (await _select("SELECT COALESCE(SUM(amount_minor),0) AS s FROM payment WHERE order_id = ? AND method_kind = 'credit'", [orderId])).first['s'] as int;
          if (credit > 0 && o['customer_id'] != null) {
            await _exec('INSERT INTO customer_ledger(id, customer_id, kind, amount_minor, order_id, staff_id, created_at) VALUES (?,?,?,?,?,?,?)',
                [_newId(), o['customer_id'], 'refund', -credit, orderId, staffId, now]);
          }
        }
        await _audit(full ? 'bill.void' : 'bill.refund', staffId: staffId, entity: 'order', entityId: orderId, after: {'amount': amount}, reason: reason.trim(), critical: true);
        await _outbox('refund', id, 'append', {'id': id, 'order_id': orderId, 'kind': full ? 'void' : 'refund', 'amount_minor': amount}, 'refund:$id');
        return id;
      });

  // ---- reports ----
  Future<SalesReport> salesReport(String businessDate) async {
    final o = (await _select("SELECT COUNT(*) AS n, COALESCE(SUM(total_minor),0) AS gross, COALESCE(SUM(tax_minor),0) AS tax FROM \"order\" WHERE business_date = ? AND status IN ('paid','void','refunded')", [businessDate])).first;
    final r = (await _select('SELECT COALESCE(SUM(amount_minor),0) AS s FROM refund WHERE order_id IN (SELECT id FROM "order" WHERE business_date = ?)', [businessDate])).first;
    final m = await _select(
        "SELECT pm.name AS name, SUM(p.amount_minor) AS s FROM payment p JOIN payment_method pm ON pm.id = p.method_id JOIN \"order\" o ON o.id = p.order_id WHERE o.business_date = ? GROUP BY pm.name",
        [businessDate]);
    return SalesReport(
      date: businessDate,
      bills: o['n'] as int,
      grossMinor: o['gross'] as int,
      refundsMinor: r['s'] as int,
      taxMinor: o['tax'] as int,
      byMethod: {for (final x in m) x['name'] as String: x['s'] as int},
    );
  }
}
