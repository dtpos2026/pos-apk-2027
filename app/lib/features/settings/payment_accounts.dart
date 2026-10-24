import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/menu_images.dart';
import '../../data/payment_method_service.dart';
import '../../data/pos_service.dart';
import '../common/menu_image.dart';
import '../common/dialogs.dart';

IconData paymentIcon(String kind) => switch (kind) {
      'cash' => Icons.payments_outlined,
      'card' => Icons.credit_card,
      'bank' => Icons.account_balance_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'credit' => Icons.menu_book_outlined,
      _ => Icons.more_horiz,
    };

/// Where payments are recorded, one card per account: logo or icon, name, provider, masked number, holder and an on/off
/// switch. Tap a card to edit it; the menu on the card deletes it when that is allowed.
class PaymentAccountCard extends ConsumerWidget {
  const PaymentAccountCard({super.key, required this.method});
  final PaymentMethodRow method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final m = method;
    final details = [if (m.provider != null) m.provider!, if (m.maskedNumber != null) m.maskedNumber!, if (m.holder != null) m.holder!].join('  ·  ');
    return Card(
      key: ValueKey('pm-${m.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: m.kind == 'cash' ? null : () => showPaymentAccountDialog(context, ref, existing: m),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 44,
              child: m.imagePath != null
                  ? MenuImage(path: m.imagePath, name: m.name, radius: 22, iconSize: 20)
                  : CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), child: Icon(paymentIcon(m.kind), color: cs.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(t['pm_${m.kind}'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                if (details.isNotEmpty) Text(details, key: ValueKey('pm-details-${m.name}'), style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
            if (!m.isSystem)
              PopupMenuButton<String>(
                key: ValueKey('pm-menu-${m.name}'),
                onSelected: (a) async {
                  if (a == 'edit') {
                    await showPaymentAccountDialog(context, ref, existing: m);
                  } else {
                    final ok = await confirmDialog(context, t['pm_delete_confirm'], okLabel: t['delete']);
                    if (!ok || !context.mounted) return;
                    try {
                      await ref.read(paymentMethodServiceProvider).remove(m.id, staffId: ref.read(sessionProvider)!.staffId);
                      ref.invalidate(allPaymentMethodsProvider);
                      ref.invalidate(paymentMethodsProvider);
                    } on PosException catch (e) {
                      if (context.mounted) showMessage(context, e.code == 'has_history' ? t['pm_has_history'] : e.message);
                    }
                  }
                },
                itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Text(t['edit'])), PopupMenuItem(key: ValueKey('pm-delete-${m.name}'), value: 'delete', child: Text(t['delete']))],
              ),
            Switch(
              key: ValueKey('pm-switch-${m.name}'),
              value: m.enabled,
              onChanged: m.kind == 'cash'
                  ? null
                  : (v) async {
                      await ref.read(paymentMethodServiceProvider).setEnabled(m.id, v, staffId: ref.read(sessionProvider)!.staffId);
                      ref.invalidate(allPaymentMethodsProvider);
                      ref.invalidate(paymentMethodsProvider);
                    },
            ),
          ]),
        ),
      ),
    );
  }
}

Future<void> showPaymentAccountDialog(BuildContext context, WidgetRef ref, {PaymentMethodRow? existing}) async {
  final t = Strings.of(context);
  final name = TextEditingController(text: existing?.name ?? '');
  final provider = TextEditingController(text: existing?.provider ?? '');
  final number = TextEditingController(text: existing?.accountNo ?? '');
  final holder = TextEditingController(text: existing?.holder ?? '');
  var kind = existing?.kind ?? 'wallet';
  Uint8List? newLogo;
  var removeLogo = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final isBank = kind == 'bank';
        return AlertDialog(
          title: Text(existing == null ? t['add_payment_account'] : t['edit']),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: newLogo != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.memory(newLogo!, fit: BoxFit.cover))
                      : (existing?.imagePath != null && !removeLogo ? MenuImage(path: existing!.imagePath, name: existing.name, radius: 28, iconSize: 22) : CircleAvatar(child: Icon(paymentIcon(kind)))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(spacing: 4, children: [
                    OutlinedButton.icon(
                      key: const ValueKey('pm-logo'),
                      onPressed: () async {
                        final b = await ref.read(logoPickerProvider).pick();
                        if (b == null) return;
                        try {
                          final jpg = MenuImageStore.normalize(b);
                          setState(() {
                            newLogo = jpg;
                            removeLogo = false;
                            error = null;
                          });
                        } on MenuImageException catch (e) {
                          setState(() => error = e.message);
                        }
                      },
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(t['pm_logo']),
                    ),
                    if (newLogo != null || (existing?.imagePath != null && !removeLogo))
                      TextButton(key: const ValueKey('pm-logo-remove'), onPressed: () => setState(() {
                            newLogo = null;
                            removeLogo = true;
                          }), child: Text(t['remove_photo'])),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(key: const ValueKey('pm-name'), controller: name, decoration: InputDecoration(labelText: t['pm_name_hint'])),
              if (existing == null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const ValueKey('pm-kind'),
                  initialValue: kind,
                  decoration: InputDecoration(labelText: t['pm_type']),
                  items: [for (final k in const ['wallet', 'bank', 'card', 'other']) DropdownMenuItem(value: k, child: Text(t['pm_$k']))],
                  onChanged: (v) => setState(() => kind = v ?? 'wallet'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(key: const ValueKey('pm-provider'), controller: provider, decoration: InputDecoration(labelText: isBank ? t['pm_bank_name'] : t['pm_provider'])),
              const SizedBox(height: 10),
              TextField(key: const ValueKey('pm-number'), controller: number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z \-]'))], decoration: InputDecoration(labelText: isBank ? '${t['pm_number']} *' : t['pm_number'])),
              const SizedBox(height: 10),
              TextField(key: const ValueKey('pm-holder'), controller: holder, decoration: InputDecoration(labelText: isBank ? '${t['pm_holder']} *' : t['pm_holder'])),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, key: const ValueKey('pm-error'), style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
            FilledButton(
              key: const ValueKey('pm-save'),
              onPressed: () async {
                final svc = ref.read(paymentMethodServiceProvider);
                final staff = ref.read(sessionProvider)!.staffId;
                try {
                  final id = existing?.id ?? await svc.add(name: name.text, kind: kind, staffId: staff, provider: provider.text, accountNo: number.text, holder: holder.text);
                  if (existing != null) await svc.update(id, name: name.text, provider: provider.text, accountNo: number.text, holder: holder.text, staffId: staff);
                  final images = ref.read(menuImageStoreProvider);
                  if (newLogo != null) await images.setPaymentMethod(id, newLogo!);
                  if (removeLogo && newLogo == null) await images.removePaymentMethod(id);
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
        );
      },
    ),
  );
}
