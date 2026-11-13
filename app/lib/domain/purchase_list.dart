import '../data/inventory_service.dart';
import 'escpos.dart' show PrintAlign;
import 'money.dart';
import 'receipt_doc.dart';

/// How much to buy so stock is back at twice its reorder level (never less than one reorder level).
int suggestedBuyMilli(StockRow r) {
  final target = r.reorderMilli * 2;
  final need = target - (r.onHandMilli < 0 ? 0 : r.onHandMilli);
  return need < r.reorderMilli ? r.reorderMilli : need;
}

/// The items that are low, as a shopping list: what to buy, what is left. Plain text for WhatsApp.
String purchaseListText(String business, List<StockRow> low, String date) {
  final b = StringBuffer('*Purchase list${business.isEmpty ? '' : ' - $business'}*\n$date\n\n');
  var i = 1;
  for (final r in low) {
    b.writeln('${i++}. ${r.name}: buy ${formatQty(suggestedBuyMilli(r))} ${r.unit} (left ${formatQty(r.onHandMilli < 0 ? 0 : r.onHandMilli)})');
  }
  return b.toString().trimRight();
}

/// The same list as a short slip for the counter printer.
ReceiptDoc purchaseListDoc(String business, List<StockRow> low, String date) => ReceiptDoc([
      if (business.isNotEmpty) RText(business, align: PrintAlign.center, bold: true),
      const RText('PURCHASE LIST', align: PrintAlign.center, bold: true),
      RText(date, align: PrintAlign.center),
      const RRule('='),
      for (final r in low) RRow(r.name, '${formatQty(suggestedBuyMilli(r))} ${r.unit}'),
      const RRule(),
      RText('${low.length} item(s) below reorder level'),
    ]);
