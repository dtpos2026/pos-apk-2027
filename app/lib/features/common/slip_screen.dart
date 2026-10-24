import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/receipt_doc.dart';
import '../settings/receipt_paper.dart';
import 'dialogs.dart';

/// Any slip (day close, reports): preview exactly what the printer prints, then print it, share it as text or as a PNG
/// picture (WhatsApp, email...), or save the PNG on the phone.
class SlipScreen extends ConsumerStatefulWidget {
  const SlipScreen({super.key, required this.title, required this.fileName, required this.build});
  final String title;

  /// Used for the PNG file name and the share subject.
  final String fileName;

  /// The document for a paper width (58 or 80 mm).
  final ReceiptDoc Function(int paperMm) build;

  @override
  ConsumerState<SlipScreen> createState() => _SlipScreenState();
}

class _SlipScreenState extends ConsumerState<SlipScreen> {
  int _paper = 58;
  final _key = GlobalKey();

  Future<File?> _png() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = ref.read(exportDirProvider)..createSync(recursive: true);
    final name = widget.fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$name.png')..writeAsBytesSync(data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final doc = widget.build(_paper);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: SegmentedButton<int>(key: const ValueKey('slip-paper'), showSelectedIcon: false, segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))], selected: {_paper}, onSelectionChanged: (s) => setState(() => _paper = s.first))),
        const SizedBox(height: 14),
        Center(child: RepaintBoundary(key: _key, child: ReceiptPaper(doc: doc, paperMm: _paper))),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            key: const ValueKey('slip-print'),
            icon: const Icon(Icons.print_outlined),
            label: Text(t['print_slip']),
            onPressed: () async {
              final jobs = await ref.read(printServiceProvider).queueDocument('report', widget.build);
              if (!context.mounted) return;
              if (jobs.isEmpty) {
                showMessage(context, t['no_printer']);
              } else {
                showMessage(context, t['sent_to_printer']);
                ref.read(printServiceProvider).processQueue();
              }
            },
          ),
          OutlinedButton.icon(
            key: const ValueKey('slip-share-png'),
            icon: const Icon(Icons.image_outlined),
            label: Text(t['share_image']),
            onPressed: () async {
              final f = await _png();
              if (f != null) await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'image/png', subject: widget.fileName);
            },
          ),
          OutlinedButton.icon(
            key: const ValueKey('slip-save-png'),
            icon: const Icon(Icons.save_alt),
            label: Text(t['save_png']),
            onPressed: () async {
              final f = await _png();
              if (f != null && context.mounted) showMessage(context, '${t['saved_to']}: ${f.path}');
            },
          ),
          OutlinedButton.icon(
            key: const ValueKey('slip-share-text'),
            icon: const Icon(Icons.share_outlined),
            label: Text(t['share_report']),
            onPressed: () => ref.read(shareServiceProvider).shareText(docToText(widget.build(_paper), _paper), subject: widget.fileName),
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }
}
