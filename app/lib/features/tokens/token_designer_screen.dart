import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/escpos.dart';
import '../../domain/logo.dart';
import '../../domain/money.dart';
import '../../domain/receipt_doc.dart';
import '../../domain/token.dart';
import '../common/dialogs.dart';
import '../settings/receipt_paper.dart';
import 'token_ui.dart';

IconData _blockIcon(BlockType b) => switch (b) {
      BlockType.logo => Icons.image_outlined,
      BlockType.business => Icons.store_outlined,
      BlockType.title => Icons.title,
      BlockType.kind => Icons.storefront_outlined,
      BlockType.token => Icons.tag,
      BlockType.collect => Icons.directions_walk,
      BlockType.orderNo => Icons.numbers,
      BlockType.dateTime => Icons.schedule,
      BlockType.orderType => Icons.table_restaurant_outlined,
      BlockType.cashier => Icons.person_outline,
      BlockType.items => Icons.list_alt,
      BlockType.totals => Icons.calculate_outlined,
      BlockType.coupon => Icons.card_giftcard_outlined,
      BlockType.qr => Icons.qr_code_2,
      BlockType.text => Icons.notes,
      BlockType.rule => Icons.horizontal_rule,
      BlockType.space => Icons.space_bar,
      BlockType.powered => Icons.verified_outlined,
    };

/// Which per-block switches each block has, in display order (flag key, label key, default).
const _flagSpecs = <BlockType, List<(String, String, bool)>>{
  BlockType.items: [('qty', 'flag_qty', true), ('price', 'flag_price', false), ('amount', 'flag_amount', false), ('header', 'flag_header', false), ('modifiers', 'flag_modifiers', true), ('bigqty', 'flag_bigqty', false)],
  BlockType.totals: [('subtotal', 'flag_subtotal', false), ('discount', 'flag_discount', false), ('tax', 'flag_tax', false)],
};

/// Visual editor of one token design: reorder blocks by dragging, show/hide them, change alignment, size, bold and wording,
/// pick language, border and margins, and see the real slip as you edit. Test print sends the same document to the printer.
class TokenDesignerScreen extends ConsumerStatefulWidget {
  const TokenDesignerScreen({super.key, required this.designId});
  final String designId;
  @override
  ConsumerState<TokenDesignerScreen> createState() => _TokenDesignerScreenState();
}

class _TokenDesignerScreenState extends ConsumerState<TokenDesignerScreen> {
  TokenDesign? _d;
  bool _dirty = false;
  int _paper = 58;
  TokenKind? _sample;
  int? _open;
  final _name = TextEditingController();
  RasterImage? _logo;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await ref.read(tokenServiceProvider).template(widget.designId);
    final bytes = await ref.read(logoStoreProvider).bytes();
    RasterImage? logo;
    if (bytes != null) {
      try {
        logo = prepareLogo(bytes, paperMm: 58);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _d = d;
      _name.text = d.name;
      _sample = d.sampleKind;
      _logo = logo;
    });
  }

  void _edit(TokenDesign Function(TokenDesign d) f) => setState(() {
        _d = f(_d!);
        _dirty = true;
      });

  void _editBlock(int i, TokenBlock Function(TokenBlock b) f) => _edit((d) => d.copyWith(blocks: [for (var k = 0; k < d.blocks.length; k++) k == i ? f(d.blocks[k]) : d.blocks[k]]));

  Future<void> _save() async {
    final t = Strings.of(context);
    await ref.read(tokenServiceProvider).saveTemplate(_d!.copyWith(name: _name.text.trim().isEmpty ? _d!.name : _name.text.trim()));
    ref.invalidate(tokenDesignsProvider);
    if (!mounted) return;
    setState(() => _dirty = false);
    showMessage(context, t['saved']);
  }

  TokenSlip _slip() {
    final biz = ref.read(businessProvider).value;
    return sampleSlip(_sample ?? TokenKind.order, businessName: biz?.name ?? '', currency: biz?.currency ?? Currency.pkr, logo: _logo, lang: _d!.lang);
  }

  Future<void> _printTest() async {
    final t = Strings.of(context);
    final d = _d!;
    final print = ref.read(printServiceProvider);
    final biz = ref.read(businessProvider).value;
    final bytes = await ref.read(logoStoreProvider).bytes();
    final jobs = await print.queueTestSlip(d, (paper) {
      RasterImage? logo;
      if (bytes != null) {
        try {
          logo = prepareLogo(bytes, paperMm: paper);
        } catch (_) {}
      }
      return sampleSlip(_sample ?? TokenKind.order, businessName: biz?.name ?? '', currency: biz?.currency ?? Currency.pkr, logo: logo, lang: d.lang);
    });
    if (jobs.isNotEmpty) print.processQueue();
    if (mounted) showMessage(context, jobs.isEmpty ? t['no_printer'] : t['print_queued']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final d = _d;
    if (d == null) return Scaffold(appBar: DtAppBar(title: Text(t['token_designs'])), body: const Center(child: CircularProgressIndicator()));
    final doc = buildTokenSlipDoc(d, _slip(), paperMm: _paper);
    final preview = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Center(child: ReceiptPaper(doc: doc, paperMm: _paper)),
        const SizedBox(height: 10),
        Text(t['preview_note'], style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
    final form = _form(t, d);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context, t['unsaved_leave'], okLabel: t['discard']);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: DtAppBar(title: Text(t['design_edit']), actions: [
          IconButton(key: const ValueKey('td-export'), tooltip: t['design_export'], icon: const Icon(Icons.ios_share), onPressed: () async {
            await Clipboard.setData(ClipboardData(text: ref.read(tokenServiceProvider).exportTemplate(d.copyWith(name: _name.text.trim().isEmpty ? d.name : _name.text.trim()))));
            if (context.mounted) showMessage(context, t['design_copied']);
          }),
          if (d.builtIn)
            IconButton(key: const ValueKey('td-reset'), tooltip: t['design_reset'], icon: const Icon(Icons.restore), onPressed: () async {
              if (!await confirmDialog(context, t['design_reset_confirm'], okLabel: t['design_reset'])) return;
              await ref.read(tokenServiceProvider).deleteOrResetTemplate(d.id);
              ref.invalidate(tokenDesignsProvider);
              _dirty = false;
              await _load();
            }),
        ]),
        body: wide
            ? Row(children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form))),
                SizedBox(width: 460, child: SingleChildScrollView(child: preview)),
              ])
            : SingleChildScrollView(child: Column(children: [preview, Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form))])),
      ),
    );
  }

  Widget _title(String s) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(s, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)));

  Widget _stepper(String label, int v, int min, int max, void Function(int) set, String key) => Row(children: [
        Text(label),
        const Spacer(),
        IconButton(key: ValueKey('$key-dec'), onPressed: v > min ? () => set(v - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        Text('$v', key: ValueKey(key), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        IconButton(key: ValueKey('$key-inc'), onPressed: v < max ? () => set(v + 1) : null, icon: const Icon(Icons.add_circle_outline)),
      ]);

  List<Widget> _form(Strings t, TokenDesign d) => [
        TextField(key: const ValueKey('td-name'), controller: _name, decoration: InputDecoration(labelText: t['design_name']), onChanged: (_) => setState(() => _dirty = true)),
        _title(t['design_language']),
        SegmentedButton<String>(
          key: const ValueKey('td-lang'),
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ur', label: Text('اردو')), ButtonSegment(value: 'both', label: Text('English + اردو'))],
          selected: {d.lang},
          onSelectionChanged: (s) => _edit((x) => x.copyWith(lang: s.first)),
        ),
        _title(t['design_border']),
        Wrap(spacing: 8, children: [
          for (final b in TokenDesign.borders)
            ChoiceChip(key: ValueKey('td-border-$b'), label: Text(t['border_$b']), selected: d.border == b, onSelected: (_) => _edit((x) => x.copyWith(border: b))),
        ]),
        const SizedBox(height: 6),
        _stepper(t['margin_top'], d.topFeed, 0, 6, (v) => _edit((x) => x.copyWith(topFeed: v)), 'td-top'),
        _stepper(t['margin_bottom'], d.bottomFeed, 0, 8, (v) => _edit((x) => x.copyWith(bottomFeed: v)), 'td-bottom'),
        _title(t['design_blocks']),
        Text(t['design_blocks_hint'], style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        ReorderableListView(
          key: const ValueKey('td-blocks'),
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          onReorderItem: (a, b) => _edit((x) {
            final list = [...x.blocks];
            final item = list.removeAt(a);
            list.insert(b, item);
            if (_open == a) _open = b;
            return x.copyWith(blocks: list);
          }),
          children: [for (var i = 0; i < d.blocks.length; i++) _blockCard(t, d, i)],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('td-add-block'),
            icon: const Icon(Icons.add),
            label: Text(t['add_block']),
            onPressed: () async {
              final type = await showModalBottomSheet<BlockType>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [for (final b in BlockType.values) ListTile(key: ValueKey('add-${b.name}'), leading: Icon(_blockIcon(b)), title: Text(t['block_${b.name}']), onTap: () => Navigator.pop(ctx, b))])),
              );
              if (type == null) return;
              _edit((x) => x.copyWith(blocks: [...x.blocks, TokenBlock(type, text: type == BlockType.text ? t['block_text_default'] : '', size: type == BlockType.space ? 1 : 1, flags: {for (final f in _flagSpecs[type] ?? const []) f.$1: f.$3})]));
              setState(() => _open = _d!.blocks.length - 1);
            },
          ),
        ),
        _title(t['design_preview']),
        DropdownButtonFormField<TokenKind>(
          key: const ValueKey('td-sample'),
          initialValue: _sample,
          decoration: InputDecoration(labelText: t['design_sample']),
          items: [for (final k in TokenKind.values) DropdownMenuItem(value: k, child: Text(kindName(t, k)))],
          onChanged: (k) => setState(() => _sample = k),
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(key: const ValueKey('td-paper'), showSelectedIcon: false, segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))], selected: {_paper}, onSelectionChanged: (s) => setState(() => _paper = s.first)),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const ValueKey('td-test'), onPressed: _printTest, icon: const Icon(Icons.print_outlined), label: Text(t['print_test']))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(key: const ValueKey('td-save'), onPressed: _save, child: Text(t['save']))),
        ]),
        const SizedBox(height: 24),
      ];

  Widget _blockCard(Strings t, TokenDesign d, int i) {
    final b = d.blocks[i];
    final open = _open == i;
    final cs = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('block-$i-${b.type.name}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: b.show ? null : cs.surfaceContainerHighest,
      child: Column(children: [
        ListTile(
          dense: true,
          leading: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator, key: ValueKey('drag-$i'))),
          title: Row(children: [Icon(_blockIcon(b.type), size: 18, color: b.show ? cs.primary : cs.outline), const SizedBox(width: 8), Expanded(child: Text(t['block_${b.type.name}'], style: TextStyle(fontWeight: FontWeight.w600, color: b.show ? null : cs.outline)))]),
          subtitle: b.type.hasText && b.text.isNotEmpty ? Text(b.text, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(key: ValueKey('block-show-$i'), value: b.show, onChanged: (v) => _editBlock(i, (x) => x.copyWith(show: v))),
            IconButton(key: ValueKey('block-open-$i'), icon: Icon(open ? Icons.expand_less : Icons.tune), onPressed: () => setState(() => _open = open ? null : i)),
          ]),
        ),
        if (open) _blockEditor(t, d, i, b),
      ]),
    );
  }

  Widget _blockEditor(Strings t, TokenDesign d, int i, TokenBlock b) {
    final flags = _flagSpecs[b.type];
    final canAlign = const {BlockType.rule, BlockType.space, BlockType.powered, BlockType.qr}.contains(b.type) == false;
    final sizeable = const {BlockType.rule, BlockType.powered, BlockType.qr, BlockType.logo}.contains(b.type) == false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (b.type.hasText) ...[
          TextFormField(key: ValueKey('block-text-$i'), initialValue: b.text, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: t['block_wording']), onChanged: (v) => _editBlock(i, (x) => x.copyWith(text: v))),
          if (d.lang == 'both') ...[const SizedBox(height: 8), TextFormField(key: ValueKey('block-alt-$i'), initialValue: b.textAlt, decoration: InputDecoration(labelText: t['block_wording_alt']), onChanged: (v) => _editBlock(i, (x) => x.copyWith(textAlt: v)))],
          const SizedBox(height: 8),
        ],
        if (canAlign)
          SegmentedButton<PrintAlign>(
            key: ValueKey('block-align-$i'),
            showSelectedIcon: false,
            segments: [ButtonSegment(value: PrintAlign.left, icon: const Icon(Icons.format_align_left), label: Text(t['left'])), ButtonSegment(value: PrintAlign.center, icon: const Icon(Icons.format_align_center), label: Text(t['center'])), ButtonSegment(value: PrintAlign.right, icon: const Icon(Icons.format_align_right), label: Text(t['right']))],
            selected: {b.align},
            onSelectionChanged: (s) => _editBlock(i, (x) => x.copyWith(align: s.first)),
          ),
        if (sizeable || b.type == BlockType.space) _stepper(b.type == BlockType.space ? t['block_lines'] : t['block_size'], b.size, 1, 5, (v) => _editBlock(i, (x) => x.copyWith(size: v)), 'block-size-$i'),
        if (sizeable && b.type != BlockType.space) SwitchListTile(key: ValueKey('block-bold-$i'), dense: true, contentPadding: EdgeInsets.zero, title: Text(t['block_bold']), value: b.bold, onChanged: (v) => _editBlock(i, (x) => x.copyWith(bold: v))),
        if (flags != null)
          Wrap(spacing: 8, children: [
            for (final f in flags) FilterChip(key: ValueKey('block-flag-$i-${f.$1}'), label: Text(t[f.$2]), selected: b.flag(f.$1, or: f.$3), onSelected: (v) => _editBlock(i, (x) => x.withFlag(f.$1, v))),
          ]),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(key: ValueKey('block-delete-$i'), onPressed: () {
          setState(() => _open = null);
          _edit((x) => x.copyWith(blocks: [for (var k = 0; k < x.blocks.length; k++) if (k != i) x.blocks[k]]));
        }, icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error), label: Text(t['delete'], style: TextStyle(color: Theme.of(context).colorScheme.error)))),
      ]),
    );
  }
}
