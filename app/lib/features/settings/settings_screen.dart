import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart' show buildTheme, contrastRatio;
import '../../app/themes.dart';
import 'receipt_design_screen.dart';
import '../tokens/token_ui.dart';
import '../tokens/tokens_settings_screen.dart';

import '../../app/business_mode.dart';
import '../../app/device_channel.dart' show PairedPrinter;
import '../../app/feedback.dart';
import '../cloud/notices.dart' show noticeClearedProvider;
import '../../app/providers.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/location_consent.dart';
import '../common/dialogs.dart';
import '../online/order_sources_screen.dart';
import '../../app/strings.dart';
import '../../data/backup_service.dart';
import '../../domain/modules.dart';
import '../../data/restore.dart';
import '../../data/payment_method_service.dart';
import 'payment_accounts.dart';
import 'print_settings_screen.dart';
import 'theme_studio_screen.dart';
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
        SizedBox(
          height: 178,
          child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in themePresets) _ThemeSwatch(key: ValueKey('theme-${p.id}'), preset: p, label: t[p.nameKey], selected: ref.watch(effectiveThemeIdProvider) == p.id, onTap: ref.watch(adminThemeProvider).locked ? null : () => ref.read(themeIdProvider.notifier).set(p.id)),
          _ThemeSwatch(
            key: const ValueKey('theme-custom'),
            preset: ref.watch(effectiveThemeIdProvider).startsWith('custom:') ? presetById(ref.watch(effectiveThemeIdProvider)) : const ThemePreset('custom', Color(0xFF757575), 'theme_custom', accent: Color(0xFFBDBDBD)),
            label: t['theme_custom'],
            selected: ref.watch(effectiveThemeIdProvider).startsWith('custom:'),
            icon: Icons.palette_outlined,
            onTap: ref.watch(adminThemeProvider).locked ? null : () => _customTheme(context, ref),
          ),
        ]),
        ),
        ListTile(key: const ValueKey('theme-studio-tile'), contentPadding: EdgeInsets.zero, leading: const Icon(Icons.brush_outlined), title: Text(t['theme_studio']), subtitle: Text(t['theme_studio_hint']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThemeStudioScreen()))),
        if (ref.watch(adminThemeProvider).locked) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t['theme_locked_note'], key: const ValueKey('theme-locked-note'), style: Theme.of(context).textTheme.bodySmall)),
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
      if (ref.watch(sessionProvider)?.can('settings.manage') ?? false)
        _Section(t['business_type'], [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in businessTypes)
              ChoiceChip(
                key: ValueKey('set-btype-${b.id}'),
                avatar: Icon(b.icon, size: 18),
                label: Text(t['btype_${b.id}']),
                selected: false,
                onSelected: (_) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t['business_type_apply']),
                      content: Text('${t['btype_${b.id}']}\n\n${t['business_type_apply_body']}'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])), FilledButton(key: const ValueKey('btype-apply'), onPressed: () => Navigator.pop(ctx, true), child: Text(t['ok']))],
                    ),
                  );
                  if (ok == true) await applyBusinessType(ref, b.id);
                },
              ),
          ]),
          SwitchListTile(
            key: const ValueKey('opt-quick-counter'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            secondary: const Icon(Icons.bolt_outlined),
            title: Text(t['quick_counter']),
            subtitle: Text(t['quick_counter_hint']),
            value: ref.watch(quickCounterProvider).value ?? false,
            onChanged: (v) => ref.read(quickCounterProvider.notifier).set(v),
          ),
        ]),
      if (ref.watch(sessionProvider)?.can('settings.manage') ?? false)
        _Section(t['modules'], [
          Text(t['modules_hint'], style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final m in allModules)
            SwitchListTile(
              key: ValueKey('module-$m'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: Text(t['module_$m']),
              subtitle: ref.watch(adminDisabledModulesProvider).contains(m) ? Text(t['module_off_by_admin'], style: TextStyle(color: Theme.of(context).colorScheme.error)) : null,
              value: ref.watch(activeModulesProvider).contains(m),
              onChanged: ref.watch(adminDisabledModulesProvider).contains(m) ? null : (v) => ref.read(modulesProvider.notifier).toggle(m, v),
            ),
        ]),
      _Section(t['business'], [
        ListTile(key: const ValueKey('business-tile'), title: Text(biz?.name ?? ''), subtitle: Text([biz?.phone, biz?.address].whereType<String>().join(' · ')), trailing: const Icon(Icons.edit_outlined), onTap: () => _editBusiness(context, ref, biz)),
        if (ref.watch(activeModulesProvider).contains('tokens')) ListTile(key: const ValueKey('tokens-settings-tile'), leading: const Icon(Icons.confirmation_number_outlined), title: Text(t['tokens_title']), subtitle: Text(t['tokens_sub']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TokensSettingsScreen()))),
        ListTile(key: const ValueKey('print-settings-tile'), leading: const Icon(Icons.print_outlined), title: Text(t['print_settings']), subtitle: Text(t['print_settings_hint']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrintSettingsScreen()))),
        ListTile(key: const ValueKey('receipt-design-tile'), leading: const Icon(Icons.receipt_long_outlined), title: Text(t['receipt_design']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiptDesignScreen()))),
      ]),
      _Section(t['payment_accounts'], [
        for (final m in ref.watch(allPaymentMethodsProvider).value ?? const <PaymentMethodRow>[]) PaymentAccountCard(method: m),
        if (ref.watch(activeModulesProvider).contains('online')) ListTile(key: const ValueKey('order-sources-tile'), leading: const Icon(Icons.storefront_outlined), title: Text(t['dl_sources']), subtitle: Text(t['dl_pay_instructions']), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OrderSourcesScreen()))),
        Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('add-payment-method'), onPressed: () => showPaymentAccountDialog(context, ref), icon: const Icon(Icons.add), label: Text(t['add_payment_account']))),
      ]),
      _Section(t['printers'], [
        if (printers.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(t['no_printer'])),
        for (final p in printers)
          ListTile(
            dense: true,
            leading: const Icon(Icons.print_outlined),
            title: Text('${p['name']}'),
            subtitle: Text('${p['connection']} · ${p['address']} · ${p['paper_mm']} mm · ${p['role']}${p['station'] == null ? '' : ' · ${p['station']}'}'),
            trailing: IconButton(
              key: ValueKey('printer-test-${p['name']}'),
              tooltip: t['print_test'],
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => testPrinter(context, ref, p),
            ),
          ),
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
          FilledButton.tonalIcon(key: const ValueKey('backup-now'), onPressed: () => _backup(context, ref), icon: const Icon(Icons.backup_outlined), label: Text(t['backup_export'])),
          OutlinedButton.icon(key: const ValueKey('restore'), onPressed: () => _restore(context, ref), icon: const Icon(Icons.file_open_outlined), label: Text(t['backup_import'])),
        ]),
      ]),
      _Section(t['about'], [
        const ListTile(dense: true, title: Text('DT Food POS'), subtitle: Text('Powered by Digital Target')),
        const ListTile(dense: true, leading: Icon(Icons.phone_outlined), title: Text('0345-1873354')),
        const ListTile(dense: true, leading: Icon(Icons.email_outlined), title: Text('digitaltarget.digital@gmail.com')),
        const ListTile(dense: true, leading: Icon(Icons.location_on_outlined), title: Text('Burewala, Pakistan')),
      ]),
      _Section(t['tax_section'], [const _TaxServiceCard()]),
      _Section(t['sound_section'], [
        SwitchListTile(
          key: const ValueKey('opt-sound'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          secondary: const Icon(Icons.volume_up_outlined),
          title: Text(t['sound_on']),
          subtitle: Text(t['sound_hint']),
          value: ref.watch(feedbackPrefsProvider).value?.sound ?? true,
          onChanged: (v) async {
            await ref.read(feedbackPrefsProvider.notifier).setSound(v);
            if (v) ref.read(appFeedbackProvider).tap();
          },
        ),
        SwitchListTile(
          key: const ValueKey('opt-vibrate'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          secondary: const Icon(Icons.vibration),
          title: Text(t['vibrate_on']),
          value: ref.watch(feedbackPrefsProvider).value?.vibrate ?? true,
          onChanged: (v) async {
            await ref.read(feedbackPrefsProvider.notifier).setVibrate(v);
            if (v) ref.read(appFeedbackProvider).tap();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(key: const ValueKey('test-tap'), onPressed: () => ref.read(appFeedbackProvider).tap(), icon: const Icon(Icons.touch_app_outlined, size: 18), label: Text(t['sound_test_tap'])),
            OutlinedButton.icon(key: const ValueKey('test-success'), onPressed: () => ref.read(appFeedbackProvider).success(), icon: const Icon(Icons.check_circle_outline, size: 18), label: Text(t['sound_test_paid'])),
            OutlinedButton.icon(key: const ValueKey('test-error'), onPressed: () => ref.read(appFeedbackProvider).failure(), icon: const Icon(Icons.error_outline, size: 18), label: Text(t['sound_test_error'])),
          ]),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(t['sound_silent_hint'], style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        if (ref.watch(cloudGatewayProvider) != null) ...[
          SwitchListTile(
            key: const ValueKey('opt-notices'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(t['notices_on']),
            subtitle: Text(t['notices_hint']),
            value: ref.watch(feedbackPrefsProvider).value?.notices ?? true,
            onChanged: (v) async {
              final ok = await ref.read(feedbackPrefsProvider.notifier).setNotices(v);
              if (v && !ok && context.mounted) showMessage(context, t['notices_denied']);
            },
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('notices-clear-all'),
              onPressed: () async {
                await ref.read(noticeClearedProvider.notifier).clearAll();
                if (context.mounted) showMessage(context, t['notices_cleared']);
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(t['notices_clear']),
            ),
          ),
        ],
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
    final station = TextEditingController();
    var role = 'both';
    var paper = 58;
    var connection = 'lan';
    PairedPrinter? bt;
    String? btError;
    final scanner = ref.read(bluetoothScannerProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(scrollable: true, 
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
              if (role != 'bill') ...[
                const SizedBox(height: 8),
                TextField(key: const ValueKey('printer-station'), controller: station, decoration: InputDecoration(labelText: t['counter_station'], helperText: t['printer_station_hint'], helperMaxLines: 3)),
              ],
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
                    "INSERT INTO printer(id, name, connection, address, paper_mm, role, station, updated_at) VALUES (?,?,?,?,?,?,?,?)",
                    [const Uuid().v4(), name.text.trim(), connection, address, paper, role, role == 'bill' || station.text.trim().isEmpty ? null : station.text.trim(), ref.read(clockProvider)().millisecondsSinceEpoch]);
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
      builder: (ctx) => AlertDialog(scrollable: true, 
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
      // a copy outside the app: it survives uninstalling the app (Downloads/DT Food POS)
      String? where;
      try {
        where = await ref.read(phoneFileSaverProvider).save(path: f.path, name: f.path.split('/').last, mime: 'application/octet-stream');
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('${t['save_failed']}: $e')));
      }
      if (where != null) messenger.showSnackBar(SnackBar(content: Text('${t['backup_saved_phone']}: $where')));
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
      builder: (ctx, setState) => AlertDialog(scrollable: true, 
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

/// A small live preview of a theme: header, a menu item with its Add button, and the bottom bar.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({super.key, required this.preset, required this.label, required this.selected, required this.onTap, this.icon});
  final ThemePreset preset;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final th = buildTheme(spec: preset);
    final cs = th.colorScheme;
    final header = th.appBarTheme.backgroundColor!;
    final onHeader = th.appBarTheme.foregroundColor!;
    final nav = th.navigationBarTheme.backgroundColor!;
    final bg = th.scaffoldBackgroundColor;
    final r = preset.radius / 2;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(width: 2.5, color: selected ? cs.primary : Colors.transparent)),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 112,
              color: bg,
              child: Column(children: [
                Container(height: 20, color: header, padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.centerLeft, child: Row(children: [
                  Container(width: 26, height: 4, color: onHeader.withValues(alpha: 0.9)),
                  const Spacer(),
                  if (icon != null) Icon(icon, size: 12, color: onHeader),
                ])),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i == 1) const SizedBox(width: 5),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(r),
                              border: preset.cardStyle == 'outline' ? Border.all(color: cs.outlineVariant, width: 0.6) : null,
                              boxShadow: preset.cardStyle == 'shadow' ? const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))] : null,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: Container(decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(r / 2)))),
                              const SizedBox(height: 3),
                              Container(width: 18, height: 3, color: cs.primary),
                              const SizedBox(height: 3),
                              Container(height: 8, decoration: BoxDecoration(color: preset.accent, borderRadius: BorderRadius.circular(r / 2))),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
                Container(height: 14, color: nav, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (var i = 0; i < 4; i++) Container(width: 10, height: 4, decoration: BoxDecoration(color: i == 0 ? cs.primary : cs.outline, borderRadius: BorderRadius.circular(2))),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) Icon(Icons.check_circle, size: 14, color: Theme.of(context).colorScheme.primary),
            if (selected) const SizedBox(width: 3),
            Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
          ]),
        ]),
      ),
    );
  }
}

/// Owner builds a theme: main colour, button colour, header, background, card style and roundness, with a live preview.
Future<void> _customTheme(BuildContext context, WidgetRef ref) async {
  final t = Strings.of(context);
  final current = presetById(ref.read(themeIdProvider));
  var main = current.seed, accent = current.accent;
  Color? header = current.header, background = current.background;
  var card = current.cardStyle;
  var radius = current.radius;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget palette(List<Color> colors, Color? selected, ValueChanged<Color> pick, String keyPrefix) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in colors)
                InkWell(
                  key: ValueKey('$keyPrefix-${c.toARGB32().toRadixString(16)}'),
                  onTap: () => setState(() => pick(c)),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                    child: c == selected ? Icon(Icons.check, size: 16, color: contrastRatio(c, Colors.white) > 3 ? Colors.white : Colors.black) : null,
                  ),
                ),
            ]);
        Widget label(String k) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(t[k], style: const TextStyle(fontWeight: FontWeight.w600)));
        final preview = presetById(customThemeId(main, accent, header: header, background: background, cardStyle: card, radius: radius));
        return AlertDialog(
          title: Text(t['theme_custom']),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: _ThemeSwatch(preset: preview, label: t['preview'], selected: false, onTap: () {})),
                label('main_color'),
                palette(customPalette, main, (c) => main = c, 'main'),
                label('accent_color'),
                palette(customPalette, accent, (c) => accent = c, 'accent'),
                label('header_color'),
                palette(customPalette, header ?? main, (c) => header = c, 'header'),
                label('background_color'),
                palette(backgroundPalette, background, (c) => background = c, 'bg'),
                label('card_style'),
                SegmentedButton<String>(
                  key: const ValueKey('card-style'),
                  showSelectedIcon: false,
                  segments: [ButtonSegment(value: 'outline', label: Text(t['card_outline'])), ButtonSegment(value: 'shadow', label: Text(t['card_shadow'])), ButtonSegment(value: 'flat', label: Text(t['card_flat']))],
                  selected: {card},
                  onSelectionChanged: (s) => setState(() => card = s.first),
                ),
                label('corner_round'),
                Slider(key: const ValueKey('radius'), min: 4, max: 28, divisions: 6, value: radius, label: '${radius.round()}', onChanged: (v) => setState(() => radius = v)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
            FilledButton(key: const ValueKey('custom-theme-save'), onPressed: () {
              ref.read(themeIdProvider.notifier).set(customThemeId(main, accent, header: header, background: background, cardStyle: card, radius: radius));
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


/// Tax and service charge: both are OFF until the owner switches them on and saves a percentage. Nothing is added to any bill otherwise.
class _TaxServiceCard extends ConsumerStatefulWidget {
  const _TaxServiceCard();
  @override
  ConsumerState<_TaxServiceCard> createState() => _TaxServiceCardState();
}

class _TaxServiceCardState extends ConsumerState<_TaxServiceCard> {
  final _taxRate = TextEditingController();
  final _serviceRate = TextEditingController();
  bool _taxOn = false, _inclusive = false, _serviceOn = false, _loaded = false;

  static String _pct(int bp) => bp == 0 ? '' : (bp / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _taxRate.dispose();
    _serviceRate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final tax = await loadTaxPolicy(db);
    final serviceOn = (await getSetting(db, 'service.auto')) == '1';
    final sbp = int.tryParse(await getSetting(db, 'service.bp') ?? '') ?? 0;
    if (!mounted) return;
    setState(() {
      _taxOn = tax.enabled;
      _inclusive = tax.inclusive;
      _taxRate.text = _pct(tax.rateBp);
      _serviceOn = serviceOn;
      _serviceRate.text = _pct(sbp);
      _loaded = true;
    });
  }

  int _bp(String s) => ((double.tryParse(s.trim().replaceAll(',', '.')) ?? 0) * 100).round().clamp(0, 10000);

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;
    final t = Strings.of(context);
    final taxBp = _bp(_taxRate.text), serviceBp = _bp(_serviceRate.text);
    final taxOn = _taxOn && taxBp > 0, serviceOn = _serviceOn && serviceBp > 0;
    await setSetting(db, TaxPolicy.keyOn, taxOn ? '1' : '0', now);
    await setSetting(db, TaxPolicy.keyRate, '$taxBp', now);
    await setSetting(db, TaxPolicy.keyInclusive, _inclusive ? '1' : '0', now);
    await setSetting(db, 'service.auto', serviceOn ? '1' : '0', now);
    await setSetting(db, 'service.bp', '$serviceBp', now);
    ref.invalidate(productsProvider);
    ref.invalidate(serviceDefaultProvider);
    if (!mounted) return;
    setState(() {
      _taxOn = taxOn;
      _serviceOn = serviceOn;
    });
    showMessage(context, t['saved']);
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    if (!_loaded) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t['tax_hint'], style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      SwitchListTile(key: const ValueKey('tax-on'), contentPadding: EdgeInsets.zero, title: Text(t['tax_on']), value: _taxOn, onChanged: (v) => setState(() => _taxOn = v)),
      if (_taxOn) ...[
        TextField(key: const ValueKey('tax-rate'), controller: _taxRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t['tax_rate'], suffixText: '%', isDense: true)),
        SwitchListTile(key: const ValueKey('tax-inclusive'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['tax_inclusive']), subtitle: Text(t['tax_inclusive_hint']), value: _inclusive, onChanged: (v) => setState(() => _inclusive = v)),
      ],
      const Divider(),
      SwitchListTile(key: const ValueKey('service-on'), contentPadding: EdgeInsets.zero, title: Text(t['service_auto']), subtitle: Text(t['service_auto_hint']), value: _serviceOn, onChanged: (v) => setState(() => _serviceOn = v)),
      if (_serviceOn) TextField(key: const ValueKey('service-rate'), controller: _serviceRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t['service_rate'], suffixText: '%', isDense: true)),
      const SizedBox(height: 8),
      Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton(key: const ValueKey('tax-save'), onPressed: _save, child: Text(t['save']))),
    ]);
  }
}
