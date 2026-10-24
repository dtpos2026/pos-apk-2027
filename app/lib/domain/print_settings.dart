import 'dart:convert';

/// How each order type prints automatically. KOT = kitchen ticket, token = customer token, bill = customer receipt.
class AutoPrint {
  const AutoPrint({this.kot = true, this.token = true, this.bill = true});
  final bool kot;
  final bool token;
  final bool bill;
  AutoPrint copyWith({bool? kot, bool? token, bool? bill}) => AutoPrint(kot: kot ?? this.kot, token: token ?? this.token, bill: bill ?? this.bill);
  Map<String, Object?> toJson() => {'kot': kot, 'token': token, 'bill': bill};
  factory AutoPrint.fromJson(Object? j) => j is Map ? AutoPrint(kot: j['kot'] as bool? ?? true, token: j['token'] as bool? ?? true, bill: j['bill'] as bool? ?? true) : const AutoPrint();
}

/// What the restaurant has switched on for printing. Three independent documents (KOT, token, bill), each with a master switch
/// (off = never printed, not even by hand: the buttons disappear) and an automatic switch (off = only when someone presses
/// Print), plus a per order-type choice of what prints by itself: a KOT, a token, a bill, any mix, or nothing.
class PrintSettings {
  const PrintSettings({
    this.kotEnabled = true,
    this.tokenEnabled = true,
    this.billEnabled = true,
    this.autoKot = true,
    this.autoToken = true,
    this.autoBill = true,
    this.perType = const {},
  });

  static const types = ['dine_in', 'takeaway', 'delivery', 'counter'];
  static const defaults = PrintSettings();

  final bool kotEnabled;
  final bool tokenEnabled;
  final bool billEnabled;

  /// Print the KOT by itself when an order is sent to the kitchen / when a sale is saved.
  final bool autoKot;

  /// Print the customer token by itself when the sale is finalized.
  final bool autoToken;
  final bool autoBill;
  final Map<String, AutoPrint> perType;

  AutoPrint forType(String orderType) => perType[orderType] ?? const AutoPrint();

  bool autoKotFor(String orderType) => kotEnabled && autoKot && forType(orderType).kot;
  bool autoTokenFor(String orderType) => tokenEnabled && autoToken && forType(orderType).token;
  bool autoBillFor(String orderType) => billEnabled && autoBill && forType(orderType).bill;

  PrintSettings copyWith({bool? kotEnabled, bool? tokenEnabled, bool? billEnabled, bool? autoKot, bool? autoToken, bool? autoBill, Map<String, AutoPrint>? perType}) => PrintSettings(
        kotEnabled: kotEnabled ?? this.kotEnabled,
        tokenEnabled: tokenEnabled ?? this.tokenEnabled,
        billEnabled: billEnabled ?? this.billEnabled,
        autoKot: autoKot ?? this.autoKot,
        autoToken: autoToken ?? this.autoToken,
        autoBill: autoBill ?? this.autoBill,
        perType: perType ?? this.perType,
      );

  PrintSettings withType(String orderType, AutoPrint a) => copyWith(perType: {...perType, orderType: a});

  String encode() => jsonEncode({
        'kotEnabled': kotEnabled, 'tokenEnabled': tokenEnabled, 'billEnabled': billEnabled,
        'autoKot': autoKot, 'autoToken': autoToken, 'autoBill': autoBill,
        'perType': {for (final e in perType.entries) e.key: e.value.toJson()},
      });

  /// Damaged or missing data falls back to "everything on", which is how the app behaved before these switches existed.
  static PrintSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return defaults;
      final per = j['perType'];
      return PrintSettings(
        kotEnabled: j['kotEnabled'] as bool? ?? true,
        tokenEnabled: j['tokenEnabled'] as bool? ?? true,
        billEnabled: j['billEnabled'] as bool? ?? true,
        autoKot: j['autoKot'] as bool? ?? true,
        autoToken: j['autoToken'] as bool? ?? true,
        autoBill: j['autoBill'] as bool? ?? true,
        perType: per is Map ? {for (final t in types) if (per[t] != null) t: AutoPrint.fromJson(per[t])} : const {},
      );
    } catch (_) {
      return defaults;
    }
  }
}
