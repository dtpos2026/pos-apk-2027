import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../app/providers.dart';
import '../../../app/strings.dart';
import '../../../app/theme.dart';
import '../../../data/queries.dart';
import '../../common/dialogs.dart';
import 'menu_doc.dart';
import 'menu_pdf.dart';
import 'menu_png.dart';
import 'menu_poster.dart';

const _sharedKey = 'menu.shared_fp';
const _templateKey = 'menu.template';
const _coverKey = 'menu.cover';

/// Words on the picture / PDF, in the app language.
MenuLabels menuLabels(Strings t) => MenuLabels(menu: t['menu'], pricesIn: t['mn_prices_in'], orderOnWhatsApp: t['mn_order_wa'], orderHow: t['mn_order_how'], scanToOrder: t['mn_scan'], poweredBy: t['mn_powered'], page: t['mn_page'], tagline: t['mn_tagline']);

/// The message sent with the menu: what it is and how to order.
String menuMessage(Strings t, MenuDoc d) =>
    '*${d.name}*\n${t['mn_msg_intro']}\n\n${t['mn_msg_how']}\n${(d.phone ?? '').isEmpty ? '' : '${t['mn_msg_call']}: ${d.phone}\n'}${(d.address ?? '').isEmpty ? '' : '${d.address}\n'}';

/// Reads the menu, the branding and the theme at this moment, so what is shown and shared is never an old copy.
Future<MenuDoc> currentMenuDoc(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final scheme = Theme.of(context).colorScheme;
  final accent = context.accent.toARGB32();
  final mark = (await rootBundle.load('assets/brand/dt_mark_red.png')).buffer.asUint8List();
  return ref.read(databaseProvider).let((db) => loadMenuDoc(db, brandMark: mark, primary: scheme.primary.toARGB32(), accent: accent, dealsTitle: t['mn_deals'], otherTitle: t['menu'], fromWord: t['mn_from']));
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Preview of the whole menu as pictures, with PNG and PDF to share (WhatsApp), save to the phone, and the ordering QR.
class MenuShareScreen extends ConsumerStatefulWidget {
  const MenuShareScreen({super.key});
  @override
  ConsumerState<MenuShareScreen> createState() => _MenuShareScreenState();
}

class _MenuShareScreenState extends ConsumerState<MenuShareScreen> {
  MenuDoc? _doc;
  List<Uint8List> _pages = const [];
  Uint8List? _pdf;
  final _message = TextEditingController();
  final _pager = PageController();
  int _page = 0;
  String _template = 'classic';
  bool _cover = true;
  bool _busy = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  @override
  void dispose() {
    _message.dispose();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = Strings.of(context);
      final d = await currentMenuDoc(context, ref);
      final db = ref.read(databaseProvider);
      final tid = await getSetting(db, _templateKey);
      if (tid != null && menuTemplateIds.contains(tid)) _template = tid;
      _cover = (await getSetting(db, _coverKey)) != '0';
      final tpl = menuTemplateById(_template);
      final labels = menuLabels(t);
      final pages = tpl == null ? await renderMenuPng(d, labels: labels) : await renderPosterPages(d, tpl, labels: labels, cover: _cover);
      final saved = await getSetting(ref.read(databaseProvider), _sharedKey);
      if (!mounted) return;
      setState(() {
        _doc = d;
        _pages = pages;
        _pdf = null;
        _page = 0;
        _changed = saved != null && saved != d.fingerprint;
        if (_message.text.isEmpty) _message.text = menuMessage(t, d);
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<Uint8List> _pdfBytes() async {
    if (_pdf != null) return _pdf!;
    final labels = menuLabels(Strings.of(context));
    final tpl = menuTemplateById(_template);
    if (tpl != null) {
      // the look's PDF is made of sharper (2x) page pictures, so it prints exactly like the picture
      final sharp = await renderPosterPages(_doc!, tpl, labels: labels, cover: _cover, scale: 2);
      return _pdf = await posterPdf(sharp, '${_doc!.name} - ${labels.menu}');
    }
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic.ttf'));
    return _pdf = await buildMenuPdf(_doc!, labels: labels, script: font);
  }

  Future<void> _pickTemplate(String id) async {
    if (id == _template) return;
    final db = ref.read(databaseProvider);
    await setSetting(db, _templateKey, id, ref.read(clockProvider)().millisecondsSinceEpoch);
    _template = id;
    await _build();
  }

  Future<void> _toggleCover(bool on) async {
    await setSetting(ref.read(databaseProvider), _coverKey, on ? '1' : '0', ref.read(clockProvider)().millisecondsSinceEpoch);
    _cover = on;
    await _build();
  }

  Future<void> _remember() async {
    await setSetting(ref.read(databaseProvider), _sharedKey, _doc!.fingerprint, ref.read(clockProvider)().millisecondsSinceEpoch);
    if (mounted) setState(() => _changed = false);
  }

  Future<List<String>> _writePngs() async {
    final dir = ref.read(exportDirProvider)..createSync(recursive: true);
    for (final f in dir.listSync().whereType<File>().where((f) => RegExp(r'menu-\d+\.png$').hasMatch(f.path))) {
      f.deleteSync(); // old pages of an older menu must never go out with the new ones
    }
    return [
      for (var i = 0; i < _pages.length; i++) (File('${dir.path}/menu-${i + 1}.png')..writeAsBytesSync(_pages[i])).path,
    ];
  }

  Future<String> _writePdf() async {
    final dir = ref.read(exportDirProvider)..createSync(recursive: true);
    return (File('${dir.path}/menu.pdf')..writeAsBytesSync(await _pdfBytes())).path;
  }

  Future<void> _guard(Future<void> Function() f) async {
    final t = Strings.of(context);
    try {
      await f();
    } catch (e) {
      if (mounted) showMessage(context, '${t['save_failed']}: $e');
    }
  }

  Future<void> _sharePng() => _guard(() async {
        final paths = await _writePngs();
        await ref.read(shareServiceProvider).shareFiles(paths, text: _message.text, mimeType: 'image/png', subject: _doc!.name);
        await _remember();
      });

  Future<void> _sharePdf() => _guard(() async {
        final path = await _writePdf();
        await ref.read(shareServiceProvider).shareFiles([path], text: _message.text, mimeType: 'application/pdf', subject: _doc!.name);
        await _remember();
      });

  Future<void> _savePng() => _guard(() async {
        final paths = await _writePngs();
        String? where;
        for (final p in paths) {
          where = await ref.read(phoneFileSaverProvider).save(path: p, name: p.split('/').last, mime: 'image/png', gallery: true);
        }
        if (mounted) showMessage(context, '${Strings.of(context)['saved_to']}: ${where ?? ''}');
      });

  Future<void> _savePdf() => _guard(() async {
        final path = await _writePdf();
        final where = await ref.read(phoneFileSaverProvider).save(path: path, name: 'menu.pdf', mime: 'application/pdf');
        if (mounted) showMessage(context, '${Strings.of(context)['saved_to']}: $where');
      });

  Future<void> _qr() async {
    final t = Strings.of(context);
    final d = _doc!;
    if (d.qrLink == null) {
      if (mounted) showMessage(context, t['qr_need_phone']);
      return;
    }
    if (!mounted) return;
    await showQrCardDialog(context, ref, d, menuLabels(t));
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final d = _doc;
    return Scaffold(
      appBar: DtAppBar(title: Text(t['share_menu']), actions: [IconButton(key: const ValueKey('menu-refresh'), tooltip: t['mn_refresh'], onPressed: _busy ? null : _build, icon: const Icon(Icons.refresh))]),
      body: _busy
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 14), Text(t['mn_generating'])]))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, key: const ValueKey('menu-error'))))
              : d == null || d.itemCount == 0
                  ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(t['mn_empty'], key: const ValueKey('menu-empty'), textAlign: TextAlign.center)))
                  : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_changed)
                        Container(
                          key: const ValueKey('menu-changed'),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [Icon(Icons.update, color: cs.onTertiaryContainer), const SizedBox(width: 8), Expanded(child: Text(t['mn_changed'], style: TextStyle(color: cs.onTertiaryContainer)))]),
                        ),
                      Text(t['mt_title'], style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final id in menuTemplateIds) ChoiceChip(key: ValueKey('menu-template-$id'), label: Text(t['mt_$id']), selected: _template == id, onSelected: (_) => _pickTemplate(id)),
                      ]),
                      if (_template != 'classic') SwitchListTile(key: const ValueKey('menu-cover'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['mt_cover']), value: _cover, onChanged: _toggleCover),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: pngPageWidth / pngPageHeight,
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
                          clipBehavior: Clip.antiAlias,
                          child: PageView.builder(key: const ValueKey('menu-pages'), controller: _pager, itemCount: _pages.length, onPageChanged: (i) => setState(() => _page = i), itemBuilder: (_, i) => Image.memory(_pages[i], key: ValueKey('menu-page-$i'), fit: BoxFit.contain, gaplessPlayback: true)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(onPressed: _page > 0 ? () => _pager.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_left)),
                        Text('${_page + 1} / ${_pages.length}', key: const ValueKey('menu-page-count'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(onPressed: _page < _pages.length - 1 ? () => _pager.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_right)),
                      ]),
                      const SizedBox(height: 4),
                      TextField(key: const ValueKey('menu-message'), controller: _message, minLines: 4, maxLines: 8, decoration: InputDecoration(labelText: t['mn_message'], helperText: t['mn_message_hint'], helperMaxLines: 2, alignLabelWithHint: true)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _action('menu-share-png', Icons.image_outlined, t['mn_share_png'], _sharePng, filled: true),
                        _action('menu-share-pdf', Icons.picture_as_pdf_outlined, t['mn_share_pdf'], _sharePdf, filled: true),
                        _action('menu-save-png', Icons.download_outlined, t['mn_save_png'], _savePng),
                        _action('menu-save-pdf', Icons.save_alt, t['mn_save_pdf'], _savePdf),
                        _action('menu-qr', Icons.qr_code_2, t['qr_title'], _qr),
                      ]),
                      const SizedBox(height: 10),
                      Text(t['mn_print_hint'], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    ])),
    );
  }

  Widget _action(String key, IconData icon, String label, Future<void> Function() onTap, {bool filled = false}) {
    final style = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(150, 48)), shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
    return filled
        ? FilledButton.icon(key: ValueKey(key), style: style, onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label))
        : OutlinedButton.icon(key: ValueKey(key), style: style, onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label));
  }
}

/// The ordering QR poster, with share and save. The owner picks what the customer's WhatsApp message will say ("Hello", "Send me the menu",
/// ...), one QR for each, or all of them on one poster, or a text of their own.
Future<void> showQrCardDialog(BuildContext context, WidgetRef ref, MenuDoc d, MenuLabels labels) => showDialog<void>(context: context, builder: (_) => _QrDialog(d: d, labels: labels));

class _QrDialog extends ConsumerStatefulWidget {
  const _QrDialog({required this.d, required this.labels});
  final MenuDoc d;
  final MenuLabels labels;
  @override
  ConsumerState<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends ConsumerState<_QrDialog> {
  static const presets = ['qr_msg_hello', 'qr_msg_menu', 'qr_msg_takeaway'];
  final _custom = TextEditingController();
  String _pick = 'qr_msg_hello'; // a preset key, 'all' or 'custom'
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  List<String> _messages(Strings t) => switch (_pick) {
        'all' => [for (final k in presets) t[k]],
        'custom' => [_custom.text],
        _ => [t[_pick]],
      };

  Future<void> _render() async {
    final t = Strings.of(context);
    final msgs = _messages(t);
    final b = await renderQrCard(widget.d, labels: widget.labels, messages: msgs);
    if (mounted && b != null) setState(() => _bytes = b);
  }

  Future<String> _write() async {
    final dir = ref.read(exportDirProvider)..createSync(recursive: true);
    return (File('${dir.path}/whatsapp-order-qr.png')..writeAsBytesSync(_bytes!)).path;
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final d = widget.d;
    Widget chip(String key, String label) => ChoiceChip(key: ValueKey('qr-pick-$key'), label: Text(label), selected: _pick == key, onSelected: (_) {
          setState(() => _pick = key);
          _render();
        });
    return AlertDialog(
      title: Text(t['qr_title']),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t['qr_msg_title'], style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (final k in presets) chip(k, t[k]),
              chip('all', t['qr_msg_all']),
              chip('custom', t['qr_msg_custom']),
            ]),
            if (_pick == 'custom')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(key: const ValueKey('qr-custom'), controller: _custom, maxLength: 80, decoration: InputDecoration(labelText: t['qr_msg_custom'], isDense: true), onChanged: (_) => _render()),
              ),
            const SizedBox(height: 8),
            if (_bytes != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_bytes!, key: const ValueKey('wa-qr-card'), fit: BoxFit.contain, gaplessPlayback: true)),
            const SizedBox(height: 8),
            Text(t['qr_hint'], textAlign: TextAlign.center),
          ]),
        ),
      ),
      actions: [
        TextButton(key: const ValueKey('qr-save'), onPressed: _bytes == null ? null : () async {
          final p = await _write();
          final where = await ref.read(phoneFileSaverProvider).save(path: p, name: 'whatsapp-order-qr.png', mime: 'image/png', gallery: true);
          if (context.mounted) showMessage(context, '${t['saved_to']}: $where');
        }, child: Text(t['mn_save_png'])),
        FilledButton(key: const ValueKey('qr-share'), onPressed: _bytes == null ? null : () async {
          final p = await _write();
          await ref.read(shareServiceProvider).shareFiles([p], text: '${d.name}\n${t['mn_qr_msg']}', mimeType: 'image/png', subject: d.name);
        }, child: Text(t['share'])),
      ],
    );
  }
}
