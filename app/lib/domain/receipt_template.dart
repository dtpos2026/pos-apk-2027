import 'dart:convert';

import 'escpos.dart';

/// Everything the owner can change about the customer bill. Stored as JSON in the `receipt_template` table.
/// Header blocks are centred by default (logo, name, address, phone); every block can be switched off or aligned.
class BillDesign {
  const BillDesign({
    this.showLogo = true,
    this.nameSize = 2,
    this.headerAlign = PrintAlign.center,
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
  });

  final bool showLogo;

  /// Business-name size, 1 (normal) to 3 (very large).
  final int nameSize;
  final PrintAlign headerAlign;

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
  }) =>
      BillDesign(
        showLogo: showLogo ?? this.showLogo,
        nameSize: (nameSize ?? this.nameSize).clamp(1, 3),
        headerAlign: headerAlign ?? this.headerAlign,
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
      );

  Map<String, dynamic> toJson() => {
        'showLogo': showLogo,
        'nameSize': nameSize,
        'headerAlign': headerAlign.name,
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
      );
    } catch (_) {
      return defaults;
    }
  }
}
