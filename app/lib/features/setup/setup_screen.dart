import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/business_mode.dart';
import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/setup_service.dart';
import '../../domain/modules.dart';
import '../login/brand_footer.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _owner = TextEditingController();
  final _pin = TextEditingController();
  String _country = 'PK';
  String _type = 'fastfood';
  bool _busy = false;

  @override
  void dispose() {
    _business.dispose();
    _owner.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final ownerId = await SetupService(ref.read(databaseProvider), ref.read(authServiceProvider))
          .completeSetup(businessName: _business.text, ownerName: _owner.text, pin: _pin.text, country: _country);
      await applyBusinessType(ref, _type);
      ref.invalidate(businessProvider);
      ref.invalidate(staffListProvider);
      ref.invalidate(paymentMethodsProvider);
      await ref.read(sessionProvider.notifier).startFor(ownerId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final locale = ref.watch(localeProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [for (final e in Strings.languageNames.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                  selected: {locale.languageCode},
                  onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
                ),
              ),
              const SizedBox(height: 16),
              Text(t['app_name'], style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 4),
              Text(t['setup_title'], style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 24),
              Form(
                key: _form,
                child: Column(children: [
                  TextFormField(controller: _business, decoration: InputDecoration(labelText: t['business_name']), textInputAction: TextInputAction.next, validator: (v) => (v ?? '').trim().isEmpty ? t['required'] : null),
                  const SizedBox(height: 14),
                  TextFormField(controller: _owner, decoration: InputDecoration(labelText: t['owner_name']), textInputAction: TextInputAction.next, validator: (v) => (v ?? '').trim().isEmpty ? t['required'] : null),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pin,
                    decoration: InputDecoration(labelText: t['create_pin']),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                    validator: (v) => RegExp(r'^\d{4,8}$').hasMatch(v ?? '') ? null : t['pin_invalid'],
                  ),
                  const SizedBox(height: 18),
                  Align(alignment: AlignmentDirectional.centerStart, child: Text(t['business_type'], style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 8),
                  BusinessTypePicker(selected: _type, onSelected: (id) => setState(() => _type = id)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _country,
                    decoration: InputDecoration(labelText: t['currency']),
                    items: const [DropdownMenuItem(value: 'PK', child: Text('PKR (Pakistan)')), DropdownMenuItem(value: 'AE', child: Text('AED (UAE)'))],
                    onChanged: (v) => setState(() => _country = v ?? 'PK'),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _finish, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t['finish_setup'])),
              const SizedBox(height: 32),
              const BrandFooter(),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Business type cards. Each one only pre-selects modules; the owner can change them later in Settings.
class BusinessTypePicker extends StatelessWidget {
  const BusinessTypePicker({super.key, required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 16) / 3;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final b in businessTypes)
            InkWell(
              key: ValueKey('btype-${b.id}'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelected(b.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                decoration: BoxDecoration(
                  color: selected == b.id ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected == b.id ? scheme.primary : scheme.outlineVariant, width: selected == b.id ? 2 : 1),
                ),
                child: Column(children: [
                  Icon(b.icon, color: scheme.primary, size: 26),
                  const SizedBox(height: 4),
                  Text(t['btype_${b.id}'], textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
