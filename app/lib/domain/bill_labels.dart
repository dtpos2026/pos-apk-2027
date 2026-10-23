/// Words printed on the customer bill, per bill language. The owner chooses the bill language independently of the
/// app language (an English app can print Urdu bills and the other way round).
class BillLabels {
  const BillLabels(this._m, {required this.rtl});
  final Map<String, String> _m;
  final bool rtl;
  String operator [](String k) => _m[k] ?? _en[k] ?? k;

  static const supported = ['en', 'ur', 'ar'];

  static BillLabels of(String lang) => switch (lang) { 'ur' => _ur, 'ar' => _ar, _ => _enLabels };

  static const _en = <String, String>{
    'invoice': 'Invoice',
    'date': 'Date',
    'type': 'Type',
    'cashier': 'Cashier',
    'subtotal': 'Subtotal',
    'discount': 'Discount',
    'service': 'Service charge',
    'delivery': 'Delivery',
    'tax': 'Tax',
    'tip': 'Tip',
    'rounding': 'Rounding',
    'total': 'TOTAL',
    'change': 'Change',
    'tel': 'Tel',
    'thanks': 'Thank you! Visit again.',
    'dine_in': 'Dine-in',
    'takeaway': 'Takeaway',
    'delivery_type': 'Delivery',
    'counter': 'Counter',
    'table': 'Table',
    'cash': 'Cash',
    'card': 'Card',
    'duplicate': '*** DUPLICATE ***',
  };

  static const _enLabels = BillLabels(_en, rtl: false);

  static const _ur = BillLabels({
    'invoice': 'بل نمبر',
    'date': 'تاریخ',
    'type': 'قسم',
    'cashier': 'کیشیئر',
    'subtotal': 'ذیلی کل',
    'discount': 'رعایت',
    'service': 'سروس چارج',
    'delivery': 'ڈیلیوری',
    'tax': 'ٹیکس',
    'tip': 'ٹپ',
    'rounding': 'راؤنڈنگ',
    'total': 'کل',
    'change': 'بقایا',
    'tel': 'فون',
    'thanks': 'شکریہ! دوبارہ تشریف لائیں',
    'dine_in': 'ڈائن اِن',
    'takeaway': 'ٹیک اوے',
    'delivery_type': 'ڈیلیوری',
    'counter': 'کاؤنٹر',
    'table': 'ٹیبل',
    'cash': 'نقد',
    'card': 'کارڈ',
    'duplicate': '*** ڈپلیکیٹ ***',
  }, rtl: true);

  static const _ar = BillLabels({
    'invoice': 'رقم الفاتورة',
    'date': 'التاريخ',
    'type': 'النوع',
    'cashier': 'الكاشير',
    'subtotal': 'المجموع الفرعي',
    'discount': 'الخصم',
    'service': 'رسوم الخدمة',
    'delivery': 'التوصيل',
    'tax': 'الضريبة',
    'tip': 'البقشيش',
    'rounding': 'التقريب',
    'total': 'الإجمالي',
    'change': 'الباقي',
    'tel': 'هاتف',
    'thanks': 'شكرًا لزيارتكم!',
    'dine_in': 'داخل المطعم',
    'takeaway': 'سفري',
    'delivery_type': 'توصيل',
    'counter': 'الكاونتر',
    'table': 'طاولة',
    'cash': 'نقدًا',
    'card': 'بطاقة',
    'duplicate': '*** نسخة ***',
  }, rtl: true);
}
