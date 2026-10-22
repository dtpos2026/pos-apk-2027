import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/menu_import.dart';
import '../../data/menu_service.dart';
import '../../data/queries.dart';
import '../../domain/money.dart';

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
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(p == null ? t['add_item'] : p.name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('item-name'), controller: name, decoration: InputDecoration(labelText: t['product_name'])),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-price'), controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: InputDecoration(labelText: t['price'])),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('item-category'), controller: category, decoration: InputDecoration(labelText: t['category'])),
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
              child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
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
                await ref.read(menuServiceProvider).saveProduct(id: p?.id, name: name.text, priceMinor: minor, categoryName: category.text, sku: p?.sku, available: p?.available ?? true, staffId: ref.read(sessionProvider)!.staffId);
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
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('csv-template'), onPressed: () => setState(() => _text.text = menuCsvTemplate()), icon: const Icon(Icons.description_outlined), label: Text(t['template']))),
            if (r != null) ...[
              const Divider(),
              Text(r.ok ? '${r.creates} new, ${r.updates} updated${r.committed ? '  ✓' : ''}' : '${r.issues.length} problem(s). Nothing was imported.', key: const ValueKey('csv-summary'), style: TextStyle(fontWeight: FontWeight.w700, color: r.ok ? Colors.green.shade700 : Theme.of(context).colorScheme.error)),
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
