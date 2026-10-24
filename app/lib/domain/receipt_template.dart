import 'dart:convert';

import 'escpos.dart';

/// Bill looks, from the receipts restaurants in Pakistan actually use:
/// classic (name x qty .... amount), boxed (pre-payment slip: Item | Qty | Rate | Amount table, big NET BILL, amount
/// in words), modern (dashed lines, numbered items, large total, QR) and compact (fewest lines, saves paper).
/// The eleven designs of DT Retail POS plus the older "boxed" look, so the same bill designs exist on the phone and on the Windows POS.
const billStyles = ['classic', 'modern', 'minimal', 'restaurant', 'retail', 'compact', 'grid', 'bold', 'tax', 'luxury', 'ticket', 'boxed'];

/// Kitchen ticket looks: classic, big (large item text, token in front) and compact.
const kotStyles = ['classic', 'big', 'compact'];

/// Everything the owner can change about the customer bill. Stored as JSON in the `receipt_template` table.
/// Header blocks are centred by default (logo, name, address, phone); every block can be switched off or aligned.
class BillDesign {
  const BillDesign({
    this.showLogo = true,
    this.nameSize = 2,
    this.headerAlign = PrintAlign.center,
    this.logoAlign,
    this.nameAlign,
    this.headerLines = const [],
    this.showAddress = true,
    this.showPhone = true,
    this.showTaxNumber = true,
    this.showOrderType = true,
    this.showTable = true,
    this.showCashier = true,
    this.footerLines = const [defaultFooter],
    this.qrText,
    this.showPoweredBy = true,
    this.copies = 1,
    this.language = 'en',
    this.style = 'classic',
    this.title = '',
    this.showToken = true,
    this.showItemCount = false,
    this.amountInWords = false,
  });

  /// Layout of the bill: see [billStyles].
  final String style;

  /// Heading printed in a box above the items, e.g. "PRE-PAYMENT BILL" or "TAX INVOICE". Empty = none.
  final String title;

  /// Prints the order's token number (big) when the order has one.
  final bool showToken;

  /// "Items: 17" under the item list.
  final bool showItemCount;

  /// Total written in words ("ONE THOUSAND TWO HUNDRED FIFTY ONLY"), English bills only.
  final bool amountInWords;

  final bool showLogo;

  /// Business-name size, 1 (normal) to 3 (very large).
  final int nameSize;
  final PrintAlign headerAlign;

  /// Own alignment of the logo and of the business name; null = follow [headerAlign] (as older designs did).
  final PrintAlign? logoAlign;
  final PrintAlign? nameAlign;
  PrintAlign get logoAt => logoAlign ?? headerAlign;
  PrintAlign get nameAt => nameAlign ?? headerAlign;

  /// Extra lines under the name, for example a slogan or a branch name.
  final List<String> headerLines;
  final bool showAddress;
  final bool showPhone;
  final bool showTaxNumber;
  final bool showOrderType;
  final bool showTable;
  final bool showCashier;
  final List<String> footerLines;

  /// Printed as a QR code at the bottom (website, payment link, review page...). null = no QR.
  final String? qrText;
  final bool showPoweredBy;
  final int copies;

  /// Language of the printed words ('en', 'ur', 'ar'), independent of the app language.
  final String language;

  /// Marker meaning "use the standard thank-you line in the bill language".
  static const defaultFooter = '@thanks';

  static const defaults = BillDesign();

  BillDesign copyWith({
    bool? showLogo,
    int? nameSize,
    PrintAlign? headerAlign,
    PrintAlign? logoAlign,
    PrintAlign? nameAlign,
    List<String>? headerLines,
    bool? showAddress,
    bool? showPhone,
    bool? showTaxNumber,
    bool? showOrderType,
    bool? showTable,
    bool? showCashier,
    List<String>? footerLines,
    String? qrText,
    bool clearQr = false,
    bool? showPoweredBy,
    int? copies,
    String? language,
    String? style,
    String? title,
    bool? showToken,
    bool? showItemCount,
    bool? amountInWords,
  }) =>
      BillDesign(
        showLogo: showLogo ?? this.showLogo,
        nameSize: (nameSize ?? this.nameSize).clamp(1, 3),
        headerAlign: headerAlign ?? this.headerAlign,
        logoAlign: logoAlign ?? this.logoAlign,
        nameAlign: nameAlign ?? this.nameAlign,
        headerLines: headerLines ?? this.headerLines,
        showAddress: showAddress ?? this.showAddress,
        showPhone: showPhone ?? this.showPhone,
        showTaxNumber: showTaxNumber ?? this.showTaxNumber,
        showOrderType: showOrderType ?? this.showOrderType,
        showTable: showTable ?? this.showTable,
        showCashier: showCashier ?? this.showCashier,
        footerLines: footerLines ?? this.footerLines,
        qrText: clearQr ? null : (qrText ?? this.qrText),
        showPoweredBy: showPoweredBy ?? this.showPoweredBy,
        copies: (copies ?? this.copies).clamp(1, 5),
        language: language ?? this.language,
        style: billStyles.contains(style) ? style! : this.style,
        title: title ?? this.title,
        showToken: showToken ?? this.showToken,
        showItemCount: showItemCount ?? this.showItemCount,
        amountInWords: amountInWords ?? this.amountInWords,
      );

  /// A ready-made look: sets the style and the switches that belong to it; business details and footer lines stay.
  BillDesign withStyle(String s) => switch (s) {
        'boxed' => copyWith(style: s, title: title.isEmpty ? 'PRE-PAYMENT BILL' : title, showItemCount: true, amountInWords: true, nameSize: 2),
        'modern' => copyWith(style: s, showItemCount: false, amountInWords: false, nameSize: 2),
        'compact' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 1, showCashier: false),
        'minimal' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 1, showCashier: false),
        'restaurant' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 2),
        'retail' => copyWith(style: s, title: 'INVOICE', showItemCount: true, amountInWords: true, nameSize: 1),
        'grid' => copyWith(style: s, title: 'CASH MEMO / RECEIPT', showItemCount: true, amountInWords: false, nameSize: 1),
        'bold' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 3),
        'tax' => copyWith(style: s, title: 'TAX INVOICE', showItemCount: true, amountInWords: true, nameSize: 1),
        'luxury' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 2, headerAlign: PrintAlign.center),
        'ticket' => copyWith(style: s, title: '', showItemCount: false, amountInWords: false, nameSize: 1, showCashier: false),
        _ => copyWith(style: 'classic', showItemCount: false, amountInWords: false),
      };

  Map<String, dynamic> toJson() => {
        'showLogo': showLogo,
        'nameSize': nameSize,
        'headerAlign': headerAlign.name,
        if (logoAlign != null) 'logoAlign': logoAlign!.name,
        if (nameAlign != null) 'nameAlign': nameAlign!.name,
        'headerLines': headerLines,
        'showAddress': showAddress,
        'showPhone': showPhone,
        'showTaxNumber': showTaxNumber,
        'showOrderType': showOrderType,
        'showTable': showTable,
        'showCashier': showCashier,
        'footerLines': footerLines,
        'qrText': qrText,
        'showPoweredBy': showPoweredBy,
        'copies': copies,
        'language': language,
        'style': style,
        'title': title,
        'showToken': showToken,
        'showItemCount': showItemCount,
        'amountInWords': amountInWords,
      };

  String encode() => jsonEncode(toJson());

  /// Tolerant: unknown or missing fields fall back to the defaults, so an older or damaged template never breaks printing.
  factory BillDesign.decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      List<String> lines(Object? v, List<String> d) => v is List ? v.map((e) => '$e').toList() : d;
      return BillDesign(
        showLogo: j['showLogo'] as bool? ?? true,
        nameSize: ((j['nameSize'] as num?)?.toInt() ?? 2).clamp(1, 3),
        headerAlign: PrintAlign.values.firstWhere((a) => a.name == j['headerAlign'], orElse: () => PrintAlign.center),
        logoAlign: PrintAlign.values.where((a) => a.name == j['logoAlign']).firstOrNull,
        nameAlign: PrintAlign.values.where((a) => a.name == j['nameAlign']).firstOrNull,
        headerLines: lines(j['headerLines'], const []),
        showAddress: j['showAddress'] as bool? ?? true,
        showPhone: j['showPhone'] as bool? ?? true,
        showTaxNumber: j['showTaxNumber'] as bool? ?? true,
        showOrderType: j['showOrderType'] as bool? ?? true,
        showTable: j['showTable'] as bool? ?? true,
        showCashier: j['showCashier'] as bool? ?? true,
        footerLines: lines(j['footerLines'], const [defaultFooter]),
        qrText: (j['qrText'] as String?)?.isEmpty ?? true ? null : j['qrText'] as String,
        showPoweredBy: j['showPoweredBy'] as bool? ?? true,
        copies: ((j['copies'] as num?)?.toInt() ?? 1).clamp(1, 5),
        language: const ['en', 'ur', 'ar'].contains(j['language']) ? j['language'] as String : 'en',
        style: billStyles.contains(j['style']) ? j['style'] as String : 'classic',
        title: j['title'] as String? ?? '',
        showToken: j['showToken'] as bool? ?? true,
        showItemCount: j['showItemCount'] as bool? ?? false,
        amountInWords: j['amountInWords'] as bool? ?? false,
      );
    } catch (_) {
      return defaults;
    }
  }
}


/// The kitchen order ticket (KOT) design. Stored in `receipt_template` id 'kot'.
class KotDesign {
  const KotDesign({this.style = 'classic', this.showToken = true, this.showTable = true, this.showWaiter = true, this.showNotes = true, this.copies = 1, this.title = 'KOT'});
  final String style;
  final bool showToken;
  final bool showTable;
  final bool showWaiter;
  final bool showNotes;
  final int copies;

  /// Heading, e.g. "KOT", "KITCHEN", "ORDER".
  final String title;

  static const defaults = KotDesign();

  KotDesign copyWith({String? style, bool? showToken, bool? showTable, bool? showWaiter, bool? showNotes, int? copies, String? title}) => KotDesign(
        style: kotStyles.contains(style) ? style! : this.style,
        showToken: showToken ?? this.showToken,
        showTable: showTable ?? this.showTable,
        showWaiter: showWaiter ?? this.showWaiter,
        showNotes: showNotes ?? this.showNotes,
        copies: (copies ?? this.copies).clamp(1, 3),
        title: title ?? this.title,
      );

  String encode() => jsonEncode({'style': style, 'showToken': showToken, 'showTable': showTable, 'showWaiter': showWaiter, 'showNotes': showNotes, 'copies': copies, 'title': title});

  factory KotDesign.decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return KotDesign(
        style: kotStyles.contains(j['style']) ? j['style'] as String : 'classic',
        showToken: j['showToken'] as bool? ?? true,
        showTable: j['showTable'] as bool? ?? true,
        showWaiter: j['showWaiter'] as bool? ?? true,
        showNotes: j['showNotes'] as bool? ?? true,
        copies: ((j['copies'] as num?)?.toInt() ?? 1).clamp(1, 3),
        title: (j['title'] as String?)?.trim().isNotEmpty ?? false ? j['title'] as String : 'KOT',
      );
    } catch (_) {
      return defaults;
    }
  }
}
