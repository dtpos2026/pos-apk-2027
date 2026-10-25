import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/deal_import.dart';
import '../../data/deal_service.dart';
import '../../data/menu_service.dart';
import '../../domain/money.dart';
import '../../domain/xlsx.dart';
import '../common/dialogs.dart';

final dealsProvider = FutureProvider.autoDispose<List<DealInfo>>((ref) => ref.watch(dealServiceProvider).deals());

/// All deals (combos): list, make a new one, edit, import many from a sheet.
class DealsScreen extends ConsumerWidget {
  const DealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final deals = ref.watch(dealsProvider);
    Future<void> open([DealInfo? d]) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DealEditor(deal: d)));
      ref.invalidate(dealsProvider);
      ref.invalidate(productsProvider);
    }

    return Scaffold(
      appBar: DtAppBar(title: Text(t['deals']), actions: [
        IconButton(
          key: const ValueKey('deal-import'),
          tooltip: t['deal_import'],
          icon: const Icon(Icons.upload_file),
          onPressed: () async {
            await showDialog<void>(context: context, builder: (_) => const _DealImportDialog());
            ref.invalidate(dealsProvider);
            ref.invalidate(productsProvider);
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-deal'), onPressed: () => open(), icon: const Icon(Icons.add), label: Text(t['add_deal'])),
      body: deals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(t['deals_none'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final d = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      key: ValueKey('deal-${d.name}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => open(d),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(d.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: context.priceColor, borderRadius: BorderRadius.circular(8)),
                              child: Text(ref.money(d.priceMinor), style: TextStyle(fontWeight: FontWeight.w800, color: readableOn(context.priceColor))),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(d.items.map((x) => '${formatQty(x.qtyMilli)} x ${x.label}').join('  ·  '), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Row(children: [
                            if (d.savingMinor > 0) Text('${t['deal_saving']}: ${ref.money(d.savingMinor)}', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w700, fontSize: 12.5)),
                            const Spacer(),
                            Text(d.active ? t['available'] : t['unavailable'], style: TextStyle(fontSize: 12.5, color: d.active ? Colors.green.shade700 : Theme.of(context).colorScheme.outline)),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Line {
  _Line(this.productId, this.name, this.unitPriceMinor, {this.variantId, this.variantName, this.qtyMilli = 1000});
  final String productId;
  final String name;
  final int unitPriceMinor;
  final String? variantId;
  final String? variantName;
  int qtyMilli;
  String get label => variantName == null ? name : '$name ($variantName)';
}

/// Make or change one deal.
class DealEditor extends ConsumerStatefulWidget {
  const DealEditor({super.key, this.deal});
  final DealInfo? deal;
  @override
  ConsumerState<DealEditor> createState() => _DealEditorState();
}

class _DealEditorState extends ConsumerState<DealEditor> {
  late final _name = TextEditingController(text: widget.deal?.name);
  late final _price = TextEditingController(text: widget.deal == null ? '' : formatMinor(widget.deal!.priceMinor, currency: ref.currency, symbol: false).replaceAll(',', ''));
  late bool _active = widget.deal?.active ?? true;
  late final List<_Line> _lines = [
    for (final i in widget.deal?.items ?? const <DealComponent>[]) _Line(i.productId, i.productName, i.unitPriceMinor, variantId: i.variantId, variantName: i.variantName, qtyMilli: i.qtyMilli),
  ];
  String? _error;
  bool _busy = false;

  int get _regular => _lines.fold(0, (s, l) => s + l.unitPriceMinor * l.qtyMilli ~/ 1000);

  Future<void> _addItem() async {
    final t = Strings.of(context);
    final svc = ref.read(dealServiceProvider);
    final picked = await showModalBottomSheet<DealItemOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ItemPicker(svc),
    );
    if (picked == null || !mounted) return;
    ({String id, String name, int priceMinor})? size;
    if (picked.sizes.isNotEmpty) {
      size = await showDialog<({String id, String name, int priceMinor})>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(t['deal_choose_size']),
          children: [for (final s in picked.sizes) SimpleDialogOption(key: ValueKey('deal-size-${s.name}'), onPressed: () => Navigator.pop(ctx, s), child: Text('${s.name}   ${ref.money(s.priceMinor)}'))],
        ),
      );
      if (size == null) return;
    }
    setState(() {
      final at = _lines.indexWhere((l) => l.productId == picked.id && l.variantId == size?.id);
      if (at >= 0) {
        _lines[at].qtyMilli += 1000;
      } else {
        _lines.add(_Line(picked.id, picked.name, size?.priceMinor ?? picked.priceMinor, variantId: size?.id, variantName: size?.name));
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final t = Strings.of(context);
    final price = parseMinor(_price.text.replaceAll(',', ''), currency: ref.currency);
    if (price == null) {
      setState(() => _error = t['bad_amount']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(dealServiceProvider).save(
            id: widget.deal?.id,
            name: _name.text,
            priceMinor: price,
            active: _active,
            items: [for (final l in _lines) DealPick(productId: l.productId, variantId: l.variantId, qtyMilli: l.qtyMilli)],
            staffId: ref.read(sessionProvider)!.staffId,
          );
      if (!mounted) return;
      showMessage(context, t['deal_saved']);
      Navigator.pop(context);
    } on MenuException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _delete() async {
    final t = Strings.of(context);
    if (!await confirmDialog(context, t['deal_delete_ask'])) return;
    await ref.read(dealServiceProvider).delete(widget.deal!.id, staffId: ref.read(sessionProvider)!.staffId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final price = parseMinor(_price.text.replaceAll(',', ''), currency: ref.currency) ?? 0;
    final saving = _regular - price;
    return Scaffold(
      appBar: DtAppBar(title: Text(widget.deal == null ? t['add_deal'] : t['edit_deal']), actions: [
        if (widget.deal != null) IconButton(key: const ValueKey('deal-delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(key: const ValueKey('deal-name'), controller: _name, decoration: InputDecoration(labelText: t['deal_name']), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('deal-price'), controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t['deal_price']), onChanged: (_) => setState(() {})),
        SwitchListTile(key: const ValueKey('deal-active'), contentPadding: EdgeInsets.zero, title: Text(t['deal_active']), value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(t['deal_items'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          OutlinedButton.icon(key: const ValueKey('deal-add-item'), onPressed: _addItem, icon: const Icon(Icons.add), label: Text(t['deal_add_item'])),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < _lines.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(children: [
                Expanded(child: Text(_lines[i].label, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(
                  key: ValueKey('deal-minus-$i'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    if (_lines[i].qtyMilli > 1000) {
                      _lines[i].qtyMilli -= 1000;
                    } else {
                      _lines.removeAt(i);
                    }
                  }),
                  icon: Icon(_lines[i].qtyMilli > 1000 ? Icons.remove_circle_outline : Icons.delete_outline),
                ),
                SizedBox(width: 30, child: Text(formatQty(_lines[i].qtyMilli), key: ValueKey('deal-qty-$i'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton(key: ValueKey('deal-plus-$i'), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _lines[i].qtyMilli += 1000), icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
          ),
        if (_lines.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Row(children: [Text(t['deal_regular']), const Spacer(), Text(ref.money(_regular), key: const ValueKey('deal-regular'))]),
              const SizedBox(height: 4),
              Row(children: [Text(t['deal_price']), const Spacer(), Text(ref.money(price), style: const TextStyle(fontWeight: FontWeight.w800))]),
              if (saving > 0) ...[const SizedBox(height: 4), Row(children: [Text(t['deal_saving']), const Spacer(), Text(ref.money(saving), key: const ValueKey('deal-saving'), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700))])],
            ]),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const ValueKey('deal-error'), style: TextStyle(color: cs.error, fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        FilledButton(key: const ValueKey('deal-save'), onPressed: _busy ? null : _save, child: Text(t['save'])),
      ]),
    );
  }
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker(this.svc);
  final DealService svc;
  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(children: [
        ListTile(title: Text(t['deal_add_item'], style: const TextStyle(fontWeight: FontWeight.w800))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(key: const ValueKey('deal-search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search_items'], isDense: true), onChanged: (v) => setState(() => _q = v))),
        Expanded(
          child: FutureBuilder<List<DealItemOption>>(
            future: widget.svc.options(_q),
            builder: (context, snap) {
              final list = snap.data ?? const [];
              return ListView(children: [
                for (final o in list) ListTile(key: ValueKey('deal-pick-${o.name}'), title: Text(o.name), subtitle: Text([if (o.categoryName != null) o.categoryName!, if (o.sizes.isNotEmpty) o.sizes.map((s) => s.name).join(' / ')].join('  ·  ')), onTap: () => Navigator.pop(context, o)),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _DealImportDialog extends ConsumerStatefulWidget {
  const _DealImportDialog();
  @override
  ConsumerState<_DealImportDialog> createState() => _DealImportDialogState();
}

class _DealImportDialogState extends ConsumerState<_DealImportDialog> {
  final _text = TextEditingController();
  bool _update = false;
  DealImportReport? _report;

  Future<void> _pick() async {
    final f = await ref.read(importFilePickerProvider).pick();
    if (f == null) return;
    final text = f.name.toLowerCase().endsWith('.xlsx') ? xlsxToCsv(f.bytes) : utf8.decode(f.bytes, allowMalformed: true);
    setState(() {
      _text.text = text ?? '';
      _report = null;
    });
    if (text == null && mounted) showMessage(context, Strings.of(context)['file_unreadable']);
  }

  Future<void> _run(bool dry) async {
    final r = await ref.read(dealImporterProvider).import(_text.text, dryRun: dry, update: _update, staffId: ref.read(sessionProvider)!.staffId);
    setState(() => _report = r);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final r = _report;
    final issues = r?.allIssues ?? const [];
    return AlertDialog(
      title: Text(t['deal_import']),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t['deal_import_hint'], style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('deal-csv-text'), controller: _text, minLines: 6, maxLines: 10, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12), decoration: InputDecoration(hintText: t['paste_csv_here'])),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            TextButton.icon(key: const ValueKey('deal-csv-template'), onPressed: () => setState(() => _text.text = dealCsvTemplate()), icon: const Icon(Icons.description_outlined), label: Text(t['template'])),
            TextButton.icon(key: const ValueKey('deal-csv-file'), onPressed: _pick, icon: const Icon(Icons.folder_open), label: Text(t['choose_file'])),
          ]),
          SwitchListTile(key: const ValueKey('deal-update-existing'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['deal_update_existing']), value: _update, onChanged: (v) => setState(() {
                _update = v;
                _report = null;
              })),
          if (r != null) ...[
            const Divider(),
            Text('${r.created} ${t['deals_new']}, ${r.updated} ${t['deals_updated']}, ${r.skipped} ${t['deals_skipped']}, ${r.invalid} ${t['deals_invalid']}${r.committed ? '  ✓' : ''}', key: const ValueKey('deal-csv-summary'), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final i in issues.take(14)) Text('• $i', style: const TextStyle(fontSize: 12.5)),
            if (issues.length > 14) Text('… +${issues.length - 14}', style: const TextStyle(fontSize: 12.5)),
          ],
        ]),
      ),
      actions: [
        DialogActions([
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel'])),
          OutlinedButton(key: const ValueKey('deal-csv-check'), onPressed: () => _run(true), child: Text(t['check'])),
          FilledButton(key: const ValueKey('deal-csv-import'), onPressed: () => _run(false), child: Text(t['import_now'])),
        ]),
      ],
    );
  }
}
