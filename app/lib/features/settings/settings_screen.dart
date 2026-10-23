import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/themes.dart';
import 'receipt_design_screen.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/backup_service.dart';
import '../../data/queries.dart';

final printersProvider = FutureProvider<List<Map<String, Object?>>>((ref) async =>
    (await ref.watch(databaseProvider).customSelect("SELECT * FROM printer WHERE deleted_at IS NULL ORDER BY name").get()).map((r) => r.data).toList());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final locale = ref.watch(localeProvider);
    final printers = ref.watch(printersProvider).value ?? const [];
    final biz = ref.watch(businessProvider).value;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _Section(t['language'], [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final e in Strings.languageNames.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {locale.languageCode},
          onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
        ),
      ]),
      _Section(t['theme'], [
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final p in themePresets)
            InkWell(
              key: ValueKey('theme-${p.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref.read(themeIdProvider.notifier).set(p.id),
              child: Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(width: 2, color: ref.watch(themeIdProvider) == p.id ? p.seed : Colors.transparent)),
                child: Column(children: [
                  CircleAvatar(radius: 18, backgroundColor: p.seed, child: ref.watch(themeIdProvider) == p.id ? const Icon(Icons.check, color: Colors.white, size: 20) : null),
                  const SizedBox(height: 6),
                  Text(t[p.nameKey], textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Text(t['theme_mode'], style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<ThemeMode>(
          key: const ValueKey('theme-mode'),
          showSelectedIcon: false,
          segments: [ButtonSegment(value: ThemeMode.system, label: Text(t['mode_system'])), ButtonSegment(value: ThemeMode.light, label: Text(t['mode_light'])), ButtonSegment(value: ThemeMode.dark, label: Text(t['mode_dark']))],
          selected: {ref.watch(themeModeProvider)},
          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
        ),
      ]),
      _Section(t['business'], [
        ListTile(key: const ValueKey('business-tile'), title: Text(biz?.name ?? ''), subtitle: Text([biz?.phone, biz?.address].whereType<String>().join(' · ')), trailing: const Icon(Icons.edit_outlined), onTap: () => _editBusiness(context, ref, biz)),
        ListTile(key: const ValueKey('receipt-design-tile'), leading: const Icon(Icons.receipt_long_outlined), title: Text(t['receipt_design']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiptDesignScreen()))),
      ]),
      _Section(t['printers'], [
        if (printers.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(t['no_printer'])),
        for (final p in printers) ListTile(dense: true, leading: const Icon(Icons.print_outlined), title: Text('${p['name']}'), subtitle: Text('${p['connection']} · ${p['address']} · ${p['paper_mm']} mm · ${p['role']}')),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('add-printer'), onPressed: () => _addPrinter(context, ref), icon: const Icon(Icons.add), label: Text(t['add_printer']))),
      ]),
      _Section(t['backup'], [
        FilledButton.tonalIcon(key: const ValueKey('backup-now'), onPressed: () => _backup(context, ref), icon: const Icon(Icons.backup_outlined), label: Text(t['backup_now'])),
      ]),
      _Section(t['about'], [
        const ListTile(dense: true, title: Text('DT Food POS'), subtitle: Text('Powered by Digital Target')),
        const ListTile(dense: true, leading: Icon(Icons.phone_outlined), title: Text('0345-1873354')),
        const ListTile(dense: true, leading: Icon(Icons.email_outlined), title: Text('digitaltarget.digital@gmail.com')),
        const ListTile(dense: true, leading: Icon(Icons.location_on_outlined), title: Text('Burewala, Pakistan')),
      ]),
    ]);
  }

  Future<void> _editBusiness(BuildContext context, WidgetRef ref, Business? b) async {
    final t = Strings.of(context);
    final name = TextEditingController(text: b?.name);
    final phone = TextEditingController(text: b?.phone);
    final address = TextEditingController(text: b?.address);
    final taxLabel = TextEditingController(text: b?.taxLabel ?? 'NTN');
    final taxNo = TextEditingController(text: b?.taxNumber);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['business']),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('biz-name'), controller: name, decoration: InputDecoration(labelText: t['business_name'])),
            const SizedBox(height: 8),
            TextField(controller: phone, decoration: InputDecoration(labelText: t['phone'])),
            const SizedBox(height: 8),
            TextField(controller: address, decoration: InputDecoration(labelText: t['address'])),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(width: 90, child: TextField(controller: taxLabel, decoration: InputDecoration(labelText: t['tax_label']))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: taxNo, decoration: InputDecoration(labelText: t['tax_number']))),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
          FilledButton(
            key: const ValueKey('biz-save'),
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(databaseProvider).customStatement(
                  "UPDATE business_profile SET name=?, phone=?, address=?, tax_number_label=?, tax_number=?, updated_at=? WHERE id='self'",
                  [name.text.trim(), phone.text.trim(), address.text.trim(), taxLabel.text.trim(), taxNo.text.trim(), ref.read(clockProvider)().millisecondsSinceEpoch]);
              ref.invalidate(businessProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t['save']),
          ),
        ],
      ),
    );
  }

  Future<void> _addPrinter(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final name = TextEditingController(text: 'Counter printer');
    final addr = TextEditingController();
    var role = 'both';
    var paper = 58;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t['add_printer']),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t['product_name'])),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('printer-address'), controller: addr, decoration: InputDecoration(labelText: t['printer_address'], hintText: '192.168.1.50:9100')),
              const SizedBox(height: 8),
              SegmentedButton<int>(showSelectedIcon: false, segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))], selected: {paper}, onSelectionChanged: (s) => setState(() => paper = s.first)),
              const SizedBox(height: 8),
              SegmentedButton<String>(showSelectedIcon: false, segments: [ButtonSegment(value: 'bill', label: Text(t['bill'])), ButtonSegment(value: 'kot', label: Text(t['kot'])), ButtonSegment(value: 'both', label: Text(t['both']))], selected: {role}, onSelectionChanged: (s) => setState(() => role = s.first)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
            FilledButton(
              key: const ValueKey('printer-save'),
              onPressed: () async {
                if (addr.text.trim().isEmpty) return;
                await ref.read(databaseProvider).customStatement(
                    "INSERT INTO printer(id, name, connection, address, paper_mm, role, updated_at) VALUES (?,?,'lan',?,?,?,?)",
                    [const Uuid().v4(), name.text.trim(), addr.text.trim(), paper, role, ref.read(clockProvider)().millisecondsSinceEpoch]);
                ref.invalidate(printersProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(t['save']),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['backup']),
        content: TextField(key: const ValueKey('backup-pass'), controller: pass, obscureText: true, decoration: InputDecoration(labelText: t['backup_passphrase'])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])), FilledButton(key: const ValueKey('backup-go'), onPressed: () => Navigator.pop(ctx, true), child: Text(t['backup_now']))],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await ref.read(backupDirProvider.future);
      final f = await ref.read(backupServiceProvider).createBackup(passphrase: pass.text, dir: dir);
      BackupService.prune(dir);
      messenger.showSnackBar(SnackBar(content: Text(f.path.split('/').last)));
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(bottom: 6, left: 4), child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children))),
        ]),
      );
}
