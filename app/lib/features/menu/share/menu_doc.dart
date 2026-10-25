import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:image/image.dart' as img;

import '../../../data/db/database.dart';
import '../../../data/queries.dart';
import '../../../domain/money.dart';
import '../../../domain/phone.dart';

/// One dish (or deal) on the shared menu.
class MenuEntry {
  const MenuEntry({required this.name, required this.price, this.description, this.image, this.sizes = const [], this.inside = const []});
  final String name;

  /// Already worded: "600", "from 600".
  final String price;
  final String? description;

  /// A small JPEG (about 200 px) of the item picture, if it has one.
  final Uint8List? image;

  /// "Small  600" lines for an item with sizes.
  final List<String> sizes;

  /// What is inside a deal: "2 x Zinger Burger".
  final List<String> inside;
}

class MenuSection {
  const MenuSection({required this.title, required this.entries, this.image, this.deals = false});
  final String title;
  final Uint8List? image;
  final bool deals;
  final List<MenuEntry> entries;
}

/// Everything the menu picture and the menu PDF show, read from the database at the moment it is made, so a changed price, a new deal
/// or a new logo always comes through. [fingerprint] changes whenever any of it changes.
class MenuDoc {
  const MenuDoc({
    required this.name,
    this.address,
    this.phone,
    this.whatsapp,
    this.logo,
    required this.primary,
    required this.accent,
    required this.currencyCode,
    required this.sections,
    required this.fingerprint,
    this.qrLink,
  });
  final String name;
  final String? address;
  final String? phone;

  /// The number customers order on, in international form (digits).
  final String? whatsapp;
  final Uint8List? logo;
  final int primary;
  final int accent;
  final String currencyCode;
  final List<MenuSection> sections;
  final String fingerprint;

  /// The wa.me link the QR on the menu opens.
  final String? qrLink;

  int get itemCount => sections.fold(0, (s, x) => s + x.entries.length);
}

String _price(int minor, Currency c) {
  final t = formatMinor(minor, currency: c, symbol: false);
  return t.endsWith('.00') ? t.substring(0, t.length - 3) : t;
}

Uint8List? _thumb(String? path, int side) {
  if (path == null) return null;
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    final d = img.decodeImage(f.readAsBytesSync());
    if (d == null) return null;
    final small = d.width > side ? img.copyResize(d, width: side, interpolation: img.Interpolation.average) : d;
    return Uint8List.fromList(img.encodeJpg(small, quality: 82));
  } catch (_) {
    return null; // a missing or damaged picture must never stop the menu
  }
}

/// Reads the menu. Only items that are on sale are listed; deals come last under "Deals"; items with no category under "Menu".
Future<MenuDoc> loadMenuDoc(AppDatabase db, {required int primary, required int accent, String dealsTitle = 'Deals', String otherTitle = 'Menu', String fromWord = 'from'}) async {
  Future<List<Map<String, Object?>>> q(String sql, [List<Object?> a = const []]) async =>
      (await db.customSelect(sql, variables: [for (final v in a) v is int ? Variable.withInt(v) : Variable.withString('$v')]).get()).map((r) => r.data).toList();

  final biz = await loadBusiness(db);
  final cur = biz?.currency ?? Currency.pkr;
  final cats = await loadCategories(db);
  final products = await loadProducts(db, includeUnavailable: false);
  final variants = <String, List<(String, int)>>{};
  for (final r in await q('SELECT product_id, name, price_minor FROM product_variant WHERE deleted_at IS NULL ORDER BY price_minor, name')) {
    (variants[r['product_id'] as String] ??= []).add((r['name'] as String, r['price_minor'] as int));
  }
  final kinds = {for (final r in await q('SELECT id, kind FROM product WHERE deleted_at IS NULL')) r['id'] as String: r['kind'] as String};
  final inside = <String, List<String>>{};
  for (final r in await q('SELECT d.deal_id, d.qty_milli, p.name AS pname, v.name AS vname FROM deal_item d JOIN product p ON p.id = d.product_id LEFT JOIN product_variant v ON v.id = d.variant_id ORDER BY d.rowid')) {
    final qty = (r['qty_milli'] as int) / 1000;
    (inside[r['deal_id'] as String] ??= []).add('${qty == qty.roundToDouble() ? qty.round() : qty} x ${r['pname']}${r['vname'] == null ? '' : ' (${r['vname']})'}');
  }

  MenuEntry entry(MenuProduct p) {
    final vs = variants[p.id] ?? const [];
    return MenuEntry(
      name: p.name,
      price: vs.isEmpty ? _price(p.priceMinor, cur) : '$fromWord ${_price(vs.first.$2, cur)}',
      description: p.description,
      image: _thumb(p.imagePath, 220),
      sizes: [for (final v in vs) '${v.$1}  ${_price(v.$2, cur)}'],
      inside: inside[p.id] ?? const [],
    );
  }

  final sections = <MenuSection>[];
  final regular = products.where((p) => kinds[p.id] != 'combo').toList();
  final deals = products.where((p) => kinds[p.id] == 'combo').toList();
  for (final c in cats) {
    final mine = regular.where((p) => p.categoryId == c.id).toList();
    if (mine.isNotEmpty) sections.add(MenuSection(title: c.name, image: _thumb(c.imagePath, 120), entries: [for (final p in mine) entry(p)]));
  }
  final loose = regular.where((p) => p.categoryId == null).toList();
  if (loose.isNotEmpty) sections.add(MenuSection(title: otherTitle, entries: [for (final p in loose) entry(p)]));
  if (deals.isNotEmpty) sections.add(MenuSection(title: dealsTitle, deals: true, entries: [for (final p in deals) entry(p)]));

  final intl = biz?.phone == null ? null : internationalPhone(biz!.phone!, countryCode: callingCodeFor(cur.code));
  final link = intl == null ? null : 'https://wa.me/$intl?text=${Uri.encodeComponent('Hello ${biz!.name}')}';
  final logo = _thumb(biz?.logoPath, 300);

  // the fingerprint: any change to what is printed changes it (text, price, picture file, colours)
  final seed = StringBuffer('${biz?.name}|${biz?.address}|${biz?.phone}|${biz?.logoPath}|$primary|$accent|${cur.code}');
  for (final s in sections) {
    seed.write('#${s.title}');
    for (final e in s.entries) {
      seed.write('|${e.name}|${e.price}|${e.description}|${e.sizes.join(',')}|${e.inside.join(',')}|${e.image?.length}');
    }
  }
  var h = 0x811c9dc5;
  for (final u in seed.toString().codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return MenuDoc(
    name: biz?.name ?? 'Menu',
    address: biz?.address,
    phone: biz?.phone,
    whatsapp: intl,
    logo: logo,
    primary: primary,
    accent: accent,
    currencyCode: cur.code,
    sections: sections,
    fingerprint: h.toRadixString(16),
    qrLink: link,
  );
}
