import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../data/menu_images.dart';
import '../common/menu_image.dart';
import '../../app/strings.dart';
import '../../data/menu_import.dart';
import '../../data/menu_service.dart';
import '../../data/queries.dart';
import '../../domain/money.dart';
import '../../domain/xlsx.dart';
import '../common/dialogs.dart';
import '../inventory/recipes_screen.dart';
import '../../data/recipe_service.dart';
import 'deals_screen.dart';
import 'share/menu_share_screen.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});
  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String _search = '';

  void _refresh() {
    ref.invalidate(productsProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final products = ref.watch(productsProvider(ProductFilter(search: _search)));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-item'), onPressed: () async {
        if (await _editDialog(context, ref, null)) _refresh();
      }, icon: const Icon(Icons.add), label: Text(t['add_item'])),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search_items'], isDense: true), onChanged: (s) => setState(() => _search = s)),
            const SizedBox(height: 8),
            SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
            OutlinedButton.icon(key: const ValueKey('categories'), onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const _CategoriesDialog());
              _refresh();
            }, icon: const Icon(Icons.category_outlined), label: Text(t['categories'])),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('menu-share'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MenuShareScreen())), icon: const Icon(Icons.ios_share, size: 18), label: Text(t['share_menu'])),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('open-deals'), onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DealsScreen()));
              _refresh();
            }, icon: const Icon(Icons.local_offer_outlined), label: Text(t['deals'])),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('import-csv'), onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const _ImportDialog());
              _refresh();
            }, icon: const Icon(Icons.upload_file), label: Text(t['import_csv'])),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('export-csv'), onPressed: () => _exportMenu(context, ref), icon: const Icon(Icons.download_outlined), label: Text(t['export_csv'])),
          ])),
          ]),
        ),
        Expanded(
          child: products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => list.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t['no_items'], textAlign: TextAlign.center)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return Card(
                        child: ListTile(
                          key: ValueKey('menu-${p.name}'),
                          leading: SizedBox(width: 48, height: 48, child: MenuImage(path: p.imagePath ?? p.categoryImagePath, name: '${p.name} ${p.categoryName ?? ''}', radius: 10, iconSize: 24)),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([if (p.categoryName != null) p.categoryName!, if (p.sku != null) p.sku!].join('  ·  ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(ref.money(p.priceMinor), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                            Switch(value: p.available, onChanged: (v) async {
                              await ref.read(menuServiceProvider).setAvailable(p.id, v, staffId: ref.read(sessionProvider)!.staffId);
                              _refresh();
                            }),
                          ]),
                          onTap: () async {
                            if (await _editDialog(context, ref, p)) _refresh();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Saves the whole menu as a CSV file in the phone's Downloads (and opens the share sheet), ready for Excel.
Future<void> _exportMenu(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final csv = await ref.read(menuImporterProvider).exportCsv();
  final dir = ref.read(exportDirProvider)..createSync(recursive: true);
  final f = File('${dir.path}/menu.csv')..writeAsStringSync('\u{FEFF}$csv'); // BOM so Excel reads Urdu names correctly
  try {
    final where = await ref.read(phoneFileSaverProvider).save(path: f.path, name: 'menu.csv', mime: 'text/csv');
    if (context.mounted) showMessage(context, '${t['saved_to']}: $where');
  } catch (e) {
    if (context.mounted) showMessage(context, '${t['save_failed']}: $e');
  }
  await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'text/csv', subject: 'menu');
}

Future<bool> _editDialog(BuildContext context, WidgetRef ref, MenuProduct? p) async {
  final variants = p == null ? const <VariantInfo>[] : (await ref.read(menuServiceProvider).optionsFor(p.id)).variants;
  if (!context.mounted) return false;
  final saved = await showDialog<bool>(context: context, builder: (_) => _ItemEditor(product: p, variants: variants));
  return saved ?? false;
}

enum _Sold { fixed, size, inch, weight, manual }

const _sizeNames = ['Small', 'Medium', 'Large', 'Extra Large'];
const _inchNames = ['7"', '9"', '12"', '15"', '21"'];

/// Add / edit an item the way DT Enterprise does it: first say how it is sold (one price, sizes, inches, by weight, price at the
/// till), then fill what that needs, all in this one window. Sizes are rows (name and price); add-ons and the recipe can be set up
/// right away: the item is saved the moment one of them is opened.
class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({required this.product, required this.variants});
  final MenuProduct? product;
  final List<VariantInfo> variants;
  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  late final MenuProduct? p = widget.product;
  late final name = TextEditingController(text: p?.name);
  late final price = TextEditingController(text: p == null || p!.askPrice || p!.hasVariants ? '' : formatMinor(p!.priceMinor, currency: ref.currency, symbol: false).replaceAll(',', ''));
  late final category = TextEditingController(text: p?.categoryName);
  late final counter = TextEditingController(text: p?.ownStation);
  late final description = TextEditingController(text: p?.description);
  final _rows = <({TextEditingController name, TextEditingController price})>[];
  late _Sold _mode = _initialMode();
  String? _error;
  Uint8List? _newPhoto; // picked but not saved yet
  bool _removePhoto = false;
  String? _id;

  _Sold _initialMode() {
    final x = p;
    if (x == null) return _Sold.fixed;
    if (x.askPrice) return _Sold.manual;
    if (const {'kg', 'g', 'l', 'ml'}.contains(x.unit)) return _Sold.weight;
    if (widget.variants.isNotEmpty) return widget.variants.any((v) => v.name.contains('"') || RegExp(r'^\d').hasMatch(v.name) || v.name.toLowerCase().contains('inch')) ? _Sold.inch : _Sold.size;
    return _Sold.fixed;
  }

  @override
  void initState() {
    super.initState();
    _id = p?.id;
    for (final v in widget.variants) {
      _rows.add((name: TextEditingController(text: v.name), price: TextEditingController(text: formatMinor(v.priceMinor, currency: ref.currency, symbol: false).replaceAll(',', ''))));
    }
  }

  @override
  void dispose() {
    for (final c in [name, price, category, counter, description]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.name.dispose();
      r.price.dispose();
    }
    super.dispose();
  }

  void _pickMode(_Sold m) => setState(() {
        _mode = m;
        _error = null;
        // a fresh sizes list starts with the usual names, ready for prices (as in DT Enterprise)
        if ((m == _Sold.size || m == _Sold.inch) && _rows.isEmpty) {
          for (final n in m == _Sold.size ? _sizeNames : _inchNames) {
            _rows.add((name: TextEditingController(text: n), price: TextEditingController()));
          }
        }
      });

  void _addRow([String n = '']) => setState(() => _rows.add((name: TextEditingController(text: n), price: TextEditingController())));

  /// Saves the item (and its sizes and picture). Returns its id, or null with the problem shown.
  Future<String?> _persist() async {
    final t = Strings.of(context);
    final cur = ref.currency;
    var base = 0;
    final sizes = <({String name, int priceMinor})>[];
    switch (_mode) {
      case _Sold.fixed:
      case _Sold.weight:
        final m = parseMinor(price.text.trim().isEmpty ? '' : price.text.trim(), currency: cur);
        if (m == null) {
          setState(() => _error = t[_mode == _Sold.weight ? 'rate_per_kg' : 'price']);
          return null;
        }
        base = m;
      case _Sold.size:
      case _Sold.inch:
        for (final r in _rows) {
          final n = r.name.text.trim();
          if (n.isEmpty && r.price.text.trim().isEmpty) continue;
          final m = parseMinor(r.price.text.trim().isEmpty ? '' : r.price.text.trim(), currency: cur);
          if (n.isEmpty || m == null) {
            setState(() => _error = t['sizes_need_price']);
            return null;
          }
          sizes.add((name: n, priceMinor: m));
        }
        if (sizes.isEmpty) {
          setState(() => _error = t['sizes_need_price']);
          return null;
        }
        base = sizes.map((s) => s.priceMinor).reduce((a, b) => a < b ? a : b);
      case _Sold.manual:
        base = 0;
    }
    final unit = _mode == _Sold.weight ? (const {'kg', 'g', 'l', 'ml'}.contains(p?.unit) ? p!.unit : 'kg') : 'pc';
    try {
      final svc = ref.read(menuServiceProvider);
      final id = await svc.saveProduct(id: _id, name: name.text, priceMinor: base, categoryName: category.text, sku: p?.sku, available: p?.available ?? true, station: counter.text, updateStation: true, description: description.text, updateDescription: true, unit: unit, askPrice: _mode == _Sold.manual, staffId: ref.read(sessionProvider)!.staffId);
      _id = id;
      await svc.saveVariants(id, sizes);
      final images = ref.read(menuImageStoreProvider);
      if (_newPhoto != null) {
        await images.setProduct(id, _newPhoto!);
        _newPhoto = null;
      } else if (_removePhoto) {
        await images.removeProduct(id);
        _removePhoto = false;
      }
      return id;
    } on MenuException catch (e) {
      setState(() => _error = e.message);
      return null;
    }
  }

  Future<MenuProduct?> _savedProduct() async {
    final id = await _persist();
    if (id == null) return null;
    return (await loadProducts(ref.read(databaseProvider), search: name.text.trim())).where((x) => x.id == id).firstOrNull ?? MenuProduct(id: id, name: name.text.trim(), priceMinor: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    Widget modeChip(_Sold m, String label) => ChoiceChip(key: ValueKey('mode-${m.name}'), label: Text(label), selected: _mode == m, onSelected: (_) => _pickMode(m));
    final sizeMode = _mode == _Sold.size || _mode == _Sold.inch;
    return AlertDialog(
      title: Text(p == null ? t['add_item'] : p!.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                width: 84,
                height: 84,
                child: _newPhoto != null ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_newPhoto!, fit: BoxFit.cover)) : MenuImage(path: _removePhoto ? null : p?.imagePath, name: name.text, radius: 12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  OutlinedButton.icon(
                    key: const ValueKey('item-photo'),
                    onPressed: () async {
                      final b = await ref.read(logoPickerProvider).pick();
                      if (b == null) return;
                      try {
                        final jpg = MenuImageStore.normalize(b);
                        setState(() {
                          _newPhoto = jpg;
                          _removePhoto = false;
                          _error = null;
                        });
                      } on MenuImageException catch (e) {
                        setState(() => _error = e.message);
                      }
                    },
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(t['choose_photo']),
                  ),
                  if (_newPhoto != null || (p?.imagePath != null && !_removePhoto))
                    TextButton(key: const ValueKey('item-photo-remove'), onPressed: () => setState(() {
                          _newPhoto = null;
                          _removePhoto = true;
                        }), child: Text(t['remove_photo'])),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(key: const ValueKey('item-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t['product_name'])),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-category'), controller: category, decoration: InputDecoration(labelText: t['category'])),
            const SizedBox(height: 14),
            Text(t['sold_as'], style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 0, children: [modeChip(_Sold.fixed, t['sold_fixed']), modeChip(_Sold.size, t['sold_size']), modeChip(_Sold.inch, t['sold_inch']), modeChip(_Sold.weight, t['sold_weight']), modeChip(_Sold.manual, t['sold_manual'])]),
            const SizedBox(height: 8),
            if (_mode == _Sold.fixed || _mode == _Sold.weight) ...[
              if (_mode == _Sold.weight) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t['weight_hint'], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
              TextField(key: const ValueKey('item-price'), controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: InputDecoration(labelText: t[_mode == _Sold.weight ? 'rate_per_kg' : 'price'])),
            ],
            if (_mode == _Sold.manual) Text(t['manual_hint'], key: const ValueKey('manual-hint'), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (sizeMode) ...[
              Text(t['size_rows_hint'], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [for (final n in _mode == _Sold.size ? _sizeNames : _inchNames) if (!_rows.any((r) => r.name.text.trim() == n)) ActionChip(key: ValueKey('size-quick-$n'), label: Text(n), visualDensity: VisualDensity.compact, onPressed: () => _addRow(n))]),
              const SizedBox(height: 6),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(flex: 5, child: TextField(key: ValueKey('size-name-$i'), controller: _rows[i].name, decoration: InputDecoration(isDense: true, labelText: t['variant_name']))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: TextField(key: ValueKey('size-price-$i'), controller: _rows[i].price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: InputDecoration(isDense: true, labelText: t['price']))),
                    IconButton(key: ValueKey('size-del-$i'), visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, color: cs.error), onPressed: () => setState(() {
                          final r = _rows.removeAt(i);
                          r.name.dispose();
                          r.price.dispose();
                        })),
                  ]),
                ),
              TextButton.icon(key: const ValueKey('size-add'), onPressed: _addRow, icon: const Icon(Icons.add), label: Text(t['variant_add'])),
            ],
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-description'), controller: description, maxLines: 2, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: t['item_description'], helperText: t['item_description_hint'], helperMaxLines: 2)),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-counter'), controller: counter, decoration: InputDecoration(labelText: t['counter_station'], helperText: t['counter_station_hint'], helperMaxLines: 2)),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(key: const ValueKey('edit-recipe'), onPressed: () async {
                  final x = await _savedProduct();
                  if (x != null && context.mounted) await _recipeFor(context, ref, x);
                }, icon: const Icon(Icons.menu_book_outlined, size: 18), label: Text(t['recipe'])),
                OutlinedButton.icon(key: const ValueKey('edit-addons'), onPressed: () async {
                  final x = await _savedProduct();
                  if (x != null && context.mounted) await _addonsDialog(context, ref, x);
                }, icon: const Icon(Icons.add_circle_outline, size: 18), label: Text(t['addons'])),
              ]),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, key: const ValueKey('item-error'), style: TextStyle(color: cs.error))),
          ]),
        ),
      ),
      actions: [
        DialogActions([
          if (p != null)
            TextButton(
              onPressed: () async {
                await ref.read(menuServiceProvider).deleteProduct(p!.id, staffId: ref.read(sessionProvider)!.staffId);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: Text(t['delete'], style: TextStyle(color: cs.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(context, _id != null), child: Text(t['cancel'])),
          FilledButton(
            key: const ValueKey('item-save'),
            onPressed: () async {
              if (await _persist() != null && context.mounted) Navigator.pop(context, true);
            },
            child: Text(t['save']),
          ),
        ]),
      ],
    );
  }
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();
  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  ImportReport? _report;

  Future<void> _pickFile() async {
    final f = await ref.read(importFilePickerProvider).pick();
    if (f == null) return;
    String? text;
    if (f.name.toLowerCase().endsWith('.xlsx')) {
      text = xlsxToCsv(f.bytes);
    } else {
      text = utf8.decode(f.bytes, allowMalformed: true);
    }
    setState(() {
      _text.text = text ?? '';
      _report = null;
    });
    if (text == null && mounted) showMessage(context, Strings.of(context)['file_unreadable']);
  }

  Future<void> _run(bool dry) async {
    final r = await ref.read(menuImporterProvider).import(_text.text, dryRun: dry, staffId: ref.read(sessionProvider)?.staffId);
    setState(() => _report = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final r = _report;
    return AlertDialog(
      title: Text(t['import_csv']),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const ValueKey('csv-text'), controller: _text, minLines: 6, maxLines: 10, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12), decoration: InputDecoration(hintText: t['paste_csv'])),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              TextButton.icon(key: const ValueKey('csv-template'), onPressed: () => setState(() => _text.text = menuCsvTemplate()), icon: const Icon(Icons.description_outlined), label: Text(t['template'])),
              TextButton.icon(key: const ValueKey('csv-file'), onPressed: _pickFile, icon: const Icon(Icons.folder_open), label: Text(t['choose_file'])),
            ]),
            if (r != null) ...[
              const Divider(),
              Text(r.ok ? '${r.creates} ${t['new_items']}, ${r.updates} ${t['updated_items']}${r.committed ? '  ✓' : ''}' : '${r.issues.length} ${t['problems']}', key: const ValueKey('csv-summary'), style: TextStyle(fontWeight: FontWeight.w700, color: r.ok ? Colors.green.shade700 : Theme.of(context).colorScheme.error)),
              for (final i in r.issues.take(12)) Text('• $i', style: const TextStyle(fontSize: 12.5)),
              if (r.issues.length > 12) Text('… and ${r.issues.length - 12} more', style: const TextStyle(fontSize: 12.5)),
            ],
          ]),
        ),
      ),
      actions: [DialogActions([
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel'])),
        OutlinedButton(key: const ValueKey('csv-check'), onPressed: () => _run(true), child: Text(t['check'])),
        FilledButton(key: const ValueKey('csv-import'), onPressed: () => _run(false), child: Text(t['import_now'])),
      ])],
    );
  }
}

/// "name, price" per line -> list, or null if any line is invalid.
List<({String name, int priceMinor})>? parseOptionLines(String text, Currency currency) {
  final out = <({String name, int priceMinor})>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final i = line.lastIndexOf(',');
    final name = (i < 0 ? line : line.substring(0, i)).trim();
    final price = i < 0 ? 0 : parseMinor(line.substring(i + 1).trim().isEmpty ? '0' : line.substring(i + 1).trim(), currency: currency);
    if (name.isEmpty || price == null) return null;
    out.add((name: name, priceMinor: price));
  }
  return out;
}

/// Opens the recipe of this item, asking which size first when it has sizes.
Future<void> _recipeFor(BuildContext context, WidgetRef ref, MenuProduct p) async {
  final rows = (await ref.read(recipeServiceProvider).rows(search: p.name)).where((r) => r.productId == p.id).toList();
  if (rows.isEmpty || !context.mounted) return;
  var row = rows.first;
  if (rows.length > 1) {
    final picked = await showDialog<RecipeRow>(context: context, builder: (ctx) => SimpleDialog(title: Text(p.name), children: [for (final r in rows) SimpleDialogOption(key: ValueKey('recipe-size-${r.variantName}'), onPressed: () => Navigator.pop(ctx, r), child: Text(r.variantName ?? p.name))]));
    if (picked == null || !context.mounted) return;
    row = picked;
  }
  final ok = await showRecipeEditor(context, ref, row);
  if (ok == true) ref.invalidate(recipeRowsProvider);
}

Future<void> _addonsDialog(BuildContext context, WidgetRef ref, MenuProduct p) async {
  final t = Strings.of(context);
  final svc = ref.read(menuServiceProvider);
  var groups = await svc.allGroups();
  final linked = (await svc.optionsFor(p.id)).groups.map((g) => g.id).toSet();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('${t['addons']}: ${p.name}'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final g in groups)
                CheckboxListTile(
                  key: ValueKey('group-${g.name}'),
                  contentPadding: EdgeInsets.zero,
                  value: linked.contains(g.id),
                  title: Text(g.name),
                  subtitle: Text('${g.minSelect}-${g.maxSelect}  ·  ${g.options.map((o) => o.name).join(', ')}'),
                  onChanged: (v) => setState(() => v == true ? linked.add(g.id) : linked.remove(g.id)),
                ),
              TextButton.icon(
                key: const ValueKey('new-group'),
                onPressed: () async {
                  final v = await showFormDialog(
                    ctx,
                    title: t['new_group'],
                    fields: [FieldSpec('name', t['group_name']), FieldSpec('min', t['min_choices'], number: true, initial: '0'), FieldSpec('max', t['max_choices'], number: true, initial: '1'), FieldSpec('options', t['options_hint'], lines: 5)],
                    validate: (v) async {
                      final opts = parseOptionLines(v['options']!, ref.currency);
                      if (opts == null) return t['invalid_lines'];
                      try {
                        await svc.saveGroup(name: v['name']!, minSelect: int.tryParse(v['min']!) ?? 0, maxSelect: int.tryParse(v['max']!) ?? 1, options: opts);
                        return null;
                      } on MenuException catch (e) {
                        return e.message;
                      }
                    },
                  );
                  if (v != null) {
                    final all = await svc.allGroups();
                    setState(() {
                      groups = all;
                      linked.add(all.firstWhere((g) => g.name == v['name']).id);
                    });
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(t['new_group']),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
          FilledButton(key: const ValueKey('addons-save'), onPressed: () async {
            await svc.setProductGroups(p.id, linked.toList());
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: Text(t['save'])),
        ],
      ),
    ),
  );
}

/// Category pictures (shown on the selling screen and used for items without their own picture).
class _CategoriesDialog extends ConsumerWidget {
  const _CategoriesDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cats = ref.watch(categoriesProvider).value ?? const <MenuCategory>[];
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      title: Text(t['categories']),
      content: SizedBox(
        width: 420,
        child: cats.isEmpty
            ? Text(t['no_categories'])
            : ListView(shrinkWrap: true, children: [
                Text(t['category_photo_hint'], style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final c in cats)
                  ListTile(
                    key: ValueKey('category-${c.name}'),
                    contentPadding: EdgeInsets.zero,
                    minLeadingWidth: 0,
                    horizontalTitleGap: 12,
                    leading: SizedBox(width: 48, height: 48, child: MenuImage(path: c.imagePath, name: c.name, radius: 10, iconSize: 24)),
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: c.station == null ? null : Text('${t['counter_station']}: ${c.station}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        key: ValueKey('category-counter-${c.name}'),
                        tooltip: t['counter_station'],
                        icon: const Icon(Icons.storefront_outlined),
                        onPressed: () async {
                          final ctl = TextEditingController(text: c.station);
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: Text('${t['counter_station']}: ${c.name}'),
                              content: TextField(key: const ValueKey('category-counter-field'), controller: ctl, autofocus: true, decoration: InputDecoration(helperText: t['counter_station_hint'], helperMaxLines: 3)),
                              actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t['cancel'])), FilledButton(key: const ValueKey('category-counter-save'), onPressed: () => Navigator.pop(d, true), child: Text(t['save']))],
                            ),
                          );
                          if (ok != true) return;
                          await ref.read(menuServiceProvider).setCategoryStation(c.id, ctl.text);
                          ref.invalidate(categoriesProvider);
                          ref.invalidate(productsProvider);
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        key: ValueKey('category-photo-${c.name}'),
                        tooltip: t['choose_photo'],
                        icon: const Icon(Icons.photo_camera_outlined),
                        onPressed: () async {
                          final b = await ref.read(logoPickerProvider).pick();
                          if (b == null) return;
                          try {
                            await ref.read(menuImageStoreProvider).setCategory(c.id, b);
                            ref.invalidate(categoriesProvider);
                            ref.invalidate(productsProvider);
                          } on MenuImageException catch (e) {
                            if (context.mounted) showMessage(context, e.message);
                          }
                        },
                      ),
                      if (c.imagePath != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: t['remove_photo'],
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref.read(menuImageStoreProvider).removeCategory(c.id);
                            ref.invalidate(categoriesProvider);
                            ref.invalidate(productsProvider);
                          },
                        ),
                    ]),
                  ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t['close']))],
    );
  }
}
