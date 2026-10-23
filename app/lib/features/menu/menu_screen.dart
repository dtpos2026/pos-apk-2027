import 'dart:convert';

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
          child: Row(children: [
            Expanded(child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search_items'], isDense: true), onChanged: (s) => setState(() => _search = s))),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('categories'), onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const _CategoriesDialog());
              _refresh();
            }, icon: const Icon(Icons.category_outlined), label: Text(t['categories'])),
            const SizedBox(width: 8),
            OutlinedButton.icon(key: const ValueKey('import-csv'), onPressed: () async {
              await showDialog<void>(context: context, builder: (_) => const _ImportDialog());
              _refresh();
            }, icon: const Icon(Icons.upload_file), label: Text(t['import_csv'])),
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

Future<bool> _editDialog(BuildContext context, WidgetRef ref, MenuProduct? p) async {
  final t = Strings.of(context);
  final name = TextEditingController(text: p?.name);
  final price = TextEditingController(text: p == null ? '' : formatMinor(p.priceMinor, currency: ref.currency, symbol: false).replaceAll(',', ''));
  final category = TextEditingController(text: p?.categoryName);
  String? error;
  Uint8List? newPhoto; // picked but not saved yet
  var removePhoto = false;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(p == null ? t['add_item'] : p.name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(
                width: 84,
                height: 84,
                child: newPhoto != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(newPhoto!, fit: BoxFit.cover))
                    : MenuImage(path: removePhoto ? null : p?.imagePath, name: name.text, radius: 12),
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
                        setState(() { newPhoto = jpg; removePhoto = false; error = null; });
                      } on MenuImageException catch (e) {
                        setState(() => error = e.message);
                      }
                    },
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(t['choose_photo']),
                  ),
                  if (newPhoto != null || (p?.imagePath != null && !removePhoto))
                    TextButton(key: const ValueKey('item-photo-remove'), onPressed: () => setState(() { newPhoto = null; removePhoto = true; }), child: Text(t['remove_photo'])),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(key: const ValueKey('item-name'), controller: name, decoration: InputDecoration(labelText: t['product_name'])),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-price'), controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: InputDecoration(labelText: t['price'])),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-category'), controller: category, decoration: InputDecoration(labelText: t['category'])),
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(key: const ValueKey('edit-variants'), onPressed: () => _variantsDialog(ctx, ref, p), icon: const Icon(Icons.straighten, size: 18), label: Text(t['variants_title'])),
                  OutlinedButton.icon(key: const ValueKey('edit-addons'), onPressed: () => _addonsDialog(ctx, ref, p), icon: const Icon(Icons.add_circle_outline, size: 18), label: Text(t['addons'])),
                ]),
              ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
        ),
        actions: [
          if (p != null)
            TextButton(
              onPressed: () async {
                await ref.read(menuServiceProvider).deleteProduct(p.id, staffId: ref.read(sessionProvider)!.staffId);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(t['delete'], style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])),
          FilledButton(
            key: const ValueKey('item-save'),
            onPressed: () async {
              final minor = parseMinor(price.text, currency: ref.currency);
              if (minor == null) {
                setState(() => error = t['price']);
                return;
              }
              try {
                final id = await ref.read(menuServiceProvider).saveProduct(id: p?.id, name: name.text, priceMinor: minor, categoryName: category.text, sku: p?.sku, available: p?.available ?? true, staffId: ref.read(sessionProvider)!.staffId);
                final images = ref.read(menuImageStoreProvider);
                if (newPhoto != null) {
                  await images.setProduct(id, newPhoto!);
                } else if (removePhoto) {
                  await images.removeProduct(id);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on MenuException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: Text(t['save']),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel'])),
        OutlinedButton(key: const ValueKey('csv-check'), onPressed: () => _run(true), child: Text(t['check'])),
        FilledButton(key: const ValueKey('csv-import'), onPressed: () => _run(false), child: Text(t['import_now'])),
      ],
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

String _optionLines(Iterable<(String, int)> items, Currency c) => items.map((e) => '${e.$1}, ${formatMinor(e.$2, currency: c, symbol: false).replaceAll(',', '')}').join('\n');

Future<void> _variantsDialog(BuildContext context, WidgetRef ref, MenuProduct p) async {
  final t = Strings.of(context);
  final svc = ref.read(menuServiceProvider);
  final current = (await svc.optionsFor(p.id)).variants;
  if (!context.mounted) return;
  await showFormDialog(
    context,
    title: '${t['variants_title']}: ${p.name}',
    fields: [FieldSpec('lines', t['variants_hint'], lines: 5, required: false, initial: _optionLines(current.map((v) => (v.name, v.priceMinor)), ref.currency))],
    validate: (v) async {
      final parsed = parseOptionLines(v['lines']!, ref.currency);
      if (parsed == null) return t['invalid_lines'];
      try {
        await svc.saveVariants(p.id, parsed);
        return null;
      } on MenuException catch (e) {
        return e.message;
      }
    },
  );
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
      title: Text(t['categories']),
      content: SizedBox(
        width: 380,
        child: cats.isEmpty
            ? Text(t['no_categories'])
            : ListView(shrinkWrap: true, children: [
                Text(t['category_photo_hint'], style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (final c in cats)
                  ListTile(
                    key: ValueKey('category-${c.name}'),
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(width: 48, height: 48, child: MenuImage(path: c.imagePath, name: c.name, radius: 10, iconSize: 24)),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
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
