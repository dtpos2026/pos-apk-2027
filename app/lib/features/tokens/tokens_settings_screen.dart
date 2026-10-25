import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/queries.dart' show loadCategories, loadProducts;
import '../../domain/money.dart';
import '../../domain/receipt.dart';
import '../../domain/receipt_template.dart';
import '../../domain/token.dart';
import '../../data/receipt_settings.dart';
import '../common/dialogs.dart';
import '../settings/receipt_paper.dart';
import '../settings/settings_screen.dart' show printersProvider;
import 'token_designer_screen.dart';
import 'token_ui.dart';

/// Token types, designs and options. Everything the owner can change about food tokens lives here.
class TokensSettingsScreen extends ConsumerWidget {
  const TokensSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: DtAppBar(
          title: Text(t['tokens_title']),
          bottom: TabBar(labelColor: Theme.of(context).appBarTheme.foregroundColor, unselectedLabelColor: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.7), indicatorColor: Theme.of(context).appBarTheme.foregroundColor, tabs: [Tab(key: const ValueKey('tab-types'), text: t['token_types']), Tab(key: const ValueKey('tab-designs'), text: t['token_designs']), Tab(key: const ValueKey('tab-options'), text: t['token_options'])]),
        ),
        body: const TabBarView(children: [_TypesTab(), _DesignsTab(), _OptionsTab()]),
      ),
    );
  }
}

Future<void> _saveConfig(WidgetRef ref, TokenConfig c) async {
  await ref.read(tokenServiceProvider).saveConfig(c);
  ref.invalidate(tokenConfigProvider);
}

// ---------------------------------------------------------------------------------------------------------------------

class _TypesTab extends ConsumerWidget {
  const _TypesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cfg = ref.watch(tokenConfigProvider).value ?? TokenConfig.none;
    final designs = ref.watch(tokenDesignsProvider).value ?? const <TokenDesign>[];
    String designName(TokenRule r) => designs.where((d) => d.id == r.template).firstOrNull?.name ?? r.template;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(t['tokens_intro'], style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 10),
      if (cfg.rules.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(t['tokens_none_set'], textAlign: TextAlign.center))),
      for (final r in cfg.rules)
        Card(
          child: ListTile(
            key: ValueKey('rule-${r.name}'),
            leading: Icon(kindIcon(r.kind), color: Theme.of(context).colorScheme.primary),
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${kindName(t, r.kind)} · ${r.format(r.startAt)} · ${designName(r)}${r.station.isEmpty ? '' : ' · ${r.station}'}'),
            trailing: Switch(
              key: ValueKey('rule-on-${r.name}'),
              value: r.enabled,
              onChanged: (v) => _saveConfig(ref, cfg.copyWith(rules: [for (final x in cfg.rules) x.id == r.id ? x.copyWith(enabled: v) : x])),
            ),
            onTap: () => _editRule(context, ref, cfg, r),
          ),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(key: const ValueKey('add-token-type'), onPressed: () => _addRule(context, ref, cfg), icon: const Icon(Icons.add), label: Text(t['add_token_type'])),
      ),
    ]);
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref, TokenConfig cfg) async {
    final t = Strings.of(context);
    final kind = await showModalBottomSheet<TokenKind>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final k in TokenKind.values)
            ListTile(key: ValueKey('kind-${k.name}'), leading: Icon(kindIcon(k)), title: Text(kindName(t, k)), subtitle: Text(kindHelp(t, k)), onTap: () => Navigator.pop(ctx, k)),
        ]),
      ),
    );
    if (kind == null) return;
    var r = newRule(kind, const Uuid().v4(), t);
    // names must be unique so the owner can tell them apart
    var n = 1;
    final base = r.name;
    while (cfg.rules.any((x) => x.name == r.name)) {
      n++;
      r = r.copyWith(name: '$base $n');
    }
    await _saveConfig(ref, cfg.copyWith(rules: [...cfg.rules, r]));
    await ref.read(modulesProvider.notifier).toggle('tokens', true); // a token type that is saved but silently off would be a trap
    if (context.mounted) _editRule(context, ref, cfg.copyWith(rules: [...cfg.rules, r]), r);
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, TokenConfig cfg, TokenRule rule) async {
    await showDialog<void>(context: context, builder: (_) => _RuleDialog(rule: rule));
  }
}

class _RuleDialog extends ConsumerStatefulWidget {
  const _RuleDialog({required this.rule});
  final TokenRule rule;
  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  late TokenRule r = widget.rule;
  late final name = TextEditingController(text: r.name);
  late final prefix = TextEditingController(text: r.prefix);
  late final start = TextEditingController(text: '${r.startAt}');
  late final station = TextEditingController(text: r.station);
  late final collect = TextEditingController(text: r.collectText);

  @override
  void dispose() {
    for (final c in [name, prefix, start, station, collect]) {
      c.dispose();
    }
    super.dispose();
  }

  TokenRule get _current => r.copyWith(
        name: name.text.trim().isEmpty ? r.name : name.text.trim(),
        prefix: prefix.text,
        startAt: int.tryParse(start.text) ?? r.startAt,
        station: station.text,
        collectText: collect.text,
      );

  Future<void> _save({bool remove = false}) async {
    final cfg = ref.read(tokenConfigProvider).value ?? TokenConfig.none;
    final rules = remove ? [for (final x in cfg.rules) if (x.id != r.id) x] : [for (final x in cfg.rules) x.id == r.id ? _current : x];
    await _saveConfig(ref, cfg.copyWith(rules: rules));
    if (mounted) Navigator.pop(context);
  }

  Future<List<String>?> _pickMany(String title, List<(String, String)> options, List<String> chosen) {
    final t = Strings.of(context);
    final sel = {...chosen};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              for (final o in options)
                CheckboxListTile(key: ValueKey('pick-${o.$2}'), dense: true, value: sel.contains(o.$1), title: Text(o.$2), onChanged: (v) => set(() => v == true ? sel.add(o.$1) : sel.remove(o.$1))),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, <String>[]), child: Text(t['clear'])), FilledButton(key: const ValueKey('pick-done'), onPressed: () => Navigator.pop(ctx, sel.toList()), child: Text(t['ok']))],
        ),
      ),
    );
  }

  Future<void> _pickCategories() async {
    final cats = await loadCategories(ref.read(databaseProvider));
    if (!mounted) return;
    final v = await _pickMany(Strings.of(context)['pick_categories'], [for (final c in cats) (c.id, c.name)], r.categoryIds);
    if (v != null) setState(() => r = r.copyWith(categoryIds: v));
  }

  Future<void> _pickItems() async {
    final items = await loadProducts(ref.read(databaseProvider));
    if (!mounted) return;
    final v = await _pickMany(Strings.of(context)['pick_items'], [for (final p in items) (p.id, p.name)], r.productIds);
    if (v != null) setState(() => r = r.copyWith(productIds: v));
  }

  Future<void> _test() async {
    final t = Strings.of(context);
    final cur = ref.read(businessProvider).value?.currency ?? Currency.pkr;
    final biz = ref.read(businessProvider).value?.name ?? '';
    final rule = _current;
    final svc = ref.read(tokenServiceProvider);
    final design = await svc.template(rule.template);
    final print = ref.read(printServiceProvider);
    // same printer choice as a real token: the one on the rule, else the counter's printer, else a bill printer
    final jobs = await print.queueTestSlip(
        design, (_) => sampleSlip(rule.kind, businessName: biz, currency: cur, lang: design.lang, counter: rule.name, collectText: rule.collectText).copyWithLabel(rule.format(rule.startAt)),
        printerId: rule.printerId, copies: rule.copies);
    if (jobs.isNotEmpty) print.processQueue();
    if (mounted) showMessage(context, jobs.isEmpty ? t['no_printer'] : t['print_queued']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final designs = ref.watch(tokenDesignsProvider).value ?? const <TokenDesign>[];
    final printers = ref.watch(printersProvider).value ?? const [];
    final example = _current;
    final needsCounter = r.kind.needsStation;
    return AlertDialog(
      title: Row(children: [Icon(kindIcon(r.kind)), const SizedBox(width: 8), Expanded(child: Text(kindName(t, r.kind), style: const TextStyle(fontSize: 18)))]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(kindHelp(t, r.kind), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(key: const ValueKey('rule-name'), controller: name, decoration: InputDecoration(labelText: t['rule_name']), onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(key: const ValueKey('rule-prefix'), controller: prefix, textCapitalization: TextCapitalization.characters, inputFormatters: [LengthLimitingTextInputFormatter(3)], decoration: InputDecoration(labelText: t['rule_prefix']), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(child: TextField(key: const ValueKey('rule-start'), controller: start, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: t['rule_start']), onChanged: (_) => setState(() {}))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text(t['rule_pad']),
              const Spacer(),
              SegmentedButton<int>(
                key: const ValueKey('rule-pad'),
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 0, label: Text('1')), ButtonSegment(value: 2, label: Text('01')), ButtonSegment(value: 3, label: Text('001')), ButtonSegment(value: 4, label: Text('0001'))],
                selected: {const [0, 2, 3, 4].contains(r.pad) ? r.pad : 0},
                onSelectionChanged: (s) => setState(() => r = r.copyWith(pad: s.first)),
              ),
            ]),
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t['rule_example']}: ${example.format(example.startAt)}, ${example.format(example.startAt + 1)}…', key: const ValueKey('rule-example'), style: const TextStyle(fontWeight: FontWeight.w700))),
            SwitchListTile(key: const ValueKey('rule-daily'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['rule_daily']), value: r.dailyReset, onChanged: (v) => setState(() => r = r.copyWith(dailyReset: v))),
            TextField(key: const ValueKey('rule-station'), controller: station, decoration: InputDecoration(labelText: needsCounter ? t['counter_station'] : '${t['counter_station']} (${t['optional']})', helperText: t['rule_station_hint'], helperMaxLines: 3), onChanged: (_) => setState(() {})),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(key: const ValueKey('rule-pick-categories'), onPressed: _pickCategories, icon: const Icon(Icons.category_outlined, size: 18), label: Text('${t['pick_categories']}${r.categoryIds.isEmpty ? '' : ' (${r.categoryIds.length})'}', overflow: TextOverflow.ellipsis))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(key: const ValueKey('rule-pick-items'), onPressed: _pickItems, icon: const Icon(Icons.fastfood_outlined, size: 18), label: Text('${t['pick_items']}${r.productIds.isEmpty ? '' : ' (${r.productIds.length})'}', overflow: TextOverflow.ellipsis))),
            ]),
            const SizedBox(height: 8),
            Text(t['stubs_title'], style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              key: const ValueKey('rule-stubs'),
              showSelectedIcon: false,
              segments: [ButtonSegment(value: 'none', label: Text(t['stubs_none'])), ButtonSegment(value: 'department', label: Text(t['stubs_department'])), ButtonSegment(value: 'item', label: Text(t['stubs_item'])), ButtonSegment(value: 'piece', label: Text(t['stubs_piece']))],
              selected: {r.stubs},
              onSelectionChanged: (v) => setState(() => r = r.copyWith(stubs: v.first)),
            ),
            if (r.kind == TokenKind.product) ...[
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const ValueKey('rule-split'),
                showSelectedIcon: false,
                segments: [ButtonSegment(value: 'group', label: Text(t['split_group'])), ButtonSegment(value: 'line', label: Text(t['split_line']))],
                selected: {r.split},
                onSelectionChanged: (s) => setState(() => r = r.copyWith(split: s.first)),
              ),
            ],
            if (r.kind == TokenKind.stall || r.kind == TokenKind.tandoor) ...[
              const SizedBox(height: 10),
              TextField(key: const ValueKey('rule-collect'), controller: collect, decoration: InputDecoration(labelText: t['rule_collect'])),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('rule-design'),
              initialValue: designs.any((d) => d.id == r.template) ? r.template : null,
              decoration: InputDecoration(labelText: t['rule_design']),
              items: [for (final d in designs) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => r = r.copyWith(templateId: v == r.kind.defaultTemplate ? '' : v)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('rule-printer'),
              initialValue: printers.any((p) => p['id'] == r.printerId) ? r.printerId : '',
              decoration: InputDecoration(labelText: t['rule_printer']),
              items: [
                DropdownMenuItem(value: '', child: Text(t['printer_auto'], overflow: TextOverflow.ellipsis)),
                for (final p in printers) DropdownMenuItem(value: p['id'] as String, child: Text('${p['name']} · ${p['paper_mm']} mm${p['station'] == null ? '' : ' · ${p['station']}'}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => r = v == null || v.isEmpty ? r.copyWith(clearPrinter: true) : r.copyWith(printerId: v)),
            ),
            Row(children: [
              Text(t['copies']),
              const Spacer(),
              IconButton(key: const ValueKey('rule-copies-dec'), onPressed: r.copies > 1 ? () => setState(() => r = r.copyWith(copies: r.copies - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('${r.copies}', key: const ValueKey('rule-copies'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(key: const ValueKey('rule-copies-inc'), onPressed: r.copies < 5 ? () => setState(() => r = r.copyWith(copies: r.copies + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            SwitchListTile(key: const ValueKey('rule-auto'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['rule_auto']), subtitle: Text(t['rule_auto_hint']), value: r.auto, onChanged: (v) => setState(() => r = r.copyWith(auto: v))),
            Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(key: const ValueKey('rule-test'), onPressed: _test, icon: const Icon(Icons.print_outlined), label: Text(t['print_test']))),
          ]),
        ),
      ),
      actions: [DialogActions([
        TextButton(key: const ValueKey('rule-delete'), onPressed: () => _confirmDelete(), child: Text(t['delete'], style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t['cancel'])),
        FilledButton(key: const ValueKey('rule-save'), onPressed: _save, child: Text(t['save'])),
      ])],
    );
  }

  Future<void> _confirmDelete() async {
    final t = Strings.of(context);
    final ok = await confirmDialog(context, t['rule_delete_confirm'], okLabel: t['delete']);
    if (ok == true) await _save(remove: true);
  }
}

extension on TokenSlip {
  TokenSlip copyWithLabel(String label) => TokenSlip(
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
      isReprint: isReprint);
}

// ---------------------------------------------------------------------------------------------------------------------

class _DesignsTab extends ConsumerWidget {
  const _DesignsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final designs = ref.watch(tokenDesignsProvider).value ?? const <TokenDesign>[];
    final cfg = ref.watch(tokenConfigProvider).value ?? TokenConfig.none;
    final svc = ref.read(tokenServiceProvider);
    void refresh() => ref.invalidate(tokenDesignsProvider);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(t['designs_intro'], style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 10),
      for (final d in designs)
        Card(
          child: ListTile(
            key: ValueKey('design-${d.id}'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              d.builtIn ? t['design_builtin'] : t['design_own'],
              {'en': 'English', 'ur': 'اردو', 'both': 'English + اردو'}[d.lang]!,
              () {
                final used = cfg.rules.where((r) => r.template == d.id).map((r) => r.name).toList();
                return used.isEmpty ? '' : '${t['design_used_by']}: ${used.join(', ')}';
              }(),
            ].where((s) => s.isNotEmpty).join(' · ')),
            trailing: PopupMenuButton<String>(
              key: ValueKey('design-menu-${d.id}'),
              onSelected: (a) async {
                switch (a) {
                  case 'edit':
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TokenDesignerScreen(designId: d.id)));
                    refresh();
                  case 'duplicate':
                    await svc.duplicateTemplate(d, name: '${d.name} ${t['copy_word']}');
                    refresh();
                  case 'export':
                    await Clipboard.setData(ClipboardData(text: svc.exportTemplate(d)));
                    if (context.mounted) showMessage(context, t['design_copied']);
                  case 'reset':
                    await svc.deleteOrResetTemplate(d.id);
                    refresh();
                    ref.invalidate(tokenConfigProvider);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t['edit'])),
                PopupMenuItem(value: 'duplicate', child: Text(t['duplicate'])),
                PopupMenuItem(value: 'export', child: Text(t['design_export'])),
                if (d.builtIn) PopupMenuItem(value: 'reset', child: Text(t['design_reset'])) else PopupMenuItem(value: 'reset', child: Text(t['delete'])),
              ],
            ),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TokenDesignerScreen(designId: d.id)));
              refresh();
            },
          ),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          key: const ValueKey('design-new'),
          onPressed: () async {
            final copy = await svc.duplicateTemplate(builtInTemplates['classic']!, name: t['design_new_name']);
            refresh();
            if (context.mounted) {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TokenDesignerScreen(designId: copy.id)));
              refresh();
            }
          },
          icon: const Icon(Icons.add),
          label: Text(t['design_new']),
        ),
        OutlinedButton.icon(key: const ValueKey('design-import'), onPressed: () => _import(context, ref), icon: const Icon(Icons.file_download_outlined), label: Text(t['design_import'])),
      ]),
    ]);
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(scrollable: true, 
        title: Text(t['design_import']),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t['design_import_hint']),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('design-import-field'), controller: ctl, minLines: 4, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder())),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final c = await Clipboard.getData(Clipboard.kTextPlain);
                  if (c?.text != null) ctl.text = c!.text!;
                },
                icon: const Icon(Icons.paste, size: 18),
                label: Text(t['paste']),
              ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])), FilledButton(key: const ValueKey('design-import-go'), onPressed: () => Navigator.pop(ctx, true), child: Text(t['design_import']))],
      ),
    );
    if (ok != true) return;
    final imported = await ref.read(tokenServiceProvider).importTemplate(ctl.text);
    ref.invalidate(tokenDesignsProvider);
    if (context.mounted) showMessage(context, imported == null ? t['design_import_failed'] : '${t['design_imported']}: ${imported.name}');
  }
}

// ---------------------------------------------------------------------------------------------------------------------

class _OptionsTab extends ConsumerWidget {
  const _OptionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cfg = ref.watch(tokenConfigProvider).value ?? TokenConfig.none;
    final kot = ref.watch(kotDesignProvider).value ?? KotDesign.defaults;
    final store = ref.read(receiptTemplateStoreProvider);
    Future<void> saveKot(KotDesign d) async {
      await store.saveKot(d);
      ref.invalidate(kotDesignProvider);
    }

    final cur = ref.watch(businessProvider).value?.currency ?? Currency.pkr;
    final doc = buildKotDoc(
      station: 'Grill',
      orderLabel: 'INV-20260112-0001',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'T4',
      dateTime: '2026-01-12 19:40',
      waiter: 'Ali',
      token: 'A17',
      lines: const [KotLine('Zinger Burger', 2000, modifiers: ['Extra cheese'], note: 'No onion'), KotLine('Fries', 1000)],
      design: kot,
    );
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(t['options_sale'], style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      SwitchListTile(key: const ValueKey('opt-print-bill'), contentPadding: EdgeInsets.zero, title: Text(t['opt_print_bill']), subtitle: Text(t['opt_print_bill_hint']), value: cfg.printBill, onChanged: (v) => _saveConfig(ref, cfg.copyWith(printBill: v))),
      SwitchListTile(key: const ValueKey('opt-manager-reprint'), contentPadding: EdgeInsets.zero, title: Text(t['opt_manager_reprint']), subtitle: Text(t['opt_manager_reprint_hint']), value: cfg.managerReprintOnly, onChanged: (v) => _saveConfig(ref, cfg.copyWith(managerReprintOnly: v))),
      const Divider(height: 28),
      Text(t['kot_design'], style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        key: const ValueKey('kot-style'),
        showSelectedIcon: false,
        segments: [for (final s in kotStyles) ButtonSegment(value: s, label: Text(t['kot_style_$s']))],
        selected: {kot.style},
        onSelectionChanged: (s) => saveKot(kot.copyWith(style: s.first)),
      ),
      const SizedBox(height: 8),
      TextFormField(key: const ValueKey('kot-title'), initialValue: kot.title, decoration: InputDecoration(labelText: t['kot_title']), onChanged: (v) => saveKot(kot.copyWith(title: v.trim().isEmpty ? 'KOT' : v.trim()))),
      SwitchListTile(key: const ValueKey('kot-token'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['show_token']), value: kot.showToken, onChanged: (v) => saveKot(kot.copyWith(showToken: v))),
      SwitchListTile(key: const ValueKey('kot-table'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['show_table']), value: kot.showTable, onChanged: (v) => saveKot(kot.copyWith(showTable: v))),
      SwitchListTile(key: const ValueKey('kot-waiter'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['show_waiter']), value: kot.showWaiter, onChanged: (v) => saveKot(kot.copyWith(showWaiter: v))),
      SwitchListTile(key: const ValueKey('kot-notes'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['show_notes']), value: kot.showNotes, onChanged: (v) => saveKot(kot.copyWith(showNotes: v))),
      Row(children: [
        Text(t['copies']),
        const Spacer(),
        IconButton(onPressed: kot.copies > 1 ? () => saveKot(kot.copyWith(copies: kot.copies - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
        Text('${kot.copies}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        IconButton(onPressed: kot.copies < 3 ? () => saveKot(kot.copyWith(copies: kot.copies + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
      ]),
      const SizedBox(height: 10),
      Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: ReceiptPaper(doc: doc, paperMm: 58)),
      ),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t['preview_note']} (${cur.code})', style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}
