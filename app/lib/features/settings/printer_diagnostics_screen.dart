import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_channel.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/print_service.dart';
import '../../data/queries.dart';
import '../../domain/escpos.dart';
import 'settings_screen.dart' show printersProvider;

/// Plain text and a small test picture, so "paired but nothing prints" can be pinned down step by step.
Uint8List plainTextTest({int paperMm = 58}) {
  final b = EscPosBuilder(paperMm: paperMm)..init();
  b.align(PrintAlign.center).bold(true).line('DT Food POS').bold(false).line('Printer test');
  b.align(PrintAlign.left).divider();
  b.line('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
  b.line('abcdefghijklmnopqrstuvwxyz');
  b.line('0123456789 !@#%&*()-+=');
  b.row('Item', 'Rs 100');
  b.row('Total', 'Rs 100');
  b.divider().feed(3);
  return b.toBytes();
}

/// A bordered picture with stripes: if this prints, the printer understands graphics and the sending speed is fine.
Uint8List graphicsTest({int paperMm = 58, int heightPx = 120}) {
  final widthBytes = paperMm >= 80 ? 72 : 48;
  final bits = Uint8List(widthBytes * heightPx);
  void set(int x, int y) => bits[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
  final w = widthBytes * 8;
  for (var y = 0; y < heightPx; y++) {
    for (var x = 0; x < w; x++) {
      final border = x < 3 || x >= w - 3 || y < 3 || y >= heightPx - 3;
      final stripe = ((x + y) ~/ 8).isEven && y > 20 && y < heightPx - 20 && x > 20 && x < w - 20;
      if (border || stripe) set(x, y);
    }
  }
  final b = EscPosBuilder(paperMm: paperMm)..init();
  b.raster(bits, widthBytes: widthBytes, heightPx: heightPx);
  b.feed(3);
  return b.toBytes();
}

/// Says on screen when a print job fails (the reason, and a button to the printer test), instead of failing silently.
class PrintFailureWatcher extends ConsumerWidget {
  const PrintFailureWatcher({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(printFailuresProvider, (_, next) {
      final f = next.value;
      if (f == null) return;
      final t = Strings.of(context);
      // replaces "sent to the printer queue" at once: the failure is what matters now
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(
        key: const ValueKey('print-failed'),
        duration: const Duration(seconds: 10),
        content: Text('${t['print_failed']} ${f.printer}: ${f.message}'),
        action: SnackBarAction(label: t['pr_diag_title'], onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrinterDiagnosticsScreen()))),
        ));
    });
    return const SizedBox.shrink();
  }
}

class PrinterDiagnosticsScreen extends ConsumerStatefulWidget {
  const PrinterDiagnosticsScreen({super.key, this.initial});
  final String? initial;
  @override
  ConsumerState<PrinterDiagnosticsScreen> createState() => _PrinterDiagnosticsScreenState();
}

class _PrinterDiagnosticsScreenState extends ConsumerState<PrinterDiagnosticsScreen> {
  String? _id;
  bool _busy = false;
  final _log = <String>[];

  void _add(String s) => setState(() => _log.add(s));

  Map<String, Object?>? _printer(List<Map<String, Object?>> list) {
    for (final p in list) {
      if (p['id'] == (_id ?? widget.initial)) return p;
    }
    return list.isEmpty ? null : list.first;
  }

  Future<void> _run(String title, Future<String> Function() work) async {
    if (_busy) return;
    final t = Strings.of(context);
    setState(() {
      _busy = true;
      _log.add('▶ $title');
    });
    try {
      final r = await work();
      _add('✔ ${t['pr_diag_ok']}: $r');
    } catch (e) {
      _add('✘ ${t['pr_diag_fail']}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _info(Map<String, Object?> p) async {
    final address = '${p['address']}';
    switch ('${p['connection']}') {
      case 'bluetooth':
        final m = await const DeviceChannel().printerInfo(address);
        final uuids = (m['uuids'] as List?)?.length ?? 0;
        return '${m['name']} · type ${m['type']} · ${m['bonded'] == true ? 'paired' : 'NOT paired'} · SPP ${m['spp'] == true ? 'yes' : 'not listed'} · $uuids services';
      case 'usb':
        final list = await const DeviceChannel().usbDevices();
        final mine = list.where((u) => u.id == address).toList();
        if (mine.isEmpty) throw PrinterException('USB device $address is not plugged in (${list.length} other USB device(s) seen)');
        return '${mine.first.label} found${mine.first.isPrinter ? ' (printer class)' : ' (not reporting itself as a printer)'}';
      default:
        final parts = address.split(':');
        final s = await Socket.connect(parts[0], parts.length > 1 ? int.parse(parts[1]) : 9100, timeout: const Duration(seconds: 5));
        await s.close();
        return 'reached $address';
    }
  }

  Future<String> _send(Map<String, Object?> p, Uint8List bytes) async {
    final transport = ref.read(printerTransportProvider)('${p['connection']}', '${p['address']}');
    final started = DateTime.now();
    await transport.send(bytes);
    final route = transport is RoutedTransport ? (transport as RoutedTransport).route : null;
    final secs = (DateTime.now().difference(started).inMilliseconds / 1000).toStringAsFixed(1);
    return '${bytes.length} bytes sent in ${secs}s${route == null ? '' : ' via $route'} (speed ${PrintSpeed.value}). Look at the paper.';
  }

  Future<void> _setSpeed(String v) async {
    setState(() => PrintSpeed.value = v);
    await setSetting(ref.read(databaseProvider), PrintSpeed.settingKey, v, ref.read(clockProvider)().millisecondsSinceEpoch);
    _add('Speed set to $v');
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final printers = ref.watch(printersProvider).value ?? const [];
    final p = _printer(printers);
    return Scaffold(
      appBar: AppBar(title: Text(t['pr_diag_title'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t['pr_diag_hint']),
        const SizedBox(height: 12),
        if (p == null)
          Text(t['pr_diag_none'])
        else ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('diag-printer'),
            initialValue: '${p['id']}',
            decoration: InputDecoration(labelText: t['pr_diag_pick']),
            items: [for (final x in printers) DropdownMenuItem(value: '${x['id']}', child: Text('${x['name']} · ${x['connection']}'))],
            onChanged: (v) => setState(() => _id = v),
          ),
          const SizedBox(height: 12),
          Text(t['pr_diag_speed'], style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            key: const ValueKey('diag-speed'),
            showSelectedIcon: false,
            segments: [for (final s in PrintSpeed.all) ButtonSegment(value: s, label: Text(t['pr_speed_$s'].split(' ').first))],
            selected: {PrintSpeed.value},
            onSelectionChanged: (s) => _setSpeed(s.first),
          ),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(t['pr_speed_safe'], style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 12),
          FilledButton.tonal(key: const ValueKey('diag-info'), onPressed: _busy ? null : () => _run(t['pr_diag_info'], () => _info(p)), child: Text(t['pr_diag_info'])),
          const SizedBox(height: 8),
          FilledButton.tonal(key: const ValueKey('diag-text'), onPressed: _busy ? null : () => _run(t['pr_diag_text'], () => _send(p, plainTextTest(paperMm: (p['paper_mm'] as int?) ?? 58))), child: Text(t['pr_diag_text'])),
          const SizedBox(height: 8),
          FilledButton.tonal(key: const ValueKey('diag-graphics'), onPressed: _busy ? null : () => _run(t['pr_diag_graphics'], () => _send(p, graphicsTest(paperMm: (p['paper_mm'] as int?) ?? 58))), child: Text(t['pr_diag_graphics'])),
        ],
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        for (final l in _log) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(l)),
        if (_log.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('diag-copy'),
              icon: const Icon(Icons.copy),
              label: Text(t['pr_diag_copy']),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: 'DT Food POS printer test\n${p == null ? '' : '${p['name']} (${p['connection']} ${p['address']}, ${p['paper_mm']} mm)\n'}${_log.join('\n')}'));
                messenger.showSnackBar(SnackBar(content: Text(t['pr_diag_copied'])));
              },
            ),
          ),
      ]),
    );
  }
}
