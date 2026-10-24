import 'dart:convert';

import 'escpos.dart';
import 'money.dart';
import 'receipt_doc.dart';

/// The kinds of token the POS can print. Each is a [TokenRule] the owner switches on and configures.
enum TokenKind {
  /// One token with a large number for the whole order.
  order,

  /// Separate tokens for the items of a counter (group) or one token per product line.
  product,

  /// One token per individual unit (3 teas = 3 tokens).
  unit,

  /// The order token with product names, quantities, prices, discount and total.
  price,

  /// Dedicated token for roti, naan, paratha and other tandoor items with large quantities.
  tandoor,

  /// Directs the customer to a food-court stall / collection counter.
  stall,

  /// Prepaid coupon: fixed-price product, redeemed once.
  coupon;

  static TokenKind parse(String? s) => TokenKind.values.firstWhere((k) => k.name == s, orElse: () => TokenKind.order);

  /// Built-in design a new rule of this kind starts with.
  String get defaultTemplate => switch (this) {
        TokenKind.order => 'classic',
        TokenKind.product || TokenKind.unit => 'product',
        TokenKind.price => 'price',
        TokenKind.tandoor => 'tandoor',
        TokenKind.stall => 'stall',
        TokenKind.coupon => 'coupon',
      };

  /// Kinds that need a counter (station) to know which items they are for.
  bool get needsStation => this == TokenKind.tandoor || this == TokenKind.stall || this == TokenKind.coupon;
}

/// One configured token type: what it is for, how it is numbered, which design and printer it uses.
class TokenRule {
  const TokenRule({
    required this.id,
    required this.kind,
    required this.name,
    this.enabled = true,
    this.prefix = '',
    this.pad = 0,
    this.startAt = 1,
    this.dailyReset = true,
    this.station = '',
    this.split = 'group',
    this.templateId = '',
    this.printerId,
    this.copies = 1,
    this.auto = true,
    this.collectText = '',
  });

  final String id;
  final TokenKind kind;

  /// Shown to the owner, and printed as the counter name when the slip has a "kind" line.
  final String name;
  final bool enabled;

  /// Letters/digits in front of the number: "A" gives A17. Up to 3 characters.
  final String prefix;

  /// Zero padding: 3 gives 017.
  final int pad;
  final int startAt;

  /// Numbering starts again at [startAt] every business day.
  final bool dailyReset;

  /// Counter/station the items must belong to (blank = every item, for order/product/unit/price kinds).
  final String station;

  /// Product kind only: 'group' = one token for all matching items, 'line' = one token per product line.
  final String split;

  /// Empty = the default design of the kind.
  final String templateId;

  /// Printer to use; null = the printer assigned to the counter, otherwise a bill printer.
  final String? printerId;
  final int copies;

  /// Print right after the sale; otherwise only when the cashier asks.
  final bool auto;

  /// "Collect from the Tandoor counter, left side": printed by the collect line of the design.
  final String collectText;

  String get template => templateId.isEmpty ? kind.defaultTemplate : templateId;

  String format(int n) => '$prefix${pad > 0 ? n.toString().padLeft(pad, '0') : n}';

  static String cleanPrefix(String p) {
    final s = p.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return s.length > 3 ? s.substring(0, 3) : s;
  }

  TokenRule copyWith({
    String? name,
    bool? enabled,
    String? prefix,
    int? pad,
    int? startAt,
    bool? dailyReset,
    String? station,
    String? split,
    String? templateId,
    String? printerId,
    bool clearPrinter = false,
    int? copies,
    bool? auto,
    String? collectText,
  }) =>
      TokenRule(
        id: id,
        kind: kind,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        prefix: prefix == null ? this.prefix : cleanPrefix(prefix),
        pad: (pad ?? this.pad).clamp(0, 5),
        startAt: (startAt ?? this.startAt).clamp(1, 99999),
        dailyReset: dailyReset ?? this.dailyReset,
        station: station?.trim() ?? this.station,
        split: split == 'line' || split == 'group' ? split! : this.split,
        templateId: templateId ?? this.templateId,
        printerId: clearPrinter ? null : (printerId ?? this.printerId),
        copies: (copies ?? this.copies).clamp(1, 5),
        auto: auto ?? this.auto,
        collectText: collectText ?? this.collectText,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'enabled': enabled,
        'prefix': prefix,
        'pad': pad,
        'startAt': startAt,
        'dailyReset': dailyReset,
        'station': station,
        'split': split,
        'templateId': templateId,
        'printerId': printerId,
        'copies': copies,
        'auto': auto,
        'collectText': collectText,
      };

  factory TokenRule.fromJson(Map<String, dynamic> j) => TokenRule(
        id: j['id'] as String,
        kind: TokenKind.parse(j['kind'] as String?),
        name: j['name'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        prefix: cleanPrefix(j['prefix'] as String? ?? ''),
        pad: ((j['pad'] as num?)?.toInt() ?? 0).clamp(0, 5),
        startAt: ((j['startAt'] as num?)?.toInt() ?? 1).clamp(1, 99999),
        dailyReset: j['dailyReset'] as bool? ?? true,
        station: j['station'] as String? ?? '',
        split: j['split'] == 'line' ? 'line' : 'group',
        templateId: j['templateId'] as String? ?? '',
        printerId: j['printerId'] as String?,
        copies: ((j['copies'] as num?)?.toInt() ?? 1).clamp(1, 5),
        auto: j['auto'] as bool? ?? true,
        collectText: j['collectText'] as String? ?? '',
      );
}

/// All token settings of the business. With no rules nothing changes: sales print exactly as before.
class TokenConfig {
  const TokenConfig({this.rules = const [], this.printBill = true, this.managerReprintOnly = false});
  final List<TokenRule> rules;

  /// Print the customer bill on the sale. Off = food points that give tokens instead of a bill (the bill can still be reprinted).
  final bool printBill;

  /// Reprinting tokens (and bills) needs a manager/owner ('settings.manage'); cashiers can only print the first copy.
  final bool managerReprintOnly;

  static const none = TokenConfig();

  TokenRule? rule(String id) => rules.where((r) => r.id == id).firstOrNull;
  Iterable<TokenRule> get active => rules.where((r) => r.enabled);

  TokenConfig copyWith({List<TokenRule>? rules, bool? printBill, bool? managerReprintOnly}) =>
      TokenConfig(rules: rules ?? this.rules, printBill: printBill ?? this.printBill, managerReprintOnly: managerReprintOnly ?? this.managerReprintOnly);

  String encode() => jsonEncode({'printBill': printBill, 'managerReprintOnly': managerReprintOnly, 'rules': [for (final r in rules) r.toJson()]});

  factory TokenConfig.decode(String? raw) {
    if (raw == null || raw.isEmpty) return none;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return TokenConfig(
        printBill: j['printBill'] as bool? ?? true,
        managerReprintOnly: j['managerReprintOnly'] as bool? ?? false,
        rules: [for (final r in (j['rules'] as List? ?? const [])) TokenRule.fromJson(r as Map<String, dynamic>)],
      );
    } catch (_) {
      return none;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Designs
// ---------------------------------------------------------------------------------------------------------------------

/// What a block of a token design shows. Every block can be hidden, moved, aligned and resized.
enum BlockType {
  logo,
  business,
  title,
  kind,
  token,
  collect,
  orderNo,
  dateTime,
  orderType,
  cashier,
  items,
  totals,
  coupon,
  qr,
  text,
  rule,
  space,
  powered;

  static BlockType? parse(String? s) => BlockType.values.where((b) => b.name == s).firstOrNull;

  /// Blocks whose wording the owner can change.
  bool get hasText => this == BlockType.title || this == BlockType.text || this == BlockType.collect;
}

class TokenBlock {
  const TokenBlock(this.type, {this.show = true, this.align = PrintAlign.center, this.size = 1, this.bold = false, this.text = '', this.textAlt = '', this.flags = const {}});
  final BlockType type;
  final bool show;
  final PrintAlign align;

  /// Character size, 1 (normal) to 5 (huge). For [BlockType.space] the number of blank lines.
  final int size;
  final bool bold;

  /// Own wording (title, free text, collect line). Empty = the standard wording of the block.
  final String text;

  /// Second-language wording for bilingual designs.
  final String textAlt;

  /// Per-block switches, e.g. items: qty / price / amount / bigqty / modifiers / header; totals: subtotal / discount / tax.
  final Map<String, bool> flags;

  bool flag(String k, {bool or = false}) => flags[k] ?? or;

  TokenBlock copyWith({bool? show, PrintAlign? align, int? size, bool? bold, String? text, String? textAlt, Map<String, bool>? flags}) => TokenBlock(type,
      show: show ?? this.show, align: align ?? this.align, size: (size ?? this.size).clamp(1, 5), bold: bold ?? this.bold, text: text ?? this.text, textAlt: textAlt ?? this.textAlt, flags: flags ?? this.flags);

  TokenBlock withFlag(String k, bool v) => copyWith(flags: {...flags, k: v});

  Map<String, dynamic> toJson() => {'t': type.name, 's': show, 'a': align.name, 'z': size, 'b': bold, if (text.isNotEmpty) 'x': text, if (textAlt.isNotEmpty) 'y': textAlt, if (flags.isNotEmpty) 'f': flags};

  static TokenBlock? fromJson(Object? o) {
    if (o is! Map) return null;
    final type = BlockType.parse(o['t'] as String?);
    if (type == null) return null;
    final f = o['f'];
    return TokenBlock(type,
        show: o['s'] as bool? ?? true,
        align: PrintAlign.values.firstWhere((a) => a.name == o['a'], orElse: () => PrintAlign.center),
        size: ((o['z'] as num?)?.toInt() ?? 1).clamp(1, 5),
        bold: o['b'] as bool? ?? false,
        text: o['x'] as String? ?? '',
        textAlt: o['y'] as String? ?? '',
        flags: f is Map ? {for (final e in f.entries) '${e.key}': e.value == true} : const {});
  }
}

/// A complete token design: an ordered list of blocks plus page settings. Stored as JSON, exported/imported as JSON.
class TokenDesign {
  const TokenDesign({required this.id, required this.name, required this.blocks, this.lang = 'en', this.border = 'line', this.topFeed = 0, this.bottomFeed = 2, this.builtIn = false, this.sampleKind = TokenKind.order});
  final String id;
  final String name;
  final List<TokenBlock> blocks;

  /// 'en', 'ur' or 'both': the language of the standard words (Token, Order, Total...).
  final String lang;

  /// Style of the rule lines: none, line, double, dots, stars.
  final String border;
  final int topFeed;
  final int bottomFeed;

  /// True for the ready-made designs (they can be edited, then reset to the original).
  final bool builtIn;

  /// What the preview shows by default.
  final TokenKind sampleKind;

  static const borders = ['none', 'line', 'double', 'dots', 'stars', 'box'];
  static const languages = ['en', 'ur', 'both'];

  String get ruleChar => switch (border) { 'double' => '=', 'dots' => '.', 'stars' => '*', 'box' => '+', _ => '-' };

  TokenDesign copyWith({String? id, String? name, List<TokenBlock>? blocks, String? lang, String? border, int? topFeed, int? bottomFeed, bool? builtIn}) => TokenDesign(
      id: id ?? this.id,
      name: name ?? this.name,
      blocks: blocks ?? this.blocks,
      lang: languages.contains(lang) ? lang! : this.lang,
      border: borders.contains(border) ? border! : this.border,
      topFeed: (topFeed ?? this.topFeed).clamp(0, 6),
      bottomFeed: (bottomFeed ?? this.bottomFeed).clamp(0, 8),
      builtIn: builtIn ?? this.builtIn,
      sampleKind: sampleKind);

  static const exportFormat = 'dt-token-template-1';

  Map<String, dynamic> toJson() => {'format': exportFormat, 'name': name, 'lang': lang, 'border': border, 'topFeed': topFeed, 'bottomFeed': bottomFeed, 'sample': sampleKind.name, 'blocks': [for (final b in blocks) b.toJson()]};

  String encode() => jsonEncode(toJson());

  /// Tolerant: unknown block types are skipped and bad values fall back, so an old or hand-edited design never breaks printing.
  /// Returns null if [raw] is not a token design at all (used by import).
  static TokenDesign? decode(String? raw, {required String id, bool builtIn = false}) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['blocks'] is! List) return null;
      final blocks = [for (final b in j['blocks'] as List) ?TokenBlock.fromJson(b)];
      if (blocks.isEmpty) return null;
      return TokenDesign(
        id: id,
        name: (j['name'] as String?)?.trim().isNotEmpty ?? false ? (j['name'] as String).trim() : 'Token design',
        blocks: blocks,
        lang: languages.contains(j['lang']) ? j['lang'] as String : 'en',
        border: borders.contains(j['border']) ? j['border'] as String : 'line',
        topFeed: ((j['topFeed'] as num?)?.toInt() ?? 0).clamp(0, 6),
        bottomFeed: ((j['bottomFeed'] as num?)?.toInt() ?? 2).clamp(0, 8),
        builtIn: builtIn,
        sampleKind: TokenKind.parse(j['sample'] as String?),
      );
    } catch (_) {
      return null;
    }
  }
}

const _itemsAll = {'qty': true, 'price': true, 'amount': true, 'header': true, 'modifiers': true};

/// The seven ready-made designs. All are editable; "reset" returns to these.
final Map<String, TokenDesign> builtInTemplates = {
  // 1. Classic food token: business, big number, order type, time.
  'classic': const TokenDesign(id: 'classic', name: 'Classic Food Token', builtIn: true, blocks: [
    TokenBlock(BlockType.logo),
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'TOKEN', bold: true),
    TokenBlock(BlockType.token, size: 5, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.items, show: false, align: PrintAlign.left, flags: {'qty': true, 'modifiers': true}),
    TokenBlock(BlockType.text, text: 'Please wait for your number'),
    TokenBlock(BlockType.powered),
  ]),
  // 2. Product-wise token: what to prepare, at which counter.
  'product': const TokenDesign(id: 'product', name: 'Product-Wise Token', builtIn: true, sampleKind: TokenKind.product, blocks: [
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.kind, size: 2, bold: true),
    TokenBlock(BlockType.token, size: 3, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.items, align: PrintAlign.left, size: 2, bold: true, flags: {'qty': true, 'modifiers': true}),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderNo, align: PrintAlign.left),
    TokenBlock(BlockType.dateTime, align: PrintAlign.left),
    TokenBlock(BlockType.powered),
  ]),
  // 3. Itemized price receipt token.
  'price': const TokenDesign(id: 'price', name: 'Itemized Price Receipt', builtIn: true, sampleKind: TokenKind.price, blocks: [
    TokenBlock(BlockType.logo),
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.title, text: 'PRICE TOKEN', bold: true),
    TokenBlock(BlockType.token, size: 3, bold: true),
    TokenBlock(BlockType.orderNo, align: PrintAlign.left),
    TokenBlock(BlockType.dateTime, align: PrintAlign.left),
    TokenBlock(BlockType.orderType, align: PrintAlign.left),
    TokenBlock(BlockType.cashier, align: PrintAlign.left),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.items, align: PrintAlign.left, flags: _itemsAll),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.totals, align: PrintAlign.left, flags: {'subtotal': true, 'discount': true, 'tax': true}),
    TokenBlock(BlockType.text, text: 'Thank you! Visit again.'),
    TokenBlock(BlockType.powered),
  ]),
  // 4. Tandoor / roti token: huge quantities.
  'tandoor': const TokenDesign(id: 'tandoor', name: 'Tandoor / Roti Token', builtIn: true, sampleKind: TokenKind.tandoor, border: 'double', blocks: [
    TokenBlock(BlockType.business),
    TokenBlock(BlockType.kind, size: 2, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.token, size: 4, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.items, align: PrintAlign.left, size: 3, bold: true, flags: {'qty': true, 'bigqty': true}),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.collect, bold: true),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.powered),
  ]),
  // 5. Food court / stall token: where to collect.
  'stall': const TokenDesign(id: 'stall', name: 'Food Court / Stall Token', builtIn: true, sampleKind: TokenKind.stall, border: 'stars', blocks: [
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.title, text: 'COLLECT FROM', bold: true),
    TokenBlock(BlockType.kind, size: 3, bold: true),
    TokenBlock(BlockType.collect),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'TOKEN', bold: true),
    TokenBlock(BlockType.token, size: 5, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.items, align: PrintAlign.left, flags: {'qty': true, 'modifiers': true}),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.powered),
  ]),
  // 6. Premium branded token: logo, frame, prices, QR.
  'premium': const TokenDesign(id: 'premium', name: 'Premium Branded Token', builtIn: true, border: 'stars', blocks: [
    TokenBlock(BlockType.logo),
    TokenBlock(BlockType.business, size: 2, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'YOUR TOKEN', bold: true),
    TokenBlock(BlockType.token, size: 5, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.items, align: PrintAlign.left, flags: {'qty': true, 'price': true, 'amount': true, 'header': true, 'modifiers': true}),
    TokenBlock(BlockType.totals, align: PrintAlign.left, flags: {'subtotal': true, 'discount': true}),
    TokenBlock(BlockType.qr),
    TokenBlock(BlockType.text, text: 'Thank you for dining with us', bold: true),
    TokenBlock(BlockType.powered),
  ]),
  // DT Retail POS token designs: Classic, Boxed, Bold Number, Minimal, Ticket.
  'r_classic': const TokenDesign(id: 'r_classic', name: 'Retail · Classic', builtIn: true, blocks: [
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'TOKEN', bold: true),
    TokenBlock(BlockType.token, size: 5, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.cashier, show: false),
    TokenBlock(BlockType.text, text: 'Thank you! Please wait for your number.'),
    TokenBlock(BlockType.powered),
  ]),
  'r_boxed': const TokenDesign(id: 'r_boxed', name: 'Retail · Boxed', builtIn: true, border: 'box', blocks: [
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'TOKEN NO.', bold: true),
    TokenBlock(BlockType.token, size: 4, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.items, align: PrintAlign.left, flags: {'qty': true, 'modifiers': true}),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.powered),
  ]),
  'r_bold': const TokenDesign(id: 'r_bold', name: 'Retail · Bold Number', builtIn: true, blocks: [
    TokenBlock(BlockType.token, size: 5, bold: true),
    TokenBlock(BlockType.orderType, size: 2, bold: true),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.powered),
  ]),
  'r_minimal': const TokenDesign(id: 'r_minimal', name: 'Retail · Minimal', builtIn: true, bottomFeed: 1, blocks: [
    TokenBlock(BlockType.token, size: 3, bold: true),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.powered),
  ]),
  'r_ticket': const TokenDesign(id: 'r_ticket', name: 'Retail · Ticket', builtIn: true, border: 'dots', blocks: [
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.title, text: 'TICKET', bold: true),
    TokenBlock(BlockType.token, size: 4, bold: true),
    TokenBlock(BlockType.items, align: PrintAlign.left, flags: {'qty': true}),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.orderType),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.text, text: 'Keep this slip until your number is called', bold: true),
    TokenBlock(BlockType.powered),
  ]),
  // 7. Prepaid coupon.
  'coupon': const TokenDesign(id: 'coupon', name: 'Prepaid Coupon', builtIn: true, sampleKind: TokenKind.coupon, border: 'dots', blocks: [
    TokenBlock(BlockType.logo),
    TokenBlock(BlockType.business, bold: true),
    TokenBlock(BlockType.title, text: 'PREPAID COUPON', bold: true),
    TokenBlock(BlockType.rule),
    TokenBlock(BlockType.coupon, size: 2, bold: true),
    TokenBlock(BlockType.qr),
    TokenBlock(BlockType.token, size: 2),
    TokenBlock(BlockType.text, text: 'Valid for ONE use. Keep it safe.', bold: true),
    TokenBlock(BlockType.dateTime),
    TokenBlock(BlockType.orderNo),
    TokenBlock(BlockType.powered),
  ]),
};

/// The designs offered in the order shown in the app: seven for food counters, then the five token designs of DT Retail POS.
const builtInTemplateOrder = ['classic', 'product', 'price', 'tandoor', 'stall', 'premium', 'coupon', 'r_classic', 'r_boxed', 'r_bold', 'r_minimal', 'r_ticket'];

// ---------------------------------------------------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------------------------------------------------

class SlipItem {
  const SlipItem({required this.name, required this.qtyMilli, this.unitPriceMinor = 0, this.totalMinor = 0, this.modifiers = const [], this.note});
  final String name;
  final int qtyMilli;
  final int unitPriceMinor;
  final int totalMinor;
  final List<String> modifiers;
  final String? note;

  Map<String, dynamic> toJson() => {'n': name, 'q': qtyMilli, 'p': unitPriceMinor, 't': totalMinor, if (modifiers.isNotEmpty) 'm': modifiers, if (note != null) 'o': note};
  factory SlipItem.fromJson(Map<String, dynamic> j) => SlipItem(
      name: j['n'] as String? ?? '', qtyMilli: (j['q'] as num?)?.toInt() ?? 1000, unitPriceMinor: (j['p'] as num?)?.toInt() ?? 0, totalMinor: (j['t'] as num?)?.toInt() ?? 0, modifiers: [for (final m in (j['m'] as List? ?? const [])) '$m'], note: j['o'] as String?);
}

/// Everything a token design can show. Built from the stored token (see TokenService) or from sample data.
class TokenSlip {
  const TokenSlip({
    required this.businessName,
    required this.label,
    required this.dateTime,
    this.counterName = '',
    this.collectText = '',
    this.orderNo = '',
    this.orderType = '',
    this.tableLabel,
    this.cashier,
    this.items = const [],
    this.subtotalMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
    this.totalMinor,
    this.currency = Currency.pkr,
    this.couponCode,
    this.couponValueMinor,
    this.qrData,
    this.logo,
    this.isReprint = false,
  });
  final String businessName;
  final String label;
  final String dateTime;
  final String counterName;
  final String collectText;
  final String orderNo;
  final String orderType;
  final String? tableLabel;
  final String? cashier;
  final List<SlipItem> items;
  final int? subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int? totalMinor;
  final Currency currency;
  final String? couponCode;
  final int? couponValueMinor;
  final String? qrData;
  final RasterImage? logo;
  final bool isReprint;

  TokenSlip reprint() => TokenSlip(
      businessName: businessName,
      label: label,
      dateTime: dateTime,
      counterName: counterName,
      collectText: collectText,
      orderNo: orderNo,
      orderType: orderType,
      tableLabel: tableLabel,
      cashier: cashier,
      items: items,
      subtotalMinor: subtotalMinor,
      discountMinor: discountMinor,
      taxMinor: taxMinor,
      totalMinor: totalMinor,
      currency: currency,
      couponCode: couponCode,
      couponValueMinor: couponValueMinor,
      qrData: qrData,
      logo: logo,
      isReprint: true);
}

const _wordsEn = {
  'token': 'Token',
  'order': 'Order',
  'date': 'Date',
  'cashier': 'Cashier',
  'subtotal': 'Subtotal',
  'discount': 'Discount',
  'tax': 'Tax',
  'total': 'TOTAL',
  'item': 'Item',
  'qty': 'Qty',
  'rate': 'Rate',
  'amount': 'Amount',
  'coupon': 'Coupon',
  'value': 'Value',
  'reprint': '*** REPRINT ***',
  'collect': 'Collect from',
  'table': 'Table',
};
const _wordsUr = {
  'token': 'ٹوکن',
  'order': 'آرڈر',
  'date': 'تاریخ',
  'cashier': 'کیشیئر',
  'subtotal': 'ذیلی کل',
  'discount': 'رعایت',
  'tax': 'ٹیکس',
  'total': 'کل',
  'item': 'آئٹم',
  'qty': 'تعداد',
  'rate': 'ریٹ',
  'amount': 'رقم',
  'coupon': 'کوپن',
  'value': 'قیمت',
  'reprint': '*** دوبارہ پرنٹ ***',
  'collect': 'یہاں سے وصول کریں',
  'table': 'ٹیبل',
};

/// A standard word in the design's language: English, Urdu, or both on one line ("Token  ٹوکن").
String slipWord(String lang, String key) {
  final en = _wordsEn[key] ?? key, ur = _wordsUr[key] ?? key;
  return switch (lang) { 'ur' => ur, 'both' => '$en  $ur', _ => en };
}

String _fmt(int minor, Currency c) => formatMinor(minor, currency: c, symbol: false);

/// Renders a design to a [ReceiptDoc] (the same document is drawn on screen and sent to the printer).
ReceiptDoc buildTokenSlipDoc(TokenDesign t, TokenSlip d, {int paperMm = 58, int copies = 1}) {
  final cols = columnsFor(paperMm);
  final rule = t.border == 'none' ? null : RRule(t.ruleChar);
  final out = <RLine>[];
  if (t.topFeed > 0) out.add(RFeed(t.topFeed));
  if (d.isReprint) out.add(RText(slipWord(t.lang == 'ur' ? 'ur' : 'en', 'reprint'), align: PrintAlign.center, bold: true));
  // blocks that print nothing leave no gap and never leave two rules in a row
  var lastWasRule = false;
  void addRule() {
    if (rule == null || lastWasRule) return;
    out.add(rule);
    lastWasRule = true;
  }

  void add(RLine l) {
    out.add(l);
    lastWasRule = false;
  }

  String label(String k) => slipWord(t.lang, k);
  // wording the owner typed, plus the second language line when the design is bilingual
  void words(TokenBlock b, String main, {String? alt}) {
    if (main.trim().isNotEmpty) add(RText(main, align: b.align, bold: b.bold, width: _w(b.size, main, cols), height: b.size));
    final second = alt ?? b.textAlt;
    if (t.lang == 'both' && second.trim().isNotEmpty) add(RText(second, align: b.align, bold: b.bold, width: _w(b.size, second, cols), height: b.size));
  }

  for (final b in t.blocks) {
    if (!b.show) continue;
    switch (b.type) {
      case BlockType.logo:
        if (d.logo != null) add(RImage(d.logo!, align: b.align));
      case BlockType.business:
        if (d.businessName.trim().isNotEmpty) add(RText(d.businessName, align: b.align, bold: b.bold, width: _w(b.size, d.businessName, cols), height: b.size));
      case BlockType.title:
        words(b, b.text);
      case BlockType.kind:
        words(b, d.counterName);
      case BlockType.token:
        add(RText(d.label, align: b.align, bold: true, width: _w(b.size, d.label, cols), height: b.size));
      case BlockType.collect:
        final txt = b.text.trim().isNotEmpty ? b.text : d.collectText;
        if (txt.trim().isNotEmpty) {
          words(b, txt);
        } else if (d.counterName.trim().isNotEmpty) {
          add(RText('${label('collect')} ${d.counterName}', align: b.align, bold: b.bold, height: b.size));
        }
      case BlockType.orderNo:
        if (d.orderNo.isNotEmpty) add(_kv(label('order'), d.orderNo, b, row: t.lang != 'en'));
      case BlockType.dateTime:
        add(_kv(label('date'), d.dateTime, b, row: t.lang != 'en'));
      case BlockType.orderType:
        if (d.orderType.isNotEmpty) add(RText(d.tableLabel == null ? d.orderType : '${d.orderType}  ${label('table')} ${d.tableLabel}', align: b.align, bold: b.bold, height: b.size));
      case BlockType.cashier:
        if (d.cashier != null) add(_kv(label('cashier'), d.cashier!, b, row: t.lang != 'en'));
      case BlockType.items:
        if (d.items.isEmpty) break;
        final price = b.flag('price') && d.items.any((i) => i.unitPriceMinor > 0);
        final amount = b.flag('amount') && d.items.any((i) => i.totalMinor > 0);
        final table = price || amount;
        final widths = [if (b.flag('qty', or: true)) 4, if (price) 8, if (amount) 9];
        if (table && b.flag('header')) {
          add(RCols([label('item').split('  ').first, if (b.flag('qty', or: true)) _short(label('qty')), if (price) _short(label('rate')), if (amount) _short(label('amount'))], widths, bold: true));
          addRule();
        }
        for (final i in d.items) {
          final qty = formatQty(i.qtyMilli);
          if (table) {
            add(RCols([i.name, if (b.flag('qty', or: true)) qty, if (price) _fmt(i.unitPriceMinor, d.currency), if (amount) _fmt(i.totalMinor, d.currency)], widths, bold: b.bold));
          } else if (b.flag('bigqty')) {
            final line = '$qty  ${i.name}';
            add(RText(line, align: b.align, bold: true, width: _w(b.size, line, cols), height: b.size));
          } else {
            final line = b.flag('qty', or: true) ? '$qty x ${i.name}' : i.name;
            add(RText(line, align: b.align, bold: b.bold, width: _w(b.size, line, cols), height: b.size));
          }
          if (b.flag('modifiers', or: true)) {
            for (final m in i.modifiers) {
              add(RText('  + $m', align: PrintAlign.left));
            }
            if (i.note != null) add(RText('  * ${i.note}', align: PrintAlign.left));
          }
        }
      case BlockType.totals:
        if (d.totalMinor == null) break;
        if (b.flag('subtotal') && d.subtotalMinor != null && (d.discountMinor > 0 || d.taxMinor > 0)) add(RRow(label('subtotal'), _fmt(d.subtotalMinor!, d.currency)));
        if (b.flag('discount') && d.discountMinor > 0) add(RRow(label('discount'), '-${_fmt(d.discountMinor, d.currency)}'));
        if (b.flag('tax') && d.taxMinor > 0) add(RRow(label('tax'), _fmt(d.taxMinor, d.currency)));
        add(RRow('${label('total')} ${d.currency.code}', _fmt(d.totalMinor!, d.currency), bold: true, height: b.size));
      case BlockType.coupon:
        if (d.couponCode != null) {
          add(RText(label('coupon'), align: b.align, bold: b.bold));
          add(RText(d.couponCode!, align: b.align, bold: true, width: _w(b.size, d.couponCode!, cols), height: b.size));
          if (d.couponValueMinor != null) add(RText('${label('value')}: ${d.currency.code} ${_fmt(d.couponValueMinor!, d.currency)}', align: b.align, bold: b.bold));
        }
      case BlockType.qr:
        final data = d.couponCode ?? d.qrData;
        if (data != null && data.isNotEmpty) add(RQr(data, moduleSize: paperMm == 80 ? 6 : 5));
      case BlockType.text:
        words(b, b.text);
      case BlockType.rule:
        addRule();
      case BlockType.space:
        add(RFeed(b.size));
      case BlockType.powered:
        add(const RText('Powered by Digital Target', align: PrintAlign.center));
    }
  }
  if (t.bottomFeed > 0) out.add(RFeed(t.bottomFeed));
  return ReceiptDoc(out, copies: copies);
}

String _short(String w) => w.split('  ').first;

/// Largest width multiplier (up to the block size) at which [text] still fits on one line.
int _w(int size, String text, int cols) {
  final len = text.isEmpty ? 1 : text.length;
  final fit = cols ~/ len;
  return fit < 1 ? 1 : (fit < size ? fit : size);
}

RLine _kv(String k, String v, TokenBlock b, {bool row = false}) => b.align == PrintAlign.left || row ? RRow(k, v, bold: b.bold) : RText('$k: $v', align: b.align, bold: b.bold);

/// Words a coupon number: 10 characters from an unambiguous alphabet, shown as CP-XXXXX-XXXXX.
String formatCouponCode(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final body = s.startsWith('CP') ? s.substring(2) : s;
  if (body.length != 10) return raw.trim().toUpperCase();
  return 'CP-${body.substring(0, 5)}-${body.substring(5)}';
}

/// Sample slip for the designer preview and test prints. Clearly a sample: nothing here is a real sale.
TokenSlip sampleSlip(TokenKind kind, {required String businessName, RasterImage? logo, Currency currency = Currency.pkr, String lang = 'en', String counter = '', String collectText = ''}) {
  final ur = lang != 'en';
  List<SlipItem> items;
  String name = counter;
  switch (kind) {
    case TokenKind.tandoor:
      name = name.isEmpty ? 'Tandoor' : name;
      items = [
        const SlipItem(name: 'Roti', qtyMilli: 6000, unitPriceMinor: 3000, totalMinor: 18000),
        SlipItem(name: ur ? 'نان' : 'Naan', qtyMilli: 4000, unitPriceMinor: 6000, totalMinor: 24000),
        const SlipItem(name: 'Paratha', qtyMilli: 2000, unitPriceMinor: 8000, totalMinor: 16000),
      ];
    case TokenKind.stall:
      name = name.isEmpty ? 'BBQ Stall 2' : name;
      items = [const SlipItem(name: 'Chicken Tikka', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000), const SlipItem(name: 'Seekh Kabab', qtyMilli: 1000, unitPriceMinor: 38000, totalMinor: 38000)];
    case TokenKind.coupon:
      name = name.isEmpty ? 'Lunch coupon' : name;
      items = [const SlipItem(name: 'Lunch coupon', qtyMilli: 1000, unitPriceMinor: 50000, totalMinor: 50000)];
    case TokenKind.unit:
      items = [const SlipItem(name: 'Karak Chai', qtyMilli: 1000, unitPriceMinor: 15000, totalMinor: 15000)];
    default:
      items = [
        const SlipItem(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000, modifiers: ['Extra cheese']),
        SlipItem(name: ur ? 'چکن کڑاہی' : 'Chicken Karahi', qtyMilli: 1000, unitPriceMinor: 120000, totalMinor: 120000),
        const SlipItem(name: 'Cola 500ml', qtyMilli: 2000, unitPriceMinor: 10000, totalMinor: 20000),
      ];
  }
  final sub = items.fold<int>(0, (s, i) => s + i.totalMinor);
  final discount = kind == TokenKind.price || kind == TokenKind.order ? 10000 : 0;
  return TokenSlip(
    businessName: businessName.isEmpty ? 'DT Food POS' : businessName,
    label: kind == TokenKind.tandoor ? 'T12' : (kind == TokenKind.stall ? 'B27' : 'A17'),
    dateTime: '2026-01-12 19:40',
    counterName: name,
    collectText: collectText,
    orderNo: 'INV-20260112-0001',
    orderType: 'Dine-in',
    tableLabel: 'T4',
    cashier: 'Ali',
    items: items,
    subtotalMinor: sub,
    discountMinor: discount,
    totalMinor: sub - discount,
    currency: currency,
    couponCode: kind == TokenKind.coupon ? 'CP-7K4M9-X2QPD' : null,
    couponValueMinor: kind == TokenKind.coupon ? 50000 : null,
    qrData: 'DT|A17|INV-20260112-0001',
    logo: logo,
  );
}

/// Tokens of an order as plain text (what the printer prints), for tests and the text fallback.
String previewSlip(TokenDesign t, TokenSlip d, {int paperMm = 58}) => docToText(buildTokenSlipDoc(t, d, paperMm: paperMm), paperMm);

