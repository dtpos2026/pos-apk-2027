import 'db_helper.dart';
import 'pos_service.dart' show PosException;

class StockRow {
  const StockRow({required this.id, required this.name, required this.unit, required this.onHandMilli, required this.reorderMilli, required this.avgCostMinor});
  final String id;
  final String name;
  final String unit;
  final int onHandMilli;
  final int reorderMilli;

  /// Average cost per ONE unit (per 1000 milli), in minor currency units.
  final int avgCostMinor;
  bool get isLow => reorderMilli > 0 && onHandMilli <= reorderMilli;
  int get valueMinor => (onHandMilli * avgCostMinor / 1000).round();
}

class PurchaseInput {
  const PurchaseInput({required this.stockItemId, required this.qtyMilli, required this.unitCostMinor});
  final String stockItemId;
  final int qtyMilli;

  /// Cost of one whole unit (e.g. per kg) in minor units.
  final int unitCostMinor;
}

class PurchaseOrderRow {
  const PurchaseOrderRow({required this.id, required this.poNo, required this.status, required this.supplierName, this.supplierPhone, this.supplierId, required this.totalMinor, required this.lines, this.note, this.expectedDate});
  final String id;
  final String poNo;

  /// draft | sent | received | cancelled
  final String status;
  final String supplierName;
  final String? supplierPhone;
  final String? supplierId;
  final int totalMinor;
  final int lines;
  final String? note;
  final String? expectedDate;
  bool get open => status == 'draft' || status == 'sent';
}

/// Stock is a ledger of movements, never an overwritten number: purchases add, sales/recipes/wastage subtract,
/// a stock count books the difference as an adjustment.
class InventoryService {
  InventoryService(this.h);
  final DbHelper h;

  Future<String> saveItem({String? id, required String name, required String unit, int reorderLevelMilli = 0, int openingMilli = 0, int openingCostMinor = 0, required String staffId}) => h.db.transaction(() async {
        if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
        if (!const {'pc', 'g', 'kg', 'ml', 'l'}.contains(unit)) throw PosException('bad_unit', 'Unit must be pc, g, kg, ml or l');
        final sid = id ?? h.id;
        if (id == null) {
          await h.exec('INSERT INTO stock_item(id, name, unit, reorder_level_milli, avg_cost_minor_per_unit, updated_at) VALUES (?,?,?,?,?,?)', [sid, name.trim(), unit, reorderLevelMilli, openingCostMinor, h.ts]);
          if (openingMilli > 0) {
            await h.exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, unit_cost_minor, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, sid, openingMilli, 'opening', openingCostMinor, staffId, h.ts]);
          }
        } else {
          await h.exec('UPDATE stock_item SET name=?, unit=?, reorder_level_milli=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), unit, reorderLevelMilli, h.ts, id]);
        }
        return sid;
      });

  Future<int> onHand(String stockItemId) => h.intValue('SELECT COALESCE(SUM(delta_milli),0) FROM stock_movement WHERE stock_item_id = ?', [stockItemId]);

  Future<List<StockRow>> list({bool lowOnly = false}) async {
    final rows = await h.q(
        'SELECT s.id, s.name, s.unit, s.reorder_level_milli, s.avg_cost_minor_per_unit, COALESCE((SELECT SUM(delta_milli) FROM stock_movement WHERE stock_item_id = s.id),0) AS onhand FROM stock_item s WHERE s.deleted_at IS NULL ORDER BY s.name');
    final all = [
      for (final r in rows)
        StockRow(id: r['id'] as String, name: r['name'] as String, unit: r['unit'] as String, onHandMilli: r['onhand'] as int, reorderMilli: r['reorder_level_milli'] as int, avgCostMinor: r['avg_cost_minor_per_unit'] as int)
    ];
    return lowOnly ? all.where((s) => s.isLow).toList() : all;
  }

  /// Total value of stock on hand at average cost.
  Future<int> valuation() async => (await list()).fold<int>(0, (s, r) => s + (r.onHandMilli > 0 ? r.valueMinor : 0));

  Future<String> saveSupplier({String? id, required String name, String? phone, String? address}) async {
    if (name.trim().isEmpty) throw PosException('name_required', 'Name is required');
    final sid = id ?? h.id;
    if (id == null) {
      await h.exec('INSERT INTO supplier(id, name, phone, address, updated_at) VALUES (?,?,?,?,?)', [sid, name.trim(), phone?.trim(), address?.trim(), h.ts]);
    } else {
      await h.exec('UPDATE supplier SET name=?, phone=?, address=?, updated_at=?, version=version+1 WHERE id=?', [name.trim(), phone?.trim(), address?.trim(), h.ts, id]);
    }
    return sid;
  }

  Future<int> supplierBalance(String supplierId) => h.intValue('SELECT COALESCE(SUM(amount_minor),0) FROM supplier_ledger WHERE supplier_id = ?', [supplierId]);

  /// Books a purchase: stock goes up, the average cost is re-weighted, and what was not paid now becomes payable
  /// to the supplier.
  Future<String> purchase({String? supplierId, String? invoiceRef, required List<PurchaseInput> lines, int paidMinor = 0, required String staffId}) => h.db.transaction(() async {
        if (lines.isEmpty) throw PosException('empty', 'Add at least one item');
        if (paidMinor < 0) throw PosException('bad_amount', 'Paid cannot be negative');
        var total = 0;
        for (final l in lines) {
          if (l.qtyMilli <= 0 || l.unitCostMinor < 0) throw PosException('bad_amount', 'Quantity and cost must be valid');
          total += (l.qtyMilli * l.unitCostMinor / 1000).round();
        }
        if (paidMinor > total) throw PosException('overpaid', 'Paid more than the purchase total');
        if (paidMinor < total && supplierId == null) throw PosException('supplier_required', 'Choose a supplier for a credit purchase');
        final pid = h.id;
        await h.exec('INSERT INTO purchase(id, supplier_id, invoice_ref, total_minor, paid_minor, business_date, created_at, staff_id) VALUES (?,?,?,?,?,?,?,?)', [pid, supplierId, invoiceRef?.trim(), total, paidMinor, h.businessDate, h.ts, staffId]);
        for (final l in lines) {
          final item = await h.one('SELECT avg_cost_minor_per_unit FROM stock_item WHERE id = ? AND deleted_at IS NULL', [l.stockItemId]);
          if (item == null) throw PosException('not_found', 'Stock item not found');
          final have = await onHand(l.stockItemId);
          final oldCost = item['avg_cost_minor_per_unit'] as int;
          // weighted average over what is on hand now (negative stock counts as zero)
          final base = have > 0 ? have : 0;
          final newCost = ((base * oldCost + l.qtyMilli * l.unitCostMinor) / (base + l.qtyMilli)).round();
          await h.exec('INSERT INTO purchase_line(id, purchase_id, stock_item_id, qty_milli, unit_cost_minor) VALUES (?,?,?,?,?)', [h.id, pid, l.stockItemId, l.qtyMilli, l.unitCostMinor]);
          await h.exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, purchase_id, unit_cost_minor, staff_id, created_at) VALUES (?,?,?,?,?,?,?,?)', [h.id, l.stockItemId, l.qtyMilli, 'purchase', pid, l.unitCostMinor, staffId, h.ts]);
          await h.exec('UPDATE stock_item SET avg_cost_minor_per_unit = ?, updated_at = ?, version = version + 1 WHERE id = ?', [newCost, h.ts, l.stockItemId]);
        }
        if (supplierId != null) {
          await h.exec('INSERT INTO supplier_ledger(id, supplier_id, kind, amount_minor, purchase_id, created_at) VALUES (?,?,?,?,?,?)', [h.id, supplierId, 'purchase', total, pid, h.ts]);
          if (paidMinor > 0) await h.exec('INSERT INTO supplier_ledger(id, supplier_id, kind, amount_minor, purchase_id, note, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, supplierId, 'payment', -paidMinor, pid, 'Paid at purchase', h.ts]);
        }
        await h.audit('purchase.add', staffId: staffId, entity: 'purchase', entityId: pid, after: {'total': total, 'paid': paidMinor});
        await h.outbox('purchase', pid, 'append', {'id': pid, 'total_minor': total, 'paid_minor': paidMinor, 'supplier_id': supplierId}, 'purchase:$pid');
        return pid;
      });

  Future<void> paySupplier({required String supplierId, required int amountMinor, required String staffId, String? note}) => h.db.transaction(() async {
        if (amountMinor <= 0) throw PosException('bad_amount', 'Amount must be positive');
        final owed = await supplierBalance(supplierId);
        if (amountMinor > owed) throw PosException('overpay', 'You only owe $owed');
        await h.exec('INSERT INTO supplier_ledger(id, supplier_id, kind, amount_minor, note, created_at) VALUES (?,?,?,?,?,?)', [h.id, supplierId, 'payment', -amountMinor, note, h.ts]);
        await h.audit('supplier.payment', staffId: staffId, entity: 'supplier', entityId: supplierId, after: {'amount': amountMinor});
      });

  /// Writes off spoiled or wasted stock. A reason is mandatory and the entry is audited.
  Future<void> wastage({required String stockItemId, required int qtyMilli, required String reason, required String staffId}) => h.db.transaction(() async {
        if (qtyMilli <= 0) throw PosException('bad_amount', 'Quantity must be positive');
        if (reason.trim().isEmpty) throw PosException('reason_required', 'A reason is required');
        await h.exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, note, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, stockItemId, -qtyMilli, 'wastage', reason.trim(), staffId, h.ts]);
        await h.audit('stock.wastage', staffId: staffId, entity: 'stock_item', entityId: stockItemId, after: {'qty_milli': qtyMilli}, reason: reason.trim());
      });

  /// After a physical count: books the difference between counted and recorded stock as an adjustment.
  Future<int> stockCount({required String stockItemId, required int countedMilli, required String staffId, String? note}) => h.db.transaction(() async {
        if (countedMilli < 0) throw PosException('bad_amount', 'Counted quantity cannot be negative');
        final diff = countedMilli - await onHand(stockItemId);
        if (diff != 0) {
          await h.exec('INSERT INTO stock_movement(id, stock_item_id, delta_milli, reason, note, staff_id, created_at) VALUES (?,?,?,?,?,?,?)', [h.id, stockItemId, diff, 'adjustment', note ?? 'Stock count', staffId, h.ts]);
          await h.audit('stock.count', staffId: staffId, entity: 'stock_item', entityId: stockItemId, after: {'diff_milli': diff});
        }
        return diff;
      });

  /// Replaces the recipe of a product (what one portion consumes). Sales then deduct these ingredients.
  Future<void> saveRecipe({required String productId, String? variantId, required Map<String, int> ingredientsMilli}) => h.db.transaction(() async {
        for (final e in ingredientsMilli.entries) {
          if (e.value <= 0) throw PosException('bad_amount', 'Ingredient quantities must be positive');
        }
        await h.exec('DELETE FROM recipe_line WHERE product_id = ? AND variant_id IS ?', [productId, variantId]);
        for (final e in ingredientsMilli.entries) {
          await h.exec('INSERT INTO recipe_line(product_id, variant_id, stock_item_id, qty_milli) VALUES (?,?,?,?)', [productId, variantId, e.key, e.value]);
        }
      });

  Future<Map<String, int>> recipe(String productId, {String? variantId}) async => {
        for (final r in await h.q('SELECT stock_item_id, qty_milli FROM recipe_line WHERE product_id = ? AND variant_id IS ?', [productId, variantId])) r['stock_item_id'] as String: r['qty_milli'] as int
      };

  // ---- purchase orders: ordered from a supplier first, booked into stock when the goods arrive ----

  Future<String> createPurchaseOrder({String? supplierId, required List<PurchaseInput> lines, String? note, String? expectedDate, required String staffId}) => h.db.transaction(() async {
        if (lines.isEmpty) throw PosException('empty', 'Add at least one item');
        for (final l in lines) {
          if (l.qtyMilli <= 0 || l.unitCostMinor < 0) throw PosException('bad_amount', 'Quantity and cost must be valid');
        }
        final n = await h.intValue('SELECT COUNT(*) FROM purchase_order') + 1;
        final id = h.id;
        await h.exec('INSERT INTO purchase_order(id, po_no, supplier_id, note, expected_date, created_at, updated_at, staff_id) VALUES (?,?,?,?,?,?,?,?)',
            [id, 'PO-${n.toString().padLeft(4, '0')}', supplierId, note?.trim(), expectedDate, h.ts, h.ts, staffId]);
        for (final l in lines) {
          await h.exec('INSERT INTO purchase_order_line(id, po_id, stock_item_id, qty_milli, unit_cost_minor) VALUES (?,?,?,?,?)', [h.id, id, l.stockItemId, l.qtyMilli, l.unitCostMinor]);
        }
        await h.audit('po.create', staffId: staffId, entity: 'purchase_order', entityId: id);
        return id;
      });

  Future<List<PurchaseOrderRow>> purchaseOrders() async => [
        for (final r in await h.q('''SELECT o.id, o.po_no, o.status, o.note, o.expected_date, o.supplier_id, COALESCE(s.name, '-') AS supplier, s.phone AS phone,
              (SELECT COUNT(*) FROM purchase_order_line l WHERE l.po_id = o.id) AS n,
              (SELECT COALESCE(SUM(l.qty_milli * l.unit_cost_minor / 1000.0),0) FROM purchase_order_line l WHERE l.po_id = o.id) AS total
            FROM purchase_order o LEFT JOIN supplier s ON s.id = o.supplier_id ORDER BY o.created_at DESC, o.po_no DESC'''))
          PurchaseOrderRow(id: r['id'] as String, poNo: r['po_no'] as String, status: r['status'] as String, supplierName: r['supplier'] as String, supplierPhone: r['phone'] as String?, supplierId: r['supplier_id'] as String?, totalMinor: (r['total'] as num).round(), lines: r['n'] as int, note: r['note'] as String?, expectedDate: r['expected_date'] as String?)
      ];

  Future<List<({String name, String unit, int qtyMilli, int unitCostMinor})>> purchaseOrderLines(String poId) async => [
        for (final r in await h.q('SELECT s.name, s.unit, l.qty_milli, l.unit_cost_minor FROM purchase_order_line l JOIN stock_item s ON s.id = l.stock_item_id WHERE l.po_id = ? ORDER BY l.rowid', [poId]))
          (name: r['name'] as String, unit: r['unit'] as String, qtyMilli: r['qty_milli'] as int, unitCostMinor: r['unit_cost_minor'] as int)
      ];

  Future<void> markPurchaseOrderSent(String poId) => h.exec("UPDATE purchase_order SET status = 'sent', updated_at = ? WHERE id = ? AND status = 'draft'", [h.ts, poId]);

  Future<void> cancelPurchaseOrder(String poId, {required String staffId}) => h.db.transaction(() async {
        final o = await h.one('SELECT status FROM purchase_order WHERE id = ?', [poId]);
        if (o == null) throw PosException('not_found', 'Order not found');
        if (o['status'] == 'received') throw PosException('already_received', 'A received order cannot be cancelled');
        await h.exec("UPDATE purchase_order SET status = 'cancelled', updated_at = ? WHERE id = ?", [h.ts, poId]);
        await h.audit('po.cancel', staffId: staffId, entity: 'purchase_order', entityId: poId);
      });

  /// The goods arrived: books a normal purchase (stock up, average cost, supplier payable) and closes the order.
  /// [actualCostMinor] can correct the unit cost per stock item when the supplier charged differently.
  Future<String> receivePurchaseOrder(String poId, {int paidMinor = 0, Map<String, int> actualCostMinor = const {}, required String staffId}) => h.db.transaction(() async {
        final o = await h.one('SELECT status, supplier_id, po_no FROM purchase_order WHERE id = ?', [poId]);
        if (o == null) throw PosException('not_found', 'Order not found');
        if (o['status'] == 'received') throw PosException('already_received', 'Already received');
        if (o['status'] == 'cancelled') throw PosException('cancelled', 'This order was cancelled');
        final lines = await h.q('SELECT stock_item_id, qty_milli, unit_cost_minor FROM purchase_order_line WHERE po_id = ?', [poId]);
        final pid = await purchase(
          supplierId: o['supplier_id'] as String?,
          invoiceRef: o['po_no'] as String,
          lines: [for (final l in lines) PurchaseInput(stockItemId: l['stock_item_id'] as String, qtyMilli: l['qty_milli'] as int, unitCostMinor: actualCostMinor[l['stock_item_id']] ?? (l['unit_cost_minor'] as int))],
          paidMinor: paidMinor,
          staffId: staffId,
        );
        await h.exec("UPDATE purchase_order SET status = 'received', received_at = ?, purchase_id = ?, updated_at = ? WHERE id = ?", [h.ts, pid, h.ts, poId]);
        return pid;
      });

  /// Message to send the supplier (WhatsApp / share sheet).
  Future<String> purchaseOrderText(String poId, {required String businessName}) async {
    final o = (await purchaseOrders()).firstWhere((x) => x.id == poId);
    final lines = await purchaseOrderLines(poId);
    String q(int m) => m % 1000 == 0 ? '${m ~/ 1000}' : (m / 1000).toStringAsFixed(2);
    return [
      '*$businessName* — ${o.poNo}',
      if (o.supplierName != '-') 'To: ${o.supplierName}',
      if (o.expectedDate != null) 'Needed by: ${o.expectedDate}',
      '',
      for (final l in lines) '• ${q(l.qtyMilli)} ${l.unit} ${l.name}',
      if (o.note != null && o.note!.isNotEmpty) '\n${o.note}',
    ].join('\n');
  }
}
