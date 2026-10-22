import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/setup_service.dart';
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
