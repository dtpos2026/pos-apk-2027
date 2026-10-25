import '../domain/bill.dart';
import 'customer_service.dart';
import 'db_helper.dart';
import 'pos_service.dart';

/// Old channel names (kept so older code and tests keep working); the real list is the editable order sources.
const onlineChannels = ['whatsapp', 'phone', 'foodpanda', 'other'];

/// The order of a delivery order's life. An order can skip ahead, never go back; it can be cancelled until it is delivered.
const deliveryStatuses = ['pending', 'confirmed', 'preparing', 'ready', 'dispatched', 'delivered'];

class OrderSource {
  const OrderSource({required this.id, required this.name, required this.platform, required this.active});
  final String id;
  final String name;

  /// true = a third-party platform (Foodpanda, Grab & Go...); false = received directly by the restaurant.
  final bool platform;
  final bool active;
}

/// The sources every restaurant starts with. Staff can rename, add and switch them off in Settings.
const _defaultSources = [
  (name: 'Direct WhatsApp Order', platform: false),
  (name: 'Phone Order', platform: false),
  (name: 'Walk-in / Manual Entry', platform: false),
  (name: 'Foodpanda', platform: true),
  (name: 'Grab & Go', platform: true),
  (name: 'Other / Custom Source', platform: false),
];

class OnlineOrder {
  const OnlineOrder({
    required this.id,
    required this.channel,
    required this.customerName,
    this.phone,
    this.address,
    required this.totalMinor,
    required this.itemsText,
    required this.status,
    required this.createdAt,
    this.note,
    this.invoiceNo,
    this.customerId,
    this.city,
    this.subtotalMinor = 0,
    this.discountMinor = 0,
    this.deliveryChargeMinor = 0,
    this.paidMinor = 0,
    this.deliveryStatus = 'pending',
    this.sourceId,
    this.sourceName = '',
    this.platform = false,
    this.platformRef,
    this.fulfilment = 'delivery',
    this.riderId,
    this.riderName,
    this.riderPhone,
  });
  final String id;
  final String channel;
  final String customerName;
  final String? phone;
  final String? address;
  final int totalMinor;
  final String itemsText;

  /// The bill's own status: held = waiting to be accepted; new / preparing / ready / served = in the kitchen; paid...
  final String status;
  final int createdAt;
  final String? note;
  final String? invoiceNo;
  final String? customerId;
  final String? city;
  final int subtotalMinor;
  final int discountMinor;
  final int deliveryChargeMinor;
  final int paidMinor;

  /// pending | confirmed | preparing | ready | dispatched | delivered | cancelled
  final String deliveryStatus;
  final String? sourceId;
  final String sourceName;

  /// true = came through a third-party platform.
  final bool platform;
  final String? platformRef;

  /// delivery | pickup
  final String fulfilment;
  final String? riderId;
  final String? riderName;
  final String? riderPhone;

  bool get pending => status == 'held';
  bool get closed => deliveryStatus == 'delivered' || deliveryStatus == 'cancelled';
  String get paymentStatus => paidMinor >= totalMinor && totalMinor > 0 ? 'paid' : (paidMinor > 0 ? 'partial' : 'unpaid');
  int get dueMinor => (totalMinor - paidMinor).clamp(0, totalMinor);
}

class StatusStep {
  const StatusStep(this.status, this.at, this.staff);
  final String status;
  final int at;
  final String? staff;
}

/// Totals for one source (or "direct" / "platforms") in a date range.
class SourceTotal {
  const SourceTotal({required this.name, required this.platform, this.orders = 0, this.salesMinor = 0, this.paidMinor = 0, this.delivered = 0, this.cancelled = 0});
  final String name;
  final bool platform;
  final int orders;
  final int salesMinor;
  final int paidMinor;
  final int delivered;
  final int cancelled;
  int get dueMinor => salesMinor - paidMinor;
}

/// Delivery orders: those typed in by staff (WhatsApp, phone, a delivery platform) and those taken in the POS with the Delivery type.
/// An order waits as PENDING until it is confirmed; confirming sends it to the kitchen. It then moves through preparing, ready,
/// dispatched (with a rider) and delivered, every step written to a history. Money is taken like any other bill.
class OnlineOrderService {
  OnlineOrderService(this.h, this.pos, this.customers);
  final DbHelper h;
  final PosService pos;
  final CustomerService customers;

  static String tag(String channel) => '[${channel.toUpperCase()}]';

  // ---- order sources ----

  Future<List<OrderSource>> sources({bool activeOnly = false}) async {
    if ((await h.intValue('SELECT COUNT(*) FROM order_source')) == 0) {
      var i = 0;
      for (final s in _defaultSources) {
        await h.exec('INSERT INTO order_source(id, name, kind, sort, updated_at) VALUES (?,?,?,?,?)', [h.id, s.name, s.platform ? 'platform' : 'direct', i++, h.ts]);
      }
    }
    return [
      for (final r in await h.q("SELECT id, name, kind, active FROM order_source WHERE deleted_at IS NULL ${activeOnly ? 'AND active = 1' : ''} ORDER BY sort, name"))
        OrderSource(id: r['id'] as String, name: r['name'] as String, platform: r['kind'] == 'platform', active: (r['active'] as int) == 1)
    ];
  }

  Future<String> saveSource({String? id, required String name, required bool platform, bool active = true}) async {
    final n = name.trim();
    if (n.isEmpty) throw PosException('name_required', 'Name is required');
    await sources();
    final dup = await h.one('SELECT id FROM order_source WHERE lower(name) = lower(?) AND deleted_at IS NULL AND id <> ?', [n, id ?? '']);
    if (dup != null) throw PosException('duplicate', 'A source called "$n" already exists');
    final sid = id ?? h.id;
    if (id == null) {
      final next = await h.intValue('SELECT COALESCE(MAX(sort), 0) + 1 FROM order_source');
      await h.exec('INSERT INTO order_source(id, name, kind, active, sort, updated_at) VALUES (?,?,?,?,?,?)', [sid, n, platform ? 'platform' : 'direct', active ? 1 : 0, next, h.ts]);
    } else {
      await h.exec('UPDATE order_source SET name=?, kind=?, active=?, updated_at=? WHERE id=?', [n, platform ? 'platform' : 'direct', active ? 1 : 0, h.ts, id]);
    }
    return sid;
  }

  /// A source that orders already use is only hidden (old orders keep their name); an unused one is removed.
  Future<void> deleteSource(String id) async {
    final used = await h.intValue('SELECT COUNT(*) FROM delivery_info WHERE source_id = ?', [id]);
    if (used > 0) {
      await h.exec('UPDATE order_source SET active = 0, deleted_at = ?, updated_at = ? WHERE id = ?', [h.ts, h.ts, id]);
    } else {
      await h.exec('DELETE FROM order_source WHERE id = ?', [id]);
    }
  }

  Future<String> _defaultSourceId() async {
    final all = await sources(activeOnly: true);
    return (all.where((s) => s.name == 'Walk-in / Manual Entry').firstOrNull ?? all.first).id;
  }

  Future<String?> _sourceForChannel(String channel) async {
    final all = await sources();
    final wanted = switch (channel) { 'whatsapp' => 'Direct WhatsApp Order', 'phone' => 'Phone Order', 'foodpanda' => 'Foodpanda', _ => 'Other / Custom Source' };
    return all.where((s) => s.name == wanted).firstOrNull?.id;
  }

  // ---- creating ----

  /// A delivery order, waiting as pending. The customer is an existing one ([customerId]) or typed in (name, phone, address, city) and
  /// then saved, so next time the phone number finds them. [sourceId] is optional (default: Walk-in / Manual Entry).
  Future<String> create({
    String? channel,
    String? sourceId,
    String? customerId,
    String customerName = '',
    String? phone,
    String? address,
    String? city,
    required List<CartItem> items,
    String? note,
    String? platformRef,
    String fulfilment = 'delivery',
    String? riderId,
    int deliveryChargeMinor = 0,
    int discountMinor = 0,
    required String staffId,
  }) async {
    if (items.isEmpty) throw PosException('empty', 'Add at least one item');
    if (deliveryChargeMinor < 0 || discountMinor < 0) throw PosException('bad_amount', 'Amounts cannot be negative');
    var name = customerName.trim();
    final p = phone?.trim().isEmpty ?? true ? null : phone!.trim();
    if (customerId != null) {
      final c = await h.one('SELECT name, phone, address, city FROM customer WHERE id = ? AND deleted_at IS NULL', [customerId]);
      if (c == null) throw PosException('not_found', 'Customer not found');
      if (name.isEmpty) name = c['name'] as String;
      address = (address?.trim().isEmpty ?? true) ? c['address'] as String? : address;
      city = (city?.trim().isEmpty ?? true) ? c['city'] as String? : city;
      phone = p ?? c['phone'] as String?;
    } else {
      if (name.isEmpty) throw PosException('name_required', 'Customer name is required');
      if (fulfilment == 'delivery' && !(sourceId != null && (await _isPlatform(sourceId))) && (address?.trim().isEmpty ?? true) && channel == null) {
        // an address is needed to deliver; a platform order or a pickup may leave it out (the platform has it)
        throw PosException('address_required', 'Write the delivery address');
      }
      if (p != null) customerId = (await h.one('SELECT id FROM customer WHERE phone = ? AND deleted_at IS NULL', [p]))?['id'] as String?;
      if (customerId != null) {
        // the number is already a customer: keep their record, learn a new address / city if they had none
        await h.exec("UPDATE customer SET address = COALESCE(NULLIF(address, ''), ?), city = COALESCE(NULLIF(city, ''), ?), updated_at = ? WHERE id = ?", [address?.trim(), city?.trim(), h.ts, customerId]);
      } else if (p != null || !(address?.trim().isEmpty ?? true)) {
        customerId = await customers.save(name: name, phone: p, address: address, city: city, staffId: staffId);
      }
      phone = p;
    }
    final source = sourceId ?? (channel != null ? await _sourceForChannel(channel) : null) ?? await _defaultSourceId();
    final sRow = await h.one('SELECT name, kind FROM order_source WHERE id = ?', [source]);
    if (sRow == null) throw PosException('bad_source', 'Choose a valid order source');
    final ref = platformRef?.trim().isEmpty ?? true ? null : platformRef!.trim();
    if (ref != null) {
      // the same platform order typed twice would be cooked and billed twice
      final dup = await h.one("SELECT i.order_id FROM delivery_info i JOIN \"order\" o ON o.id = i.order_id WHERE i.source_id = ? AND lower(i.platform_ref) = lower(?) AND i.status <> 'cancelled' AND o.status NOT IN ('void','cancelled')", [source, ref]);
      if (dup != null) throw PosException('duplicate_order', 'Order $ref from ${sRow['name']} is already entered');
    }
    final chan = channel ?? switch (sRow['name']) { 'Direct WhatsApp Order' => 'whatsapp', 'Phone Order' => 'phone', 'Foodpanda' => 'foodpanda', _ => 'other' };
    final id = await pos.saveDraft(
      DraftOrder(
        orderType: 'delivery',
        items: items,
        customerId: customerId,
        note: '${tag(chan)} $name${note == null || note.trim().isEmpty ? '' : ' - ${note.trim()}'}',
        held: true,
        source: 'online',
        deliveryAddress: address?.trim(),
        riderId: riderId,
        config: BillConfig(deliveryChargeMinor: deliveryChargeMinor, billDiscount: discountMinor > 0 ? Discount.fixed(discountMinor) : null),
      ),
      staffId: staffId,
    );
    await h.exec(
        'INSERT INTO delivery_info(order_id, status, city, channel, customer_name, note, source_id, platform_ref, fulfilment, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [id, 'pending', city?.trim().isEmpty ?? true ? null : city!.trim(), chan, name, note?.trim(), source, ref, fulfilment, h.ts]);
    await h.exec('INSERT INTO delivery_status_log(id, order_id, status, staff_id, created_at) VALUES (?,?,?,?,?)', [h.id, id, 'pending', staffId, h.ts]);
    await h.audit('delivery.create', staffId: staffId, entity: 'order', entityId: id, after: {'source': sRow['name'], 'ref': ref});
    return id;
  }

  Future<bool> _isPlatform(String sourceId) async => (await h.one('SELECT kind FROM order_source WHERE id = ?', [sourceId]))?['kind'] == 'platform';

  // ---- listing ----

  static const _select = '''SELECT o.id, o.invoice_no, o.status, o.note, o.total_minor, o.subtotal_minor, o.discount_minor, o.delivery_charge_minor, o.paid_minor, o.created_at,
          o.delivery_address, o.customer_id, o.source AS osource, o.rider_id, c.phone AS phone, c.name AS cname, COALESCE(di.city, c.city) AS city,
          di.status AS dstatus, di.channel, di.customer_name, di.note AS dnote, di.platform_ref, COALESCE(di.fulfilment, 'delivery') AS fulfilment,
          s.id AS sid, s.name AS sname, s.kind AS skind, m.name AS rider, m.phone AS rider_phone,
          (SELECT GROUP_CONCAT(CASE WHEN i.qty_milli % 1000 = 0 THEN (i.qty_milli / 1000) || ' x ' ELSE '' END || i.name, ', ') FROM order_item i WHERE i.order_id = o.id AND i.status = 'active') AS items
        FROM "order" o LEFT JOIN customer c ON c.id = o.customer_id LEFT JOIN delivery_info di ON di.order_id = o.id
        LEFT JOIN order_source s ON s.id = di.source_id LEFT JOIN team_member m ON m.id = o.rider_id''';

  /// What the old inbox showed: web/phone orders still open.
  Future<List<OnlineOrder>> orders() async => [
        for (final r in await h.q("$_select WHERE o.source = 'online' AND o.status IN ('held','new','preparing','ready','served') ORDER BY o.created_at DESC")) _parse(r)
      ];

  /// Every delivery order (online or taken in the POS as Delivery), newest first, narrowed by the filters. Dates are business dates.
  Future<List<OnlineOrder>> list({String? from, String? to, bool? platform, String? sourceId, String? payment, String? status, bool openOnly = false}) async {
    final rows = await h.q(
        "$_select WHERE (o.source = 'online' OR o.order_type = 'delivery') AND o.status NOT IN ('draft') AND o.business_date BETWEEN ? AND ? ORDER BY o.created_at DESC, o.rowid DESC",
        [from ?? '0000-00-00', to ?? '9999-99-99']);
    return [
      for (final r in rows)
        _parse(r)
    ].where((o) {
      if (platform != null && o.platform != platform) return false;
      if (sourceId != null && o.sourceId != sourceId) return false;
      if (payment != null && o.paymentStatus != payment) return false;
      if (status != null && o.deliveryStatus != status) return false;
      if (openOnly && o.closed) return false;
      return true;
    }).toList();
  }

  /// Orders taken in the POS have no delivery record: their status follows the bill.
  static String _derived(String orderStatus) => switch (orderStatus) {
        'held' => 'pending',
        'new' => 'confirmed',
        'preparing' => 'preparing',
        'ready' || 'served' => 'ready',
        'paid' || 'refunded' => 'delivered',
        _ => 'cancelled',
      };

  OnlineOrder _parse(Map<String, Object?> r) {
    final note = (r['note'] as String?) ?? '';
    final m = RegExp(r'^\[([A-Z]+)\]\s*(.*)$').firstMatch(note);
    var channel = (r['channel'] as String?) ?? (m?.group(1) ?? 'OTHER').toLowerCase();
    final rest = m?.group(2) ?? note;
    var name = (r['customer_name'] as String?) ?? rest, extra = (r['dnote'] as String?) ?? '';
    if (r['customer_name'] == null) {
      final dash = rest.indexOf(' - ');
      if (dash >= 0) {
        name = rest.substring(0, dash);
        extra = rest.substring(dash + 3);
      }
      if (m == null) name = (r['cname'] as String?) ?? '';
    }
    final orderStatus = r['status'] as String;
    var ds = (r['dstatus'] as String?) ?? _derived(orderStatus);
    if (ds == 'pending' && orderStatus != 'held') ds = 'confirmed';
    if (ds != 'cancelled' && ds != 'delivered' && const {'void', 'cancelled'}.contains(orderStatus)) ds = 'cancelled';
    if (ds != 'cancelled' && ds != 'delivered' && orderStatus == 'paid' && r['dstatus'] == null) ds = 'delivered';
    final posOrder = r['osource'] != 'online';
    return OnlineOrder(
      id: r['id'] as String,
      channel: channel,
      customerName: name,
      phone: r['phone'] as String?,
      address: r['delivery_address'] as String?,
      totalMinor: r['total_minor'] as int,
      itemsText: (r['items'] as String?) ?? '',
      status: orderStatus,
      createdAt: r['created_at'] as int,
      note: extra.isEmpty ? null : extra,
      invoiceNo: r['invoice_no'] as String?,
      customerId: r['customer_id'] as String?,
      city: r['city'] as String?,
      subtotalMinor: r['subtotal_minor'] as int,
      discountMinor: r['discount_minor'] as int,
      deliveryChargeMinor: r['delivery_charge_minor'] as int,
      paidMinor: orderStatus == 'paid' ? r['total_minor'] as int : r['paid_minor'] as int,
      deliveryStatus: ds,
      sourceId: r['sid'] as String?,
      sourceName: (r['sname'] as String?) ?? (posOrder ? 'POS' : ''),
      platform: r['skind'] == 'platform',
      platformRef: r['platform_ref'] as String?,
      fulfilment: r['fulfilment'] as String,
      riderId: r['rider_id'] as String?,
      riderName: r['rider'] as String?,
      riderPhone: r['rider_phone'] as String?,
    );
  }

  Future<OnlineOrder?> byId(String id) async {
    final r = (await h.q('$_select WHERE o.id = ?', [id])).firstOrNull;
    return r == null ? null : _parse(r);
  }

  // ---- moving an order along ----

  /// Next step(s) allowed from [from]: forward in the chain (a step may be skipped), or cancel until delivered. Pickup orders
  /// never go out with a rider: they skip "dispatched".
  static List<String> nextSteps(String from, {String fulfilment = 'delivery'}) {
    final i = deliveryStatuses.indexOf(from);
    if (i < 0) return const [];
    return [for (final s in deliveryStatuses.skip(i + 1)) if (!(fulfilment == 'pickup' && s == 'dispatched')) s, if (from != 'delivered') 'cancelled'];
  }

  Future<void> setStatus(String orderId, String status, {required String staffId, String? riderId}) => h.db.transaction(() async {
        final o = await byId(orderId);
        if (o == null) throw PosException('not_found', 'Order not found');
        final stored = (await h.one('SELECT status FROM delivery_info WHERE order_id = ?', [orderId]))?['status'] as String?;
        if (stored == status) return;
        // (a bill the kitchen already accepted shows "confirmed" before anyone wrote it down: writing it down is allowed)
        if (o.deliveryStatus != status && !nextSteps(o.deliveryStatus, fulfilment: o.fulfilment).contains(status)) throw PosException('bad_status', 'This order cannot go from ${o.deliveryStatus} to $status');
        if (status == 'dispatched') {
          final rider = riderId ?? o.riderId;
          if (rider == null) throw PosException('rider_required', 'Choose the rider before dispatching');
          await h.exec('UPDATE "order" SET rider_id = ?, updated_at = ?, version = version + 1 WHERE id = ?', [rider, h.ts, orderId]);
        }
        if (status == 'cancelled') {
          if (o.paidMinor > 0 || o.status == 'paid') throw PosException('already_paid', 'A paid order cannot be cancelled here: refund it from Bills');
          await _cancelBill(orderId, o.status, staffId, 'Delivery order cancelled');
        }
        final has = await h.one('SELECT order_id FROM delivery_info WHERE order_id = ?', [orderId]);
        if (has == null) {
          await h.exec("INSERT INTO delivery_info(order_id, status, channel, source_id, updated_at) VALUES (?,?,'other',?,?)", [orderId, status, await _defaultSourceId(), h.ts]);
        } else {
          await h.exec('UPDATE delivery_info SET status = ?, updated_at = ? WHERE order_id = ?', [status, h.ts, orderId]);
        }
        await h.exec('INSERT INTO delivery_status_log(id, order_id, status, staff_id, created_at) VALUES (?,?,?,?,?)', [h.id, orderId, status, staffId, h.ts]);
        await h.audit('delivery.$status', staffId: staffId, entity: 'order', entityId: orderId);
        if (status == 'delivered') {
          // the food has reached the customer: whatever is still open on the kitchen board is finished
          final k = await h.one('SELECT status FROM kitchen_event WHERE order_id = ? ORDER BY at DESC, rowid DESC LIMIT 1', [orderId]);
          if (k != null && k['status'] != 'served') {
            await h.exec('INSERT INTO kitchen_event(id, order_id, status, at, staff_id) VALUES (?,?,?,?,?)', [h.id, orderId, 'served', h.ts, staffId]);
          }
        }
      });

  /// The bill is kept (as cancelled) so history and reports still show it. A waiting order never reached the kitchen, so anyone may
  /// refuse it; one already in the kitchen is cancelled the normal way (which needs the void permission).
  Future<void> _cancelBill(String orderId, String billStatus, String staffId, String reason) async {
    if (billStatus == 'held') {
      await h.exec("UPDATE \"order\" SET status = 'cancelled', updated_at = ?, version = version + 1 WHERE id = ? AND status = 'held'", [h.ts, orderId]);
    } else {
      await pos.cancelOrder(orderId, staffId: staffId, reason: reason);
    }
  }

  Future<void> assignRider(String orderId, String? riderId, {required String staffId}) async {
    await h.exec('UPDATE "order" SET rider_id = ?, updated_at = ?, version = version + 1 WHERE id = ?', [riderId, h.ts, orderId]);
    await h.audit('delivery.rider', staffId: staffId, entity: 'order', entityId: orderId, after: {'rider': riderId});
  }

  Future<List<StatusStep>> history(String orderId) async => [
        for (final r in await h.q('SELECT l.status, l.created_at, s.name AS staff FROM delivery_status_log l LEFT JOIN staff s ON s.id = l.staff_id WHERE l.order_id = ? ORDER BY l.created_at, l.rowid', [orderId]))
          StatusStep(r['status'] as String, r['created_at'] as int, r['staff'] as String?)
      ];

  Future<void> reject(String orderId, {String staffId = ''}) async {
    final o = await h.one("SELECT status FROM \"order\" WHERE id = ? AND source = 'online'", [orderId]);
    if (o == null || o['status'] != 'held') throw PosException('not_pending', 'Only a waiting order can be rejected');
    await _cancelBill(orderId, 'held', staffId, 'Delivery order rejected');
    await h.exec("UPDATE delivery_info SET status = 'cancelled', updated_at = ? WHERE order_id = ?", [h.ts, orderId]);
    await h.exec('INSERT INTO delivery_status_log(id, order_id, status, staff_id, created_at) VALUES (?,?,?,?,?)', [h.id, orderId, 'cancelled', staffId.isEmpty ? null : staffId, h.ts]);
  }

  // ---- reports ----

  /// Sales per source and in total for direct and for platform orders (cancelled orders are counted but carry no sales).
  Future<({List<SourceTotal> bySource, SourceTotal direct, SourceTotal platforms})> totals(String from, String to) async {
    final all = await list(from: from, to: to);
    final map = <String, SourceTotal>{};
    SourceTotal add(SourceTotal? t, OnlineOrder o, String name) {
      final cancelled = o.deliveryStatus == 'cancelled';
      return SourceTotal(
        name: name,
        platform: o.platform,
        orders: (t?.orders ?? 0) + 1,
        salesMinor: (t?.salesMinor ?? 0) + (cancelled ? 0 : o.totalMinor),
        paidMinor: (t?.paidMinor ?? 0) + (cancelled ? 0 : o.paidMinor),
        delivered: (t?.delivered ?? 0) + (o.deliveryStatus == 'delivered' ? 1 : 0),
        cancelled: (t?.cancelled ?? 0) + (cancelled ? 1 : 0),
      );
    }

    var direct = const SourceTotal(name: 'Direct', platform: false), platforms = const SourceTotal(name: 'Platforms', platform: true);
    for (final o in all) {
      final n = o.sourceName.isEmpty ? 'Other' : o.sourceName;
      map[n] = add(map[n], o, n);
      if (o.platform) {
        platforms = add(platforms, o, 'Platforms');
      } else {
        direct = add(direct, o, 'Direct');
      }
    }
    return (bySource: map.values.toList()..sort((a, b) => b.salesMinor.compareTo(a.salesMinor)), direct: direct, platforms: platforms);
  }

  /// Message for the customer, e.g. "Your order is accepted".
  static String acceptedText(String business, OnlineOrder o, String total) => '$business: order accepted ✅\n${o.itemsText}\nTotal: $total';
}
