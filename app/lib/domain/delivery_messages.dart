/// The customer's WhatsApp messages for a delivery order. Plain text, built from what the order and the settings say; the person
/// presses Send themselves. [t] gives the words in the app's language.
class PayAccount {
  const PayAccount({required this.name, this.number, this.holder, this.provider, this.qrPath});
  final String name;
  final String? number;
  final String? holder;
  final String? provider;

  /// A picture of the account's payment QR (kept on the phone), if one was added in Payment accounts.
  final String? qrPath;
}

class MessageOrder {
  const MessageOrder({
    required this.customerName,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.delivery,
    required this.total,
    required this.due,
    this.ref,
    this.address,
    this.city,
    this.rider,
    this.riderPhone,
    this.platform,
  });
  final String customerName;

  /// One line per item, already worded (e.g. "2 x Zinger Burger").
  final List<String> items;

  /// Money, already formatted with the currency.
  final String subtotal, discount, delivery, total, due;
  final String? ref;
  final String? address;
  final String? city;
  final String? rider;
  final String? riderPhone;
  final String? platform;
}

enum DeliveryMessageKind { confirmation, bill, dispatch, delivered, paymentReminder }

String _lines(MessageOrder o, String Function(String) t) => [for (final i in o.items) '• $i'].join('\n');

String _where(MessageOrder o) => [if ((o.address ?? '').trim().isNotEmpty) o.address!.trim(), if ((o.city ?? '').trim().isNotEmpty) o.city!.trim()].join(', ');

/// Bank / wallet details for the customer to pay into, with the owner's own instructions underneath.
String paymentBlock(List<PayAccount> accounts, String instructions, String Function(String) t) {
  final b = StringBuffer();
  if (accounts.isNotEmpty) {
    b.writeln('*${t('msg_pay_to')}*');
    for (final a in accounts) {
      b.writeln(a.provider == null || a.provider!.isEmpty ? a.name : '${a.name} (${a.provider})');
      if ((a.number ?? '').isNotEmpty) b.writeln('${t('msg_account_no')}: ${a.number}');
      if ((a.holder ?? '').isNotEmpty) b.writeln('${t('msg_account_title')}: ${a.holder}');
    }
  }
  if (instructions.trim().isNotEmpty) {
    if (b.isNotEmpty) b.writeln();
    b.writeln(instructions.trim());
  }
  return b.toString().trimRight();
}

String buildDeliveryMessage(DeliveryMessageKind kind, {required String business, required MessageOrder order, List<PayAccount> accounts = const [], String instructions = '', required String Function(String) t}) {
  final o = order;
  final head = StringBuffer();
  final ref = o.ref == null || o.ref!.isEmpty ? '' : ' ${o.ref}';
  switch (kind) {
    case DeliveryMessageKind.confirmation:
      head
        ..writeln('*$business*')
        ..writeln('${t('msg_hello')} ${o.customerName},')
        ..writeln('${t('msg_confirmed')}$ref ✅')
        ..writeln()
        ..writeln(_lines(o, t))
        ..writeln()
        ..writeln('${t('total')}: ${o.total}');
      if (_where(o).isNotEmpty) head.writeln('${t('msg_deliver_to')}: ${_where(o)}');
      head.writeln(t('msg_thanks'));
    case DeliveryMessageKind.bill:
      head
        ..writeln('*$business*')
        ..writeln('${t('msg_bill_for')}$ref')
        ..writeln()
        ..writeln(_lines(o, t))
        ..writeln()
        ..writeln('${t('subtotal')}: ${o.subtotal}');
      if (o.discount.isNotEmpty) head.writeln('${t('discount')}: -${o.discount}');
      if (o.delivery.isNotEmpty) head.writeln('${t('delivery_charge')}: ${o.delivery}');
      head.writeln('*${t('total')}: ${o.total}*');
      if (o.due != o.total && o.due.isNotEmpty) head.writeln('${t('msg_due')}: ${o.due}');
    case DeliveryMessageKind.dispatch:
      head
        ..writeln('*$business*')
        ..writeln('${t('msg_hello')} ${o.customerName},')
        ..writeln('${t('msg_on_the_way')}$ref 🛵');
      if ((o.rider ?? '').isNotEmpty) head.writeln('${t('msg_rider')}: ${o.rider}${(o.riderPhone ?? '').isEmpty ? '' : ' (${o.riderPhone})'}');
      head.writeln('${t('msg_amount_due')}: ${o.due}');
    case DeliveryMessageKind.delivered:
      head
        ..writeln('*$business*')
        ..writeln('${t('msg_hello')} ${o.customerName},')
        ..writeln('${t('msg_delivered')}$ref ✅')
        ..writeln(t('msg_thanks'));
    case DeliveryMessageKind.paymentReminder:
      head
        ..writeln('*$business*')
        ..writeln('${t('msg_hello')} ${o.customerName},')
        ..writeln('${t('msg_reminder')}$ref: *${o.due}*');
  }
  final needsPay = kind == DeliveryMessageKind.bill || kind == DeliveryMessageKind.dispatch || kind == DeliveryMessageKind.paymentReminder || kind == DeliveryMessageKind.confirmation;
  final pay = needsPay ? paymentBlock(accounts, instructions, t) : '';
  return [head.toString().trimRight(), if (pay.isNotEmpty) '', if (pay.isNotEmpty) pay].join('\n');
}
