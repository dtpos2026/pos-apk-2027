import 'customer_service.dart';
import 'db_helper.dart';
import 'pos_service.dart';

const onlineChannels = ['whatsapp', 'phone', 'foodpanda', 'other'];

class OnlineOrder {
  const OnlineOrder({required this.id, required this.channel, required this.customerName, this.phone, this.address, required this.totalMinor, required this.itemsText, required this.status, required this.createdAt, this.note});
  final String id;
  final String channel;
  final String customerName;
  final String? phone;
  final String? address;
  final int totalMinor;
  final String itemsText;

  /// held = waiting to be accepted; new / preparing / ready / served = accepted and in the kitchen
  final String status;
  final int createdAt;
  final String? note;
  bool get pending => status == 'held';
}

/// Orders that arrive outside the counter (WhatsApp, phone, delivery apps) and are typed in by staff.
/// They wait as PENDING until accepted; accepting sends them to the kitchen (board + ticket) and they are paid like any other order.
class OnlineOrderService {
  OnlineOrderService(this.h, this.pos, this.customers);
  final DbHelper h;
  final PosService pos;
  final CustomerService customers;

  static String tag(String channel) => '[${channel.toUpperCase()}]';

  Future<String> create({required String channel, required String customerName, String? phone, String? address, required List<CartItem> items, String? note, required String staffId}) async {
    if (items.isEmpty) throw PosException('empty', 'Add at least one item');
    if (customerName.trim().isEmpty) throw PosException('name_required', 'Customer name is required');
    if (!onlineChannels.contains(channel)) channel = 'other';
    final p = phone?.trim().isEmpty ?? true ? null : phone!.trim();
    String? customerId;
    if (p != null) {
      customerId = (await h.one('SELECT id FROM customer WHERE phone = ? AND deleted_at IS NULL', [p]))?['id'] as String?;
    }
    customerId ??= p == null && (address?.trim().isEmpty ?? true) ? null : await customers.save(name: customerName, phone: p, address: address, staffId: staffId);
    return pos.saveDraft(
      DraftOrder(orderType: 'delivery', items: items, customerId: customerId, note: '${tag(channel)} ${customerName.trim()}${note == null || note.trim().isEmpty ? '' : ' - ${note.trim()}'}', held: true, source: 'online', deliveryAddress: address?.trim()),
      staffId: staffId,
    );
  }

  Future<List<OnlineOrder>> orders() async => [
        for (final r in await h.q('''SELECT o.id, o.status, o.note, o.total_minor, o.created_at, o.delivery_address, c.phone AS phone,
              (SELECT GROUP_CONCAT(CASE WHEN i.qty_milli % 1000 = 0 THEN (i.qty_milli / 1000) || ' x ' ELSE '' END || i.name, ', ') FROM order_item i WHERE i.order_id = o.id AND i.status = 'active') AS items
            FROM "order" o LEFT JOIN customer c ON c.id = o.customer_id
            WHERE o.source = 'online' AND o.status IN ('held','new','preparing','ready','served') ORDER BY o.created_at DESC'''))
          _parse(r)
      ];

  OnlineOrder _parse(Map<String, Object?> r) {
    final note = (r['note'] as String?) ?? '';
    final m = RegExp(r'^\[([A-Z]+)\]\s*(.*)$').firstMatch(note);
    final channel = (m?.group(1) ?? 'OTHER').toLowerCase();
    var rest = m?.group(2) ?? note;
    var name = rest, extra = '';
    final dash = rest.indexOf(' - ');
    if (dash >= 0) {
      name = rest.substring(0, dash);
      extra = rest.substring(dash + 3);
    }
    return OnlineOrder(id: r['id'] as String, channel: channel, customerName: name, phone: r['phone'] as String?, address: r['delivery_address'] as String?, totalMinor: r['total_minor'] as int, itemsText: (r['items'] as String?) ?? '', status: r['status'] as String, createdAt: r['created_at'] as int, note: extra.isEmpty ? null : extra);
  }

  Future<void> reject(String orderId) async {
    final o = await h.one("SELECT status FROM \"order\" WHERE id = ? AND source = 'online'", [orderId]);
    if (o == null || o['status'] != 'held') throw PosException('not_pending', 'Only a waiting order can be rejected');
    await pos.discardDraft(orderId);
  }

  /// Message for the customer, e.g. "Your order is accepted".
  static String acceptedText(String business, OnlineOrder o, String total) => '$business: order accepted ✅\n${o.itemsText}\nTotal: $total';
}
