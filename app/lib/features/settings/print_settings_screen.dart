import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../domain/print_settings.dart';

/// Settings > Printing: KOT, token and bill are three separate documents with their own switches. Each has a master switch
/// (off = never printed, the Print buttons disappear) and an automatic switch (off = only when someone presses Print); the grid
/// below says what prints by itself for dine-in, takeaway, delivery and counter orders.
class PrintSettingsScreen extends ConsumerWidget {
  const PrintSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final cfg = ref.watch(printSettingsProvider).value ?? PrintSettings.defaults;
    Future<void> save(PrintSettings s) => ref.read(printSettingsProvider.notifier).save(s);

    Widget doc({required String keyId, required IconData icon, required String title, required bool enabled, required ValueChanged<bool> onEnabled, required String autoText, required bool auto, required ValueChanged<bool> onAuto}) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(children: [
              SwitchListTile(
                key: ValueKey('ps-$keyId-enabled'),
                contentPadding: EdgeInsets.zero,
                secondary: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), child: Icon(icon, color: cs.primary)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t['ps_enabled_hint']),
                value: enabled,
                onChanged: onEnabled,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: ValueKey('ps-$keyId-auto'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(autoText),
                value: auto,
                onChanged: enabled ? onAuto : null,
              ),
            ]),
          ),
        );

    Widget typeRow(String type) {
      final a = cfg.forType(type);
      Widget chip(String id, String label, bool on, bool masterOn, bool autoOn, AutoPrint Function(bool) change) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              key: ValueKey('ps-$type-$id'),
              label: Text(label),
              selected: on && masterOn && autoOn,
              showCheckmark: false,
              selectedColor: cs.primary,
              labelStyle: TextStyle(color: on && masterOn && autoOn ? cs.onPrimary : cs.onSurface, fontWeight: FontWeight.w600),
              onSelected: masterOn && autoOn ? (v) => save(cfg.withType(type, change(v))) : null,
            ),
          );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 92, child: Text(t[type == 'dine_in' ? 'dine_in' : type], style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: Wrap(children: [
              chip('kot', 'KOT', a.kot, cfg.kotEnabled, cfg.autoKot, (v) => a.copyWith(kot: v)),
              chip('token', t['ps_token_short'], a.token, cfg.tokenEnabled, cfg.autoToken, (v) => a.copyWith(token: v)),
              chip('bill', t['ps_bill_short'], a.bill, cfg.billEnabled, cfg.autoBill, (v) => a.copyWith(bill: v)),
            ]),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: DtAppBar(title: Text(t['print_settings'])),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t['print_settings_hint'], style: TextStyle(color: cs.onSurfaceVariant))),
        doc(keyId: 'kot', icon: Icons.soup_kitchen_outlined, title: t['ps_kot'], enabled: cfg.kotEnabled, onEnabled: (v) => save(cfg.copyWith(kotEnabled: v)), autoText: t['ps_auto_kot'], auto: cfg.autoKot, onAuto: (v) => save(cfg.copyWith(autoKot: v))),
        doc(keyId: 'token', icon: Icons.confirmation_number_outlined, title: t['ps_token'], enabled: cfg.tokenEnabled, onEnabled: (v) => save(cfg.copyWith(tokenEnabled: v)), autoText: t['ps_auto_token'], auto: cfg.autoToken, onAuto: (v) => save(cfg.copyWith(autoToken: v))),
        doc(keyId: 'bill', icon: Icons.receipt_long_outlined, title: t['ps_bill'], enabled: cfg.billEnabled, onEnabled: (v) => save(cfg.copyWith(billEnabled: v)), autoText: t['ps_auto_bill'], auto: cfg.autoBill, onAuto: (v) => save(cfg.copyWith(autoBill: v))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['ps_by_type'], style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
              const SizedBox(height: 6),
              for (final type in PrintSettings.types) typeRow(type),
            ]),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 0), child: Text(t['ps_routing_hint'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
      ]),
    );
  }
}
