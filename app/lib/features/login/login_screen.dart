import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../data/auth_service.dart';
import '../../data/queries.dart';
import 'brand_footer.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  StaffEntry? _who;
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final t = Strings.of(context);
    setState(() => _busy = true);
    final r = await ref.read(sessionProvider.notifier).signIn(_who!.id, _pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _error = switch (r) { PinResult.ok => null, PinResult.locked => t['pin_locked'], _ => t['wrong_pin'] };
    });
  }

  void _press(String d) {
    if (_busy || _pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final staff = ref.watch(staffListProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 8),
                _BusinessHeader(compact: _who != null),
                const SizedBox(height: 6),
                Text(_who == null ? t['choose_user'] : _who!.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                Expanded(
                  child: _who == null
                      ? staff.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('$e'),
                          data: (list) => ListView(children: [
                            for (final s in list)
                              Card(
                                child: ListTile(
                                  key: ValueKey('staff-${s.name}'),
                                  leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Text(s.name.characters.first.toUpperCase())),
                                  title: Text(s.name),
                                  subtitle: Text(s.roleName),
                                  onTap: () => setState(() => _who = s),
                                ),
                              ),
                          ]),
                        )
                      : _PinPad(pin: _pin, error: _error, title: t['enter_pin'], onDigit: _press, onBack: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)), onSubmit: _pin.length >= 4 ? _submit : null, onChangeUser: () => setState(() {
                            _who = null;
                            _pin = '';
                            _error = null;
                          })),
                ),
                const BrandFooter(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.pin, required this.error, required this.title, required this.onDigit, required this.onBack, required this.onSubmit, required this.onChangeUser});
  final String pin;
  final String? error;
  final String title;
  final void Function(String) onDigit;
  final VoidCallback onBack;
  final VoidCallback? onSubmit;
  final VoidCallback onChangeUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 62,
            child: FilledButton.tonal(key: ValueKey('key-$label'), onPressed: onTap, child: child ?? Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
          ),
        );
    return Column(children: [
      Text(title),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < (pin.length < 4 ? 4 : pin.length); i++)
          Container(margin: const EdgeInsets.all(6), width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? scheme.primary : scheme.outlineVariant)),
      ]),
      SizedBox(height: 22, child: Text(error ?? '', key: const ValueKey('pin-error'), style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600))),
      Expanded(
        child: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 1.45,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) key(d, onTap: () => onDigit(d)),
            key('back', onTap: onBack, child: const Icon(Icons.backspace_outlined)),
            key('0', onTap: () => onDigit('0')),
            key('ok', onTap: onSubmit, child: const Icon(Icons.check_rounded)),
          ],
        ),
      ),
      TextButton(onPressed: onChangeUser, child: const Icon(Icons.swap_horiz)),
    ]);
  }
}

/// Business logo, name, address and phone, all centred: the face of the app on the sign-in screen.
class _BusinessHeader extends ConsumerWidget {
  const _BusinessHeader({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(businessProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final logo = b?.logoPath;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5);
    return Column(children: [
      if (logo != null && File(logo).existsSync())
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Image.file(File(logo), key: const ValueKey('login-logo'), height: compact ? 56 : 96, fit: BoxFit.contain)),
      Text(b?.name ?? Strings.of(context)['app_name'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary)),
      if (!compact && (b?.address?.trim().isNotEmpty ?? false)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b!.address!, textAlign: TextAlign.center, style: muted)),
      if (!compact && (b?.phone?.trim().isNotEmpty ?? false)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b!.phone!, textAlign: TextAlign.center, style: muted)),
    ]);
  }
}
