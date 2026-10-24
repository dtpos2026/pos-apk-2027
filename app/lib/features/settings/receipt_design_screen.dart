import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/receipt_settings.dart';
import '../../domain/bill_labels.dart';
import '../../domain/escpos.dart';
import '../../domain/logo.dart';
import '../../domain/money.dart';
import '../../domain/receipt.dart';
import '../../domain/receipt_doc.dart';
import '../../domain/receipt_template.dart';
import 'receipt_paper.dart';

/// Sample bill used for the preview and the test print. It is clearly a sample: nothing here is a real sale.
ReceiptData sampleReceipt({
  required String name,
  String? address,
  String? phone,
  String? taxLabel,
  String? taxNumber,
  RasterImage? logo,
  required Currency currency,
  bool withUrduItem = false,
}) =>
    ReceiptData(
      businessName: name.isEmpty ? 'DT Food POS' : name,
      address: address,
      phone: phone,
      taxLabel: taxLabel,
      taxNumber: taxNumber,
      invoiceNo: 'INV-20260112-0001',
      token: 'A17',
      dateTime: '2026-01-12 19:40',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'T4',
      cashier: 'Ali',
      lines: [
        const ReceiptLine(name: 'Zinger Burger', qtyMilli: 2000, unitPriceMinor: 45000, totalMinor: 90000),
        if (withUrduItem) const ReceiptLine(name: 'چکن کڑاہی', qtyMilli: 1000, unitPriceMinor: 120000, totalMinor: 120000),
        const ReceiptLine(name: 'Fries', qtyMilli: 1000, unitPriceMinor: 15000, totalMinor: 15000),
        const ReceiptLine(name: 'Cola 500ml', qtyMilli: 2000, unitPriceMinor: 10000, totalMinor: 20000),
      ],
      subtotalMinor: withUrduItem ? 245000 : 125000,
      totalMinor: withUrduItem ? 245000 : 125000,
      payments: [ReceiptPayment('Cash', withUrduItem ? 250000 : 150000)],
      changeMinor: 5000 + (withUrduItem ? 0 : 20000),
      currency: currency,
      logo: logo,
    );

class ReceiptDesignScreen extends ConsumerStatefulWidget {
  const ReceiptDesignScreen({super.key});
  @override
  ConsumerState<ReceiptDesignScreen> createState() => _ReceiptDesignScreenState();
}

class _ReceiptDesignScreenState extends ConsumerState<ReceiptDesignScreen> {
  BillDesign _d = BillDesign.defaults;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _taxLabel = TextEditingController();
  final _taxNo = TextEditingController();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _qr = TextEditingController();
  final _title = TextEditingController();
  Uint8List? _logoBytes;
  RasterImage? _logoBitmap;
  String? _logoError;
  int _paper = 58;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _taxLabel, _taxNo, _header, _footer, _qr, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final d = await ref.read(receiptTemplateStoreProvider).load();
    final b = await ref.read(businessProvider.future);
    final bytes = await ref.read(logoStoreProvider).bytes();
    if (!mounted) return;
    setState(() {
      _d = d;
      _name.text = b?.name ?? '';
      _phone.text = b?.phone ?? '';
      _address.text = b?.address ?? '';
      _taxLabel.text = b?.taxLabel ?? 'NTN';
      _taxNo.text = b?.taxNumber ?? '';
      _header.text = d.headerLines.join('\n');
      _footer.text = d.footerLines.map((l) => l == BillDesign.defaultFooter ? BillLabels.of(d.language)['thanks'] : l).join('\n');
      _qr.text = d.qrText ?? '';
      _title.text = d.title;
      _logoBytes = bytes;
      _loaded = true;
    });
    _refreshLogo();
  }

  void _refreshLogo() {
    final bytes = _logoBytes;
    RasterImage? r;
    String? err;
    if (bytes != null) {
      try {
        r = prepareLogo(bytes, paperMm: _paper);
      } on LogoException catch (e) {
        err = e.message;
      }
    }
    setState(() {
      _logoBitmap = r;
      _logoError = err;
    });
  }

  List<String> _lines(String text) => text.split('\n').map((l) => l.trimRight()).where((l) => l.trim().isNotEmpty).toList();

  BillDesign get _design {
    final thanks = BillLabels.supported.map((l) => BillLabels.of(l)['thanks']).toSet();
    final footers = _lines(_footer.text).map((l) => thanks.contains(l) ? BillDesign.defaultFooter : l).toList();
    return _d.copyWith(title: _title.text.trim(), headerLines: _lines(_header.text), footerLines: footers, qrText: _qr.text.trim(), clearQr: _qr.text.trim().isEmpty);
  }

  ReceiptData _sample(Currency c, {RasterImage? logo}) => sampleReceipt(
        name: _name.text,
        address: _address.text,
        phone: _phone.text,
        taxLabel: _taxLabel.text,
        taxNumber: _taxNo.text,
        logo: logo ?? _logoBitmap,
        currency: c,
        withUrduItem: _d.language != 'en' || ref.read(localeProvider).languageCode != 'en',
      );

  Future<void> _pickLogo() async {
    final t = Strings.of(context);
    final bytes = await ref.read(logoPickerProvider).pick();
    if (bytes == null) return;
    try {
      await ref.read(logoStoreProvider).save(bytes);
      _logoBytes = await ref.read(logoStoreProvider).bytes();
      _refreshLogo();
    } on LogoException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['logo_error'])));
    }
  }

  Future<void> _removeLogo() async {
    await ref.read(logoStoreProvider).remove();
    setState(() => _logoBytes = null);
    _refreshLogo();
  }

  Future<void> _save() async {
    final t = Strings.of(context);
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await ref.read(receiptTemplateStoreProvider).save(_design);
    await updateBusinessProfile(ref.read(databaseProvider),
        name: _name.text, phone: _phone.text, address: _address.text, taxLabel: _taxLabel.text, taxNumber: _taxNo.text, now: ref.read(clockProvider)().millisecondsSinceEpoch);
    ref.invalidate(businessProvider);
    ref.invalidate(billDesignProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['saved'])));
  }

  Future<void> _printTest() async {
    final t = Strings.of(context);
    final cur = ref.read(businessProvider).value?.currency ?? Currency.pkr;
    final jobs = await ref.read(printServiceProvider).queueTestBill((paper) {
      RasterImage? logo;
      if (_logoBytes != null) {
        try {
          logo = prepareLogo(_logoBytes!, paperMm: paper);
        } catch (_) {}
      }
      return _sample(cur, logo: logo);
    }, _design);
    if (jobs.isNotEmpty) ref.read(printServiceProvider).processQueue();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jobs.isEmpty ? t['no_printer'] : t['print_queued'])));
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    if (!_loaded) return Scaffold(appBar: AppBar(title: Text(t['receipt_design'])), body: const Center(child: CircularProgressIndicator()));
    final cur = ref.watch(businessProvider).value?.currency ?? Currency.pkr;
    final doc = buildBillDoc(_sample(cur), template: _design);
    final preview = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Center(child: ReceiptPaper(doc: doc, paperMm: _paper)),
        const SizedBox(height: 10),
        Text(t['preview_note'], style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
    final form = _form(t);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(title: Text(t['receipt_design'])),
      body: wide
          ? Row(children: [
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form))),
              SizedBox(width: 460, child: SingleChildScrollView(child: preview)),
            ])
          : SingleChildScrollView(child: Column(children: [preview, Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: form))])),
    );
  }

  Widget _sw(String label, bool v, ValueChanged<bool> on, {String? key}) =>
      SwitchListTile(key: key == null ? null : ValueKey(key), dense: true, contentPadding: EdgeInsets.zero, title: Text(label), value: v, onChanged: (x) => setState(() => on(x)));

  Widget _alignPicker(String key, PrintAlign v, void Function(PrintAlign) set, Strings t) => SegmentedButton<PrintAlign>(
        key: ValueKey(key),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: PrintAlign.left, icon: const Icon(Icons.format_align_left), label: Text(t['left'])),
          ButtonSegment(value: PrintAlign.center, icon: const Icon(Icons.format_align_center), label: Text(t['center'])),
          ButtonSegment(value: PrintAlign.right, icon: const Icon(Icons.format_align_right), label: Text(t['right'])),
        ],
        selected: {v},
        onSelectionChanged: (s) => setState(() => set(s.first)),
      );

  Widget _heading(String s) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(s, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)));

  List<Widget> _form(Strings t) => [
        _heading(t['bill_style']),
        Text(t['bill_style_hint'], style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in billStyles)
            ChoiceChip(
              key: ValueKey('bill-style-$s'),
              label: Text(t['bill_style_$s']),
              selected: _d.style == s,
              onSelected: (_) => setState(() {
                _d = _d.withStyle(s);
                _title.text = _d.title;
              }),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-title'), controller: _title, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['bill_heading'], hintText: 'PRE-PAYMENT BILL / TAX INVOICE')),
        _sw(t['show_token'], _d.showToken, (v) => _d = _d.copyWith(showToken: v), key: 'sw-token'),
        _sw(t['show_item_count'], _d.showItemCount, (v) => _d = _d.copyWith(showItemCount: v), key: 'sw-itemcount'),
        _sw(t['amount_in_words'], _d.amountInWords, (v) => _d = _d.copyWith(amountInWords: v), key: 'sw-words'),
        _heading(t['logo']),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.tonalIcon(key: const ValueKey('choose-logo'), onPressed: _pickLogo, icon: const Icon(Icons.image_outlined), label: Text(t['choose_logo'])),
          if (_logoBytes != null) OutlinedButton.icon(key: const ValueKey('remove-logo'), onPressed: _removeLogo, icon: const Icon(Icons.delete_outline), label: Text(t['remove_logo'])),
          if (_logoBytes != null) SizedBox(width: 180, child: _sw(t['logo'], _d.showLogo, (v) => _d = _d.copyWith(showLogo: v), key: 'sw-logo')),
        ]),
        if (_logoError != null) Text(_logoError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        _heading(t['business_details']),
        TextField(key: const ValueKey('rd-name'), controller: _name, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['business_name'])),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-address'), controller: _address, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['address'])),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-phone'), controller: _phone, onChanged: (_) => setState(() {}), keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t['phone'])),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 150, child: TextField(controller: _taxLabel, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['tax_label']))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _taxNo, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['tax_number']))),
        ]),
        _heading(t['align_logo']),
        _alignPicker('align-logo', _d.logoAt, (a) => _d = _d.copyWith(logoAlign: a), t),
        _heading(t['align_name']),
        _alignPicker('align-name', _d.nameAt, (a) => _d = _d.copyWith(nameAlign: a), t),
        _heading(t['align_details']),
        _alignPicker('align-details', _d.headerAlign, (a) => _d = _d.copyWith(headerAlign: a), t),
        _heading(t['name_size']),
        SegmentedButton<int>(showSelectedIcon: false, segments: const [ButtonSegment(value: 1, label: Text('1x')), ButtonSegment(value: 2, label: Text('2x')), ButtonSegment(value: 3, label: Text('3x'))], selected: {_d.nameSize}, onSelectionChanged: (s) => setState(() => _d = _d.copyWith(nameSize: s.first))),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-header'), controller: _header, onChanged: (_) => setState(() {}), minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: t['header_lines'])),
        _sw(t['show_address'], _d.showAddress, (v) => _d = _d.copyWith(showAddress: v), key: 'sw-address'),
        _sw(t['show_phone'], _d.showPhone, (v) => _d = _d.copyWith(showPhone: v), key: 'sw-phone'),
        _sw(t['show_tax'], _d.showTaxNumber, (v) => _d = _d.copyWith(showTaxNumber: v)),
        _sw(t['show_order_type'], _d.showOrderType, (v) => _d = _d.copyWith(showOrderType: v)),
        _sw(t['show_table'], _d.showTable, (v) => _d = _d.copyWith(showTable: v)),
        _sw(t['show_cashier'], _d.showCashier, (v) => _d = _d.copyWith(showCashier: v)),
        _heading(t['bill_language']),
        SegmentedButton<String>(
          key: const ValueKey('bill-language'),
          showSelectedIcon: false,
          segments: [for (final l in BillLabels.supported) ButtonSegment(value: l, label: Text(Strings.languageNames[l]!))],
          selected: {_d.language},
          onSelectionChanged: (s) {
            final old = BillLabels.of(_d.language)['thanks'];
            setState(() {
              // keep the standard thank-you line in step with the language unless the owner wrote their own
              if (_footer.text.trim() == old) _footer.text = BillLabels.of(s.first)['thanks'];
              _d = _d.copyWith(language: s.first);
            });
          },
        ),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-footer'), controller: _footer, onChanged: (_) => setState(() {}), minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: t['footer_lines'])),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('rd-qr'), controller: _qr, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t['qr_text'])),
        _sw(t['show_powered'], _d.showPoweredBy, (v) => _d = _d.copyWith(showPoweredBy: v), key: 'sw-powered'),
        Row(children: [
          Text(t['copies']),
          const Spacer(),
          IconButton(onPressed: _d.copies > 1 ? () => setState(() => _d = _d.copyWith(copies: _d.copies - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('${_d.copies}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(onPressed: _d.copies < 5 ? () => setState(() => _d = _d.copyWith(copies: _d.copies + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        _heading(t['paper']),
        SegmentedButton<int>(key: const ValueKey('paper'), showSelectedIcon: false, segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))], selected: {_paper}, onSelectionChanged: (s) {
          _paper = s.first;
          _refreshLogo();
        }),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: OutlinedButton.icon(key: const ValueKey('print-test'), onPressed: _printTest, icon: const Icon(Icons.print_outlined), label: Text(t['print_test']))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(key: const ValueKey('rd-save'), onPressed: _busy ? null : _save, child: Text(t['save']))),
        ]),
        const SizedBox(height: 24),
      ];
}
