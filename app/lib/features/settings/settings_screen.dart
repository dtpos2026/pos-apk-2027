import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/themes.dart';
import 'receipt_design_screen.dart';

import '../../app/device_channel.dart' show PairedPrinter;
import '../../app/providers.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/location_consent.dart';
import '../common/dialogs.dart';
import '../../app/strings.dart';
import '../../data/backup_service.dart';
import '../../data/restore.dart';
import '../../data/payment_method_service.dart';
import '../../data/pos_service.dart' show PosException;
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
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in themePresets) _ThemeSwatch(key: ValueKey('theme-${p.id}'), preset: p, label: t[p.nameKey], selected: ref.watch(themeIdProvider) == p.id, onTap: () => ref.read(themeIdProvider.notifier).set(p.id)),
          _ThemeSwatch(
            key: const ValueKey('theme-custom'),
            preset: ref.watch(themeIdProvider).startsWith('custom:') ? presetById(ref.watch(themeIdProvider)) : const ThemePreset('custom', Color(0xFF9E9E9E), 'theme_custom', accent: Color(0xFFBDBDBD)),
            label: t['theme_custom'],
            selected: ref.watch(themeIdProvider).startsWith('custom:'),
            icon: Icons.palette_outlined,
            onTap: () => _customTheme(context, ref),
          ),
        ]),
        const SizedBox(height: 14),
        Text(t['menu_layout'], style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: const ValueKey('pos-layout'),
          showSelectedIcon: false,
          segments: [ButtonSegment(value: 'photos', icon: const Icon(Icons.grid_view), label: Text(t['layout_photos'])), ButtonSegment(value: 'compact', icon: const Icon(Icons.view_comfy_alt_outlined), label: Text(t['layout_compact']))],
          selected: {ref.watch(posLayoutProvider)},
          onSelectionChanged: (s) => ref.read(posLayoutProvider.notifier).set(s.first),
        ),
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
      _Section(t['payment_accounts'], [
        for (final m in ref.watch(allPaymentMethodsProvider).value ?? const <PaymentMethodRow>[])
          ListTile(
            key: ValueKey('pm-${m.name}'),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: Icon(switch (m.kind) { 'cash' => Icons.payments_outlined, 'card' => Icons.credit_card, 'bank' => Icons.account_balance_outlined, 'wallet' => Icons.account_balance_wallet_outlined, 'credit' => Icons.menu_book_outlined, _ => Icons.more_horiz }),
            title: Text(m.name),
            subtitle: Text(t['pm_${m.kind}']),
            onTap: m.kind == 'cash' ? null : () => _paymentMethodDialog(context, ref, existing: m),
            trailing: Switch(
              key: ValueKey('pm-switch-${m.name}'),
              value: m.enabled,
              onChanged: m.kind == 'cash' ? null : (v) async {
                await ref.read(paymentMethodServiceProvider).setEnabled(m.id, v, staffId: ref.read(sessionProvider)!.staffId);
                ref.invalidate(allPaymentMethodsProvider);
                ref.invalidate(paymentMethodsProvider);
              },
            ),
          ),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('add-payment-method'), onPressed: () => _paymentMethodDialog(context, ref), icon: const Icon(Icons.add), label: Text(t['add_payment_account']))),
      ]),
      _Section(t['printers'], [
        if (printers.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(t['no_printer'])),
        for (final p in printers) ListTile(dense: true, leading: const Icon(Icons.print_outlined), title: Text('${p['name']}'), subtitle: Text('${p['connection']} · ${p['address']} · ${p['paper_mm']} mm · ${p['role']}')),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('add-printer'), onPressed: () => _addPrinter(context, ref), icon: const Icon(Icons.add), label: Text(t['add_printer']))),
      ]),
      if (ref.watch(cloudGatewayProvider) != null)
        _Section(t['account_section'], [
          SwitchListTile(
            key: const ValueKey('share-location'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            secondary: const Icon(Icons.location_on_outlined),
            title: Text(t['share_location']),
            subtitle: Text(t['share_location_hint']),
            value: ref.watch(locationConsentProvider).value ?? false,
            onChanged: (v) async {
              final ok = await ref.read(locationConsentProvider.notifier).set(v);
              if (v && !ok && context.mounted) showMessage(context, t['location_denied']);
            },
          ),
        ]),
      _Section(t['backup'], [
        Text(t['backup_hint'], style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(key: const ValueKey('backup-now'), onPressed: () => _backup(context, ref), icon: const Icon(Icons.backup_outlined), label: Text(t['backup_now'])),
          OutlinedButton.icon(key: const ValueKey('restore'), onPressed: () => _restore(context, ref), icon: const Icon(Icons.settings_backup_restore), label: Text(t['restore'])),
        ]),
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

  Future<void> _paymentMethodDialog(BuildContext context, WidgetRef ref, {PaymentMethodRow? existing}) async {
    final t = Strings.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    var kind = existing?.kind ?? 'wallet';
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? t['add_payment_account'] : t['edit']),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const ValueKey('pm-name'), controller: name, decoration: InputDecoration(labelText: t['pm_name_hint'])),
            if (existing == null) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: InputDecoration(labelText: t['pm_type']),
                items: [for (final k in const ['wallet', 'bank', 'card', 'other']) DropdownMenuItem(value: k, child: Text(t['pm_$k']))],
                onChanged: (v) => setState(() => kind = v ?? 'wallet'),
              ),
            ],
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
            FilledButton(
              key: const ValueKey('pm-save'),
              onPressed: () async {
                final svc = ref.read(paymentMethodServiceProvider);
                final staff = ref.read(sessionProvider)!.staffId;
                try {
                  existing == null ? await svc.add(name: name.text, kind: kind, staffId: staff) : await svc.rename(existing.id, name.text, staffId: staff);
                  ref.invalidate(allPaymentMethodsProvider);
                  ref.invalidate(paymentMethodsProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on PosException catch (e) {
                  setState(() => error = e.message);
                }
              },
              child: Text(t['save']),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPrinter(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final name = TextEditingController(text: 'Counter printer');
    final addr = TextEditingController();
    var role = 'both';
    var paper = 58;
    var connection = 'lan';
    PairedPrinter? bt;
    String? btError;
    final scanner = ref.read(bluetoothScannerProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t['add_printer']),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t['product_name'])),
              const SizedBox(height: 8),
              if (scanner != null) ...[
                SegmentedButton<String>(
                  key: const ValueKey('printer-connection'),
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 'lan', icon: const Icon(Icons.wifi), label: Text(t['printer_lan'])), ButtonSegment(value: 'bluetooth', icon: const Icon(Icons.bluetooth), label: Text(t['printer_bluetooth']))],
                  selected: {connection},
                  onSelectionChanged: (s) => setState(() => connection = s.first),
                ),
                const SizedBox(height: 8),
              ],
              if (connection == 'lan')
                TextField(key: const ValueKey('printer-address'), controller: addr, decoration: InputDecoration(labelText: t['printer_address'], hintText: '192.168.1.50:9100'))
              else ...[
                OutlinedButton.icon(
                  key: const ValueKey('printer-choose-bt'),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(bt == null ? t['choose_paired'] : '${bt!.name} (${bt!.address})'),
                  onPressed: () async {
                    try {
                      final list = await scanner!.paired();
                      if (!ctx.mounted) return;
                      if (list.isEmpty) {
                        setState(() => btError = t['no_paired']);
                        return;
                      }
                      final pick = await showDialog<PairedPrinter>(
                        context: ctx,
                        builder: (c2) => SimpleDialog(title: Text(t['choose_paired']), children: [
                          for (final p in list) SimpleDialogOption(key: ValueKey('bt-${p.address}'), onPressed: () => Navigator.pop(c2, p), child: Text('${p.name}\n${p.address}')),
                        ]),
                      );
                      if (pick != null) setState(() { bt = pick; btError = null; });
                    } catch (e) {
                      setState(() => btError = '$e');
                    }
                  },
                ),
                if (btError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(btError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
              ],
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
                final address = connection == 'lan' ? addr.text.trim() : (bt?.address ?? '');
                if (address.isEmpty) return;
                await ref.read(databaseProvider).customStatement(
                    "INSERT INTO printer(id, name, connection, address, paper_mm, role, updated_at) VALUES (?,?,?,?,?,?,?)",
                    [const Uuid().v4(), name.text.trim(), connection, address, paper, role, ref.read(clockProvider)().millisecondsSinceEpoch]);
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
      final f = await ref.read(backupServiceProvider).createBackup(
        passphrase: pass.text,
        dir: dir,
        media: {'menu_images': ref.read(menuImageDirProvider), 'logo': ref.read(logoDirProvider)},
      );
      BackupService.prune(dir);
      messenger.showSnackBar(SnackBar(content: Text(t['backup_saved_share'])));
      // the copy inside the app disappears if the app is uninstalled: send it to Google Drive / WhatsApp / USB
      await ref.read(shareServiceProvider).shareFile(f.path, mimeType: 'application/octet-stream', subject: f.path.split('/').last);
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

Future<void> _restore(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final picked = await ref.read(backupFilePickerProvider).pick();
  if (picked == null || !context.mounted) return;
  final pass = TextEditingController();
  String? error;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t['restore']),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(picked.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(t['restore_warning']),
          const SizedBox(height: 10),
          TextField(key: const ValueKey('restore-pass'), controller: pass, obscureText: true, decoration: InputDecoration(labelText: t['backup_passphrase'])),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])),
          FilledButton(
            key: const ValueKey('restore-go'),
            onPressed: () async {
              final docs = ref.read(docsDirProvider);
              final pending = pendingRestoreDir(docs);
              try {
                if (pending.existsSync()) pending.deleteSync(recursive: true);
                pending.createSync(recursive: true);
                final file = File('${pending.path}/incoming.dtbak')..writeAsBytesSync(picked.bytes, flush: true);
                await BackupService.decryptAndVerify(backup: file, passphrase: pass.text, target: File('${pending.path}/$dbFileName'), mediaRoot: Directory('${pending.path}/media'));
                file.deleteSync();
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on BackupException catch (e) {
                if (pending.existsSync()) pending.deleteSync(recursive: true);
                setState(() => error = e.message);
              }
            },
            child: Text(t['restore']),
          ),
        ],
      ),
    ),
  );
  if (done != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: Text(t['restore_ready_title']),
      content: Text(t['restore_ready_body']),
      actions: [FilledButton(key: const ValueKey('restore-close-app'), onPressed: () => SystemNavigator.pop(), child: Text(t['close_app']))],
    ),
  );
}

/// A theme sample: main colour with the accent as a corner dot.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({super.key, required this.preset, required this.label, required this.selected, required this.onTap, this.icon});
  final ThemePreset preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(width: 2, color: selected ? preset.seed : Colors.transparent)),
          child: Column(children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(children: [
                CircleAvatar(radius: 18, backgroundColor: preset.seed, child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : (icon == null ? null : Icon(icon, color: Colors.white, size: 20))),
                Positioned(right: 0, bottom: 0, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: preset.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ]),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}

/// Owner picks a main colour and an accent colour; the whole app follows.
Future<void> _customTheme(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final current = presetById(ref.read(themeIdProvider));
  var main = current.seed, accent = current.accent;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget palette(Color selected, ValueChanged<Color> pick, String keyPrefix) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in customPalette)
                InkWell(
                  key: ValueKey('$keyPrefix-${c.toARGB32().toRadixString(16)}'),
                  onTap: () => setState(() => pick(c)),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(radius: 16, backgroundColor: c, child: c == selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                ),
            ]);
        return AlertDialog(
          title: Text(t['theme_custom']),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['main_color'], style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              palette(main, (c) => main = c, 'main'),
              const SizedBox(height: 16),
              Text(t['accent_color'], style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              palette(accent, (c) => accent = c, 'accent'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Container(height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: main, borderRadius: BorderRadius.circular(10)), child: Text(t['app_name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
                const SizedBox(width: 8),
                Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)), child: Text('+ ${t['add']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
            FilledButton(key: const ValueKey('custom-theme-save'), onPressed: () {
              ref.read(themeIdProvider.notifier).setCustom(main, accent);
              Navigator.pop(ctx);
            }, child: Text(t['save'])),
          ],
        );
      },
    ),
  );
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
