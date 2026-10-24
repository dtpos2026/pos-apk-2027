import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/logo.dart';
import '../domain/money.dart';
import '../domain/receipt_doc.dart';
import '../domain/token.dart';
import 'db/database.dart';
import 'queries.dart';
import 'receipt_loader.dart';

const tokenConfigKey = 'token.config';

/// A token that has been handed out (stored in `token_issue`).
class IssuedToken {
  const IssuedToken({
    required this.id,
    required this.orderId,
    required this.ruleId,
    required this.kind,
    required this.part,
    required this.seq,
    required this.label,
    required this.status,
    required this.printCount,
    required this.businessDate,
    required this.createdAt,
    required this.payload,
    this.station,
    this.lastPrintedAt,
    this.collectedAt,
  });
  final String id;
  final String orderId;
  final String ruleId;
  final TokenKind kind;
  final int part;
  final int seq;
  final String label;
  final String? station;
  final String status;
  final int printCount;
  final int? lastPrintedAt;
  final String businessDate;
  final int createdAt;
  final int? collectedAt;
  final Map<String, dynamic> payload;

  List<SlipItem> get items => [for (final i in (payload['items'] as List? ?? const [])) SlipItem.fromJson(i as Map<String, dynamic>)];
  String get counter => payload['counter'] as String? ?? '';
  String? get couponCode => payload['coupon'] as String?;
  String get orderNo => payload['orderNo'] as String? ?? '';
  bool get isIssued => status == 'issued';
}

enum RedeemStatus { ok, notFound, alreadyRedeemed, voided }

class RedeemResult {
  const RedeemResult(this.status, {this.code, this.label, this.valueMinor, this.redeemedAt});
  final RedeemStatus status;
  final String? code;
  final String? label;
  final int? valueMinor;

  /// When it was redeemed before (alreadyRedeemed).
  final int? redeemedAt;
  bool get ok => status == RedeemStatus.ok;
}

/// Token numbering, routing and bookkeeping. Everything is local SQLite, so it works offline, and every method that writes
/// does so inside one transaction: a number is never handed out twice and a token is never created twice for the same
/// order/rule/part (database UNIQUE constraint), even if the caller retries.
class TokenService {
  TokenService(this.db, {DateTime Function()? now, String Function()? newId})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());
  final AppDatabase db;
  final DateTime Function() _now;
  final String Function() _newId;

  int get _ts => _now().millisecondsSinceEpoch;

  Variable _v(Object? o) => o == null ? const Variable<Object>(null) : (o is int ? Variable.withInt(o) : Variable.withString(o as String));
  Future<List<Map<String, Object?>>> _select(String sql, [List<Object?> args = const []]) async => (await db.customSelect(sql, variables: args.map(_v).toList()).get()).map((r) => r.data).toList();
  Future<void> _exec(String sql, [List<Object?> args = const []]) => db.customStatement(sql, args);

  // ---- settings ----
  /// The settings as saved (what the owner edits). Records and settings are kept even while the module is off.
  Future<TokenConfig> rawConfig() async => TokenConfig.decode(await getSetting(db, tokenConfigKey));

  /// Is the "tokens" module on? Off when the owner switched it off, or Digital Target switched it off for this account.
  /// Enforced here (not only in the menus) so a hidden module cannot keep numbering or printing tokens.
  Future<bool> moduleOn() async {
    try {
      final mine = await getSetting(db, 'modules');
      if (mine != null && !(jsonDecode(mine) as List).contains('tokens')) return false;
      final off = await getSetting(db, 'cloud.modules_off');
      if (off != null && (jsonDecode(off) as List).contains('tokens')) return false;
    } catch (_) {}
    return true;
  }

  /// What applies right now: the saved settings, or nothing while the module is off.
  Future<TokenConfig> config() async => await moduleOn() ? await rawConfig() : TokenConfig.none;
  Future<void> saveConfig(TokenConfig c) => setSetting(db, tokenConfigKey, c.encode(), _ts);

  // ---- designs ----
  /// Built-in designs (with the owner's edits applied) followed by the owner's own designs.
  Future<List<TokenDesign>> templates() async {
    final rows = await _select('SELECT id, name, config FROM token_template ORDER BY name');
    final saved = <String, TokenDesign>{};
    for (final r in rows) {
      final id = r['id'] as String;
      final t = TokenDesign.decode(r['config'] as String, id: id, builtIn: builtInTemplates.containsKey(id));
      if (t != null) saved[id] = t.copyWith(name: r['name'] as String);
    }
    return [
      for (final id in builtInTemplateOrder) saved[id] ?? builtInTemplates[id]!,
      for (final e in saved.entries) if (!builtInTemplates.containsKey(e.key)) e.value,
    ];
  }

  Future<TokenDesign> template(String id) async {
    final rows = await _select('SELECT name, config FROM token_template WHERE id = ?', [id]);
    if (rows.isNotEmpty) {
      final t = TokenDesign.decode(rows.first['config'] as String, id: id, builtIn: builtInTemplates.containsKey(id));
      if (t != null) return t.copyWith(name: rows.first['name'] as String);
    }
    return builtInTemplates[id] ?? builtInTemplates['classic']!;
  }

  Future<void> saveTemplate(TokenDesign t) => _exec(
      'INSERT INTO token_template(id, name, config, updated_at) VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, config = excluded.config, updated_at = excluded.updated_at',
      [t.id, t.name.trim().isEmpty ? 'Token design' : t.name.trim(), t.encode(), _ts]);

  /// Copy of [source] under a new id; the copy is the owner's own design.
  Future<TokenDesign> duplicateTemplate(TokenDesign source, {String? name}) async {
    final copy = TokenDesign(
        id: 'c-${_newId()}', name: name ?? '${source.name} copy', blocks: source.blocks, lang: source.lang, border: source.border, topFeed: source.topFeed, bottomFeed: source.bottomFeed, sampleKind: source.sampleKind);
    await saveTemplate(copy);
    return copy;
  }

  /// Own designs are deleted; built-in designs go back to the original (the "reset"). Rules using a deleted design fall back to the default of their kind.
  Future<void> deleteOrResetTemplate(String id) async {
    await _exec('DELETE FROM token_template WHERE id = ?', [id]);
    if (!builtInTemplates.containsKey(id)) {
      final c = await config();
      final fixed = [for (final r in c.rules) r.templateId == id ? r.copyWith(templateId: '') : r];
      if (fixed.any((r) => r.templateId != c.rule(r.id)?.templateId)) await saveConfig(c.copyWith(rules: fixed));
    }
  }

  /// Imports a design exported with [exportTemplate]. Returns null if the text is not a token design.
  Future<TokenDesign?> importTemplate(String raw) async {
    final t = TokenDesign.decode(raw, id: 'c-${_newId()}');
    if (t == null) return null;
    await saveTemplate(t);
    return t;
  }

  String exportTemplate(TokenDesign t) => const JsonEncoder.withIndent('  ').convert(t.toJson());

  // ---- issuing ----
  static bool _stationMatches(String? itemStation, String ruleStation) => ruleStation.trim().isEmpty || (itemStation ?? '').trim().toLowerCase() == ruleStation.trim().toLowerCase();

  Future<int> _next(TokenRule r, String date) async {
    final scope = r.dailyReset ? '$date:${r.id}' : r.id;
    final cur = (await _select('SELECT last_no FROM token_seq WHERE scope = ?', [scope])).firstOrNull?['last_no'] as int?;
    final n = cur == null ? r.startAt : cur + 1;
    await _exec('INSERT INTO token_seq(scope, last_no) VALUES (?,?) ON CONFLICT(scope) DO UPDATE SET last_no = excluded.last_no', [scope, n]);
    return n;
  }

  String _couponCode() {
    // 10 characters, no 0/O/1/I/L so a code read out over the phone is not mixed up
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final bytes = const Uuid().v4().replaceAll('-', '');
    final b = StringBuffer('CP-');
    for (var i = 0; i < 10; i++) {
      b.write(alphabet[int.parse(bytes.substring(i * 2, i * 2 + 2), radix: 16) % alphabet.length]);
      if (i == 4) b.write('-');
    }
    return b.toString();
  }

  /// Creates the tokens the active rules call for on a paid order. Safe to call again: rules that already have tokens
  /// for this order are skipped, so a retry never produces a second token or a second number.
  Future<List<IssuedToken>> issueForOrder(String orderId) => db.transaction(() async {
        final cfg = await config();
        final active = cfg.active.toList();
        if (active.isEmpty) return const <IssuedToken>[];
        final o = (await _select('SELECT * FROM "order" WHERE id = ?', [orderId])).firstOrNull;
        if (o == null || o['status'] != 'paid') return forOrder(orderId);
        final rows = await _select("SELECT * FROM order_item WHERE order_id = ? AND status = 'active' ORDER BY rowid", [orderId]);
        if (rows.isEmpty) return forOrder(orderId);

        final table = o['table_id'] == null ? null : (await _select('SELECT label FROM dining_table WHERE id = ?', [o['table_id']])).firstOrNull?['label'] as String?;
        final cashier = o['cashier_id'] == null ? null : (await _select('SELECT name FROM staff WHERE id = ?', [o['cashier_id']])).firstOrNull?['name'] as String?;
        final items = <(Map<String, Object?>, SlipItem)>[];
        for (final r in rows) {
          final mods = await _select('SELECT name FROM order_item_modifier WHERE order_item_id = ?', [r['id']]);
          items.add((r, SlipItem(name: r['name'] as String, qtyMilli: r['qty_milli'] as int, unitPriceMinor: r['unit_price_minor'] as int, totalMinor: r['line_total_minor'] as int, modifiers: [for (final m in mods) m['name'] as String], note: r['note'] as String?, station: r['station'] as String?)));
        }
        final categoryOf = {for (final r in await _select('SELECT id, category_id FROM product WHERE id IN (SELECT product_id FROM order_item WHERE order_id = ?)', [orderId])) r['id'] as String: r['category_id'] as String?};
        final date = o['business_date'] as String;
        final orderNo = (o['invoice_no'] as String?) ?? '';

        for (final rule in active) {
          if ((await _select('SELECT 1 AS x FROM token_issue WHERE order_id = ? AND rule_id = ? LIMIT 1', [orderId, rule.id])).isNotEmpty) continue;
          final scoped = rule.kind.needsStation || rule.station.isNotEmpty || rule.hasPicks;
          final mine = scoped
              ? [
                  for (final e in items)
                    if (!(rule.kind.needsStation && !rule.isScoped) &&
                        _stationMatches(e.$1['station'] as String?, rule.station) &&
                        rule.picks(e.$1['product_id'] as String?, categoryOf[e.$1['product_id']]))
                      e.$2
                ]
              : [for (final e in items) e.$2];
          if (mine.isEmpty) continue;

          // each part becomes one token: the items it shows, and the money of the order for order/price tokens
          final parts = <List<SlipItem>>[];
          switch (rule.kind) {
            case TokenKind.order || TokenKind.price:
              parts.add(mine);
            case TokenKind.product:
              if (rule.split == 'line') {
                for (final i in mine) {
                  parts.add([i]);
                }
              } else {
                parts.add(mine);
              }
            case TokenKind.tandoor || TokenKind.stall:
              parts.add(mine);
            case TokenKind.unit || TokenKind.coupon:
              for (final i in mine) {
                // whole units get a token each (weighed items stay one token); 50 is a sanity cap
                final units = i.qtyMilli % 1000 == 0 ? (i.qtyMilli ~/ 1000).clamp(1, 50) : 1;
                for (var u = 0; u < units; u++) {
                  parts.add([SlipItem(name: i.name, qtyMilli: units == 1 && i.qtyMilli % 1000 != 0 ? i.qtyMilli : 1000, unitPriceMinor: i.unitPriceMinor, totalMinor: i.qtyMilli % 1000 == 0 ? i.totalMinor ~/ (i.qtyMilli ~/ 1000) : i.totalMinor, modifiers: i.modifiers, note: i.note, station: i.station)]);
                }
              }
          }
          for (var p = 0; p < parts.length; p++) {
            final n = await _next(rule, date);
            final label = rule.format(n);
            final id = _newId();
            final wholeOrder = rule.kind == TokenKind.order || rule.kind == TokenKind.price;
            final code = rule.kind == TokenKind.coupon ? _couponCode() : null;
            final payload = <String, dynamic>{
              'items': [for (final i in parts[p]) i.toJson()],
              'counter': rule.name.trim().isNotEmpty ? rule.name.trim() : rule.station.trim(),
              'collect': rule.collectText,
              'orderNo': orderNo,
              'type': orderTypeLabels[o['order_type']] ?? '${o['order_type']}',
              'table': ?table,
              'cashier': ?cashier,
              'sub': wholeOrder ? o['subtotal_minor'] : parts[p].fold<int>(0, (s, i) => s + i.totalMinor),
              if (wholeOrder) 'disc': o['discount_minor'],
              if (wholeOrder) 'tax': o['tax_minor'],
              'total': wholeOrder ? o['total_minor'] : parts[p].fold<int>(0, (s, i) => s + i.totalMinor),
              'coupon': ?code,
              if (code != null) 'couponValue': parts[p].first.unitPriceMinor,
            };
            await _exec(
                'INSERT INTO token_issue(id, order_id, rule_id, kind, part, seq, label, station, payload, business_date, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                [id, orderId, rule.id, rule.kind.name, p, n, label, rule.station.isEmpty ? null : rule.station, jsonEncode(payload), date, _ts]);
            if (code != null) {
              await _exec('INSERT INTO coupon(id, code, token_id, order_id, label, value_minor, created_at) VALUES (?,?,?,?,?,?,?)', [_newId(), code, id, orderId, parts[p].first.name, parts[p].first.unitPriceMinor, _ts]);
            }
          }
        }
        return forOrder(orderId);
      });

  IssuedToken _row(Map<String, Object?> r) => IssuedToken(
        id: r['id'] as String,
        orderId: r['order_id'] as String,
        ruleId: r['rule_id'] as String,
        kind: TokenKind.parse(r['kind'] as String?),
        part: r['part'] as int,
        seq: r['seq'] as int,
        label: r['label'] as String,
        station: r['station'] as String?,
        status: r['status'] as String,
        printCount: r['print_count'] as int,
        lastPrintedAt: r['last_printed_at'] as int?,
        businessDate: r['business_date'] as String,
        createdAt: r['created_at'] as int,
        collectedAt: r['collected_at'] as int?,
        payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
      );

  Future<List<IssuedToken>> forOrder(String orderId) async => [for (final r in await _select('SELECT * FROM token_issue WHERE order_id = ? ORDER BY created_at, rule_id, part', [orderId])) _row(r)];

  Future<List<IssuedToken>> forDate(String date, {String? status}) async => [
        for (final r in await _select('SELECT * FROM token_issue WHERE business_date = ? ${status == null ? '' : 'AND status = ?'} ORDER BY created_at DESC, part', [date, ?status])) _row(r)
      ];

  Future<IssuedToken?> byId(String id) async => (await _select('SELECT * FROM token_issue WHERE id = ?', [id])).map(_row).firstOrNull;

  /// The token number shown on the customer bill: the first order-type token of the sale.
  Future<String?> orderTokenLabel(String orderId) async =>
      (await _select("SELECT label FROM token_issue WHERE order_id = ? AND kind IN ('order','price') AND status != 'void' ORDER BY created_at LIMIT 1", [orderId])).firstOrNull?['label'] as String?;

  // ---- collection / cancellation ----
  /// Marks a token as collected by the customer. Returns false if it was not waiting (already collected or void).
  Future<bool> markCollected(String id) => db.transaction(() async {
        final t = await byId(id);
        if (t == null || !t.isIssued) return false;
        await _exec("UPDATE token_issue SET status = 'collected', collected_at = ? WHERE id = ? AND status = 'issued'", [_ts, id]);
        return true;
      });

  /// A cancelled/refunded sale cancels its waiting tokens and unredeemed coupons. Collected tokens and redeemed coupons stay as they are.
  Future<void> voidForOrder(String orderId) async {
    await _exec("UPDATE token_issue SET status = 'void' WHERE order_id = ? AND status = 'issued'", [orderId]);
    await _exec("UPDATE coupon SET status = 'void' WHERE order_id = ? AND status = 'issued'", [orderId]);
  }

  Future<void> recordPrinted(String id) => _exec('UPDATE token_issue SET print_count = print_count + 1, last_printed_at = ? WHERE id = ?', [_ts, id]);

  // ---- coupons ----
  /// Redeems a coupon once. The database update only succeeds while the coupon is still unused, so two cashiers
  /// scanning the same code at the same moment cannot both get it.
  Future<RedeemResult> redeem(String rawCode, {String? staffId}) => db.transaction(() async {
        final code = formatCouponCode(rawCode);
        final c = (await _select('SELECT * FROM coupon WHERE code = ?', [code])).firstOrNull;
        if (c == null) return const RedeemResult(RedeemStatus.notFound);
        RedeemResult res(RedeemStatus s) => RedeemResult(s, code: code, label: c['label'] as String, valueMinor: c['value_minor'] as int, redeemedAt: c['redeemed_at'] as int?);
        if (c['status'] == 'redeemed') return res(RedeemStatus.alreadyRedeemed);
        if (c['status'] == 'void') return res(RedeemStatus.voided);
        await _exec("UPDATE coupon SET status = 'redeemed', redeemed_at = ?, redeemed_by = ? WHERE code = ? AND status = 'issued'", [_ts, staffId, code]);
        final changed = (await _select('SELECT changes() AS n')).first['n'] as int;
        if (changed != 1) return res(RedeemStatus.alreadyRedeemed);
        if (c['token_id'] != null) await _exec("UPDATE token_issue SET status = 'collected', collected_at = ? WHERE id = ? AND status = 'issued'", [_ts, c['token_id']]);
        await _exec('INSERT INTO audit_log(id, at, staff_id, event, entity, entity_id, after_json, critical) VALUES (?,?,?,?,?,?,?,0)', [_newId(), _ts, staffId, 'coupon.redeem', 'coupon', c['id'], jsonEncode({'code': code})]);
        return RedeemResult(RedeemStatus.ok, code: code, label: c['label'] as String, valueMinor: c['value_minor'] as int, redeemedAt: _ts);
      });

  Future<int> couponsLeft() async => (await _select("SELECT COUNT(*) AS n FROM coupon WHERE status = 'issued'")).first['n'] as int;

  // ---- slips ----
  /// What a stored token prints: its snapshot plus the business details of today (name, logo for this paper width).
  Future<TokenSlip> slip(IssuedToken t, {int paperMm = 58, bool reprint = false}) async {
    final biz = (await _select("SELECT * FROM business_profile WHERE id = 'self'")).firstOrNull;
    RasterImage? logo;
    final path = biz?['logo_path'] as String?;
    if (path != null && File(path).existsSync()) {
      try {
        logo = prepareLogo(File(path).readAsBytesSync(), paperMm: paperMm);
      } catch (_) {}
    }
    final p = t.payload;
    final when = DateTime.fromMillisecondsSinceEpoch(t.createdAt);
    return TokenSlip(
      businessName: biz?['name'] as String? ?? 'DT Food POS',
      label: t.label,
      dateTime: formatDateTime(when),
      counterName: t.counter,
      collectText: p['collect'] as String? ?? '',
      orderNo: t.orderNo,
      orderType: p['type'] as String? ?? '',
      tableLabel: p['table'] as String?,
      cashier: p['cashier'] as String?,
      items: t.items,
      subtotalMinor: (p['sub'] as num?)?.toInt(),
      discountMinor: (p['disc'] as num?)?.toInt() ?? 0,
      taxMinor: (p['tax'] as num?)?.toInt() ?? 0,
      totalMinor: (p['total'] as num?)?.toInt(),
      currency: Currency(biz?['currency'] as String? ?? 'PKR', minorDigits: biz?['currency_minor_digits'] as int? ?? 2),
      couponCode: t.couponCode,
      couponValueMinor: (p['couponValue'] as num?)?.toInt(),
      qrData: 'DT|${t.label}|${t.orderNo}',
      logo: logo,
      isReprint: reprint || t.printCount > 0,
    );
  }
}
