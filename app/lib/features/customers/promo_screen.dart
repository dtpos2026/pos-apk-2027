import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../app/whatsapp.dart';
import '../../domain/promo.dart';
import 'customers_screen.dart';

/// Promotional message to many customers: pick who, choose or write the message, then WhatsApp opens for one customer at a time with
/// the message typed in. The person presses Send in WhatsApp; nothing is sent by the app on its own.
class PromoScreen extends ConsumerStatefulWidget {
  const PromoScreen({super.key});
  @override
  ConsumerState<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends ConsumerState<PromoScreen> {
  final _selected = <String>{};
  late final TextEditingController _text = TextEditingController(text: promoTemplates.values.first);
  bool _owingOnly = false;
  PromoQueue? _queue;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(customersProvider('')).value ?? const [];
    final withPhone = all.where((c) => (c.phone ?? '').trim().isNotEmpty && (!_owingOnly || c.balanceMinor > 0)).toList();
    final shop = ref.watch(businessProvider).value?.name ?? '';
    final q = _queue;
    return Scaffold(
      appBar: DtAppBar(title: Text(t['promo_title'])),
      body: q != null ? _sending(context, q, shop) : Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 12), children: [
            Text(t['promo_message'], style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in promoTemplates.entries) ActionChip(key: ValueKey(e.key), label: Text(t[e.key]), onPressed: () => setState(() => _text.text = e.value)),
            ]),
            const SizedBox(height: 8),
            TextField(key: const ValueKey('promo-text'), controller: _text, minLines: 3, maxLines: 6, onChanged: (_) => setState(() {}), decoration: InputDecoration(helperText: t['promo_hint'])),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('${t['promo_to']} (${_selected.length})', style: const TextStyle(fontWeight: FontWeight.w800))),
              FilterChip(key: const ValueKey('promo-owing'), label: Text(t['owing_only']), selected: _owingOnly, showCheckmark: false, onSelected: (v) => setState(() => _owingOnly = v)),
              TextButton(key: const ValueKey('promo-all'), onPressed: () => setState(() => _selected.length == withPhone.length ? _selected.clear() : _selected.addAll(withPhone.map((c) => c.id))), child: Text(t['promo_all'])),
            ]),
            if (withPhone.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(t['promo_no_phone'], textAlign: TextAlign.center)),
            for (final c in withPhone)
              Card(
                margin: const EdgeInsets.only(top: 6),
                child: CheckboxListTile(
                  key: ValueKey('promo-c-${c.name}'),
                  value: _selected.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _selected.add(c.id) : _selected.remove(c.id)),
                  secondary: CustomerAvatar(c, radius: 20),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.phone ?? ''),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant))),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('promo-start'),
                icon: const Icon(Icons.send),
                label: Text('${t['promo_start']} (${_selected.length})'),
                onPressed: _selected.isEmpty || _text.text.trim().isEmpty
                    ? null
                    : () => setState(() => _queue = PromoQueue([for (final c in all.where((c) => _selected.contains(c.id))) PromoTarget(name: c.name, phone: c.phone ?? '')], template: _text.text, shop: shop)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sending(BuildContext context, PromoQueue q, String shop) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    if (q.finished) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade700),
            const SizedBox(height: 12),
            Text('${t['promo_done']}: ${q.total}', key: const ValueKey('promo-done'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            FilledButton(key: const ValueKey('promo-close'), onPressed: () => Navigator.pop(context), child: Text(t['close'])),
          ]),
        ),
      );
    }
    final c = q.current!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(value: q.done / q.total, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 10),
        Text('${q.done + 1} / ${q.total}', key: const ValueKey('promo-progress'), style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Text(c.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(c.phone, style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)), child: Text(q.currentText!, key: const ValueKey('promo-preview'))),
        const Spacer(),
        FilledButton.icon(
          key: const ValueKey('promo-open'),
          icon: const Icon(Icons.chat),
          label: Text(t['promo_open']),
          onPressed: () async {
            final text = q.currentText!;
            await sendViaWhatsApp(ref, c.phone, text);
            if (mounted) setState(q.advance);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton(key: const ValueKey('promo-skip'), onPressed: () => setState(q.advance), child: Text(t['promo_skip'])),
        const SizedBox(height: 8),
        TextButton(key: const ValueKey('promo-stop'), onPressed: () => setState(() => _queue = null), child: Text(t['cancel'])),
      ]),
    );
  }
}
