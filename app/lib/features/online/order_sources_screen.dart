import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../data/online_order_service.dart';
import '../../data/pos_service.dart' show PosException;
import '../../data/queries.dart';
import '../common/dialogs.dart';
import 'delivery_orders_screen.dart' show payInstructionsKey, payInstructionsProvider;

final orderSourcesProvider = FutureProvider.autoDispose<List<OrderSource>>((ref) => ref.watch(onlineOrderServiceProvider).sources());

/// Where delivery orders come from (Direct WhatsApp, Phone, Foodpanda, Grab & Go...). Staff can add their own, rename and switch them off.
/// Also holds the payment instructions that go under the bank details in customer messages.
class OrderSourcesScreen extends ConsumerWidget {
  const OrderSourcesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, OrderSource? s) async {
    final t = Strings.of(context);
    var platform = s?.platform ?? false;
    var active = s?.active ?? true;
    final v = await showFormDialog(
      context,
      title: s == null ? t['dl_add_source'] : s.name,
      fields: [FieldSpec('name', t['name'], initial: s?.name ?? '')],
      extra: (set) => Column(children: [
        SwitchListTile(key: const ValueKey('src-platform'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['dl_is_platform']), subtitle: Text(t['dl_is_platform_hint']), value: platform, onChanged: (x) => set(() => platform = x)),
        SwitchListTile(key: const ValueKey('src-active'), contentPadding: EdgeInsets.zero, dense: true, title: Text(t['dl_source_active']), value: active, onChanged: (x) => set(() => active = x)),
      ]),
      validate: (v) async {
        try {
          await ref.read(onlineOrderServiceProvider).saveSource(id: s?.id, name: v['name']!, platform: platform, active: active);
          return null;
        } on PosException catch (e) {
          return e.message;
        }
      },
    );
    if (v != null) ref.invalidate(orderSourcesProvider);
  }

  Future<void> _instructions(BuildContext context, WidgetRef ref) async {
    final t = Strings.of(context);
    final current = await ref.read(payInstructionsProvider.future);
    if (!context.mounted) return;
    final v = await showFormDialog(context, title: t['dl_pay_instructions'], fields: [FieldSpec('text', t['dl_pay_instructions_hint'], initial: current, lines: 4, required: false)]);
    if (v == null) return;
    await setSetting(ref.read(databaseProvider), payInstructionsKey, v['text']!.trim(), ref.read(clockProvider)().millisecondsSinceEpoch);
    ref.invalidate(payInstructionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = ref.watch(orderSourcesProvider).value ?? const <OrderSource>[];
    return Scaffold(
      appBar: DtAppBar(title: Text(t['dl_sources'])),
      floatingActionButton: FloatingActionButton.extended(key: const ValueKey('add-source'), onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.add), label: Text(t['dl_add_source'])),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), children: [
        Text(t['dl_sources_hint'], style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        for (final s in list)
          Card(
            child: ListTile(
              key: ValueKey('source-${s.name}'),
              leading: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.1), child: Icon(s.platform ? Icons.storefront_outlined : Icons.person_pin_circle_outlined, color: cs.primary)),
              title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: s.active ? null : TextDecoration.lineThrough)),
              subtitle: Text(s.platform ? t['dl_platform'] : t['dl_direct']),
              onTap: () => _edit(context, ref, s),
              trailing: IconButton(
                key: ValueKey('source-delete-${s.name}'),
                tooltip: t['delete'],
                icon: Icon(Icons.delete_outline, color: cs.error),
                onPressed: () async {
                  await ref.read(onlineOrderServiceProvider).deleteSource(s.id);
                  ref.invalidate(orderSourcesProvider);
                },
              ),
            ),
          ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            key: const ValueKey('pay-instructions'),
            leading: const Icon(Icons.payments_outlined),
            title: Text(t['dl_pay_instructions']),
            subtitle: Text(t['dl_pay_instructions_sub']),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _instructions(context, ref),
          ),
        ),
      ]),
    );
  }
}
