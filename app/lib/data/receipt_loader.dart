import 'package:drift/drift.dart';

import '../domain/money.dart';
import '../domain/receipt.dart';
import 'db/database.dart';

const orderTypeLabels = {'dine_in': 'Dine-in', 'takeaway': 'Takeaway', 'delivery': 'Delivery', 'counter': 'Counter'};

String two(int n) => n.toString().padLeft(2, '0');
String formatDateTime(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';

/// Builds the receipt for a settled order from what is stored in the database (item names and prices are the
/// snapshot taken at sale time, so later menu edits never change an old receipt).
Future<ReceiptData> loadReceipt(AppDatabase db, String orderId, {bool duplicate = false, String? footer}) async {
  Future<List<Map<String, Object?>>> q(String sql, [List<String> args = const []]) async =>
      (await db.customSelect(sql, variables: args.map(Variable.withString).toList()).get()).map((r) => r.data).toList();

  final o = (await q('SELECT * FROM "order" WHERE id = ?', [orderId])).firstOrNull;
  if (o == null) throw StateError('Order $orderId not found');
  final biz = (await q("SELECT * FROM business_profile WHERE id = 'self'")).firstOrNull;
  final cur = Currency(biz?['currency'] as String? ?? 'PKR', minorDigits: biz?['currency_minor_digits'] as int? ?? 2);

  final lines = <ReceiptLine>[];
  for (final i in await q("SELECT * FROM order_item WHERE order_id = ? AND status = 'active' ORDER BY rowid", [orderId])) {
    final mods = await q('SELECT name FROM order_item_modifier WHERE order_item_id = ?', [i['id'] as String]);
    lines.add(ReceiptLine(
      name: i['name'] as String,
      qtyMilli: i['qty_milli'] as int,
      unitPriceMinor: i['unit_price_minor'] as int,
      totalMinor: i['line_total_minor'] as int,
      modifiers: [for (final m in mods) m['name'] as String],
      note: i['note'] as String?,
    ));
  }
  final pays = await q('SELECT pm.name AS name, p.amount_minor AS amount, p.tendered_minor AS tendered, p.change_minor AS change FROM payment p JOIN payment_method pm ON pm.id = p.method_id WHERE p.order_id = ? ORDER BY p.rowid', [orderId]);
  final cashier = o['cashier_id'] == null ? null : (await q('SELECT name FROM staff WHERE id = ?', [o['cashier_id'] as String])).firstOrNull?['name'] as String?;
  final table = o['table_id'] == null ? null : (await q('SELECT label FROM dining_table WHERE id = ?', [o['table_id'] as String])).firstOrNull?['label'] as String?;
  final when = DateTime.fromMillisecondsSinceEpoch((o['settled_at'] ?? o['created_at']) as int);

  return ReceiptData(
    businessName: biz?['name'] as String? ?? 'DT Food POS',
    address: biz?['address'] as String?,
    phone: biz?['phone'] as String?,
    taxLabel: biz?['tax_number_label'] as String?,
    taxNumber: biz?['tax_number'] as String?,
    invoiceNo: (o['invoice_no'] as String?) ?? 'DRAFT',
    dateTime: formatDateTime(when),
    orderTypeLabel: orderTypeLabels[o['order_type']] ?? '${o['order_type']}',
    tableLabel: table,
    cashier: cashier,
    lines: lines,
    subtotalMinor: o['subtotal_minor'] as int,
    discountMinor: o['discount_minor'] as int,
    serviceChargeMinor: o['service_charge_minor'] as int,
    deliveryChargeMinor: o['delivery_charge_minor'] as int,
    taxMinor: o['tax_minor'] as int,
    tipMinor: o['tip_minor'] as int,
    roundingMinor: o['rounding_minor'] as int,
    totalMinor: o['total_minor'] as int,
    payments: [for (final p in pays) ReceiptPayment(p['name'] as String, (p['tendered'] as int?) ?? (p['amount'] as int))],
    changeMinor: pays.fold<int>(0, (s, p) => s + ((p['change'] as int?) ?? 0)),
    footer: footer ?? 'Thank you! Visit again.',
    isDuplicate: duplicate,
    currency: cur,
  );
}
